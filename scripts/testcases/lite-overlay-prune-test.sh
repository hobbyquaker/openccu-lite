#!/bin/sh
# openccu-lite: board/lite/pre-build-systemd.sh on an incremental build - a file that left the
# overlays leaves the target, a file a package also installs makes that package install again, and
# nothing else in the target is touched.
#
# Usage: sh scripts/testcases/lite-overlay-prune-test.sh    (from the fork's checkout; needs bash, rsync)
# shellcheck disable=SC2034  # variables set here are read by check's eval'd expressions
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$HERE/buildroot-external/board/lite/pre-build-systemd.sh"
[ -f "$SCRIPT" ] || { echo "pre-build-systemd.sh not found under $HERE"; exit 2; }
command -v rsync >/dev/null || { echo "lite-overlay-prune-test: rsync is missing"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
B="$T/base"          # BASE_DIR
TG="$B/target"       # TARGET_DIR
S="$T/src"           # the source overlays

ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

put() { mkdir -p "$(dirname "$1")" && echo "$2" > "$1"; }

# pkg <dir name> <name> [path]...: an installed package whose file list names the paths
pkg() {
  d="$B/build/$1" n=$2; shift 2
  mkdir -p "$d"
  touch "$d/.stamp_target_installed" "$d/.stamp_installed"
  : > "$d/.files-list.txt"
  for p in "$@"; do echo "$n,$p" >> "$d/.files-list.txt"; done
}
stamped() { [ -e "$B/build/$1/.stamp_target_installed" ] && [ -e "$B/build/$1/.stamp_installed" ]; }

run() {
  BASE_DIR="$B" BUILD_DIR="$B/build" bash "$SCRIPT" "$TG" "$S/base" "$S/lite" > "$T/out" 2>&1
  rc=$?
}
# what buildroot's target-finalize does with the copies
finalize() {
  for o in base lite; do rsync -a --keep-dirlinks "$B/overlay-merged/$o/" "$TG/"; done
}

# a merged-/usr target with a directory alias and a link out of the target
mkdir -p "$TG/usr/bin" "$TG/usr/lib" "$TG/usr/sbin" "$TG/etc/real" "$T/host"
ln -s usr/bin "$TG/bin"; ln -s usr/lib "$TG/lib"; ln -s usr/sbin "$TG/sbin"
ln -s real "$TG/etc/alias"
ln -s "$T/host" "$TG/etc/outside"
put "$TG/usr/bin/busybox" busybox
put "$TG/etc/lighttpd/lighttpd.conf" "from the lighttpd package"
put "$TG/usr/lib/systemd/system/lighttpd.service" "from the lighttpd package"
put "$TG/etc/real/f.conf" "from the pkgalias package"
put "$T/host/x" "a file of the build host"
pkg busybox-1.0 busybox ./usr/bin/busybox
pkg lighttpd-1.0 lighttpd ./etc/lighttpd/lighttpd.conf ./usr/lib/systemd/system/lighttpd.service
pkg pkgalias-1.0 pkgalias ./etc/real/f.conf

put "$S/base/bin/eq3tool" tool
put "$S/base/etc/moved.conf" moved
put "$S/base/etc/lighttpd/lighttpd.conf" "overlay"
put "$S/base/etc/outside/x" "overlay"
put "$S/lite/usr/lib/systemd/system/occulited.service.d/10-openccu-lite.conf" "After=radio"
put "$S/lite/usr/lib/systemd/system/lighttpd.service" "overlay"
put "$S/lite/usr/libexec/occu/tool" tool
put "$S/lite/etc/alias/f.conf" "overlay"
put "$S/lite/etc/keep.conf" keep

# 1. a clean build: no previous copies, nothing removed
before=$(find "$TG" | sort | cksum)
run
check "clean build: exit 0" '[ $rc = 0 ]'
check "clean build: the target is untouched" '[ "$(find "$TG" | sort | cksum)" = "$before" ]'
check "clean build: bin moved under usr/" '[ -f "$B/overlay-merged/base/usr/bin/eq3tool" ] && [ ! -e "$B/overlay-merged/base/bin" ]'
check "clean build: no staging copy left" '[ ! -e "$B/overlay-merged.new" ]'
finalize

# 2. nothing changed
before=$(find "$TG" | sort | cksum)
run
check "unchanged overlays: exit 0" '[ $rc = 0 ]'
check "unchanged overlays: the target is untouched" '[ "$(find "$TG" | sort | cksum)" = "$before" ]'

# 3. files leave the overlays, one moves between overlays, a directory takes a file's place
rm "$S/lite/usr/lib/systemd/system/occulited.service.d/10-openccu-lite.conf"
rm "$S/base/bin/eq3tool"
mv "$S/base/etc/moved.conf" "$S/lite/etc/moved.conf"
rm "$S/lite/usr/libexec/occu/tool"
rm "$TG/usr/libexec/occu/tool"; mkdir "$TG/usr/libexec/occu/tool"
rm "$S/base/etc/outside/x"
run
check "removed files: exit 0 (no package installs them)" '[ $rc = 0 ]'
check "the deleted drop-in left the target" '[ ! -e "$TG/usr/lib/systemd/system/occulited.service.d/10-openccu-lite.conf" ]'
check "its directory stays" '[ -d "$TG/usr/lib/systemd/system/occulited.service.d" ]'
check "a file from the overlay's bin/ left usr/bin" '[ ! -e "$TG/usr/bin/eq3tool" ]'
check "a file moved to another overlay stays" '[ -f "$TG/etc/moved.conf" ]'
check "a directory at an old file's path stays" '[ -d "$TG/usr/libexec/occu/tool" ]'
check "a path through a link out of the target is left alone" '[ -f "$T/host/x" ] && grep -q "outside the target" "$T/out"'
check "other overlay files stay" '[ -f "$TG/etc/keep.conf" ] && [ -f "$TG/usr/lib/systemd/system/lighttpd.service" ]'
check "package files stay" '[ -f "$TG/usr/bin/busybox" ]'
check "no package is marked for reinstall" 'stamped busybox-1.0 && stamped lighttpd-1.0 && stamped pkgalias-1.0'
check "the copies no longer have the drop-in" '[ ! -e "$B/overlay-merged/lite/usr/lib/systemd/system/occulited.service.d/10-openccu-lite.conf" ]'
finalize

# 4. an overlay stops replacing a package's file
rm "$S/lite/usr/lib/systemd/system/lighttpd.service"
run
check "a package's path left the overlay: exit 1" '[ $rc = 1 ] && grep -q "run make again" "$T/out"'
check "the overlay's copy left the target" '[ ! -e "$TG/usr/lib/systemd/system/lighttpd.service" ]'
check "that package is marked for reinstall" '! [ -e "$B/build/lighttpd-1.0/.stamp_target_installed" ] && ! [ -e "$B/build/lighttpd-1.0/.stamp_installed" ]'
check "the others are not" 'stamped busybox-1.0 && stamped pkgalias-1.0'
run
check "make again: exit 0" '[ $rc = 0 ]'
pkg lighttpd-1.0 lighttpd ./etc/lighttpd/lighttpd.conf ./usr/lib/systemd/system/lighttpd.service
put "$TG/usr/lib/systemd/system/lighttpd.service" "from the lighttpd package"
finalize

# 5. the package's list spells the path through the target's real directory
rm "$S/lite/etc/alias/f.conf"
run
check "a path through a directory alias: exit 1" '[ $rc = 1 ]'
check "the package behind the alias is marked for reinstall" '! [ -e "$B/build/pkgalias-1.0/.stamp_target_installed" ] && stamped lighttpd-1.0'
pkg pkgalias-1.0 pkgalias ./etc/real/f.conf
finalize

# 6. an installed package without a file list (after <pkg>-reinstall) may own any removed path;
# the ca-certificates hook's link etc/ssl/certs, dangling on the build host, would stop libopenssl's
# reinstall ("mkdir -p": File exists), so it goes with a reinstall and only then
mkdir -p "$TG/etc/ssl"; ln -s /var/etc/ssl/certs "$TG/etc/ssl/certs"
pkg nolist-1.0 nolist
rm "$S/lite/etc/keep.conf"
run
check "a package without a list: exit 1" '[ $rc = 1 ]'
check "keep.conf left the target" '[ ! -e "$TG/etc/keep.conf" ]'
check "the package without a list is marked, listed ones are not" '! [ -e "$B/build/nolist-1.0/.stamp_target_installed" ] && stamped busybox-1.0 && stamped lighttpd-1.0'
check "the dangling etc/ssl/certs link is removed for the reinstall" '[ ! -L "$TG/etc/ssl/certs" ] && [ ! -e "$TG/etc/ssl/certs" ]'
check "and a mkdir -p through the path works again (libopenssl's install_ssldirs)" 'mkdir -p "$TG/etc/ssl/certs" && rmdir "$TG/etc/ssl/certs"'
ln -s /var/etc/ssl/certs "$TG/etc/ssl/certs"
run
check "make again: exit 0" '[ $rc = 0 ]'
finalize

check "without a reinstall the link stays" '[ -L "$TG/etc/ssl/certs" ]'

# 7. a host package whose list names a target path (host-gcc-final installs the toolchain libraries)
d="$B/build/host-gcc-final-1.0"
mkdir -p "$d"
touch "$d/.stamp_host_installed" "$d/.stamp_installed"
echo "host-gcc-final,./usr/lib/libgcc_s.so.1" > "$d/.files-list.txt"
put "$S/lite/usr/lib/libgcc_s.so.1" "overlay"
run
finalize
rm "$S/lite/usr/lib/libgcc_s.so.1"
run
check "a host package's target path: exit 1" '[ $rc = 1 ]'
check "the host package is marked for reinstall" '! [ -e "$d/.stamp_host_installed" ] && ! [ -e "$d/.stamp_installed" ] && stamped busybox-1.0'

if [ "$fails" -gt 0 ]; then
  echo "lite-overlay-prune-test: $fails failed"
  cat "$T/out"
  exit 1
fi
echo "lite-overlay-prune-test: all passed"
exit 0
