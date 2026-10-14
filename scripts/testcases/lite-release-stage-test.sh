#!/bin/sh
# openccu-lite (B-306): lite-release-github.sh removes the STAGE directory it made, however it ends;
# one the caller names stays. Every release used to leave its staged SBOMs, API documents and
# SHA256SUMS (a few MB) in the runner's /tmp. The script runs with TMPDIR pointing at a directory
# of the test's own:
#   - a bad commit argument (it fails right after making STAGE): rc 1, TMPDIR empty;
#   - a run that fails while staging (a build tree without the product's files): rc != 0 after the
#     staging began, TMPDIR empty;
#   - STAGE given: the directory and what the run wrote into it are kept.
#
# Usage: sh scripts/testcases/lite-release-stage-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S="$HERE/scripts/lite-release-github.sh"
[ -f "$S" ] || { echo "lite-release-github.sh not found at $S"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
left() { find "$T/tmp" -mindepth 1 -maxdepth 1 2>/dev/null | head -5; }

# a commit with what the script reads from it, and a build tree at that commit without products
g() { git -c user.name=t -c user.email=t@example.org -c init.defaultBranch=lite "$@"; }
mkdir -p "$T/tmp" "$T/repo/buildroot-external/package/occulited"
printf 'VERSION=1.0.0-test\nBASE=3.89.11\n' >"$T/repo/LITE-VERSION"
printf 'OCCULITED_VERSION = 0123456789abcdef0123456789abcdef01234567\n' >"$T/repo/buildroot-external/package/occulited/occulited.mk"
g -C "$T/repo" init -q && g -C "$T/repo" add -A && g -C "$T/repo" commit -qm test || { echo "git setup failed"; exit 2; }
SHA=$(git -C "$T/repo" rev-parse HEAD)
g clone -q "$T/repo" "$T/tree" || { echo "git clone failed"; exit 2; }

run() { # [env…]: runs the script's dry run in the commit's repository; $rc, $out
  out=$(cd "$T/repo" && env -u STAGE TMPDIR="$T/tmp" TREE="$T/tree" PRODUCTS=x86_64-ova "$@" bash "$S" --dry-run 1.0.0-test "${SHA_ARG:-$SHA}" 2>&1)
  rc=$?
}

SHA_ARG=nosha run
[ "$rc" = 1 ] && ok "a bad commit: rc 1" || bad "a bad commit: rc $rc: $out"
printf '%s\n' "$out" | grep -q "is not a full sha" && ok "and it says why" || bad "no 'is not a full sha' in: $out"
[ -z "$(left)" ] && ok "and its STAGE is gone" || bad "STAGE left behind: $(left)"

SHA_ARG='' run
[ "$rc" != 0 ] && ok "a failure while staging: rc $rc" || bad "a build tree without products passed: $out"
printf '%s\n' "$out" | grep -q "release v1.0.0-test from $SHA" && ok "and the staging had begun" || bad "the run ended before the staging: $out"
[ -z "$(left)" ] && ok "and its STAGE is gone" || bad "STAGE left behind: $(left)"

mkdir -p "$T/keep"
SHA_ARG='' run STAGE="$T/keep"
[ -f "$T/keep/assets" ] && ok "a STAGE given is kept, with what the run wrote" || bad "the given STAGE lost its files: $(ls -A "$T/keep")"
[ -z "$(left)" ] && ok "and nothing went to TMPDIR" || bad "TMPDIR got: $(left)"

[ "$fails" = 0 ] && echo "all ok" || echo "$fails failed"
[ "$fails" = 0 ]
