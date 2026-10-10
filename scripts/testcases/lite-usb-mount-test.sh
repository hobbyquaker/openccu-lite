#!/bin/sh
# openccu-lite (task 161): USB sticks mounted in the host's namespace - lite-usb-mount (udev's facts
# handed to usbmount without eval), the udev rule, the template unit, the usbmount.conf options and
# the post-build removal of usbmount.rules; the usbstorage group (B-259).
#
# Usage: sh scripts/testcases/lite-usb-mount-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
L="$HERE/buildroot-external/overlay/lite"
TOOL="$L/usr/libexec/occu/lite-usb-mount"
UNIT="$L/usr/lib/systemd/system/occu-usb-mount@.service"
RULE="$L/usr/lib/udev/rules.d/63-openccu-lite-usb-storage.rules"
CONF="$L/etc/usbmount/usbmount.conf"
POST="$HERE/buildroot-external/board/lite/post-build-systemd.sh"
[ -f "$TOOL" ] || { echo "lite-usb-mount not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# udevadm: the partition's properties, the label an attacker's
cat > "$T/udevadm" <<EOS
#!/bin/sh
cat <<'EOP'
DEVPATH=/devices/platform/usb/sda/sda1
DEVNAME=/dev/sda1
ID_FS_USAGE=filesystem
ID_FS_TYPE=vfat
ID_FS_UUID=1234-ABCD
ID_FS_LABEL=x\$(touch $T/pwned)';touch $T/pwned2;'
ID_VENDOR=SanDisk
EOP
EOS
# usbmount: what it was given
cat > "$T/usbmount" <<EOS
#!/bin/sh
{ echo "action=\$1"; env | grep -E '^(DEVNAME|ID_FS_|DEVPATH|ID_VENDOR)' | sort; } > $T/got
exit \${FAKE_RC:-0}
EOS
chmod +x "$T/udevadm" "$T/usbmount"
export LITE_UDEVADM="$T/udevadm" LITE_USBMOUNT="$T/usbmount"
# never this machine's mounts: the remove would unmount what it finds there
: > "$T/mounts"; export LITE_MOUNTS="$T/mounts" LITE_USB_CONFIG="$T/usbstorage"

sh "$TOOL" add sda1 >/dev/null; rc=$?
[ $rc = 0 ] && grep -qx 'action=add' "$T/got" && grep -qx 'DEVNAME=/dev/sda1' "$T/got" && grep -qx 'ID_FS_TYPE=vfat' "$T/got" && grep -qx 'ID_FS_USAGE=filesystem' "$T/got" && grep -qx 'DEVPATH=/devices/platform/usb/sda/sda1' "$T/got" && ok "add: udev's facts reach usbmount" || bad "add: rc $rc, $(cat "$T/got")"
grep -q '^ID_FS_LABEL=x\$(touch' "$T/got" && ok "the label arrives as it is" || bad "label: $(grep LABEL "$T/got")"
[ ! -e "$T/pwned" ] && [ ! -e "$T/pwned2" ] && ok "the label is never run" || bad "the label ran"
grep -q '^ID_VENDOR' "$T/got" && bad "a key usbmount does not use was passed" || ok "only usbmount's keys"
sh "$TOOL" remove sda1 >/dev/null; rc=$?
[ $rc = 0 ] && grep -qx 'action=remove' "$T/got" && grep -qx 'DEVNAME=/dev/sda1' "$T/got" && ok "remove: the device name" || bad "remove: $(cat "$T/got")"
FAKE_RC=1 sh "$TOOL" add sda1 >/dev/null; [ $? = 1 ] && ok "usbmount's failure is the unit's" || bad "exit code"
for n in "" "../sda" "sda1;x" "sd a"; do
  sh "$TOOL" add "$n" 2>/dev/null; [ $? = 2 ] && ok "name '$n' refused" || bad "name '$n' accepted"
done
sh "$TOOL" format sda1 2>/dev/null; [ $? = 2 ] && ok "unknown action refused" || bad "unknown action"

# B-278: usbmount's lock (lockfile-progs, content 0, no PID) left by a usbmount that was killed while
# it mounted - the stick pulled, the unit stopped by BindsTo=, usbmount SIGTERMed before its EXIT
# trap ran. The next add removes it when no usbmount process is alive, and leaves a live one alone.
export LITE_USBMOUNT_LOCK="$T/run/usbmount/.mount.lock"
mkdir -p "$T/run/usbmount" "$T/proc/1" "$T/proc/42"
echo systemd > "$T/proc/1/comm"; printf '/sbin/init\0' > "$T/proc/1/cmdline"
echo sh > "$T/proc/42/comm"; printf 'sh\0/usr/libexec/occu/lite-usb-mount\0add\0sda1\0' > "$T/proc/42/cmdline"
stale() { echo 0 > "$LITE_USBMOUNT_LOCK"; rm -f "$T/got"; }
stale
out=$(LITE_PROC="$T/proc" sh "$TOOL" add sda1); rc=$?
[ $rc = 0 ] && [ ! -e "$LITE_USBMOUNT_LOCK" ] && grep -qx 'action=add' "$T/got" && ok "a stale lock is removed before the add, and usbmount runs" || bad "stale lock: rc $rc, lock $(ls "$LITE_USBMOUNT_LOCK" 2>&1)"
case "$out" in *"removed the stale usbmount lock"*) ok "the removal is said in the unit's journal" ;; *) bad "no word on the removal: $out" ;; esac
out=$(LITE_PROC="$T/proc" sh "$TOOL" add sda1)
case "$out" in *"removed the stale"*) bad "a removal without a lock: $out" ;; *) ok "no lock, nothing removed" ;; esac
# a usbmount alive - by its name (run by its #! line), or through sh by its command line
mkdir -p "$T/proc/77"; echo usbmount > "$T/proc/77/comm"
stale; LITE_PROC="$T/proc" sh "$TOOL" add sda1 >/dev/null
[ -e "$LITE_USBMOUNT_LOCK" ] && ok "a live usbmount's lock stays (by name)" || bad "a live lock removed (by name)"
echo sh > "$T/proc/77/comm"; printf 'sh\0/usr/share/usbmount/usbmount\0add\0' > "$T/proc/77/cmdline"
stale; LITE_PROC="$T/proc" sh "$TOOL" add sda1 >/dev/null
[ -e "$LITE_USBMOUNT_LOCK" ] && ok "a live usbmount's lock stays (by command line)" || bad "a live lock removed (by command line)"
rm -rf "$T/proc/77"
# the remove takes no lock and touches none
stale; LITE_PROC="$T/proc" sh "$TOOL" remove sda1 >/dev/null
[ -e "$LITE_USBMOUNT_LOCK" ] && ok "remove leaves the lock alone" || bad "remove took the lock away"
# the real thing, in this machine's /proc: a usbmount that takes the lock and holds it - alive, the
# lock stays; killed with it held, the lock is left behind, and the next add mounts the stick
mkdir -p "$T/slow"
cat > "$T/slow/usbmount" <<EOS
#!/bin/sh
echo 0 > "$LITE_USBMOUNT_LOCK"
sleep 30 &
echo \$! > "$T/slow/child"
wait
EOS
chmod +x "$T/slow/usbmount"
rm -f "$LITE_USBMOUNT_LOCK"
"$T/slow/usbmount" add &
slow=$!
i=0; while [ ! -s "$T/slow/child" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
rm -f "$T/got"
sh "$TOOL" add sda1 >/dev/null
[ -e "$LITE_USBMOUNT_LOCK" ] && ok "a running usbmount's lock stays (this machine's /proc)" || bad "a running usbmount's lock was removed"
kill -9 $slow 2>/dev/null; wait $slow 2>/dev/null
kill "$(cat "$T/slow/child" 2>/dev/null)" 2>/dev/null
[ -e "$LITE_USBMOUNT_LOCK" ] && ok "the killed usbmount left its lock" || bad "no lock left by the killed usbmount"
rm -f "$T/got"
sh "$TOOL" add sda1 >/dev/null; rc=$?
[ $rc = 0 ] && [ ! -e "$LITE_USBMOUNT_LOCK" ] && grep -qx 'action=add' "$T/got" && ok "after a killed mount the stick mounts again" || bad "after a killed mount: rc $rc"
unset LITE_USBMOUNT_LOCK

# B-316: the unmount - a plain umount first, usbmount's hooks after it; the holders logged and the
# lazy unmount (usbmount) when it fails; a pulled stick lazily at once
cat > "$T/umount" <<EOS
#!/bin/sh
echo "umount \$*" >> $T/umount.log
[ -n "\${FAKE_UMOUNT_FAIL:-}" ] && { echo "target is busy" >&2; exit 32; }
exit 0
EOS
cat > "$T/fuser" <<EOS
#!/bin/sh
echo "/media/usb1:  4711  4712" 
EOS
cat > "$T/run-parts" <<EOS
#!/bin/sh
echo "run-parts \$* \$UM_DEVICE \$UM_MOUNTPOINT \$UM_FILESYSTEM" >> $T/hooks.log
EOS
chmod +x "$T/umount" "$T/fuser" "$T/run-parts"
mkdir -p "$T/proc/4711"; echo node-red > "$T/proc/4711/comm"
export LITE_UMOUNT="$T/umount" LITE_FUSER="$T/fuser" LITE_RUNPARTS="$T/run-parts" LITE_UMOUNT_TRIES=2
echo "/dev/sda1 /media/usb1 vfat rw,nosuid 0 0" > "$T/mounts"
rm -f "$T/got" "$T/umount.log" "$T/hooks.log"
out=$(LITE_DEVICE_PRESENT=1 sh "$TOOL" remove sda1); rc=$?
[ $rc = 0 ] && grep -qx 'umount /media/usb1' "$T/umount.log" && [ ! -e "$T/got" ] && ok "remove: a plain umount, usbmount's lazy one not run" || bad "remove plain: rc $rc, $(cat "$T/umount.log" "$T/got" 2>&1)"
grep -qx 'run-parts /etc/usbmount/umount.d /dev/sda1 /media/usb1 vfat' "$T/hooks.log" && ok "remove: usbmount's hooks run after the plain umount" || bad "hooks: $(cat "$T/hooks.log" 2>&1)"
case "$out" in *"/dev/sda1 unmounted from /media/usb1"*) ok "remove: says which unmount it was" ;; *) bad "remove message: $out" ;; esac
rm -f "$T/got" "$T/umount.log" "$T/hooks.log"
out=$(FAKE_UMOUNT_FAIL=1 LITE_DEVICE_PRESENT=1 LITE_PROC="$T/proc" sh "$TOOL" remove sda1); rc=$?
[ "$(grep -c 'umount /media/usb1' "$T/umount.log")" = 2 ] && ok "remove: the plain umount is retried" || bad "retries: $(cat "$T/umount.log")"
grep -qx 'action=remove' "$T/got" && [ ! -e "$T/hooks.log" ] && ok "remove: the lazy unmount (usbmount) when the plain one fails" || bad "fallback: $(cat "$T/got" "$T/hooks.log" 2>&1)"
case "$out" in *"<4>/dev/sda1: umount /media/usb1 failed (target is busy); held by: 4711(node-red) 4712(?); unmounting it lazily"*) ok "remove: the holders logged as a warning" ;; *) bad "holders: $out" ;; esac
rm -f "$T/got" "$T/umount.log"
echo "/dev/sdz9 /media/usb2 vfat rw 0 0" > "$T/mounts"
out=$(sh "$TOOL" remove sdz9)
[ ! -e "$T/umount.log" ] && grep -qx 'action=remove' "$T/got" && ok "remove: a pulled stick goes to the lazy unmount at once" || bad "pulled: $(cat "$T/umount.log" "$T/got" 2>&1)"
case "$out" in *"/dev/sdz9 is gone"*) ok "remove: says the stick is gone" ;; *) bad "pulled message: $out" ;; esac
: > "$T/mounts"; rm -f "$T/got"
sh "$TOOL" remove sda1 >/dev/null; grep -qx 'action=remove' "$T/got" && ok "remove: nothing mounted - usbmount as before" || bad "not mounted"

# B-316: fsck at a dirty mount, only when switched on in /etc/config/usbstorage
cat > "$T/fsck" <<EOS
#!/bin/sh
echo "\$(basename \$0) \$*" >> $T/fsck.log
echo "fsck says hello"
exit \${FAKE_FSCK_RC:-0}
EOS
chmod +x "$T/fsck"; cp "$T/fsck" "$T/fsck.fat"; cp "$T/fsck" "$T/fsck.exfat"
export LITE_FSCK_FAT="$T/fsck.fat" LITE_FSCK_EXFAT="$T/fsck.exfat"
# boot sectors: FAT32 (16-bit FAT size 0, state at 0x41), FAT16 (state at 0x25), exFAT (flags at 0x6A)
mkimg() { dd if=/dev/zero of="$1" bs=512 count=1 2>/dev/null; printf "$3" | dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null; }
mkimg "$T/fat32-dirty" 65 '\001'; mkimg "$T/fat32-clean" 65 '\000'
mkimg "$T/fat16-dirty" 22 '\040'; printf '\001' | dd of="$T/fat16-dirty" bs=1 seek=37 conv=notrunc 2>/dev/null
mkimg "$T/exfat-dirty" 106 '\002'
fsckrun() { rm -f "$T/fsck.log" "$T/got"; LITE_RAWDEV="$T/$1" sh "$TOOL" add sda1; }
rm -f "$T/usbstorage"
out=$(fsckrun fat32-dirty); [ ! -e "$T/fsck.log" ] && grep -qx 'action=add' "$T/got" && ok "fsck off (no file): not checked, mounted" || bad "off: $(cat "$T/fsck.log" 2>&1)"
case "$out" in *"<4>/dev/sda1 (vfat) was not unmounted cleanly; not checked"*) ok "a dirty stick is said, as a warning" ;; *) bad "dirty message: $out" ;; esac
printf 'FSCK_AT_DIRTY_MOUNT=0\n' > "$T/usbstorage"
fsckrun fat32-dirty >/dev/null; [ ! -e "$T/fsck.log" ] && ok "fsck off (=0): not checked" || bad "=0 checked"
printf '# the Storage page\nFSCK_AT_DIRTY_MOUNT="1"\n' > "$T/usbstorage"
out=$(fsckrun fat32-dirty); grep -qx 'fsck.fat -a -w /dev/sda1' "$T/fsck.log" && grep -qx 'action=add' "$T/got" && ok "fsck on: a dirty FAT32 is checked with fsck.fat -a, then mounted" || bad "on fat32: $(cat "$T/fsck.log" "$T/got" 2>&1)"
case "$out" in *"fsck says hello"*"found nothing to repair"*) ok "the check's output and result are logged" ;; *) bad "fsck log: $out" ;; esac
fsckrun fat32-clean >/dev/null; [ ! -e "$T/fsck.log" ] && ok "fsck on: a clean FAT is not checked" || bad "clean checked"
fsckrun fat16-dirty >/dev/null; grep -qx 'fsck.fat -a -w /dev/sda1' "$T/fsck.log" && ok "fsck on: a dirty FAT16 (state at 0x25)" || bad "fat16"
out=$(FAKE_FSCK_RC=4 fsckrun fat32-dirty); rc=$?
[ $rc = 0 ] && grep -qx 'action=add' "$T/got" && ok "a failed check still mounts the stick" || bad "fsck failure: rc $rc"
case "$out" in *"<4>/dev/sda1: the check ended with exit 4"*) ok "a failed check is a warning" ;; *) bad "fsck failure message: $out" ;; esac
sed -i 's/ID_FS_TYPE=vfat/ID_FS_TYPE=exfat/' "$T/udevadm"
fsckrun exfat-dirty >/dev/null; grep -qx 'fsck.exfat -p /dev/sda1' "$T/fsck.log" && ok "fsck on: a dirty exFAT is checked with fsck.exfat -p" || bad "exfat: $(cat "$T/fsck.log" 2>&1)"
fsckrun fat32-clean >/dev/null; [ ! -e "$T/fsck.log" ] && ok "fsck on: a clean exFAT is not checked" || bad "exfat clean checked"
sed -i 's/ID_FS_TYPE=exfat/ID_FS_TYPE=ntfs/' "$T/udevadm"
fsckrun fat32-dirty >/dev/null; [ ! -e "$T/fsck.log" ] && ok "fsck: only FAT and exFAT" || bad "ntfs checked"
sed -i 's/ID_FS_TYPE=ntfs/ID_FS_TYPE=vfat/' "$T/udevadm"
rm -f "$T/usbstorage"

# usbmount.conf: nosuid, and the usbstorage group (B-259) on FAT, exFAT and NTFS, read and write
printf 'root:x:0:\nocculite:x:8100:\ncerts:x:8101:\nusbstorage:x:8102:occulite\n' > "$T/group"
out=$(LITE_GROUP_FILE="$T/group" sh -c ". '$CONF'; echo \"\$MOUNTOPTIONS|\$FS_MOUNTOPTIONS\"")
case "$out" in *nosuid*) ok "nosuid" ;; *) bad "no nosuid: $out" ;; esac
for fs in vfat exfat ntfs-3g fuseblk; do
  case " ${out#*|} " in *" -fstype=${fs},"*"uid=0,gid=8102,umask=0007 "*) ok "$fs: root, the usbstorage group" ;; *) bad "$fs: $out" ;; esac
done
# an image without the group: the occulite group, read only, as before B-259; without either, root's
printf 'root:x:0:\nocculite:x:8100:\n' > "$T/group-old"
out=$(LITE_GROUP_FILE="$T/group-old" sh -c ". '$CONF'; echo \"\$FS_MOUNTOPTIONS\"")
case " $out " in *" -fstype=exfat,uid=0,gid=8100,umask=0027 "*) ok "no usbstorage group: occulite's, read only" ;; *) bad "fallback: $out" ;; esac
out=$(LITE_GROUP_FILE="$T/none" sh -c ". '$CONF'; echo \"\$FS_MOUNTOPTIONS\"")
case "$out" in *gid=0,*) ok "no group at all: root's" ;; *) bad "fallback: $out" ;; esac
# the image's accounts: the group pinned at 8102, occulite its member
MK="$HERE/buildroot-external/package/occulited/occulited.mk"
grep -qE '^[[:space:]]+- -1 usbstorage 8102 \* - - - ' "$MK" && ok "occulited.mk: usbstorage 8102" || bad "occulited.mk: no usbstorage group"
grep -qE '^[[:space:]]+occulite 8100 occulite 8100 \* /usr/local/etc/occulite - usbstorage ' "$MK" && ok "occulited.mk: occulite in usbstorage" || bad "occulited.mk: occulite not in usbstorage"

# the rule: the system's own partitions left alone, the unit wanted for a filesystem
grep -q 'ENV{SYSTEMD_WANTS}+="occu-usb-mount@%k.service"' "$RULE" && grep -q '^TAG+="systemd"' "$RULE" && ok "rule: wants the unit" || bad "rule: SYSTEMD_WANTS"
for m in 'ENV{ID_PART_TABLE_UUID}=="deedbeef"' 'ENV{ID_FS_LABEL}=="bootfs|rootfs|userfs"' 'ENV{ID_FS_USAGE}!="filesystem"' 'ACTION=="remove"'; do
  grep -qF "$m" "$RULE" && ok "rule: $m" || bad "rule: $m missing"
done
# the unit: bound to the device, usbmount at start and at stop
grep -qx 'BindsTo=dev-%i.device' "$UNIT" && grep -qx 'ExecStart=/usr/libexec/occu/lite-usb-mount add %I' "$UNIT" && grep -qx 'ExecStop=/usr/libexec/occu/lite-usb-mount remove %I' "$UNIT" && grep -qx 'RemainAfterExit=yes' "$UNIT" && ok "unit" || bad "unit"
# the journal's copies: switched to the stick after the mount, a last copy before the unmount - both
# steps "-" so the journal never keeps a stick from being mounted or unmounted
execs=$(grep -E '^Exec(Start|StartPost|Stop)=' "$UNIT" | tr '\n' '|')
[ "$execs" = 'ExecStart=/usr/libexec/occu/lite-usb-mount add %I|ExecStartPost=-/usr/libexec/occu/lite-journal-sync attach %I|ExecStop=-/usr/libexec/occu/lite-journal-sync detach %I|ExecStop=/usr/libexec/occu/lite-usb-mount remove %I|' ] \
  && ok "unit: the journal's attach after the mount, its detach before the unmount" || bad "unit's Exec lines: $execs"
# the image: no usbmount.rules
grep -q 'rm -f "${TARGET_DIR}/lib/udev/rules.d/usbmount.rules"' "$POST" && ok "post-build removes usbmount.rules" || bad "post-build"

[ $fails = 0 ] && echo "all passed" || echo "$fails failed"
[ $fails = 0 ]
