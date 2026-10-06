#!/bin/bash
# The ONE way back to the initial state.
#   scripts/reset.sh            soft: Jenkins keeps running, caches kept. Takes seconds.
#   scripts/reset.sh --hard     fresh Jenkins: new jenkins_home, build #1 again. Keeps the Maven cache.
# Options: --keep-history (soft: do not delete the build list)
#          --purge-cache  (hard: also delete the Maven cache => next first build is slow)
#          --rebuild      (hard: rebuild the Jenkins image, needs internet)
# Only touches this lab: compose project "turnos-ci", turnos-staging/turnos-prod, localhost:5001/turnos-api:* images.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

HARD=0 KEEP_HISTORY=0 PURGE_CACHE=0 BUILD_FLAG=""
for a in "$@"; do
  case "$a" in
    --hard) HARD=1 ;;
    --keep-history) KEEP_HISTORY=1 ;;
    --purge-cache) PURGE_CACHE=1 ;;
    --rebuild) BUILD_FLAG="--build" ;;
    *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
  esac
done

VOLUME_PREFIX="turnos-ci"   # compose project name (see "name:" in docker-compose.yml)
START=$SECONDS
step() { printf '\n== %s\n' "$*"; }

JOB_DISABLED=0
enable_job() { [ "$JOB_DISABLED" = 1 ] && jpost "$JENKINS_URL/job/$JOB/enable" >/dev/null 2>&1 || true; }

remove_app_containers() {
  # shellcheck disable=SC2086
  docker rm -f $APP_CONTAINERS >/dev/null 2>&1 || true
  say "app containers removed (turnos-staging, turnos-prod)"
}

remove_app_images() {
  local imgs
  imgs="$(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep "^$APP_IMAGE_PREFIX" || true)"
  # shellcheck disable=SC2086
  [ -z "$imgs" ] || docker image rm -f $imgs >/dev/null 2>&1 || true
  say "app images removed: $(echo "$imgs" | grep -c . || true)"
}

remove_volume() { # name; ignores a missing volume
  docker volume inspect "$1" >/dev/null 2>&1 && docker volume rm "$1" >/dev/null && say "volume removed: $1" || true
}

stop_builds() {
  jpost "$JENKINS_URL/scriptText" --data-urlencode 'script=jenkins.model.Jenkins.get().queue.clear()' >/dev/null
  local n i
  for n in $(running_builds); do jpost "$JENKINS_URL/job/$JOB/$n/stop" >/dev/null 2>&1 || true; done
  for i in $(seq 1 30); do
    [ -z "$(running_builds)" ] && { say "no build running or queued"; return; }
    sleep 2
  done
  for n in $(running_builds); do jpost "$JENKINS_URL/job/$JOB/$n/kill" >/dev/null 2>&1 || true; done
  sleep 3
  [ -z "$(running_builds)" ] || die "a build would not stop. Look at $JENKINS_URL/job/$JOB/"
  say "stuck build killed"
}

clear_history() {
  jpost "$JENKINS_URL/scriptText" --data-urlencode "script=def j = jenkins.model.Jenkins.get().getItemByFullName('$JOB')
j.builds.collect { it }.each { it.delete() }
j.updateNextBuildNumber(1)
println 'builds left: ' + j.builds.size()" | sed 's/^/  /'
}

wait_for_job() {
  local i
  for i in $(seq 1 60); do
    jget "$JENKINS_URL/job/$JOB/api/json" >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

# ---- 0. refuse before destroying anything if git holds work that is not ours --------------------
step "Checking that the repository holds only demo commits"
bash scripts/demo.sh restore --check

if [ "$HARD" = 0 ]; then
  # ---- SOFT ---------------------------------------------------------------------------------------
  step "Making sure Jenkins and the registry are up"
  compose up -d --wait
  wait_for_job || die "job $JOB not found in Jenkins"
  trap enable_job EXIT
  jpost "$JENKINS_URL/job/$JOB/disable" >/dev/null && JOB_DISABLED=1   # stops pollSCM while we clean

  step "Stopping builds"
  stop_builds
  step "Removing app containers, images and registry content"
  remove_app_containers
  compose rm -sf registry >/dev/null 2>&1
  remove_volume "${VOLUME_PREFIX}_registry_data"
  compose up -d --wait registry >/dev/null 2>&1
  remove_app_images
  step "Undoing demo commits"
  bash scripts/demo.sh restore
  if [ "$KEEP_HISTORY" = 0 ]; then
    step "Clearing build history"
    clear_history
  fi
  enable_job; JOB_DISABLED=0
else
  # ---- HARD ---------------------------------------------------------------------------------------
  step "Removing app containers and images"
  remove_app_containers
  remove_app_images
  step "Removing Jenkins and the registry, with their data"
  compose down --remove-orphans
  remove_volume "${VOLUME_PREFIX}_jenkins_home"
  remove_volume "${VOLUME_PREFIX}_registry_data"
  if [ "$PURGE_CACHE" = 1 ]; then remove_volume "${VOLUME_PREFIX}_maven_cache"; else say "Maven cache kept (--purge-cache deletes it)"; fi
  step "Undoing demo commits"
  bash scripts/demo.sh restore
  step "Starting a fresh Jenkins"
  # shellcheck disable=SC2086
  compose up -d $BUILD_FLAG --wait
  wait_for_job || die "job $JOB did not appear after startup (check: docker logs turnos-jenkins)"
fi

# ---- verification -------------------------------------------------------------------------------
step "Verifying the resulting state"
FAILS=0
check() { if eval "$2"; then ok "$1"; else bad "$1"; FAILS=$((FAILS + 1)); fi; }
check "Jenkins answers at $JENKINS_URL" 'jenkins_up'
check "job $JOB exists and is enabled" 'jget "$JENKINS_URL/job/$JOB/api/json?tree=buildable" | grep -q "\"buildable\":true"'
if [ "$KEEP_HISTORY" = 0 ]; then
  check "build history is empty (next build is #1)" '[ "$(last_build)" = "0" ] && jget "$JENKINS_URL/job/$JOB/api/json?tree=nextBuildNumber" | grep -q "\"nextBuildNumber\":1"'
fi
check "no build running" '[ -z "$(running_builds)" ]'
check "no app containers (turnos-staging / turnos-prod)" '[ -z "$(docker ps -aq --filter name=^turnos-staging$ --filter name=^turnos-prod$)" ]'
check "registry is empty" 'curl -fs -m 5 http://localhost:5001/v2/_catalog | grep -q "\"repositories\":\[\]"'
check "no turnos-api images left in Docker" '[ -z "$(docker image ls -q "localhost:5001/turnos-api")" ]'
check "git: main is at $BASELINE_TAG and clean" '[ "$(git rev-parse HEAD)" = "$(git rev-parse "$BASELINE_TAG^{commit}")" ] && [ -z "$(git status --porcelain --untracked-files=no)" ]'

say ""
if [ "$FAILS" -gt 0 ]; then say "Reset finished with $FAILS problem(s) in $((SECONDS - START))s. Run scripts/doctor.sh"; exit 1; fi
say "Reset OK in $((SECONDS - START))s. Jenkins builds #1 by itself within about a minute (pollSCM),"
say "or start it now:  scripts/jenkins.sh build"
