#!/bin/sh
# openccu-lite (task 325): the U-Boot boot script in images/ must be the product's boot.cmd.
#
# buildroot's host-uboot-tools runs mkimage over BR2_PACKAGE_HOST_UBOOT_TOOLS_BOOT_SCRIPT_SOURCE
# (board/<board>/boot.cmd) in its build step and installs the result as images/boot.scr. A warm
# tree never reruns that step for a changed boot.cmd: the first dev.39 images carried the old
# boot.scr (with rootdelay) although the commit had removed it. The boot partition takes
# images/boot.scr as it is (genimage.cfg), so a stale one ships unnoticed.
#
# boot.scr is a legacy U-Boot image of type "script": a 64-byte header (magic 27 05 19 56, the
# type byte 6 at offset 30), then the length table - the script's length as a big-endian 32-bit
# word and a zero word - and then the script itself, byte for byte. The check takes that script
# out of boot.scr and compares it with boot.cmd.
#
# Usage: scripts/lite-bootscr-check.sh [--guard] <buildroot output dir> [<br2-external dir>]
#   <br2-external dir> replaces $(BR2_EXTERNAL_EQ3_PATH) in the .config's source path; default
#   $BR2_EXTERNAL_EQ3_PATH, else this checkout's buildroot-external.
#   Without --guard (the Makefile's prepare step, before the build):
#     exit 0  nothing to do - no boot script configured, host-uboot-tools not built yet (the build
#             makes boot.scr from the current boot.cmd), or boot.scr is boot.cmd
#     exit 10 stale - host-uboot-tools is built and boot.scr is missing or not boot.cmd: run
#             `make -C <output dir> host-uboot-tools-rebuild` before the build
#   With --guard (the lite post-build, after host-uboot-tools ran): exit 1 unless boot.scr is
#   there and is boot.cmd.
#   exit 2 on a usage error or an unreadable .config / boot.cmd.
set -u

guard=0
if [ "${1:-}" = --guard ]; then guard=1; shift; fi
OUT=${1:-}
[ -n "$OUT" ] || { echo "usage: lite-bootscr-check.sh [--guard] <output dir> [<br2-external dir>]" >&2; exit 2; }
EXT=${2:-${BR2_EXTERNAL_EQ3_PATH:-$(cd "$(dirname "$0")/.." && pwd)/buildroot-external}}
CONFIG="$OUT/.config"
SCR="$OUT/images/boot.scr"
me=lite-bootscr-check

[ -r "$CONFIG" ] || { echo "$me: ERROR: no $CONFIG" >&2; exit 2; }
grep -q '^BR2_PACKAGE_HOST_UBOOT_TOOLS_BOOT_SCRIPT=y$' "$CONFIG" || exit 0

src=$(sed -n 's/^BR2_PACKAGE_HOST_UBOOT_TOOLS_BOOT_SCRIPT_SOURCE="\(.*\)"$/\1/p' "$CONFIG")
# shellcheck disable=SC2016 # the literal make variable as .config spells it
src=$(printf '%s\n' "$src" | sed 's|\$(BR2_EXTERNAL_EQ3_PATH)|'"$EXT"'|g')
case "$src" in
  /*) ;;
  *) echo "$me: ERROR: the boot script source '$src' in $CONFIG is not an absolute path" >&2; exit 2 ;;
esac
[ -r "$src" ] || { echo "$me: ERROR: the boot script source $src is not readable" >&2; exit 2; }

stale() {
  if [ "$guard" = 1 ]; then
    echo "$me: ERROR: $SCR $1 - run 'make -C $OUT host-uboot-tools-rebuild' and build again" >&2
    exit 1
  fi
  echo "$me: $SCR $1: host-uboot-tools must be rebuilt"
  exit 10
}

if [ "$guard" = 0 ]; then
  # not built yet: the build's own host-uboot-tools step makes boot.scr from the current boot.cmd
  built=0
  for s in "$OUT"/build/host-uboot-tools-*/.stamp_built; do
    [ -e "$s" ] && built=1
  done
  [ "$built" = 1 ] || exit 0
fi

[ -f "$SCR" ] || stale "is missing (source $src)"

# bytes <offset> <count>: the bytes of boot.scr as lower-case hex, no spaces
bytes() { od -A n -t x1 -j "$1" -N "$2" "$SCR" | tr -d ' \n'; }
[ "$(bytes 0 4)" = 27051956 ] || stale "is not a U-Boot image (source $src)"
[ "$(bytes 30 1)" = 06 ] || stale "is not a U-Boot script image (source $src)"
len=$(od -A n -t u1 -j 64 -N 4 "$SCR" | awk '{ print ($1 * 16777216) + ($2 * 65536) + ($3 * 256) + $4 }')
[ -n "$len" ] || stale "has no length table (source $src)"
want=$(wc -c < "$src" | tr -d ' ')
[ "$len" = "$want" ] || stale "holds a script of $len bytes, $src has $want"
tail -c +73 "$SCR" | head -c "$len" | cmp -s - "$src" || stale "differs from $src"
[ "$guard" = 1 ] && echo "$me: $SCR is $src"
exit 0
