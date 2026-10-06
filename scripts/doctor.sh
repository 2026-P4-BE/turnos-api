#!/bin/bash
# Pre-class check (a few seconds): will the demo work? If not, what to run.
# Read-only: it changes nothing. Exit code 1 when something blocks the demo.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

FAILS=0 WARNS=0
fail() { bad "$1"; [ -z "${2:-}" ] || say "         fix: $2"; FAILS=$((FAILS + 1)); }
note() { warn "$1"; [ -z "${2:-}" ] || say "         fix: $2"; WARNS=$((WARNS + 1)); }

# Who listens on a host port? Prints the owner, or nothing when the port is free.
port_owner() {
  (echo > "/dev/tcp/127.0.0.1/$1") 2>/dev/null || return 0
  docker ps --filter "publish=$1" --format '{{.Names}}' | head -1 | grep . || echo "a process outside Docker"
}

say "Docker"
if docker info >/dev/null 2>&1; then
  mem="$(docker info --format '{{.MemTotal}}' 2>/dev/null)"
  ok "Docker daemon answers ($(( mem / 1024 / 1024 )) MB for containers)"
  [ "$mem" -ge 3500000000 ] || note "Docker has less than 3.5 GB: Jenkins + builds may be killed" "Docker Desktop > Settings > Resources"
else
  fail "Docker daemon does not answer" "start Docker Desktop and wait for the whale icon to stop moving"
  say ""; say "NOT READY: $FAILS blocking problem(s)."; exit 1
fi
if docker image inspect turnos-jenkins:1.0 >/dev/null 2>&1; then ok "Jenkins image turnos-jenkins:1.0 is built"
else fail "Jenkins image is not built (needs internet, takes minutes)" "docker compose up -d --build --wait"; fi

say ""; say "Ports (free, or owned by this lab)"
for spec in 8090:turnos-jenkins 5001:turnos-registry 8081:turnos-staging 8082:turnos-prod; do
  p="${spec%%:*}" mine="${spec#*:}" owner="$(port_owner "$p")"
  if [ -z "$owner" ]; then
    case "$p" in 8081|8082) ok "port $p free (filled by the pipeline later)" ;; *) ok "port $p free" ;; esac
  elif [ "$owner" = "$mine" ]; then ok "port $p used by $mine (this lab)"
  else fail "port $p is used by $owner" "stop it, or free the port before the class"; fi
done

say ""; say "Lab"
state() { docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$1" 2>/dev/null; }
js="$(state turnos-jenkins)"; rs="$(state turnos-registry)"
case "$js" in "running healthy"|"running ") ok "container turnos-jenkins running and healthy" ;;
  "running starting") note "Jenkins is still starting" "wait 30 s and run doctor again" ;;
  *) fail "container turnos-jenkins is not running (${js:-missing})" "docker compose up -d --wait" ;; esac
case "$rs" in running*) ok "container turnos-registry running" ;;
  *) fail "container turnos-registry is not running (${rs:-missing})" "docker compose up -d --wait" ;; esac

if jenkins_up; then
  ok "Jenkins answers at $JENKINS_URL"
  if jget "$JENKINS_URL/job/$JOB/api/json?tree=buildable" 2>/dev/null | grep -q '"buildable":true'; then
    ok "job $JOB exists and is enabled (created by JCasC, no UI step)"
    last="$(last_build)"; run="$(running_builds | tr '\n' ' ')"
    if [ -n "$run" ]; then note "build(s) running or paused at Approval: ${run}(a paused one blocks the next builds)" "scripts/reset.sh"
    elif [ "$last" = "0" ]; then ok "no builds yet: build #1 starts by itself within a minute of startup"
    else note "$last build(s) in history (leftovers from an earlier run)" "scripts/reset.sh"; fi
  else fail "job $JOB is missing or disabled" "scripts/reset.sh  (or: scripts/reset.sh --hard)"; fi
else
  fail "Jenkins does not answer at $JENKINS_URL" "docker compose up -d --wait"
fi
curl -fs -m 3 http://localhost:5001/v2/_catalog >/dev/null 2>&1 && ok "registry answers at localhost:5001" \
  || fail "registry does not answer at localhost:5001" "docker compose up -d --wait"

say ""; say "Repository"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] && ok "branch main" || fail "not on branch main (Jenkins polls main)" "git switch main"
if git rev-parse -q --verify "refs/tags/$BASELINE_TAG" >/dev/null; then
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse "$BASELINE_TAG^{commit}")" ]; then ok "HEAD is at $BASELINE_TAG"
  else note "HEAD is not at $BASELINE_TAG: $(git rev-list --count "$BASELINE_TAG"..HEAD) commit(s) after it" "scripts/demo.sh status ; scripts/reset.sh"; fi
else fail "tag $BASELINE_TAG is missing (demo.sh restore needs it)" "git tag $BASELINE_TAG"; fi
[ -z "$(git status --porcelain --untracked-files=no)" ] && ok "working tree clean" \
  || note "uncommitted changes: Jenkins only sees commits" "git status"
[ "$(git ls-files --eol -- 'scripts/*.sh' Jenkinsfile | grep -c 'i/crlf')" = "0" ] && ok "scripts and Jenkinsfile use LF line endings" \
  || fail "a script or the Jenkinsfile has CRLF line endings" "git ls-files --eol ; fix with: git add --renormalize ."

say ""
if [ "$FAILS" -gt 0 ]; then say "NOT READY: $FAILS blocking problem(s), $WARNS warning(s). Follow the 'fix:' lines."; exit 1; fi
if [ "$WARNS" -gt 0 ]; then say "READY with $WARNS warning(s): the demo works, but the starting state is not clean (scripts/reset.sh)."; exit 0; fi
say "READY. Open $JENKINS_URL (admin / admin)."
