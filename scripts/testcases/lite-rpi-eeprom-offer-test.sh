#!/bin/sh
# shellcheck disable=SC2016 # make variables and the stubs' own $1, literally
# openccu-lite (task 366): the Pi 4/5 bootloader EEPROM update is offered, never flashed by itself.
# The boards' post-image.sh runs in a sandbox (genimage and mkfs.ext4 replaced by stubs that keep
# what they were given): with BR2_PACKAGE_RPI_EEPROM_OFFER=y the genimage config it hands over
# names no rpi-eeprom file - nothing for the boot ROM in the boot partition - and without it the
# board's genimage.cfg goes as it is (upstream's products). Also the wiring: both lite Pi 4/5
# products set the option, the package installs the files under /usr/share/rpi-eeprom/firmware-<chip>/
# exactly when it is set, and rpi-eeprom-info reads the offered image when /boot has none.
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

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
