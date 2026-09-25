#!/bin/sh
# openccu-lite (task 161): USB sticks mounted in the host's namespace - lite-usb-mount (udev's facts
# handed to usbmount without eval), the udev rule, the template unit, the usbmount.conf options and
# the post-build removal of usbmount.rules.
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

# usbmount.conf: nosuid, and the occulite group on FAT, exFAT and NTFS
printf 'root:x:0:\nocculite:x:8100:\n' > "$T/group"
out=$(LITE_GROUP_FILE="$T/group" sh -c ". '$CONF'; echo \"\$MOUNTOPTIONS|\$FS_MOUNTOPTIONS\"")
case "$out" in *nosuid*) ok "nosuid" ;; *) bad "no nosuid: $out" ;; esac
for fs in vfat exfat ntfs-3g fuseblk; do
  case " ${out#*|} " in *" -fstype=${fs},"*"uid=0,gid=8100,umask=0027"*) ok "$fs: root, the occulite group" ;; *) bad "$fs: $out" ;; esac
done
out=$(LITE_GROUP_FILE="$T/none" sh -c ". '$CONF'; echo \"\$FS_MOUNTOPTIONS\"")
case "$out" in *gid=0,*) ok "no occulite group: root's" ;; *) bad "fallback: $out" ;; esac

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
