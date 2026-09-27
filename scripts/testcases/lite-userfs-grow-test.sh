#!/bin/sh
# openccu-lite: the recovery grows a userfs that is too small for the update and gets a retry
# right - the fix for a CCU3-shaped card whose 2 GB userfs cannot take the 2 GB rootfs image.
#
#   - fwinstall.sh's expand_userfs_to_max compares the filesystem with its partition, so a run
#     that was cut short after resizepart (the partition at the disk end, the filesystem still
#     small) is finished by resize2fs on the retry instead of "userfs already maxed";
#   - what e2fsck -p refuses to fix (rc >= 4, a corrupted orphan list after a hard reboot with
#     the userfs mounted) gets an e2fsck -fy, both results in the log, and the update goes on
#     when that leaves the filesystem clean;
#   - S90AutoUpdate ends an unattended update - failed or not - with both boot markers gone,
#     the reason of a failure in the saved log, and a reboot into the normal system;
#   - the growth branch itself runs against a loop-device image inside a privileged container
#     (lite-userfs-grow-inner.sh): fresh growth, the retry, nothing to grow, preen's refusal,
#     a busy userfs. Skipped with a note when docker is not available.
#
# Usage: sh scripts/testcases/lite-userfs-grow-test.sh    (from the fork's checkout)
#        LITE_GROW_NO_DOCKER=1 skips the container part.
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
REC="$HERE/buildroot-external/package/recovery-system/external/overlay/base"
FW="$REC/bin/fwinstall.sh"
S90="$REC/etc/init.d/S90AutoUpdate"

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

bash -n "$FW" && ok "fwinstall.sh parses" || bad "fwinstall.sh does not parse"
sh -n "$S90" && ok "S90AutoUpdate parses" || bad "S90AutoUpdate does not parse"

# --- fwinstall.sh: the shape of the growth branch ------------------------------------------------
fn=$(sed -n '/^expand_userfs_to_max()$/,/^}$/p' "$FW")
[ -n "$fn" ] && ok "expand_userfs_to_max() found" || bad "expand_userfs_to_max() is not in fwinstall.sh"
echo "$fn" | grep -q 'FS_BYTES=$(get_ext_fs_size "${USER_DEV}")' && ok "the filesystem's size is read" || bad "no filesystem size in the growth branch"
echo "$fn" | grep -q 'PART_BYTES - FS_BYTES' && ok "the filesystem is compared with its partition" || bad "no comparison of filesystem and partition"
echo "$fn" | grep -q 'userfs already maxed' && ok "'already maxed' stays for a filesystem that fills the disk" || bad "'already maxed' is gone"
echo "$fn" | grep -q 'e2fsck -pDf' && ok "preen first" || bad "no e2fsck -p"
echo "$fn" | grep -q 'e2fsck -fy "${USER_DEV}"' && ok "e2fsck -fy after preen's refusal" || bad "no e2fsck -fy fallback"
echo "$fn" | grep -q 'retrying with e2fsck -fy' && ok "the fallback is logged" || bad "the fallback is silent"
echo "$fn" | grep -q '/proc/mounts' && ok "a userfs that stays mounted is an error, not a fsck of a mounted filesystem" || bad "no mount check after umount"
# the order: umount, resizepart (conditional), fsck, resize2fs, mount rw
echo "$fn" | awk '
  /umount -f \/userfs/ && !u { u=NR }
  /parted -s -f/ && !p { p=NR }
  /e2fsck -pDf/ && !f { f=NR }
  /resize2fs "\$\{USER_DEV\}"/ && !r { r=NR }
  /mount -o rw \/userfs;|if ! mount -o rw \/userfs/ && !m { m=NR }
  END { if (u && p && f && r && m && u<p && p<f && f<r && r<m) print "ordered"; else print "u=" u " p=" p " f=" f " r=" r " m=" m }' >"${TMPDIR:-/tmp}/lite-grow-order.$$"
[ "$(cat "${TMPDIR:-/tmp}/lite-grow-order.$$")" = "ordered" ] && ok "umount, resizepart, fsck, resize2fs, mount in this order" || bad "order: $(cat "${TMPDIR:-/tmp}/lite-grow-order.$$")"
rm -f "${TMPDIR:-/tmp}/lite-grow-order.$$"
grep -q '^get_ext_fs_size()$' "$FW" && ok "get_ext_fs_size() found" || bad "get_ext_fs_size() is not in fwinstall.sh"
grep -q '/sbin/tune2fs -l' "$FW" && ok "the size comes from tune2fs -l (e2fsprogs, in the recovery)" || bad "no tune2fs"
grep -q '^BR2_PACKAGE_E2FSPROGS=y' "$HERE/buildroot-external/package/recovery-system/external/Buildroot.config" && ok "the recovery builds e2fsprogs (tune2fs is always installed)" || bad "e2fsprogs is not in the recovery's config"

# --- S90AutoUpdate: a failed unattended update boots the normal system ------------------------------
grep -q '^finish_update() {$' "$S90" && ok "finish_update() found" || bad "finish_update() is not in S90AutoUpdate"
fu=$(sed -n '/^finish_update() {$/,/^}$/p' "$S90")
echo "$fu" | grep -q 'rm -f /usr/local/.recoveryMode' && ok "the recovery marker is removed (the bootloader's trigger)" || bad "finish_update leaves .recoveryMode"
echo "$fu" | grep -q 'rm -f /usr/local/.firmwareUpdate' && ok "the update marker is removed" || bad "finish_update leaves .firmwareUpdate"
echo "$fu" | grep -q 'mount -o rw,remount /userfs 2>/dev/null || mount -o rw /userfs' && ok "the userfs is mounted again if the update left it unmounted" || bad "no fallback mount in finish_update"
echo "$fu" | grep -q 'save_install_log' && ok "the log is saved" || bad "finish_update does not save the log"
[ "$(grep -c '^ *finish_update$' "$S90")" -eq 2 ] && ok "both unattended paths end in finish_update" || bad "finish_update is called $(grep -c '^ *finish_update$' "$S90") times, want 2"
[ "$(grep -c 'unattended firmware update failed (rc=${FWINSTALL_RC}), rebooting into the normal system' "$S90")" -eq 2 ] && ok "a failure writes its reason into the log on both paths" || bad "the failure reason is not written on both paths"
grep -q '/sbin/reboot' "$S90" && ok "the reboot follows" || bad "no reboot"
# the failure branch no longer hides the exit code behind 'if !'
grep -q 'if ! ( set -o pipefail; /bin/fwinstall.sh' "$S90" && bad "fwinstall's exit code is still hidden behind if !" || ok "fwinstall's exit code is kept (FWINSTALL_RC)"

# --- the growth branch on a loop device, in a container -------------------------------------------
if [ "${LITE_GROW_NO_DOCKER:-0}" = 1 ]; then
  echo "skip the container part (LITE_GROW_NO_DOCKER=1)"
elif ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "skip the container part: docker is not available"
else
  name="lite-grow-$$"
  # privileged for losetup, mount and partprobe; /dev of the host so the partition nodes appear;
  # trixie for util-linux >= 2.39 (lsblk's PARTN column, which the recovery's util-linux has)
  if docker run --rm --name "$name" --privileged -v /dev:/dev -v "$HERE:/fork:ro" debian:trixie-slim \
       sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get -qq update >/dev/null 2>&1 && apt-get -qq install -y --no-install-recommends parted e2fsprogs fdisk util-linux dosfstools >/dev/null 2>&1 || { echo "apt failed"; exit 3; }; bash /fork/scripts/testcases/lite-userfs-grow-inner.sh /fork/buildroot-external/package/recovery-system/external/overlay/base/bin/fwinstall.sh' \
       >"${TMPDIR:-/tmp}/lite-grow-inner.$$" 2>&1; then
    sed 's/^/     /' "${TMPDIR:-/tmp}/lite-grow-inner.$$"
    ok "the growth branch on a loop device (container)"
  else
    sed 's/^/     /' "${TMPDIR:-/tmp}/lite-grow-inner.$$"
    bad "the growth branch on a loop device (container)"
  fi
  rm -f "${TMPDIR:-/tmp}/lite-grow-inner.$$"
fi

echo; [ "$fails" -eq 0 ] && { echo "lite-userfs-grow-test: all checks passed"; exit 0; }
echo "lite-userfs-grow-test: $fails check(s) failed"; exit 1
