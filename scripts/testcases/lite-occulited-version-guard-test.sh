#!/bin/sh
# openccu-lite: scripts/lite-occulited-version-guard.sh against fake image roots and package files -
# the image's occulited must carry the pinned commit (its version since occulited task 16); a binary
# of another pin, a pin that is no commit and an image without occulited fail.
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
mk() { printf 'OCCULITED_VERSION = %s\nOCCULITED_SITE = x\n' "$1" > "$T/occulited.mk"; }
# the binary's strings as -X leaves them: the version and the commit, among other bytes
bin() { mkdir -p "$T/root/usr/bin"; printf '\177ELF\0\0%s\0%s\0occulited\0' "$1" "$1" > "$T/root/usr/bin/occulited"; }
run() { sh "$GUARD" "$T/root" "$T/occulited.mk" > "$T/out" 2>&1; }

# the real package file: a commit, no release line (occulited task 16), the commit as the version
real="$HERE/buildroot-external/package/occulited/occulited.mk"
if grep -qE '^OCCULITED_VERSION = [0-9a-f]{40}$' "$real" && ! grep -q '^OCCULITED_RELEASE' "$real" \
	&& grep -q 'main.version=$(OCCULITED_VERSION)' "$real"; then ok "the package pins a commit and builds it as the version"; else fail "the package file: $(grep 'OCCULITED_' "$real")"; fi

rm -rf "$T/root"; mk "$PIN"; bin "$PIN"
if run; then ok "a binary of the pinned commit passes"; else fail "matching binary: $(cat "$T/out")"; fi

rm -rf "$T/root"; mk "$PIN"; bin eb512490cd2786afa2dc2b91796344a953f6e2c8
if ! run && grep -q "does not carry the pinned commit $PIN" "$T/out"; then ok "a binary of another pin fails"; else fail "other binary: $(cat "$T/out")"; fi

rm -rf "$T/root"; mk 1.0.0-dev.40; bin 1.0.0-dev.40
if ! run && grep -q "is not a commit: '1.0.0-dev.40'" "$T/out"; then ok "a pin that is no commit fails"; else fail "no commit: $(cat "$T/out")"; fi

rm -rf "$T/root"; mk "$PIN"
if ! run && grep -q "not in the image" "$T/out"; then ok "an image without occulited fails"; else fail "no binary: $(cat "$T/out")"; fi

[ "$fails" -eq 0 ] && echo "all ok" || echo "$fails failed"
exit "$fails"
