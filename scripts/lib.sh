#!/bin/bash
# Shared helpers for the classroom scripts. Source it, do not run it.

# Git Bash would rewrite arguments such as /var/jenkins_home into C:/... : switch that off.
export MSYS_NO_PATHCONV=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JENKINS_URL="${JENKINS_URL:-http://localhost:8090}"
JENKINS_AUTH="${JENKINS_AUTH:-admin:admin}"   # throwaway demo credentials, see jenkins/casc.yaml
JOB="turnos-api"
BASELINE_TAG="class-baseline"
APP_CONTAINERS="turnos-staging turnos-prod"   # created by the pipeline, not by compose
APP_IMAGE_PREFIX="localhost:5001/turnos-api:" # one image per build, created by the pipeline

# Works from any directory: always point compose at this repo's file.
compose() { docker compose -f "$ROOT/docker-compose.yml" "$@"; }

say()  { printf '%s\n' "$*"; }
ok()   { printf '  [ OK ] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---- Jenkins REST (curl always has a timeout; -g keeps [ ] in URLs from being globbed) ----
JAR="$(mktemp)"
trap 'rm -f "$JAR"' EXIT

jenkins_up() {
  [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$JENKINS_URL/login" 2>/dev/null)" = "200" ]
}

jget() { curl -gfsS -m 20 -u "$JENKINS_AUTH" -b "$JAR" -c "$JAR" "$@"; }

# POST needs a crumb (CSRF token) bound to the session cookie
jpost() {
  [ -n "${CRUMB:-}" ] || CRUMB="$(jget "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")"
  curl -gfsS -m 60 -u "$JENKINS_AUTH" -b "$JAR" -c "$JAR" -H "$CRUMB" -X POST "$@"
}

# Number of the newest build (0 when there is none)
last_build() {
  local n
  n="$(jget "$JENKINS_URL/job/$JOB/api/json?tree=lastBuild[number]" | sed -n 's/.*"number":\([0-9]*\).*/\1/p')"
  echo "${n:-0}"
}

# Numbers of the builds that are running or paused (one per line)
running_builds() {
  jget "$JENKINS_URL/job/$JOB/api/json?tree=builds[number,building]" \
    | sed 's/},{/}\n{/g' | sed -n '/"building":true/s/.*"number":\([0-9]*\).*/\1/p'
}
