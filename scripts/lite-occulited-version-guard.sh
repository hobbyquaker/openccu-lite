#!/bin/sh
# openccu-lite: occulited in the image reports the version of the image it was built for.
#
# occulited is versioned like the image (occulited task 9): every build round tags occulited's pinned
# commit with the image version (v1.0.0-dev.38) and sets OCCULITED_RELEASE in
# package/occulited/occulited.mk to it, beside the commit (OCCULITED_VERSION); the package passes
# both to the binary (-X main.version, -X main.commit). Nothing else ties the two together: a round
# that bumps LITE_VERSION and forgets the pin's release builds an image whose occulited names the
# previous round, and nothing fails.
#
# The check:
#   - the binary carries the pinned commit (main.commit; main.version for a pin without a release);
#   - with a release in the pin, the binary carries it;
#   - in a build round - LITE_VERSION given and not LITE-VERSION's bare VERSION, which is what a
#     build without LITE_VERSION= (CI's) gets - the release must be the image version.
#
# Usage: scripts/lite-occulited-version-guard.sh <target root> <occulited.mk> [<LITE_VERSION> <LITE-VERSION's VERSION>]
#        exit 1 with one line per finding
set -u

ROOT=${1:?usage: lite-occulited-version-guard.sh <target root> <occulited.mk> [<lite version> <default version>]}
MK=${2:?usage: lite-occulited-version-guard.sh <target root> <occulited.mk> [<lite version> <default version>]}
LITE=${3:-}
DEFAULT=${4:-}

[ -f "$MK" ] || { echo "lite-occulited-version-guard: ERROR: no $MK" >&2; exit 1; }
COMMIT=$(sed -n 's/^OCCULITED_VERSION *= *//p' "$MK")
RELEASE=$(sed -n 's/^OCCULITED_RELEASE *= *//p' "$MK")
BIN="$ROOT/usr/bin/occulited"

bad=0
err() { echo "lite-occulited-version-guard: ERROR: $*" >&2; bad=1; }

case "$COMMIT" in
	*[!0-9a-f]*|"") err "OCCULITED_VERSION in $MK is not a commit: '$COMMIT'" ;;
esac
case "$RELEASE" in
	"") ;;
	v*) err "OCCULITED_RELEASE is the version without the tag's v: '$RELEASE'" ;;
	*[!0-9A-Za-z.-]*) err "OCCULITED_RELEASE is not a version: '$RELEASE'" ;;
esac
if [ ! -f "$BIN" ]; then
	err "/usr/bin/occulited is not in the image"
else
	[ -z "$COMMIT" ] || grep -aqF "$COMMIT" "$BIN" || err "/usr/bin/occulited does not carry the pinned commit $COMMIT: built from another pin?"
	[ -z "$RELEASE" ] || grep -aqF "$RELEASE" "$BIN" || err "/usr/bin/occulited does not carry the pin's release $RELEASE"
fi
if [ -n "$LITE" ] && [ "$LITE" != "$DEFAULT" ] && [ "$RELEASE" != "$LITE" ]; then
	err "this round builds $LITE, but occulited's pin says ${RELEASE:-no release}: tag occulited's pinned commit $COMMIT v$LITE and set OCCULITED_RELEASE = $LITE in $MK"
fi
exit "$bad"
