#!/bin/sh
# Deploys an image as a container and verifies it. Rolls back if the health check fails.
# Usage: deploy.sh <container-name> <APP_ENV> <image> <host-port>
set -eu

NAME="$1"; APP_ENV="$2"; IMAGE="$3"; HOST_PORT="$4"
NETWORK="turnos-net"

# Remember what is running now, so we can go back to it
PREVIOUS="$(docker inspect -f '{{.Config.Image}}' "$NAME" 2>/dev/null || true)"

# Classroom switch: BREAK_DEPLOY=true starts the NEW version with a broken datasource URL,
# so it crashes on boot (a bad config reaching production). The rollback never gets it.
FAULT=""
if [ "${BREAK_DEPLOY:-false}" = "true" ]; then
  FAULT="--env=SPRING_DATASOURCE_URL=jdbc:postgresql://nowhere/none"
  echo "BREAK_DEPLOY=true: injecting a bad configuration on purpose"
fi

# start <image> [extra docker run flag]
start() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" --network "$NETWORK" -p "$HOST_PORT:8080" \
    -e APP_ENV="$APP_ENV" --memory 256m ${2:+"$2"} "$1" >/dev/null
}

# Health check from inside the Docker network (Jenkins reaches the container by name)
healthy() {
  for i in $(seq 1 30); do
    # Container crashed: no point in waiting
    [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" = "true" ] || return 1
    if curl -fs --max-time 3 "http://$NAME:8080/actuator/health" | grep -q '"status":"UP"'; then
      return 0
    fi
    sleep 3
  done
  return 1
}

docker pull "$IMAGE"
echo "Deploying $IMAGE as $NAME (APP_ENV=$APP_ENV, port $HOST_PORT)"
start "$IMAGE" "$FAULT"

if healthy; then
  echo "Health check OK for $NAME"
  exit 0
fi

echo "Health check FAILED for $NAME"
echo "Why (last causes in the container log):"
docker logs "$NAME" 2>&1 | grep -E 'Caused by|APPLICATION FAILED|Description:' | tail -3 | cut -c1-200 || true
if [ -n "$PREVIOUS" ]; then
  echo "Rolling back to $PREVIOUS"
  start "$PREVIOUS"
  healthy && echo "Rollback OK" || echo "Rollback is also unhealthy"
else
  docker rm -f "$NAME" >/dev/null 2>&1 || true
fi
exit 1
