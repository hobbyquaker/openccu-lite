#!/bin/sh
# shellcheck disable=SC2016 # make variables and the stubs' own $1, literally
# openccu-lite (task 366): the Pi 4/5 bootloader EEPROM update is offered, never flashed by itself.
# The boards' post-image.sh runs in a sandbox (genimage and mkfs.ext4 replaced by stubs that keep
# what they were given): with BR2_PACKAGE_RPI_EEPROM_OFFER=y the genimage config it hands over
# names no rpi-eeprom file - nothing for the boot ROM in the boot partition - and without it the
# board's genimage.cfg goes as it is (upstream's products). Also the wiring: both lite Pi 4/5
# products set the option, the package installs the files under /usr/share/rpi-eeprom/firmware-<chip>/
# exactly when it is set, and rpi-eeprom-info reads the offered image when /boot has none.
# Task 394: every file from the default channel, the update script's choice of it, and
# rpi-eeprom-info's "update available" only for an image newer than the running bootloader.
#
# Usage: sh scripts/testcases/lite-rpi-eeprom-offer-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$HERE/buildroot-external"
[ -d "$EXT/package/rpi-eeprom" ] || { echo "the rpi-eeprom package is not under $EXT"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# run_post_image <board> <offer: y|n>: the board's post-image.sh with stubs; the config genimage got
# ends up in $T/<board>-<offer>.cfg
run_post_image() {
  board=$1 offer=$2 sb="$T/sb-$1-$2"
  mkdir -p "$sb/support/scripts" "$sb/host/sbin" "$sb/images/overlays" "$sb/target/boot" "$sb/build"
  printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -c ] && cp "$2" "%s"; shift; done\n' "$T/$board-$offer.cfg" > "$sb/support/scripts/genimage.sh"
  printf '#!/bin/sh\nexit 0\n' > "$sb/host/sbin/mkfs.ext4"
  chmod +x "$sb/support/scripts/genimage.sh" "$sb/host/sbin/mkfs.ext4"
  echo 'VERSION=x' > "$sb/target/boot/VERSION"
  { echo 'BR2_PACKAGE_RPI_EEPROM=y'; [ "$offer" = y ] && echo 'BR2_PACKAGE_RPI_EEPROM_OFFER=y'; } > "$sb/config"
  (cd "$sb" && BR2_CONFIG="$sb/config" BINARIES_DIR="$sb/images" BUILD_DIR="$sb/build" HOST_DIR="$sb/host" TARGET_DIR="$sb/target" \
    sh "$EXT/board/$board/post-image.sh") > "$T/$board-$offer.log" 2>&1
}

for board in rpi4 rpi5; do
  if run_post_image "$board" y && [ -f "$T/$board-y.cfg" ]; then
    if grep -q 'rpi-eeprom' "$T/$board-y.cfg"; then
      fail "$board offered: the boot partition still names rpi-eeprom files"
    else
      ok "$board offered: no rpi-eeprom file in the boot partition"
    fi
    # everything else of the board's config is there, unchanged
    if [ "$(grep -v '"rpi-eeprom/' "$EXT/board/$board/genimage.cfg")" = "$(cat "$T/$board-y.cfg")" ]; then
      ok "$board offered: the rest of genimage.cfg as it is"
    else
      fail "$board offered: genimage.cfg changed beyond the rpi-eeprom lines"
    fi
  else
    fail "$board offered: post-image.sh failed: $(cat "$T/$board-y.log")"
  fi
  if run_post_image "$board" n && cmp -s "$EXT/board/$board/genimage.cfg" "$T/$board-n.cfg"; then
    ok "$board without the option: the board's genimage.cfg (upstream's layout)"
  else
    fail "$board without the option: not the board's genimage.cfg: $(cat "$T/$board-n.log")"
  fi
  grep -q '"rpi-eeprom/pieeprom.upd"' "$EXT/board/$board/genimage.cfg" || fail "$board: genimage.cfg no longer names rpi-eeprom/pieeprom.upd (the filter tests nothing)"
done

# the lite products set the option; the upstream ones do not
for c in aarch64-rpi4 aarch64-rpi5; do
  if grep -q '^BR2_PACKAGE_RPI_EEPROM_OFFER=y' "$EXT/configs/$c.config"; then ok "$c offers the update"; else fail "$c does not set BR2_PACKAGE_RPI_EEPROM_OFFER"; fi
done
for c in rpi4 rpi5; do
  if grep -q 'RPI_EEPROM_OFFER' "$EXT/configs/$c.config"; then fail "upstream's $c sets the option"; else ok "upstream's $c keeps its layout"; fi
done
grep -q '^config BR2_PACKAGE_RPI_EEPROM_OFFER$' "$EXT/package/rpi-eeprom/Config.in" && ok "the option is in Config.in" || fail "no BR2_PACKAGE_RPI_EEPROM_OFFER in Config.in"

# the package: the offered files under /usr/share/rpi-eeprom/firmware-<chip>/, only with the option
mk="$EXT/package/rpi-eeprom/rpi-eeprom.mk"
for f in pieeprom.upd pieeprom.sig recovery.bin vl805.bin vl805.sig vl805.ver; do
  grep -q "\$(RPI_EEPROM_OFFER_DIR)/$f" "$mk" || fail "rpi-eeprom.mk does not install $f for the offer"
done
grep -q 'RPI_EEPROM_OFFER_DIR = $(TARGET_DIR)/usr/share/rpi-eeprom/firmware-$(RPI_EEPROM_CHIP)' "$mk" && ok "the offered files go to /usr/share/rpi-eeprom/firmware-<chip>/" || fail "the offer directory is not /usr/share/rpi-eeprom/firmware-<chip>/"
grep -q '^ifeq ($(BR2_PACKAGE_RPI_EEPROM_OFFER),y)$' "$mk" && ok "only with the option" || fail "the offer install is not conditional on the option"

# rpi-eeprom-info: the offered image when /boot has none (sandboxed through its own variables)
info="$EXT/package/rpi-eeprom/rpi-eeprom-info"
if grep -q '/usr/share/rpi-eeprom/firmware-${BCM_CHIP}/pieeprom.upd' "$info" && grep -q '/usr/share/rpi-eeprom/firmware-${BCM_CHIP}/vl805.ver' "$info"; then
  ok "rpi-eeprom-info falls back to the offered image"
else
  fail "rpi-eeprom-info reads only /boot"
fi

# task 394: the images come from the default channel, for both chips, and the update script keeps
# it that way (the newest pieeprom-*.bin of default/, never latest/ or the stable link)
for chip in 2711 2712; do
  paths=$(grep -E "^[[:space:]]*RPI_EEPROM_(FIRMWARE_PATH|RECOVERY_PATH|VL805_GLOB) = firmware-$chip/" "$mk")
  if [ -n "$paths" ] && ! echo "$paths" | grep -qv "= firmware-$chip/default/"; then
    ok "firmware-$chip: every file from the default channel"
  else
    fail "firmware-$chip: not all from default/: $paths"
  fi
done
grep -Eq '^[[:space:]]*RPI_EEPROM_FIRMWARE_PATH = firmware-2711/default/pieeprom-[0-9]{4}-[0-9]{2}-[0-9]{2}\.bin$' "$mk" \
  && ok "the Pi 4 pins a dated default image" || fail "no firmware-2711/default/pieeprom-YYYY-MM-DD.bin in rpi-eeprom.mk"
upd="$HERE/scripts/update-rpi-eeprom.sh"
fn=$(sed -n '/^function resolve_default_rpi_eeprom_firmware() {$/,/^}$/p' "$upd")
if [ -n "$fn" ] && command -v bash >/dev/null; then
  # a stand-in tar that lists a release tree: latest/ is newer than default/
  mkdir -p "$T/bin"
  printf '#!/bin/sh\ncat <<EOT\nr/firmware-2711/default/pieeprom-2026-05-17.bin\nr/firmware-2711/default/pieeprom-2026-09-23.bin\nr/firmware-2711/latest/pieeprom-2026-10-15.bin\nr/firmware-2711/stable/pieeprom-2026-10-15.bin\nr/firmware-2711/old/pieeprom-2027-01-01.bin\nEOT\n' > "$T/bin/tar"
  chmod +x "$T/bin/tar"
  got=$(PATH="$T/bin:$PATH" bash -c "$fn"'
resolve_default_rpi_eeprom_firmware x firmware-2711')
  [ "$got" = pieeprom-2026-09-23.bin ] && ok "update-rpi-eeprom.sh picks the newest default image" || fail "update-rpi-eeprom.sh picks '$got', not pieeprom-2026-09-23.bin"
else
  fail "update-rpi-eeprom.sh has no resolve_default_rpi_eeprom_firmware (or no bash here)"
fi
grep -q 'firmware-2711/stable/\${RPI4\|firmware-2712/stable/\${RPI5' "$upd" && fail "update-rpi-eeprom.sh still writes stable/ paths" || ok "update-rpi-eeprom.sh writes default/ paths"

# task 394: rpi-eeprom-info offers only a newer image, as rpi-eeprom-update does - a Pi that flashed
# a newer latest is not told to go back to the older default
# ts <file> <seconds>: the device tree's build-timestamp, 4 bytes big-endian
ts() { n=$2 b=""; for sh in 24 16 8 0; do b="$b$(printf '\\%03o' $(( (n >> sh) & 255 )))"; done; printf "$b" > "$1"; }
# the system runs it with busybox's ash, which has [[ ]]; dash has not
if command -v busybox >/dev/null && busybox sh -c '[[ 1 ]]' 2>/dev/null; then ish="busybox sh"; else ish=bash; fi
if command -v strings >/dev/null; then
  for c in "older 1760500000 1758600000 0 newer" "same 1760500000 1760500000 0 date" "newer 1758600000 1760500000 1 avail"; do
    set -- $c
    ts "$T/dt-ts" "$2"
    printf 'xxxx\nBUILD_TIMESTAMP=%s\nxxxx\n' "$3" > "$T/pieeprom.upd"
    for board in c03111 d04170; do
      out=$(BOARD_INFO=$board DT_BOOTLOADER_TS="$T/dt-ts" BOOTLOADER_UPDATE_IMAGE="$T/pieeprom.upd" $ish "$info" 2>&1); rc=$?
      case "$5" in
        newer) want="up to date (the running bootloader is newer" ;;
        date)  want="BOOTLOADER: up to date" ;;
        avail) want="BOOTLOADER: update available" ;;
      esac
      if [ "$rc" = "$4" ] && echo "$out" | grep -qF "$want" && ! echo "$out" | grep -q '\[\[: not found'; then ok "rpi-eeprom-info ($board), image $1: exit $rc"; else fail "rpi-eeprom-info ($board), image $1: exit $rc, $out"; fi
    done
  done
else
  echo "skip rpi-eeprom-info's comparison: no strings(1) here"
fi

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
