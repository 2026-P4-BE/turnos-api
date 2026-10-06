#!/bin/bash
# Small wrapper around the Jenkins REST calls that are awkward to type live.
# Also the plan B when the UI misbehaves. Build number N defaults to the newest build.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/jenkins.sh <command> [args]

  build [break-prod]   start a build (break-prod = BREAK_PRODUCTION=true, see RUNBOOK)
  status [N]           last builds, and the stages of build N
  wait [N|next]        wait until build N finishes or pauses at Approval
                       ("next" = the build that has not started yet, e.g. after demo.sh)
  approve [N]          click "Deploy to production" on the paused build
  abort [N]            stop build N
  log [N]              console output of build N
EOF
  exit "${1:-0}"
}

# Prints "STATUS stage:state stage:state ..." for build N
describe() {
  local json status stages
  json="$(jget "$JENKINS_URL/job/$JOB/$1/wfapi/describe")"
  status="$(echo "$json" | sed -n 's/.*"name":"#[0-9]*","status":"\([A-Z_]*\)".*/\1/p')"
  stages="$(echo "$json" | grep -o '"name":"[^"]*","execNode":"[^"]*","status":"[A-Z_]*"' \
    | sed 's/"name":"\([^"]*\)","execNode":"[^"]*","status":"\([A-Z_]*\)"/\1=\2/' | paste -sd, - | sed 's/,/, /g')"
  echo "${status:-?}|$stages"
}

resolve() { # N, default newest
  local n="${1:-$(last_build)}"
  [ "$n" != "0" ] || die "there are no builds yet"
  echo "$n"
}

cmd_build() {
  local before; before="$(last_build)"
  if [ "${1:-}" = "break-prod" ]; then
    jpost "$JENKINS_URL/job/$JOB/buildWithParameters?BREAK_PRODUCTION=true" >/dev/null \
      || die "job has no BREAK_PRODUCTION parameter yet: run a normal build first"
  else
    jpost "$JENKINS_URL/job/$JOB/buildWithParameters" >/dev/null 2>&1 \
      || jpost "$JENKINS_URL/job/$JOB/build" >/dev/null
  fi
  say "Build requested (previous newest: #$before). It may wait in the queue if another build is paused."
}

cmd_status() {
  say "Newest builds:"
  local builds; builds="$(jget "$JENKINS_URL/job/$JOB/api/json?tree=builds[number,result,building]{0,6}")"
  echo "$builds" | sed 's/},{/}\n{/g' | sed -n 's/.*"building":\(true\|false\),"number":\([0-9]*\),"result":\(null\|"[A-Z]*"\).*/  #\2 building=\1 result=\3/p'
  local n; n="${1:-$(last_build)}"
  [ "$n" = "0" ] && { say "  (no builds)"; return; }
  local d; d="$(describe "$n")"
  say "Build #$n: ${d%%|*}"
  say "  stages: ${d#*|}"
}

cmd_wait() {
  local target="${1:-}" start=$SECONDS
  if [ "$target" = "next" ]; then target=$(( $(last_build) + 1 )); fi
  target="$(resolve "$target")"
  say "Waiting for build #$target (Ctrl+C to stop waiting; the build keeps going)..."
  local seen="" d status stages
  while [ $((SECONDS - start)) -lt 1800 ]; do
    if d="$(describe "$target" 2>/dev/null)"; then
      status="${d%%|*}"; stages="${d#*|}"
      [ "$stages" = "$seen" ] || { say "  [$((SECONDS - start))s] $status  $stages"; seen="$stages"; }
      case "$status" in
        PAUSED_PENDING_INPUT) say "Paused at Approval after $((SECONDS - start))s."; return 0 ;;
        SUCCESS|FAILED|ABORTED|UNSTABLE|NOT_EXECUTED) say "Finished: $status after $((SECONDS - start))s."; return 0 ;;
      esac
    fi
    sleep 3
  done
  die "timed out waiting for build #$target"
}

cmd_approve() {
  local n; n="$(resolve "${1:-}")"
  local id
  id="$(jget "$JENKINS_URL/job/$JOB/$n/wfapi/pendingInputActions" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$id" ] || die "build #$n is not waiting at Approval"
  jpost "$JENKINS_URL/job/$JOB/$n/input/$id/proceedEmpty" >/dev/null
  say "Approved build #$n."
}

cmd_abort() {
  local n; n="$(resolve "${1:-}")"
  jpost "$JENKINS_URL/job/$JOB/$n/stop" >/dev/null
  say "Stop requested for build #$n."
}

cmd_log() { jget "$JENKINS_URL/job/$JOB/$(resolve "${1:-}")/consoleText"; }

jenkins_up || die "Jenkins does not answer at $JENKINS_URL. Start it: docker compose up -d --wait"
case "${1:-}" in
  build)   shift; cmd_build "$@" ;;
  status)  shift; cmd_status "$@" ;;
  wait)    shift; cmd_wait "$@" ;;
  approve) shift; cmd_approve "$@" ;;
  abort)   shift; cmd_abort "$@" ;;
  log)     shift; cmd_log "$@" ;;
  -h|--help|help) usage 0 ;;
  *) usage 1 ;;
esac
