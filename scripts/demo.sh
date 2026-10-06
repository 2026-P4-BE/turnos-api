#!/bin/bash
# Classroom exercises: each one is a small, known commit on main. Jenkins polls the repo
# every minute, so the commit is what triggers the build. "restore" undoes them safely.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

MARK="Class-Demo"   # trailer that identifies a commit made by this script

usage() {
  cat <<EOF
Usage: scripts/demo.sh <exercise>

  trivial-change    empty commit: shows that a commit alone triggers a build   -> GREEN, waits at Approval
  new-version       changes the version the API reports (1.0.0-demo1)       -> GREEN, staging != production
  break-test        a unit test asserts a wrong value                         -> RED at Test
  drop-coverage     adds a class with no tests (coverage < 80%)               -> RED at Coverage Gate
  pmd-violation     adds a System.out.println                                 -> RED at Static Analysis

  fix               revert the last demo commit with a new commit (the normal way to repair main)
  status            commits since the baseline tag ($BASELINE_TAG) and who made them
  restore           undo every demo commit (git reset --hard $BASELINE_TAG), only if it is safe
  restore --check   same checks, changes nothing
  baseline          move $BASELINE_TAG to HEAD (after you changed the repo on purpose)
EOF
  exit "${1:-0}"
}

# ---- safety ---------------------------------------------------------------------------------
require_clean_main() {
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "not on branch main (Jenkins polls main)."
  [ -z "$(git status --porcelain --untracked-files=no)" ] \
    || die "uncommitted changes in tracked files: commit or stash them first. Nothing was touched."
}

is_demo_commit() { git show -s --format=%B "$1" | grep -q "^$MARK: "; }

# Refuses (exit 1 + explanation) unless HEAD is the baseline plus demo commits made by this script.
check_restorable() {
  git rev-parse -q --verify "refs/tags/$BASELINE_TAG" >/dev/null \
    || die "tag $BASELINE_TAG does not exist. Create it on the commit that is your starting point: git tag $BASELINE_TAG"
  require_clean_main
  git merge-base --is-ancestor "$BASELINE_TAG" HEAD \
    || die "HEAD is not ahead of $BASELINE_TAG (history was rewritten or main moved elsewhere). Refusing to reset."
  local c extra=""
  for c in $(git rev-list "$BASELINE_TAG"..HEAD); do
    is_demo_commit "$c" || extra="$extra\n  $(git log -1 --format='%h %s' "$c")"
  done
  if [ -n "$extra" ]; then
    printf 'REFUSING to reset: these commits since %s were NOT made by demo.sh:%b\n' "$BASELINE_TAG" "$extra" >&2
    say "A reset would delete them. Keep them with 'git tag -f $BASELINE_TAG HEAD' (they become the new starting point)," >&2
    say "or move them to another branch first, then run restore again." >&2
    exit 1
  fi
}

demo_commits() { git rev-list --reverse "$BASELINE_TAG"..HEAD 2>/dev/null || true; }

cmd_status() {
  local n=0 c
  say "Baseline $BASELINE_TAG = $(git rev-parse --short "$BASELINE_TAG" 2>/dev/null || echo MISSING); HEAD = $(git rev-parse --short HEAD)"
  for c in $(demo_commits); do
    n=$((n + 1))
    if is_demo_commit "$c"; then say "  demo   $(git log -1 --format='%h %s' "$c")"
    else say "  YOURS  $(git log -1 --format='%h %s' "$c")"; fi
  done
  [ "$n" -gt 0 ] || say "  (no commits since the baseline: initial state)"
}

cmd_restore() {
  check_restorable
  [ "${1:-}" != "--check" ] || { say "OK: restore would be safe ($(demo_commits | wc -l | tr -d ' ') demo commit(s))."; return; }
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse "$BASELINE_TAG^{commit}")" ]; then
    say "Already at $BASELINE_TAG: nothing to undo."
  else
    git reset --hard "$BASELINE_TAG" >/dev/null
    say "Restored main to $BASELINE_TAG ($(git rev-parse --short HEAD))."
  fi
}

cmd_fix() {
  local subject; subject="$(git log -1 --format=%s)"
  is_demo_commit HEAD || die "HEAD is not a demo commit; nothing to fix."
  git show -s --format=%B HEAD | grep -q "^$MARK: fix" && die "HEAD already is a fix. Use restore to go back to the baseline."
  git revert --no-commit HEAD 2>/dev/null || { git revert --abort 2>/dev/null; die "HEAD is an empty commit: nothing to revert."; }
  git commit -q -m "fix(demo): revert \"$subject\"" -m "$MARK: fix"
  say "Committed: $(git log -1 --format='%h %s')"
  say "Jenkins polls every minute: follow it with  scripts/jenkins.sh wait next"
}

cmd_baseline() {
  require_clean_main
  local c
  for c in $(demo_commits); do
    ! is_demo_commit "$c" || die "demo commits exist after the current baseline: run 'scripts/demo.sh restore' first."
  done
  git tag -f "$BASELINE_TAG" HEAD >/dev/null
  say "$BASELINE_TAG now points to $(git rev-parse --short HEAD)."
}

# ---- exercises -----------------------------------------------------------------------------
# commit <exercise> <subject>: commits what is staged/changed, tagging it with the trailer
commit() {
  git add -A -- src
  git commit -q --allow-empty -m "$2" -m "$MARK: $1"
  say "Committed: $(git log -1 --format='%h %s')"
  say "Jenkins polls every minute: follow it with  scripts/jenkins.sh wait next"
}

SERVICE_TEST="src/test/java/ar/edu/utn/frc/turnos/service/AppointmentServiceTest.java"
SERVICE="src/main/java/ar/edu/utn/frc/turnos/service/AppointmentService.java"
UNTESTED="src/main/java/ar/edu/utn/frc/turnos/service/CancellationFeePolicy.java"

ex_trivial_change() { commit trivial-change "chore(demo): empty commit to trigger the pipeline"; }

# Changes the version the API reports (-demo1, -demo2, ...). The pom is NOT touched on purpose:
# a different pom.xml invalidates the Docker dependency cache and the build takes minutes longer.
ex_new_version() {
  local props="src/main/resources/application.properties" n
  n="$(sed -n 's|^app.version=@project.version@-demo\([0-9]*\)$|\1|p' "$props")"
  n=$(( ${n:-0} + 1 ))
  sed -i "s|^app.version=.*|app.version=@project.version@-demo$n|" "$props"
  commit new-version "chore(demo): report version -demo$n"
}

ex_break_test() {
  grep -q 'created.getProfessional()).isEqualTo("Dr. House");' "$SERVICE_TEST" \
    || die "break-test is already applied (or the test changed). Run: scripts/demo.sh restore"
  sed -i 's|assertThat(created.getProfessional()).isEqualTo("Dr. House");|assertThat(created.getProfessional()).isEqualTo("Dr. Wilson");|' "$SERVICE_TEST"
  git diff --quiet -- "$SERVICE_TEST" && die "break-test patch did not apply: the test file changed."
  commit break-test "test(demo): break createsAppointmentWhenSlotIsFree on purpose"
}

ex_drop_coverage() {
  [ ! -e "$UNTESTED" ] || die "drop-coverage is already applied. Run: scripts/demo.sh restore"
  cat > "$UNTESTED" <<'JAVA'
package ar.edu.utn.frc.turnos.service;

/** Demo: a feature added without tests. It drags line coverage below the 80% gate. */
public class CancellationFeePolicy {

    public int feeInCents(int hoursBeforeSlot, boolean premiumPatient) {
        if (premiumPatient) {
            return 0;
        }
        if (hoursBeforeSlot >= 48) {
            return 0;
        }
        if (hoursBeforeSlot >= 24) {
            return 500;
        }
        if (hoursBeforeSlot >= 2) {
            return 1500;
        }
        return 3000;
    }

    public String describe(int hoursBeforeSlot, boolean premiumPatient) {
        int fee = feeInCents(hoursBeforeSlot, premiumPatient);
        if (fee == 0) {
            return "Free cancellation";
        }
        if (fee < 1000) {
            return "Small fee: " + fee / 100 + " USD";
        }
        return "Cancellation fee: " + fee / 100 + " USD";
    }

    public boolean isFree(int hoursBeforeSlot, boolean premiumPatient) {
        return feeInCents(hoursBeforeSlot, premiumPatient) == 0;
    }
}
JAVA
  commit drop-coverage "feat(demo): add cancellation fee policy without tests"
}

ex_pmd_violation() {
  ! grep -q 'System.out.println' "$SERVICE" || die "pmd-violation is already applied. Run: scripts/demo.sh restore"
  sed -i '/public List<Appointment> findAll() {/a\        System.out.println("findAll called");' "$SERVICE"
  git diff --quiet -- "$SERVICE" && die "pmd-violation patch did not apply: the service file changed."
  commit pmd-violation "chore(demo): add a debug println to findAll"
}

case "${1:-}" in
  trivial-change|new-version|break-test|drop-coverage|pmd-violation)
    require_clean_main
    "ex_$(echo "$1" | tr - _)" ;;
  status)  cmd_status ;;
  fix)     require_clean_main; cmd_fix ;;
  restore) shift; cmd_restore "$@" ;;
  baseline) cmd_baseline ;;
  -h|--help|help) usage 0 ;;
  *) usage 1 ;;
esac
