#!/bin/sh
# openccu-lite: scripts/lite-upstream-merge.sh on a made-up fork. An "upstream" history and a
# "lite" branch that removed upstream paths and rewrote some as its own (with the real
# scripts/lite-upstream-paths.txt); then an upstream commit that changes a removed file
# (modify/delete), adds a workflow and an issue form, edits CONTRIBUTING.md, changes a product
# config lite keeps and makes one real conflict. After `git merge --no-commit` and the script:
# the removed paths are gone again, lite's own files are lite's, upstream's other changes are in,
# only the real conflict is left, and --check agrees. Then the fork itself must pass --check.
#
# Usage: sh scripts/testcases/lite-upstream-merge-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$HERE/scripts/lite-upstream-merge.sh"
PATHS="$HERE/scripts/lite-upstream-paths.txt"
[ -f "$HELPER" ] && [ -f "$PATHS" ] || { echo "lite-upstream-merge.sh or its list not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
R="$T/repo"
g() { git -C "$R" "$@"; }
put() { mkdir -p "$(dirname "$R/$1")"; printf '%s\n' "$2" > "$R/$1"; }

mkdir -p "$R" && git init -q -b upstream "$R" || exit 2
put keep.txt 'line one'
put CONTRIBUTING.md 'upstream contributing'
put .github/ISSUE_TEMPLATE/bug-report.yml 'name: upstream bug'
put .github/workflows/ci.yml 'name: ci'
put .github/FUNDING.yml 'ko_fi: someone'
put home-assistant-addon/config.yaml 'version: 1'
put buildroot-external/configs/oci_amd64.config 'BR2_X=1'
put buildroot-external/configs/rpi3.config 'BR2_X=1'
put buildroot-external/overlay/base-openccu_oci/etc/fstab 'oci fstab'
put DEVELOPMENT.md 'upstream dev guide'
g add -A && g commit -q -m 'upstream 1' || exit 2

# lite: the list's removals, its own files, the helper
g checkout -q -b lite
g rm -r -q home-assistant-addon .github/workflows/ci.yml .github/FUNDING.yml DEVELOPMENT.md \
  buildroot-external/configs/oci_amd64.config buildroot-external/overlay/base-openccu_oci
put CONTRIBUTING.md 'lite contributing'
put .github/ISSUE_TEMPLATE/bug-report.yml 'name: lite bug'
put .github/workflows/lite-check.yml 'name: lite-check'
put keep.txt 'line one, lite'
mkdir -p "$R/scripts" && cp "$HELPER" "$PATHS" "$R/scripts/" || exit 2
g add -A && g commit -q -m 'lite' || exit 2

# upstream moves on
g checkout -q upstream
put home-assistant-addon/config.yaml 'version: 2'
put .github/workflows/ci.yml 'name: ci 2'
put .github/workflows/stale.yml 'name: stale'
put .github/ISSUE_TEMPLATE/question.yml 'name: question'
put .github/ISSUE_TEMPLATE/bug-report.yml 'name: upstream bug 2'
put CONTRIBUTING.md 'upstream contributing 2'
put buildroot-external/configs/oci_amd64.config 'BR2_X=2'
put buildroot-external/configs/rpi3.config 'BR2_X=2'
put buildroot-external/overlay/base-openccu_oci/etc/inittab 'new oci file'
put keep.txt 'line one, upstream'
put newfile.txt 'upstream adds this'
g add -A && g commit -q -m 'upstream 2' || exit 2
g tag up2

g checkout -q lite
g merge -q --no-commit up2 >/dev/null 2>&1
[ -n "$(g diff --name-only --diff-filter=U)" ] && ok "the merge stops with conflicts" || fail "the merge did not conflict"

sh "$R/scripts/lite-upstream-merge.sh" > "$T/out" 2>&1; rc=$?
[ $rc -eq 0 ] && ok "the script runs ($(head -1 "$T/out"))" || { fail "the script failed ($rc)"; cat "$T/out"; }

for p in home-assistant-addon/config.yaml .github/workflows/ci.yml .github/workflows/stale.yml \
  .github/FUNDING.yml DEVELOPMENT.md buildroot-external/configs/oci_amd64.config \
  buildroot-external/overlay/base-openccu_oci/etc/inittab .github/ISSUE_TEMPLATE/question.yml; do
  if [ -n "$(g ls-files -- "$p")" ] || [ -e "$R/$p" ]; then fail "$p is back"; else ok "$p stays removed"; fi
done
[ -f "$R/.github/workflows/lite-check.yml" ] && ok "lite's own workflow stays" || fail "lite-check.yml was removed"
[ "$(cat "$R/CONTRIBUTING.md")" = 'lite contributing' ] && ok "CONTRIBUTING.md is lite's" || fail "CONTRIBUTING.md: $(cat "$R/CONTRIBUTING.md")"
[ "$(cat "$R/.github/ISSUE_TEMPLATE/bug-report.yml")" = 'name: lite bug' ] && ok "the bug form is lite's" \
  || fail "bug-report.yml: $(cat "$R/.github/ISSUE_TEMPLATE/bug-report.yml")"
[ "$(cat "$R/buildroot-external/configs/rpi3.config")" = 'BR2_X=2' ] && ok "upstream's change to a kept product is in" \
  || fail "rpi3.config lost upstream's change"
[ -f "$R/newfile.txt" ] && ok "upstream's new file elsewhere is in" || fail "newfile.txt is missing"
[ "$(g diff --name-only --diff-filter=U)" = keep.txt ] && ok "only the real conflict is left" \
  || fail "conflicts left: $(g diff --name-only --diff-filter=U | tr '\n' ' ')"
grep -q '^  keep.txt$' "$T/out" && ok "the script names the conflict" || { fail "keep.txt not named"; cat "$T/out"; }

if sh "$R/scripts/lite-upstream-merge.sh" --check > "$T/out" 2>&1; then fail "--check passes with a conflict left"
else ok "--check fails while a conflict is left"; fi
put keep.txt 'line one, both'
g add keep.txt
if sh "$R/scripts/lite-upstream-merge.sh" --check > "$T/out" 2>&1; then ok "--check passes once it is resolved"
else fail "--check fails after the resolution:"; cat "$T/out"; fi
g commit -q -m 'merge up2' && ok "the merge commits" || fail "the merge does not commit"

# --check catches a merge committed without the script
g checkout -q -b plain lite~1
g merge -q -X theirs --no-edit up2 >/dev/null 2>&1
g add -A >/dev/null 2>&1; g commit -q -m 'merged blindly' >/dev/null 2>&1
if sh "$R/scripts/lite-upstream-merge.sh" --check > "$T/out" 2>&1; then fail "--check passes a blind merge"
else grep -q 'home-assistant-addon/config.yaml' "$T/out" && ok "--check names what a blind merge brought back" \
  || { fail "--check output:"; cat "$T/out"; }; fi

# the fork itself
if sh "$HELPER" --check > "$T/out" 2>&1; then ok "the fork carries none of the removed paths"
else fail "the fork fails --check:"; cat "$T/out"; fi

[ $fails -eq 0 ] && echo "lite-upstream-merge-test: all passed" || echo "lite-upstream-merge-test: $fails failed"
[ $fails -eq 0 ]
