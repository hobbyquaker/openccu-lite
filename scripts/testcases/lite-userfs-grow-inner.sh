#!/bin/bash
# openccu-lite: the growth branch of the recovery's fwinstall.sh on a loop-device image. Run by
# lite-userfs-grow-test.sh inside a privileged container (it mounts, partitions and corrupts a
# filesystem of its own and writes /etc/fstab); do not run it on a real system.
#
#   $1  fwinstall.sh (the recovery's, read only)
#
# The image: an MBR disk with three partitions like a CCU3-shaped card (bootfs, rootfs, userfs)
# and free space behind the userfs. The function under test is extracted from fwinstall.sh
# unchanged and runs against the real paths it uses (/userfs, LABEL=userfs, /etc/fstab).
set -u
FW=$1
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

IMG=/tmp/lite-userfs-grow.img
FN=/tmp/fn.sh
sed -n '/^get_ext_fs_size()$/,/^}$/p' "$FW" >"$FN"
sed -n '/^expand_userfs_to_max()$/,/^}$/p' "$FW" >>"$FN"
grep -q '^expand_userfs_to_max()$' "$FN" && grep -q '^get_ext_fs_size()$' "$FN" && ok "both functions extracted" || { bad "functions not found in $FW"; exit 1; }

# --- the disk ------------------------------------------------------------------------------------
rm -f "$IMG"; truncate -s 128M "$IMG"
parted -s "$IMG" mklabel msdos mkpart primary fat32 1MiB 9MiB mkpart primary ext4 9MiB 25MiB mkpart primary ext4 25MiB 57MiB 2>/dev/null || { bad "parted mklabel"; exit 1; }
LOOP=$(losetup -fP --show "$IMG" 2>/dev/null) || { bad "losetup"; exit 1; }
DEV="${LOOP}p3"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -b "$DEV" ] && break; partprobe "$LOOP" >/dev/null 2>&1; sleep 0.5; done
if [ ! -b "$DEV" ]; then
  # no udev in the container: make the nodes from sysfs
  for p in /sys/class/block/"$(basename "$LOOP")"/"$(basename "$LOOP")"p*; do
    [ -e "$p/dev" ] || continue
    mknod "/dev/$(basename "$p")" b "$(cut -d: -f1 "$p/dev")" "$(cut -d: -f2 "$p/dev")" 2>/dev/null
  done
fi
[ -b "$DEV" ] && ok "loop device $LOOP with partitions" || { bad "no partition device $DEV"; losetup -d "$LOOP"; exit 1; }
cleanup() {
  umount /userfs 2>/dev/null
  losetup -d "$LOOP" 2>/dev/null
  rm -f "$IMG"
}
trap cleanup EXIT

mkfs.vfat -n bootfs "${LOOP}p1" >/dev/null 2>&1
mkfs.ext4 -q -F -L rootfs "${LOOP}p2" >/dev/null 2>&1
mkfs.ext4 -q -F -L userfs "$DEV" >/dev/null 2>&1 || { bad "mkfs userfs"; exit 1; }
found=$(blkid --label userfs 2>/dev/null)
[ "$found" = "$DEV" ] && ok "blkid --label userfs is the loop partition" || { echo "skip: blkid --label userfs is '$found', not $DEV (another userfs on this host)"; exit 0; }

mkdir -p /userfs
echo "LABEL=userfs /userfs auto defaults,ro,noatime,nodiratime,nofail 0 2" >>/etc/fstab
mount -o rw /userfs || { bad "mount /userfs"; exit 1; }
echo "keep me across the resize" >/userfs/keep
mkdir -p /userfs/tmp
mount -o ro,remount /userfs

disk_bytes() { blockdev --getsize64 "$LOOP"; }
part_bytes() { blockdev --getsize64 "$DEV"; }
fs_bytes() { tune2fs -l "$DEV" 2>/dev/null | awk -F: '/^Block count:/ {c=$2} /^Block size:/ {s=$2} END {gsub(/ /,"",c); gsub(/ /,"",s); printf "%d\n", c*s}'; }
part_end_sector() { sfdisk -d "$LOOP" | awk -v p="$DEV" '$1==p { for(i=1;i<=NF;i++){ if($i=="start=") s=$(i+1); if($i=="size=") z=$(i+1) } gsub(/,/,"",s); gsub(/,/,"",z); print s+z }'; }
run_fn() { bash -c ". '$FN'; expand_userfs_to_max; rc=\$?; echo; echo rc=\$rc" 2>&1; }
MiB=$((1024*1024))
DISK_SECTORS=$(( $(disk_bytes) / 512 ))

# --- 1: the partition has free space behind it: resizepart, fsck, resize2fs -------------------------
p0=$(part_bytes); f0=$(fs_bytes)
[ "$p0" -eq $((32*MiB)) ] && [ "$f0" -eq $((32*MiB)) ] && ok "start: partition and filesystem 32 MiB" || bad "start: partition $p0, filesystem $f0"
out=$(run_fn); rc=${out##*rc=}
[ "$rc" = 0 ] && ok "1 fresh growth: rc 0" || bad "1 fresh growth: rc $rc: $out"
echo "$out" | grep -q "resize userfs to disk end" && ok "1 says: resize userfs to disk end" || bad "1 output: $out"
end=$(part_end_sector); [ $((DISK_SECTORS - end)) -le 2048 ] && ok "1 the partition reaches the disk end ($end of $DISK_SECTORS sectors)" || bad "1 partition end $end, disk $DISK_SECTORS"
p1=$(part_bytes); f1=$(fs_bytes)
[ $((p1 - f1)) -ge 0 ] && [ $((p1 - f1)) -le "$MiB" ] && [ "$f1" -gt "$f0" ] && ok "1 the filesystem fills the partition ($f1 of $p1 bytes)" || bad "1 filesystem $f1, partition $p1"
grep -q " /userfs .* rw" /proc/mounts && ok "1 /userfs mounted read-write again" || bad "1 /userfs not rw: $(grep ' /userfs ' /proc/mounts)"
[ "$(cat /userfs/keep 2>/dev/null)" = "keep me across the resize" ] && ok "1 the data survived" || bad "1 the data is gone"
sig=$(dd if="$LOOP" bs=1 skip=440 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$sig" = "efbeedde" ] && ok "1 MBR disk signature 0xdeedbeef" || bad "1 MBR disk signature is $sig"

# --- 2: the retry after a run cut short: partition at the disk end, filesystem still small ----------
umount /userfs || bad "2 umount"
e2fsck -fy "$DEV" >/dev/null 2>&1
resize2fs "$DEV" 32M >/dev/null 2>&1 || bad "2 resize2fs shrink"
mount /userfs || bad "2 mount ro"
f2=$(fs_bytes); [ "$f2" -eq $((32*MiB)) ] && ok "2 setup: filesystem shrunk to 32 MiB, partition $(part_bytes) bytes" || bad "2 setup: filesystem $f2"
out=$(run_fn); rc=${out##*rc=}
[ "$rc" = 0 ] && ok "2 retry: rc 0" || bad "2 retry: rc $rc: $out"
echo "$out" | grep -q "userfs partition already at disk end, grow filesystem" && ok "2 says: partition already at disk end, grow filesystem" || bad "2 output: $out"
echo "$out" | grep -q "resize userfs to disk end" && bad "2 ran resizepart again" || ok "2 no resizepart"
p2=$(part_bytes); f2=$(fs_bytes)
[ $((p2 - f2)) -ge 0 ] && [ $((p2 - f2)) -le "$MiB" ] && ok "2 the filesystem fills the partition again ($f2 of $p2 bytes)" || bad "2 filesystem $f2, partition $p2"
grep -q " /userfs .* rw" /proc/mounts && ok "2 /userfs mounted read-write" || bad "2 /userfs not rw"
[ "$(cat /userfs/keep 2>/dev/null)" = "keep me across the resize" ] && ok "2 the data survived" || bad "2 the data is gone"

# --- 3: nothing left to grow ---------------------------------------------------------------------
mount -o ro,remount /userfs
out=$(run_fn); rc=${out##*rc=}
[ "$rc" = 1 ] && ok "3 maxed: rc 1" || bad "3 maxed: rc $rc: $out"
echo "$out" | grep -q "userfs already maxed" && ok "3 says: userfs already maxed" || bad "3 output: $out"
grep -q " /userfs " /proc/mounts && ok "3 /userfs left mounted" || bad "3 /userfs unmounted"

# --- 4: preen refuses (rc 4), the -fy run repairs, the growth goes on -------------------------------
umount /userfs || bad "4 umount"
resize2fs "$DEV" 32M >/dev/null 2>&1 || bad "4 resize2fs shrink"
# an inode in use whose dtime holds an inode number: the mark of a corrupted orphan list,
# which e2fsck -p will not fix on its own (task 277's lab finding)
debugfs -w -R "sif /keep dtime 12" "$DEV" >/dev/null 2>&1 || bad "4 debugfs"
e2fsck -pf "$DEV" >/dev/null 2>&1; prc=$?
[ "$prc" -ge 4 ] && ok "4 setup: e2fsck -p refuses (rc $prc)" || bad "4 setup: e2fsck -p rc $prc, the corruption does not reproduce preen's refusal"
mount /userfs || bad "4 mount ro"
out=$(run_fn); rc=${out##*rc=}
[ "$rc" = 0 ] && ok "4 preen refused, -fy repaired: rc 0" || bad "4 rc $rc: $out"
echo "     the log line: $(echo "$out" | head -1 | cut -c1-400)"
echo "$out" | grep -q "e2fsck -p rc=4" && ok "4 logs the preen result" || bad "4 output: $out"
echo "$out" | grep -q "retrying with e2fsck -fy, rc=1" && ok "4 logs the -fy result (rc 1: corrected)" || bad "4 output: $out"
echo "$out" | grep -q -i "orphan" && ok "4 e2fsck's words are in the log" || bad "4 no e2fsck output in: $out"
p4=$(part_bytes); f4=$(fs_bytes)
[ $((p4 - f4)) -ge 0 ] && [ $((p4 - f4)) -le "$MiB" ] && ok "4 the filesystem fills the partition ($f4 of $p4 bytes)" || bad "4 filesystem $f4, partition $p4"
[ "$(cat /userfs/keep 2>/dev/null)" = "keep me across the resize" ] && ok "4 the data survived the repair" || bad "4 the data is gone"
umount /userfs
e2fsck -fn "$DEV" >/dev/null 2>&1 && ok "4 the filesystem is clean afterwards" || bad "4 e2fsck -fn finds errors"
mount /userfs

# --- 5: the userfs cannot be unmounted: a clear error, nothing changed --------------------------------
umount /userfs; resize2fs "$DEV" 32M >/dev/null 2>&1; mount /userfs
( cd /userfs && sleep 60 ) & holder=$!
sleep 0.2
out=$(run_fn); rc=${out##*rc=}
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
[ "$rc" = 2 ] && ok "5 busy userfs: rc 2" || bad "5 busy userfs: rc $rc: $out"
echo "$out" | grep -q "ERROR: (umount /userfs failed, still mounted)" && ok "5 says why" || bad "5 output: $out"
[ "$(fs_bytes)" -eq $((32*MiB)) ] && ok "5 the filesystem is untouched" || bad "5 the filesystem changed: $(fs_bytes)"

echo; [ "$fails" -eq 0 ] && { echo "lite-userfs-grow-inner: all checks passed"; exit 0; }
echo "lite-userfs-grow-inner: $fails check(s) failed"; exit 1
