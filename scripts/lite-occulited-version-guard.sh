#!/bin/sh
# openccu-lite: occulited in the image is the pinned commit.
#
# occulited's version is the commit it was built from (occulited task 16, which took back task 9's
# image version): package/occulited/occulited.mk passes its pin, OCCULITED_VERSION, to the binary as
# both main.version and main.commit. A warm tree that kept the binary of an earlier pin - a bump whose
# package was never rebuilt - would ship that one under the new pin's name, and nothing else fails.
#
# The check: the pin is a commit, the binary is in the image, and it carries that commit.
#
# Usage: scripts/lite-occulited-version-guard.sh <target root> <occulited.mk>
#        exit 1 with one line per finding
set -u

ROOT=${1:?usage: lite-occulited-version-guard.sh <target root> <occulited.mk>}
MK=${2:?usage: lite-occulited-version-guard.sh <target root> <occulited.mk>}

[ -f "$MK" ] || { echo "lite-occulited-version-guard: ERROR: no $MK" >&2; exit 1; }
COMMIT=$(sed -n 's/^OCCULITED_VERSION *= *//p' "$MK")
BIN="$ROOT/usr/bin/occulited"

bad=0
err() { echo "lite-occulited-version-guard: ERROR: $*" >&2; bad=1; }

case "$COMMIT" in
	*[!0-9a-f]*|"") err "OCCULITED_VERSION in $MK is not a commit: '$COMMIT'" ;;
esac
if [ ! -f "$BIN" ]; then
	err "/usr/bin/occulited is not in the image"
elif [ -n "$COMMIT" ] && ! grep -aqF "$COMMIT" "$BIN"; then
	err "/usr/bin/occulited does not carry the pinned commit $COMMIT: built from another pin?"
fi
exit "$bad"
