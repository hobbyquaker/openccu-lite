#!/bin/sh
# openccu-lite (task 325): scripts/lite-bootscr-check.sh against fake buildroot output dirs - a
# boot.scr made from another boot.cmd than the product's (the first dev.39 images, which kept
# rootdelay) is found before the build, so the Makefile rebuilds host-uboot-tools, and stops the
# lite post-build; a current one, a tree that has not built host-uboot-tools yet and a product
# without a boot script pass. Also the wiring: the Makefile's build step and the post-build call it,
# and every lite product's boot script source exists.
#
# Usage: sh scripts/testcases/lite-bootscr-check-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
CHECK="$HERE/scripts/lite-bootscr-check.sh"
[ -f "$CHECK" ] || { echo "lite-bootscr-check.sh not found under $HERE"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is needed to make the fake boot.scr"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# mkscr <script> <boot.scr> [type]: a legacy U-Boot image as mkimage -T script writes it - the
# 64-byte header (magic, data size, os/arch/type/comp), the length table, the script
mkscr() {
  python3 - "$1" "$2" "${3:-6}" <<'PY'
import struct, sys
body = open(sys.argv[1], 'rb').read()
data = struct.pack('>II', len(body), 0) + body
hdr = struct.pack('>IIIIIII4B32s', 0x27051956, 0, 0, len(data), 0, 0, 0, 5, 0x16, int(sys.argv[3]), 0, b'')
open(sys.argv[2], 'wb').write(hdr + data)
PY
}

EXT="$T/external"
OUT="$T/build-aarch64-rpi3"
cmd="$EXT/board/rpi3/boot.cmd"
# tree <with boot script: 1|0> <host-uboot-tools built: 1|0>
tree() {
  rm -rf "$EXT" "$OUT"; mkdir -p "$EXT/board/rpi3" "$OUT/images" "$OUT/build/host-uboot-tools-2026.04"
  printf '%s\n' '# modify bootargs' 'setenv bootargs "root=/dev/mmcblk0p2 rootwait consoleblank=0"' 'booti ${kernel_addr_r} - ${fdt_addr}' > "$cmd"
  {
    echo 'BR2_PACKAGE_HOST_UBOOT_TOOLS=y'
    if [ "$1" = 1 ]; then
      echo 'BR2_PACKAGE_HOST_UBOOT_TOOLS_BOOT_SCRIPT=y'
      # shellcheck disable=SC2016 # the make variable, literally, as buildroot's .config holds it
      echo 'BR2_PACKAGE_HOST_UBOOT_TOOLS_BOOT_SCRIPT_SOURCE="$(BR2_EXTERNAL_EQ3_PATH)/board/rpi3/boot.cmd"'
    fi
  } > "$OUT/.config"
  [ "$2" = 1 ] && : > "$OUT/build/host-uboot-tools-2026.04/.stamp_built"
  return 0
}
prep()  { sh "$CHECK" "$OUT" "$EXT" > "$T/out" 2>&1; }
guard() { BR2_EXTERNAL_EQ3_PATH="$EXT" sh "$CHECK" --guard "$OUT" > "$T/out" 2>&1; }
rc() { "$@"; echo $?; }

tree 0 1
[ "$(rc prep)" = 0 ] && [ "$(rc guard)" = 0 ] && ok "a product without a boot script (the ova) passes both" || fail "no boot script: $(cat "$T/out")"

tree 1 0
[ "$(rc prep)" = 0 ] && ok "prepare: host-uboot-tools not built yet - the build makes boot.scr" || fail "not built: $(cat "$T/out")"
[ "$(rc guard)" = 1 ] && grep -q 'is missing' "$T/out" && ok "guard: no boot.scr after the build fails" || fail "guard without boot.scr: $(cat "$T/out")"

tree 1 1; mkscr "$cmd" "$OUT/images/boot.scr"
[ "$(rc prep)" = 0 ] && [ "$(rc guard)" = 0 ] && ok "boot.scr made from the current boot.cmd passes both" || fail "current: $(cat "$T/out")"

# the dev.39 case: boot.scr from the old boot.cmd, the new one without rootdelay
tree 1 1
sed 's/rootwait/rootdelay=5 rootwait/' "$cmd" > "$T/old.cmd"; mkscr "$T/old.cmd" "$OUT/images/boot.scr"
[ "$(rc prep)" = 10 ] && grep -q 'host-uboot-tools must be rebuilt' "$T/out" && ok "prepare: boot.scr of an older boot.cmd is stale (exit 10)" || fail "older boot.cmd, prepare: $(cat "$T/out")"
[ "$(rc guard)" = 1 ] && grep -q 'host-uboot-tools-rebuild' "$T/out" && ok "guard: boot.scr of an older boot.cmd fails the post-build" || fail "older boot.cmd, guard: $(cat "$T/out")"

tree 1 1
sed 's/rootwait/rootWAIT/' "$cmd" > "$T/same-length.cmd"; mkscr "$T/same-length.cmd" "$OUT/images/boot.scr"
[ "$(rc prep)" = 10 ] && grep -q 'differs from' "$T/out" && ok "a script of the same length with other bytes is stale" || fail "same length: $(cat "$T/out")"

tree 1 1
[ "$(rc prep)" = 10 ] && grep -q 'is missing' "$T/out" && ok "prepare: host-uboot-tools built but boot.scr gone is stale" || fail "boot.scr gone: $(cat "$T/out")"

tree 1 1; echo 'not an image' > "$OUT/images/boot.scr"
[ "$(rc prep)" = 10 ] && grep -q 'not a U-Boot image' "$T/out" && ok "a boot.scr that is no U-Boot image is stale" || fail "garbage: $(cat "$T/out")"

tree 1 1; mkscr "$cmd" "$OUT/images/boot.scr" 2
[ "$(rc prep)" = 10 ] && grep -q 'not a U-Boot script image' "$T/out" && ok "a U-Boot image of another type (a kernel) is stale" || fail "other type: $(cat "$T/out")"

tree 1 1; mkscr "$cmd" "$OUT/images/boot.scr"; printf 'setenv x y\n' >> "$OUT/images/boot.scr"
[ "$(rc prep)" = 0 ] && ok "bytes after the script (mkimage's padding) are not compared" || fail "trailing bytes: $(cat "$T/out")"

tree 1 1; mkscr "$cmd" "$OUT/images/boot.scr"; rm -f "$cmd"
[ "$(rc prep)" = 2 ] && grep -q 'not readable' "$T/out" && ok "a missing boot.cmd is an error (exit 2), not a pass" || fail "no boot.cmd: $(cat "$T/out")"

tree 1 1; mkscr "$cmd" "$OUT/images/boot.scr"; rm -f "$OUT/.config"
[ "$(rc prep)" = 2 ] && ok "a tree without .config is an error (exit 2)" || fail "no .config: $(cat "$T/out")"

# with mkimage on the host (the runner has u-boot-tools): its own output is understood
if command -v mkimage >/dev/null 2>&1; then
  tree 1 1
  if mkimage -C none -A arm64 -T script -d "$cmd" "$OUT/images/boot.scr" >/dev/null 2>&1; then
    [ "$(rc prep)" = 0 ] && ok "mkimage's own boot.scr of boot.cmd passes" || fail "mkimage, current: $(cat "$T/out")"
    echo 'setenv rootdelay 5' >> "$cmd"
    [ "$(rc prep)" = 10 ] && ok "mkimage's boot.scr of an older boot.cmd is stale" || fail "mkimage, older: $(cat "$T/out")"
  else
    fail "mkimage could not make a script image"
  fi
else
  echo "skip mkimage is not installed here (u-boot-tools): the real-format cases run on the runner"
fi

# the wiring
mk="$HERE/Makefile"
if grep -q 'lite-bootscr-check.sh' "$mk" && grep -q 'host-uboot-tools-rebuild' "$mk" \
  && awk '/^build:/{b=1} b && /lite-bootscr-check/{c=NR} b && /PRODUCT_PLATFORM=\$\(PLATFORM\)$/{if (c) {print "ok"; exit}}' "$mk" | grep -q ok; then
  ok "the Makefile's build step checks boot.scr and rebuilds host-uboot-tools before the build"
else
  fail "the Makefile does not run lite-bootscr-check.sh before the buildroot build"
fi
grep -q 'lite-bootscr-check.sh" --guard "${BASE_DIR}"' "$HERE/buildroot-external/board/lite/post-build.sh" \
  && ok "the lite post-build guards boot.scr" || fail "board/lite/post-build.sh does not call lite-bootscr-check.sh --guard"
[ -x "$CHECK" ] && ok "lite-bootscr-check.sh is executable (the post-build runs it directly)" || fail "lite-bootscr-check.sh is not executable"

# every lite product with a boot script names a boot.cmd that exists in this checkout
for c in "$HERE"/buildroot-external/configs/aarch64-*.config "$HERE"/buildroot-external/configs/x86_64-*.config; do
  [ -f "$c" ] || continue
  s=$(sed -n 's/^BR2_PACKAGE_HOST_UBOOT_TOOLS_BOOT_SCRIPT_SOURCE="\(.*\)"$/\1/p' "$c")
  [ -n "$s" ] || continue
  # shellcheck disable=SC2016 # the literal make variable
  f=$(printf '%s\n' "$s" | sed 's|\$(BR2_EXTERNAL_EQ3_PATH)|'"$HERE"'/buildroot-external|')
  [ -f "$f" ] && ok "$(basename "$c" .config): boot script source ${f#"$HERE"/} exists" || fail "$(basename "$c" .config): $s does not exist"
done

[ "$fails" -eq 0 ] && echo "all ok" || echo "$fails failed"
exit "$fails"
