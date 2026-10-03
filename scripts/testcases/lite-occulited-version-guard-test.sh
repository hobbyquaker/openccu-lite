#!/bin/sh
# openccu-lite: scripts/lite-occulited-version-guard.sh against fake image roots and package files -
# a build round whose occulited pin carries another release than the image version, or none, must
# fail; a round that matches, a build outside a round and a binary of another pin are told apart.
#
# Usage: sh scripts/testcases/lite-occulited-version-guard-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
GUARD="$HERE/scripts/lite-occulited-version-guard.sh"
[ -f "$GUARD" ] || { echo "lite-occulited-version-guard.sh not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

PIN=fa42dfde1e31fb074df53220dd573ceb92642ff0
mk() { printf 'OCCULITED_VERSION = %s\nOCCULITED_RELEASE =%s\nOCCULITED_SITE = x\n' "$1" "${2:+ $2}" > "$T/occulited.mk"; }
# the binary's strings as -X leaves them: the version, the commit, among other bytes
bin() { mkdir -p "$T/root/usr/bin"; printf '\177ELF\0\0%s\0%s\0occulited\0' "$1" "$2" > "$T/root/usr/bin/occulited"; }
run() { sh "$GUARD" "$T/root" "$T/occulited.mk" "$@" > "$T/out" 2>&1; }

# the real package file parses: a commit, and the release line is there
real="$HERE/buildroot-external/package/occulited/occulited.mk"
if grep -qE '^OCCULITED_VERSION = [0-9a-f]{40}$' "$real" && grep -qE '^OCCULITED_RELEASE =' "$real"; then ok "the package names a commit and a release line"; else fail "the package file: $(grep '^OCCULITED_' "$real")"; fi

rm -rf "$T/root"; mk "$PIN" 1.0.0-dev.38; bin 1.0.0-dev.38 "$PIN"
if run 1.0.0-dev.38 1.0.0-dev; then ok "a round whose pin carries its version passes"; else fail "matching round: $(cat "$T/out")"; fi

if run 1.0.0-dev 1.0.0-dev && run; then ok "a build outside a round (LITE-VERSION's bare version, or none) passes"; else fail "no round: $(cat "$T/out")"; fi

if ! run 1.0.0-dev.39 1.0.0-dev && grep -q "builds 1.0.0-dev.39, but occulited's pin says 1.0.0-dev.38" "$T/out"; then ok "a round with the previous round's release fails, named"; else fail "stale release: $(cat "$T/out")"; fi

rm -rf "$T/root"; mk "$PIN" ""; bin "$PIN" "$PIN"
if ! run 1.0.0-dev.38 1.0.0-dev && grep -q "says no release: tag occulited's pinned commit $PIN v1.0.0-dev.38" "$T/out"; then ok "a round with an untagged pin fails and says what to do"; else fail "no release in a round: $(cat "$T/out")"; fi
if run 1.0.0-dev 1.0.0-dev; then ok "an untagged pin outside a round passes (the commit is the version)"; else fail "untagged, no round: $(cat "$T/out")"; fi

rm -rf "$T/root"; mk "$PIN" 1.0.0-dev.38; bin 1.0.0-dev.37 eb512490cd2786afa2dc2b91796344a953f6e2c8
if ! run 1.0.0-dev.38 1.0.0-dev && grep -q "does not carry the pinned commit $PIN" "$T/out" && grep -q "does not carry the pin's release 1.0.0-dev.38" "$T/out"; then ok "a binary of another pin fails"; else fail "other binary: $(cat "$T/out")"; fi

rm -rf "$T/root"; mk "$PIN" v1.0.0-dev.38; bin v1.0.0-dev.38 "$PIN"
if ! run && grep -q "without the tag's v" "$T/out"; then ok "a release written as the tag fails"; else fail "v prefix: $(cat "$T/out")"; fi

rm -rf "$T/root"; mk "$PIN" 1.0.0-dev.38
if ! run && grep -q "not in the image" "$T/out"; then ok "an image without occulited fails"; else fail "no binary: $(cat "$T/out")"; fi

[ "$fails" -eq 0 ] && echo "all ok" || echo "$fails failed"
exit "$fails"
