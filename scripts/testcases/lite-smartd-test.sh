#!/bin/sh
# openccu-lite: smartd is on no lite image, smartctl only on the hardware products (task 111).
#
# The configs: every lite product (LITE_PRODUCTS in lite-version.mk) -
# the Pi products build smartmontools for smartctl, the VM and the container products say "is not
# set"; each one's post-build list reaches board/lite/post-build.sh, which runs
# board/lite/no-smartd.sh; no lite overlay carries a smartd file. Then that script on fake targets:
# a Pi target as smartmontools installs it on a merged /usr (the daemon, the unit, the drop-in an
# older overlay had, the enable link, the configuration) keeps smartctl and loses the rest; a Pi
# target without smartctl stops the build; a VM target an earlier build left smartmontools in loses
# all of it; a smartd in a place the script does not know, or a preset that names it, stops the
# build; a clean target passes, twice.
#
# Usage: sh scripts/testcases/lite-smartd-test.sh    (from the fork's checkout)
# shellcheck disable=SC2034  # variables set here are read by check's eval'd expressions
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$HERE/buildroot-external"
SCRIPT="$EXT/board/lite/no-smartd.sh"
[ -f "$SCRIPT" ] || { echo "no-smartd.sh not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# --- the configs
products=$(sed -n 's/^LITE_PRODUCTS:=//p' "$HERE/lite-version.mk")
check "lite-version.mk names the lite products" '[ -n "$products" ]'
hw=0
for p in $products; do
  cfg="$EXT/configs/$p.config"
  if [ ! -f "$cfg" ]; then fail "$p: configs/$p.config is missing"; continue; fi
  case "$p" in
    aarch64-rpi*)
      hw=$((hw+1))
      check "$p builds smartmontools (smartctl for the storage panel)" "grep -qx 'BR2_PACKAGE_SMARTMONTOOLS=y' '$cfg'" ;;
    *)
      check "$p: smartmontools is not set" "grep -qx '# BR2_PACKAGE_SMARTMONTOOLS is not set' '$cfg' && ! grep -q '^BR2_PACKAGE_SMARTMONTOOLS=' '$cfg'" ;;
  esac
  # the post-build scripts, and whether one of them is (or execs) board/lite/post-build.sh
  reach=no
  for s in $(sed -n 's/^BR2_ROOTFS_POST_BUILD_SCRIPT="\(.*\)"$/\1/p' "$cfg"); do
    s=${s#'$(BR2_EXTERNAL_EQ3_PATH)/'}
    case "$s" in board/lite/post-build.sh) reach=yes ;; esac
    if [ -f "$EXT/$s" ] && grep -v '^[[:space:]]*#' "$EXT/$s" | grep -q '/lite/post-build\.sh"'; then reach=yes; fi
  done
  check "$p runs board/lite/post-build.sh" '[ "$reach" = yes ]'
done
check "the three Pi products are among them" '[ "$hw" -eq 3 ]'
check "board/lite/post-build.sh runs no-smartd.sh" "grep -v '^[[:space:]]*#' '$EXT/board/lite/post-build.sh' | grep -q 'no-smartd\.sh\" \"\${TARGET_DIR}\" \"\${BR2_CONFIG}\"'"
check "no lite overlay carries a smartd file" '[ -z "$(find "$EXT"/overlay/lite* -name "*smartd*" 2>/dev/null)" ]'

# --- the script on fake targets
echo 'BR2_PACKAGE_SMARTMONTOOLS=y' > "$T/pi.config"
echo '# BR2_PACKAGE_SMARTMONTOOLS is not set' > "$T/vm.config"

# a merged-/usr target: /usr/sbin is a link to bin, as on the systemd products
mktarget() {
  mkdir -p "$1/usr/bin" "$1/usr/lib/systemd/system" "$1/usr/lib/systemd/system-preset" "$1/etc/systemd/system/multi-user.target.wants"
  ln -s bin "$1/usr/sbin"
  echo busybox > "$1/usr/bin/busybox"
  echo 'enable occulited.service' > "$1/usr/lib/systemd/system-preset/50-openccu-lite.preset"
}
exe() { printf '#!/bin/sh\n' > "$1" && chmod +x "$1"; }
# what smartmontools installs, the drop-in the lite overlay had, and preset-all's enable link
smartmontools() {
  exe "$1/usr/sbin/smartctl"; exe "$1/usr/sbin/smartd"; exe "$1/usr/sbin/update-smart-drivedb"
  mkdir -p "$1/usr/share/smartmontools" "$1/usr/lib/systemd/system/smartd.service.d" "$1/etc/smartd_warning.d"
  echo 'drivedb' > "$1/usr/share/smartmontools/drivedb.h"
  printf '[Service]\nExecStart=/usr/sbin/smartd -n\n' > "$1/usr/lib/systemd/system/smartd.service"
  printf '[Unit]\nConditionPathExistsGlob=|/dev/sd*\n' > "$1/usr/lib/systemd/system/smartd.service.d/10-openccu-lite.conf"
  ln -s /usr/lib/systemd/system/smartd.service "$1/etc/systemd/system/multi-user.target.wants/smartd.service"
  echo 'DEVICESCAN' > "$1/etc/smartd.conf"
  exe "$1/etc/smartd_warning.sh"
}
run() { sh "$SCRIPT" "$@" > "$T/out" 2>&1; rc=$?; }

# a Pi: smartctl stays, smartd goes with everything that belongs to it
P="$T/pi"; mktarget "$P"; smartmontools "$P"
run "$P" "$T/pi.config"
check "pi: the step succeeds" '[ "$rc" -eq 0 ]'
check "pi: the daemon is gone" '[ ! -e "$P/usr/bin/smartd" ] && [ ! -e "$P/usr/sbin/smartd" ]'
check "pi: smartd.service is gone" '[ ! -e "$P/usr/lib/systemd/system/smartd.service" ]'
check "pi: the drop-in is gone" '[ ! -e "$P/usr/lib/systemd/system/smartd.service.d" ]'
check "pi: the enable link is gone" '[ ! -L "$P/etc/systemd/system/multi-user.target.wants/smartd.service" ]'
check "pi: smartd.conf and the warning hooks are gone" '[ ! -e "$P/etc/smartd.conf" ] && [ ! -e "$P/etc/smartd_warning.sh" ] && [ ! -e "$P/etc/smartd_warning.d" ]'
check "pi: nothing named smartd is left" '[ -z "$(find "$P" -name "*smartd*")" ]'
check "pi: smartctl and its drive database stay" '[ -x "$P/usr/sbin/smartctl" ] && [ -f "$P/usr/share/smartmontools/drivedb.h" ] && [ -x "$P/usr/sbin/update-smart-drivedb" ]'
check "pi: everything else is untouched" '[ -f "$P/usr/bin/busybox" ] && [ -f "$P/usr/lib/systemd/system-preset/50-openccu-lite.preset" ] && [ -L "$P/usr/sbin" ]'
check "pi: the step names what it removed" 'grep -q "removed /usr/lib/systemd/system/smartd.service.d" "$T/out" && grep -q "removed /etc/systemd/system/multi-user.target.wants/smartd.service" "$T/out"'
run "$P" "$T/pi.config"
check "pi: a second run on the clean target succeeds and removes nothing" '[ "$rc" -eq 0 ] && ! grep -q removed "$T/out"'

# a Pi product whose target has no smartctl: the storage panel would have nothing to read with
N="$T/pi-no-smartctl"; mktarget "$N"; smartmontools "$N"; rm -f "$N/usr/sbin/smartctl"
run "$N" "$T/pi.config"
check "pi without smartctl: the build stops" '[ "$rc" -ne 0 ] && grep -q "smartctl is not in the target" "$T/out"'

# the VM: an incremental build keeps the files of a package that was switched off
V="$T/vm"; mktarget "$V"; smartmontools "$V"
run "$V" "$T/vm.config"
check "vm: the step succeeds" '[ "$rc" -eq 0 ]'
check "vm: neither smartctl nor smartd nor the drive database is left" '[ -z "$(find "$V" -name "*smart*")" ]'
check "vm: everything else is untouched" '[ -f "$V/usr/bin/busybox" ]'
run "$V" "$T/vm.config"
check "vm: a second run succeeds" '[ "$rc" -eq 0 ]'

# a smartd somewhere the step does not know: stop and name it rather than ship it
U="$T/unknown"; mktarget "$U"; smartmontools "$U"; mkdir -p "$U/usr/libexec"; exe "$U/usr/libexec/smartd"
run "$U" "$T/pi.config"
check "a smartd in an unknown place stops the build and is named" '[ "$rc" -ne 0 ] && grep -q "^  /usr/libexec/smartd$" "$T/out"'

# a preset that would enable smartd again
R="$T/preset"; mktarget "$R"; exe "$R/usr/sbin/smartctl"; echo 'enable smartd.service' >> "$R/usr/lib/systemd/system-preset/50-openccu-lite.preset"
run "$R" "$T/pi.config"
check "a preset that names smartd stops the build" '[ "$rc" -ne 0 ] && grep -q "preset names smartd" "$T/out"'

# the arguments
run "$P"
check "without a configuration the step refuses" '[ "$rc" -ne 0 ]'
run "$P" "$T/missing.config"
check "with a configuration that is not there the step refuses" '[ "$rc" -ne 0 ]'

if [ "$fails" -eq 0 ]; then echo "lite-smartd-test: all passed"; else echo "lite-smartd-test: $fails failed"; fi
[ "$fails" -eq 0 ]
