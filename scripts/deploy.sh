#!/bin/sh
# Deploys an image as a container and verifies it. Rolls back if the health check fails.
# Usage: deploy.sh <container-name> <APP_ENV> <image> <host-port>
set -eu

NAME="$1"; APP_ENV="$2"; IMAGE="$3"; HOST_PORT="$4"
NETWORK="turnos-net"

# Remember what is running now, so we can go back to it
PREVIOUS="$(docker inspect -f '{{.Config.Image}}' "$NAME" 2>/dev/null || true)"

start() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" --network "$NETWORK" -p "$HOST_PORT:8080" \
    -e APP_ENV="$APP_ENV" --memory 256m "$1" >/dev/null
}

# Health check from inside the Docker network (Jenkins reaches the container by name)
healthy() {
  for i in $(seq 1 30); do
    if curl -fs "http://$NAME:8080/actuator/health" | grep -q '"status":"UP"'; then
      return 0
    fi
    sleep 3
  done
  return 1
}

docker pull "$IMAGE"
echo "Deploying $IMAGE as $NAME (APP_ENV=$APP_ENV, port $HOST_PORT)"
start "$IMAGE"

if healthy; then
  echo "Health check OK for $NAME"
  exit 0
fi

echo "Health check FAILED for $NAME"
docker logs --tail 30 "$NAME" || true
if [ -n "$PREVIOUS" ]; then
  echo "Rolling back to $PREVIOUS"
  start "$PREVIOUS"
  healthy && echo "Rollback OK" || echo "Rollback is also unhealthy"
else
  docker rm -f "$NAME" >/dev/null 2>&1 || true
fi
exit 1
