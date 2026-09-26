#!/bin/sh
# openccu-lite: lite-journal-sync, the journal's ram-sync copy - the interval, the unit's condition,
# a copy (rotate, copy under a temporary name, remove from RAM, trim), a copy that fails, and the
# unit's stop ordering.
#
# Usage: sh scripts/testcases/lite-journal-sync-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-journal-sync"
PERSIST_TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-journal-persist"
UNIT="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/occu-journal-sync.service"
PRESET="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system-preset/50-openccu-lite.preset"
[ -f "$TOOL" ] || { echo "lite-journal-sync not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# a journalctl that logs its arguments; --rotate turns the active file into a closed one
cat > "$T/journalctl" <<'EOF'
#!/bin/sh
echo "$*" >> "$OCCU_TEST_LOG"
[ "${OCCU_TEST_JOURNALCTL_FAIL:-}" = "$1" ] && exit 1
if [ "$1" = --rotate ]; then
  for f in "$OCCU_JOURNAL_RUNTIME"/*/system.journal; do
    [ -f "$f" ] && mv "$f" "${f%/*}/system@rotated-0000000000000009-0000000000000009.journal" && printf 'new' > "$f"
  done
fi
[ "${OCCU_TEST_JOURNALCTL_FAIL:-}" = "$1" ] && exit 1
exit 0
EOF
chmod +x "$T/journalctl"
printf '#!/bin/sh\nexec sh %s "$@"\n' "$PERSIST_TOOL" > "$T/persist"
chmod +x "$T/persist"

export OCCU_JOURNAL_CONFIG="$T/journal" OCCU_JOURNAL_RUNTIME="$T/run" OCCU_JOURNAL_TARGET="$T/userfs"
export OCCU_JOURNAL_STATE="$T/state" OCCU_JOURNALCTL="$T/journalctl" OCCU_TEST_LOG="$T/calls"
export OCCU_JOURNAL_PERSIST="$T/persist" OCCU_VERSION_FILE="$T/VERSION"
# the clock gate has passed, unless a case below says otherwise (B-205); no container
printf 'ntp\n' > "$T/clock-state"
export OCCU_CLOCK_STATE="$T/clock-state" OCCU_CONTAINER_FILE="$T/no-container"

interval() {  # interval <config value or -> <want seconds>
  if [ "$1" = - ]; then rm -f "$T/journal"; else printf 'SYNC_INTERVAL=%s\n' "$1" > "$T/journal"; fi
  got=$(sh "$TOOL" interval)
  [ "$got" = "$2" ] && ok "interval '$1' = $2" || bad "interval '$1': want $2, got $got"
}
interval - 21600
interval "" 21600
interval 1h 3600
interval 12h 43200
interval 30min 1800
interval 5min 900
interval 10d 604800
interval 08h 28800
interval 6 21600
interval "-1h" 21600
interval 99999999999h 604800

# the condition
printf 'PLATFORM=rpi4\n' > "$T/VERSION"
printf 'STORAGE=ram-sync\n' > "$T/journal"
sh "$TOOL" active && ok "active in ram-sync" || bad "not active in ram-sync"
printf 'STORAGE=ram\n' > "$T/journal"
sh "$TOOL" active && bad "active in ram" || ok "inactive in ram"
rm -f "$T/journal"
sh "$TOOL" active && bad "active on rpi4's default" || ok "inactive on the product default"
printf 'STORAGE=ram-sync\nTARGET=/media/usb0/journal\n' > "$T/journal"
sh "$TOOL" active && bad "active with a path target" || ok "inactive with a plain path as the target"
printf 'STORAGE=ram-sync\nTARGET=usb:LOGSTICK/journal\n' > "$T/journal"
sh "$TOOL" active && ok "active with a USB stick as the target" || bad "not active with a USB stick as the target"
printf 'STORAGE=persistent\nTARGET=usb:LOGSTICK/journal\n' > "$T/journal"
sh "$TOOL" active && bad "active in persistent on a stick" || ok "inactive in persistent on a stick (refused)"

# a copy: two closed files and the active one in RAM
MID=0123456789abcdef0123456789abcdef
setup() {
  rm -rf "$T/run" "$T/userfs" "$T/state" "$T/calls"
  mkdir -p "$T/run/$MID"
  printf 'aaaa' > "$T/run/$MID/system@a-0000000000000001-0000000000000001.journal"
  printf 'bbbbbb' > "$T/run/$MID/system@a-0000000000000002-0000000000000002.journal"
  printf 'active' > "$T/run/$MID/system.journal"
}
setup
printf 'STORAGE=ram-sync\nTARGET_MAX_USE=128M\nTARGET_MAX_AGE=30d\n' > "$T/journal"
out=$(sh "$TOOL" copy); rc=$?
[ "$rc" -eq 0 ] && ok "copy exits 0" || bad "copy exited $rc: $out"
n=$(ls "$T/userfs/$MID" | wc -l)
[ "$n" -eq 3 ] && ok "three closed files on the userfs (two and the rotated one)" || bad "userfs has $n files: $(ls "$T/userfs/$MID")"
[ "$(cat "$T/userfs/$MID/system@a-0000000000000002-0000000000000002.journal")" = bbbbbb ] && ok "a copy has the content" || bad "content"
[ -n "$(find "$T/userfs/$MID" -maxdepth 1 -name '*.part' -print -quit)" ] && bad "a temporary file is left" || ok "no temporary file left"
[ "$(ls "$T/run/$MID")" = system.journal ] && ok "RAM keeps only the new active file" || bad "RAM has: $(ls "$T/run/$MID")"
[ ! -e "$T/userfs/$MID/system.journal" ] && ok "the active file is not copied" || bad "the active file was copied"
grep -qx -- '--rotate' "$T/calls" && ok "rotated first" || bad "no rotate: $(cat "$T/calls")"
grep -qx -- "-q -D $T/userfs --vacuum-size=128M --vacuum-time=30d" "$T/calls" && ok "trimmed to TARGET_MAX_USE and TARGET_MAX_AGE" || bad "vacuum call: $(cat "$T/calls")"
grep -qx 'LAST_RESULT=ok' "$T/state/sync.state" && grep -qx 'LAST_COPIED=3' "$T/state/sync.state" && ok "state: ok, 3 copied" || bad "state: $(cat "$T/state/sync.state")"
case "$out" in *"3 journal file(s) copied"*) ok "says what it copied" ;; *) bad "output: $out" ;; esac

# a file already on the userfs but still in RAM (a copy that stopped before its end): removed from
# RAM, not copied again; the default trim size
setup
mkdir -p "$T/userfs/$MID"
printf 'aaaa' > "$T/userfs/$MID/system@a-0000000000000001-0000000000000001.journal"
printf 'STORAGE=ram-sync\n' > "$T/journal"
sh "$TOOL" copy >/dev/null
[ ! -e "$T/run/$MID/system@a-0000000000000001-0000000000000001.journal" ] && ok "a leftover in RAM is removed" || bad "leftover still in RAM"
grep -qx 'LAST_COPIED=2' "$T/state/sync.state" && ok "and not counted as a copy" || bad "state: $(cat "$T/state/sync.state")"
grep -qx -- "-q -D $T/userfs --vacuum-size=64M" "$T/calls" && ok "the default trim is 64M, no age" || bad "vacuum call: $(cat "$T/calls")"

# a copy that fails: the target is not a directory - RAM keeps everything, the state says why
setup
printf 'not a directory' > "$T/userfs"
out=$(sh "$TOOL" copy); rc=$?
[ "$rc" -ne 0 ] && ok "a failed copy exits non-zero" || bad "a failed copy exited 0"
[ "$(ls "$T/run/$MID" | wc -l)" -eq 3 ] && ok "nothing leaves RAM when the copy fails" || bad "RAM has: $(ls "$T/run/$MID")"
grep -qx 'LAST_RESULT=failed' "$T/state/sync.state" && grep -q "^LAST_ERROR=the target $T/userfs cannot be created" "$T/state/sync.state" && ok "state: failed, with the reason" || bad "state: $(cat "$T/state/sync.state")"
rm -f "$T/userfs"

# a failing rotate still copies what is closed, and says the copy failed
setup
OCCU_TEST_JOURNALCTL_FAIL=--rotate sh "$TOOL" copy >/dev/null; rc=$?
[ "$rc" -ne 0 ] && grep -qx 'LAST_RESULT=failed' "$T/state/sync.state" && grep -qx 'LAST_COPIED=2' "$T/state/sync.state" && ok "a failed rotate: the closed files copied, the copy reported failed" || bad "rotate failure: rc=$rc $(cat "$T/state/sync.state")"

# the unit: the condition, the loop, the copy at stop, stopped after the daemons, enabled
grep -qx 'ExecCondition=/usr/libexec/occu/lite-journal-sync active' "$UNIT" && grep -qx 'ExecStop=/usr/libexec/occu/lite-journal-sync copy stop' "$UNIT" && ok "the unit copies when it stops" || bad "the unit's Exec lines"
before=$(sed -n 's/^Before=//p' "$UNIT" | tr ' ' '\n')
for u in shutdown.target rfd.service hmipserver.service multimacd.service lighttpd.service occulited.service addons.target; do
  echo "$before" | grep -qx "$u" && ok "stops after $u" || bad "must order Before=$u"
done
grep -qx 'DefaultDependencies=no' "$UNIT" && grep -qx 'Conflicts=shutdown.target' "$UNIT" && grep -qx 'RequiresMountsFor=/usr/local' "$UNIT" && ok "stops before the userfs is unmounted" || bad "the shutdown dependencies"
grep -qx 'enable occu-journal-sync.service' "$PRESET" && ok "enabled in the preset" || bad "not in the preset"

# task 85 (D-67): why a copy ran - the loop says interval or early; the unit's stop is shutdown while
# the system goes down and manual otherwise (Copy now restarts the unit); the state is also left
# beside the copies, so the copy at shutdown is known after the reboot
printf '#!/bin/sh\necho "${OCCU_TEST_SYSTEM_STATE:-running}"\n' > "$T/systemctl"
chmod +x "$T/systemctl"
export OCCU_SYSTEMCTL="$T/systemctl"
reason() {  # reason <copy argument or -> <system state> <want>
  setup
  printf 'STORAGE=ram-sync\n' > "$T/journal"
  if [ "$1" = - ]; then
    OCCU_TEST_SYSTEM_STATE=$2 sh "$TOOL" copy >/dev/null
  else
    OCCU_TEST_SYSTEM_STATE=$2 sh "$TOOL" copy "$1" >/dev/null
  fi
  grep -qx "LAST_REASON=$3" "$T/state/sync.state" && ok "copy '$1' while $2: $3" || bad "copy '$1' while $2: want $3, state $(cat "$T/state/sync.state")"
}
reason interval running interval
reason early running early
reason stop stopping shutdown
reason stop running manual
reason stop degraded manual
reason - running manual
setup
OCCU_TEST_SYSTEM_STATE=stopping sh "$TOOL" copy stop >/dev/null
cmp -s "$T/state/sync.state" "$T/userfs/.occu-sync.state" && ok "the state is also beside the copies, for the next boot" || bad "no state on the userfs: $(ls -a "$T/userfs")"
[ -n "$(find "$T/userfs" -maxdepth 1 -name '*.new' -print -quit)" ] && bad "a temporary state file is left" || ok "no temporary state file left"
grep -qx 'ExecStop=/usr/libexec/occu/lite-journal-sync copy stop' "$UNIT" && ok "the unit's stop copies as 'stop'" || bad "the unit's ExecStop"

# ---- a USB stick as the target: TARGET=usb:<label>/<dir>, looked up by its label among the mounts
# at /media/usb1…8 (a fake mount table and udevadm; /media lives under $T/mr); attach and detach
# are occu-usb-mount@'s start and stop
cat > "$T/udevadm" <<'EOF'
#!/bin/sh
# udevadm info --query=property --name=<dev>: the label from the test's table, nothing for a device it lacks
for a in "$@"; do case "$a" in --name=*) dev=${a#--name=} ;; esac; done
l=$(sed -n "s|^$dev ||p" "$OCCU_TEST_LABELS" | head -1)
[ -n "$l" ] || exit 4
echo "DEVNAME=$dev"
echo "ID_FS_LABEL=$l"
EOF
cat > "$T/systemctl-stick" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$OCCU_TEST_LOG"
case "$*" in
  is-system-running) echo "${OCCU_TEST_SYSTEM_STATE:-running}" ;;
  *is-active*)
    n=$(cat "$OCCU_TEST_UNIT_POLLS" 2>/dev/null || echo 0); echo $((n + 1)) > "$OCCU_TEST_UNIT_POLLS"
    s=${OCCU_TEST_UNIT_STATE:-inactive}
    # "deactivating" for the first polls, then inactive: the copy unit's own last copy at shutdown
    [ "$s" = deactivating ] && [ "$n" -ge 2 ] && s=inactive
    case "$*" in *-q*) ;; *) echo "$s" ;; esac
    [ "$s" = active ]; exit $? ;;
esac
exit 0
EOF
chmod +x "$T/udevadm" "$T/systemctl-stick"
export OCCU_UDEVADM="$T/udevadm" OCCU_TEST_LABELS="$T/labels" OCCU_MOUNTS="$T/mounts" OCCU_MEDIA_ROOT="$T/mr" OCCU_DEV_DIR="$T/dev"
export OCCU_TEST_UNIT_POLLS="$T/polls" OCCU_JOURNAL_STICK_WAIT=10
stick_setup() {  # stick_setup <mount options of the journal's stick>
  setup
  rm -rf "${T:?}/mr" "${T:?}/dev" "$T/polls"
  mkdir -p "$T/mr/media/usb1" "$T/mr/media/usb2" "$T/dev"
  : > "$T/dev/sda1"
  : > "$T/dev/sdb1"
  printf '/dev/sda1 OTHERSTICK\n/dev/sdb1 LOGSTICK\n' > "$T/labels"
  printf '/dev/root / ext4 ro 0 0\n/dev/sda1 /media/usb1 vfat rw,nosuid 0 0\n/dev/sdb1 /media/usb2 vfat %s 0 0\n' "${1:-rw,nosuid,nodev}" > "$T/mounts"
  # as occulited writes it: PERSIST in step, which is also a name the script must not use for itself
  printf 'PERSIST=0\nSTORAGE=ram-sync\nTARGET=usb:LOGSTICK/journal\n' > "$T/journal"
}
SD="$T/mr/media/usb2/journal"

stick_setup
printf 'STORAGE=ram-sync\n' > "$T/journal"
[ "$(sh "$TOOL" target)" = "$T/userfs" ] && ok "target: the userfs" || bad "target for the userfs: $(sh "$TOOL" target)"
stick_setup
[ "$(sh "$TOOL" target)" = "$SD" ] && ok "target: the stick with the label, not the first stick" || bad "target: $(sh "$TOOL" target)"
[ "$(cat "$T/state/stick" 2>/dev/null)" = "/dev/sdb1 /media/usb2" ] && ok "the stick is recorded by device and mount" || bad "stick record: $(cat "$T/state/stick" 2>/dev/null)"
printf '/dev/sda1 /media/usb1 vfat rw 0 0\n' > "$T/mounts"
sh "$TOOL" target >/dev/null && bad "target: found a stick that is not plugged in" || ok "target: exit 1 without the stick"
printf '/dev/sdb1 /media/usb0 vfat rw 0 0\n/dev/sdb1 /mnt/x vfat rw 0 0\n' > "$T/mounts"
sh "$TOOL" target >/dev/null && bad "target: a mount outside /media/usb1…8 counts" || ok "target: only /media/usb1…8 count"

stick_setup
out=$(sh "$TOOL" copy); rc=$?
[ "$rc" -eq 0 ] && [ "$(ls "$SD/$MID" 2>/dev/null | wc -l)" -eq 3 ] && ok "a copy to the stick: three files" || bad "copy to the stick: rc=$rc $(ls -R "$T/mr") $out"
[ -z "$(ls -A "$T/mr/media/usb1")" ] && ok "the stick with another label is not written" || bad "the other stick has: $(ls -A "$T/mr/media/usb1")"
[ ! -e "$T/userfs" ] && ok "nothing on the userfs" || bad "the userfs was written"
[ "$(ls "$T/run/$MID")" = system.journal ] && ok "RAM keeps only the new active file" || bad "RAM has: $(ls "$T/run/$MID")"
grep -qx -- "-q -D $SD --vacuum-size=64M" "$T/calls" && ok "the copies on the stick are trimmed" || bad "vacuum: $(cat "$T/calls")"
cmp -s "$T/state/sync.state" "$SD/.occu-sync.state" && ok "the state is also on the stick" || bad "no state beside the copies on the stick"
case "$out" in *"copied from RAM to the USB stick LOGSTICK"*) ok "says it copied to the stick" ;; *) bad "output: $out" ;; esac

stick_setup
printf '/dev/sda1 /media/usb1 vfat rw 0 0\n' > "$T/mounts"
out=$(sh "$TOOL" copy interval); rc=$?
[ "$rc" -eq 0 ] && [ "$(ls "$T/run/$MID" | wc -l)" -eq 3 ] && [ ! -e "$T/state/sync.state" ] && ! grep -qx -- '--rotate' "$T/calls" 2>/dev/null && ok "no stick: no copy, RAM untouched, no state" || bad "no stick: rc=$rc $(ls "$T/run/$MID") $out"
case "$out" in *"the USB stick LOGSTICK is not plugged in: no copy (interval)"*) ok "and says so" ;; *) bad "output: $out" ;; esac

stick_setup "ro,nosuid"
out=$(sh "$TOOL" copy); rc=$?
[ "$rc" -ne 0 ] && grep -qx 'LAST_RESULT=failed' "$T/state/sync.state" && grep -qx 'LAST_ERROR=the USB stick LOGSTICK is mounted read-only' "$T/state/sync.state" && [ "$(ls "$T/run/$MID" | wc -l)" -eq 3 ] && ok "a read-only stick: failed, RAM untouched" || bad "read-only stick: rc=$rc $(cat "$T/state/sync.state" 2>/dev/null)"

# FAT: chmod and chgrp fail, the copy goes on
stick_setup
mkdir -p "$T/bin-fat"
printf '#!/bin/sh\nexit 1\n' > "$T/bin-fat/chmod"
printf '#!/bin/sh\nexit 1\n' > "$T/bin-fat/chgrp"
chmod +x "$T/bin-fat/chmod" "$T/bin-fat/chgrp"
PATH="$T/bin-fat:$PATH" sh "$TOOL" copy >/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ "$(ls "$SD/$MID" | wc -l)" -eq 3 ] && grep -qx 'LAST_RESULT=ok' "$T/state/sync.state" && ok "chmod and chgrp failing (FAT) do not fail the copy" || bad "FAT copy: rc=$rc $(cat "$T/state/sync.state")"

# ---- task 228: a network share as the target, TARGET=share:<name>/<dir> - the first access mounts
# it (here: the fake mount table says whether it came), nothing is written unless it is mounted
share_setup() {  # share_setup <mounted: rw|ro|no|unset> [<mount point exists: yes|no>]
  setup
  rm -rf "$T/mr"
  [ "${2:-yes}" = yes ] && mkdir -p "$T/mr/media/net/nas"
  case "$1" in
    rw) printf '/dev/root / ext4 ro 0 0\nsystemd-1 /media/net/nas autofs rw 0 0\n//nas/logs /media/net/nas cifs rw,nosuid,nodev,vers=3.1.1 0 0\n' > "$T/mounts" ;;
    ro) printf '/dev/root / ext4 ro 0 0\n//nas/logs /media/net/nas cifs ro,nosuid,nodev 0 0\n' > "$T/mounts" ;;
    no) printf '/dev/root / ext4 ro 0 0\nsystemd-1 /media/net/nas autofs rw 0 0\n' > "$T/mounts" ;;
    unset) printf '/dev/root / ext4 ro 0 0\n' > "$T/mounts" ;;
  esac
  printf 'PERSIST=0\nSTORAGE=ram-sync\nTARGET=share:nas/ccu/journal\n' > "$T/journal"
}
ND="$T/mr/media/net/nas/ccu/journal"
share_setup rw
printf 'STORAGE=ram-sync\nTARGET=share:nas/ccu/journal\n' > "$T/journal"
sh "$TOOL" active && ok "active with a share as the target" || bad "not active with a share as the target"
[ "$(sh "$TOOL" target)" = "$ND" ] && ok "target: the share's directory" || bad "share target: $(sh "$TOOL" target)"
share_setup rw
echo "the network share nas cannot be reached, the journal stays in RAM until a copy reaches it" > "$T/state/fallback"
out=$(sh "$TOOL" copy interval); rc=$?
[ "$rc" -eq 0 ] && [ "$(ls "$ND/$MID" 2>/dev/null | wc -l)" -eq 3 ] && [ "$(ls "$T/run/$MID")" = system.journal ] && ok "a copy to the share: three files, RAM emptied" || bad "copy to the share: rc=$rc $out"
grep -qx -- "-q -D $ND --vacuum-size=64M" "$T/calls" && ok "the copies on the share are trimmed" || bad "vacuum: $(cat "$T/calls")"
[ ! -e "$T/state/fallback" ] && ok "a copy that reaches the share clears its warning" || bad "the fallback stayed"
case "$out" in *"copied from RAM to the network share nas (interval)"*) ok "says it copied to the share" ;; *) bad "output: $out" ;; esac
[ ! -e "$T/userfs" ] && ok "nothing on the userfs" || bad "the userfs was written"
# the share did not mount: nothing is written to the tmpfs under the mount point, RAM keeps it all
share_setup no
out=$(sh "$TOOL" copy interval); rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$ND" ] && [ "$(ls "$T/run/$MID" | wc -l)" -eq 3 ] && ! grep -qx -- '--rotate' "$T/calls" 2>/dev/null && ok "an unreachable share: no copy, nothing on the mount point, RAM untouched" || bad "unreachable share: rc=$rc $(ls -R "$T/mr") $out"
grep -qx 'LAST_RESULT=failed' "$T/state/sync.state" && grep -qx 'LAST_ERROR=the network share nas cannot be reached' "$T/state/sync.state" && ok "and the result says why" || bad "state: $(cat "$T/state/sync.state" 2>/dev/null)"
grep -q 'cannot be reached, the journal stays in RAM' "$T/state/fallback" 2>/dev/null && ok "and the warning's reason is written" || bad "fallback: $(cat "$T/state/fallback" 2>/dev/null)"
# occulited has not set the share up (no automount, no mount point): the same, with that reason
share_setup unset no
out=$(sh "$TOOL" copy interval); rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$T/mr/media/net" ] && grep -q 'is not set up on this system' "$T/state/sync.state" && ok "a share that is not set up: no copy, no directory made" || bad "not set up: rc=$rc $(cat "$T/state/sync.state" 2>/dev/null)"
# a mount point without the automount is not set up either (a directory left behind)
share_setup unset
out=$(sh "$TOOL" copy interval); rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$ND" ] && grep -q 'is not set up on this system (no automount at /media/net/nas)' "$T/state/sync.state" && ok "a mount point without its automount: not set up" || bad "no automount: rc=$rc $(cat "$T/state/sync.state" 2>/dev/null)"
# B-222: the automount is there but a stat of its mount point fails (an SMB server that is gone:
# EHOSTDOWN) - here the directory is missing, as a failing stat shows it: unreachable, not missing
share_setup no no
out=$(sh "$TOOL" copy interval); rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$T/mr/media/net" ] && grep -qx 'LAST_ERROR=the network share nas cannot be reached' "$T/state/sync.state" && [ "$(ls "$T/run/$MID" | wc -l)" -eq 3 ] && ok "an automount whose mount point cannot be read: cannot be reached, nothing written" || bad "stat fails: rc=$rc $(cat "$T/state/sync.state" 2>/dev/null)"
grep -q 'cannot be reached, the journal stays in RAM' "$T/state/fallback" 2>/dev/null && ok "and the warning says cannot be reached" || bad "fallback: $(cat "$T/state/fallback" 2>/dev/null)"
share_setup ro
out=$(sh "$TOOL" copy); rc=$?
[ "$rc" -ne 0 ] && grep -qx 'LAST_ERROR=the network share nas is mounted read-only' "$T/state/sync.state" && [ "$(ls "$T/run/$MID" | wc -l)" -eq 3 ] && ok "a read-only share: failed, RAM untouched" || bad "read-only share: rc=$rc $(cat "$T/state/sync.state" 2>/dev/null)"
for bad_target in "share:NAS/j" "share:1nas/j" "share:nas/../x" "share:nas/.hidden" "share:averyveryverylongname/j"; do
  share_setup rw
  printf 'STORAGE=ram-sync\nTARGET=%s\n' "$bad_target" > "$T/journal"
  sh "$TOOL" target >/dev/null && bad "target $bad_target accepted" || ok "target $bad_target refused"
done
grep -q '^After=.*remote-fs.target' "$UNIT" && ok "the copy unit stops before the shares are unmounted (After=remote-fs.target)" || bad "the unit is not ordered after remote-fs.target"

# attach: the journal's stick switches the copies to it and copies at once
export OCCU_SYSTEMCTL="$T/systemctl-stick"
stick_setup
mkdir -p "$T/state"
echo "the USB stick LOGSTICK is not plugged in" > "$T/state/fallback"
out=$(sh "$TOOL" attach sda1); rc=$?
[ "$rc" -eq 0 ] && [ -e "$T/state/fallback" ] && [ ! -e "$T/state/sync.state" ] && ok "attach of a stick with another label: left alone" || bad "attach other label: rc=$rc $out"
case "$out" in *"not the journal's USB stick LOGSTICK: left alone"*) ok "and says so" ;; *) bad "output: $out" ;; esac
out=$(sh "$TOOL" attach sdb1); rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$T/state/fallback" ] && grep -qx 'LAST_REASON=plug' "$T/state/sync.state" && [ "$(ls "$SD/$MID" | wc -l)" -eq 3 ] && ok "attach of the journal's stick: the warning goes, a copy at once" || bad "attach: rc=$rc $out $(cat "$T/state/sync.state" 2>/dev/null)"
grep -qx 'systemctl start --no-block occu-journal-sync.service' "$T/calls" && ok "attach starts the copy unit when it is not running" || bad "attach calls: $(cat "$T/calls")"
stick_setup
printf 'STORAGE=ram\nTARGET=usb:LOGSTICK/journal\n' > "$T/journal"
sh "$TOOL" attach sdb1 >/dev/null
[ ! -e "$T/state/sync.state" ] && ok "attach does nothing outside ram-sync" || bad "attach copied in ram"
sh "$TOOL" attach 'sdb1;x' >/dev/null 2>&1; [ $? -eq 2 ] && ok "attach refuses a name that is not a device's" || bad "attach took a bad name"

# detach: a last copy while the stick is there, then RAM and the warning
stick_setup
sh "$TOOL" target >/dev/null
out=$(sh "$TOOL" detach sda1); rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$T/state/sync.state" ] && [ ! -e "$T/state/fallback" ] && ok "detach of another stick: nothing" || bad "detach other: rc=$rc $out"
out=$(sh "$TOOL" detach sdb1); rc=$?
[ "$rc" -eq 0 ] && grep -qx 'LAST_REASON=unplug' "$T/state/sync.state" && [ "$(ls "$SD/$MID" | wc -l)" -eq 3 ] && ok "detach: a last copy onto the stick" || bad "detach: rc=$rc $out"
grep -q 'not plugged in' "$T/state/fallback" 2>/dev/null && [ ! -e "$T/state/stick" ] && ok "detach: the warning's reason, the record gone" || bad "detach: fallback $(cat "$T/state/fallback" 2>/dev/null), record $(cat "$T/state/stick" 2>/dev/null)"
stick_setup
sh "$TOOL" target >/dev/null
rm -f "$T/dev/sdb1"
out=$(sh "$TOOL" detach sdb1); rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$T/state/sync.state" ] && [ "$(ls "$T/run/$MID" | wc -l)" -eq 3 ] && grep -q 'not plugged in' "$T/state/fallback" && ok "detach of a pulled stick: no copy, RAM kept, the warning" || bad "pulled: rc=$rc $out"
case "$out" in *"was pulled out: no last copy"*) ok "and says so" ;; *) bad "output: $out" ;; esac
# at shutdown: waits for the copy unit's own last copy, copies as shutdown, no warning
stick_setup
sh "$TOOL" target >/dev/null
out=$(OCCU_TEST_SYSTEM_STATE=stopping OCCU_TEST_UNIT_STATE=deactivating sh "$TOOL" detach sdb1); rc=$?
[ "$rc" -eq 0 ] && grep -qx 'LAST_REASON=shutdown' "$T/state/sync.state" && [ ! -e "$T/state/fallback" ] && ok "detach at shutdown: a copy as shutdown, no warning" || bad "detach at shutdown: rc=$rc $out $(cat "$T/state/sync.state" 2>/dev/null)"
[ "$(cat "$T/polls")" -ge 3 ] && ok "detach at shutdown waited for the copy unit ($(cat "$T/polls") polls)" || bad "no wait: $(cat "$T/polls")"
export OCCU_SYSTEMCTL="$T/systemctl"

# the early copy's decision: 80 % of RUNTIME_MAX_USE (or of journald's default, 10 % of /run's
# filesystem, at most 4G), at most every 15 minutes after the last copy; a figure that cannot be
# read starts nothing. du and df are fakes that print the figures the case gives.
printf '#!/bin/sh\n[ -n "${OCCU_TEST_DU_KIB:-}" ] || exit 1\nprintf "%%s\\t%%s\\n" "$OCCU_TEST_DU_KIB" "$2"\n' > "$T/du"
printf '#!/bin/sh\n[ -n "${OCCU_TEST_DF_KIB:-}" ] || exit 1\necho "Filesystem 1024-blocks Used Available Capacity Mounted on"\necho "tmpfs $OCCU_TEST_DF_KIB 0 $OCCU_TEST_DF_KIB 0%% /run"\n' > "$T/df"
chmod +x "$T/du" "$T/df"
export OCCU_DU="$T/du" OCCU_DF="$T/df"
early() {  # early <journal file> <du KiB or -> <df KiB or -> <now> <last> <due|not> <what>
  printf "$1" > "$T/journal"
  du_kib=$2
  df_kib=$3
  [ "$du_kib" = - ] && du_kib=""
  [ "$df_kib" = - ] && df_kib=""
  OCCU_TEST_DU_KIB=$du_kib OCCU_TEST_DF_KIB=$df_kib sh "$TOOL" early-due "$4" "$5" >/dev/null
  rc=$?
  if [ "$6" = due ]; then
    [ "$rc" -eq 0 ] && ok "early copy: $7" || bad "early copy: $7 (not due)"
  else
    [ "$rc" -ne 0 ] && ok "no early copy: $7" || bad "no early copy: $7 (due)"
  fi
}
early 'RUNTIME_MAX_USE=16M\n' 13108 - 2000 1000 due "80 % of 16M, 16:40 after the last copy"
early 'RUNTIME_MAX_USE=16M\n' 13107 - 2000 1000 not "just under 80 % of 16M"
early 'RUNTIME_MAX_USE=16M\n' 16384 - 1899 1000 not "full, but 14:59 after the last copy"
early 'RUNTIME_MAX_USE=16M\n' 16384 - 1900 1000 due "full, 15:00 after the last copy"
early 'RUNTIME_MAX_USE=16m\n' 14000 - 5000 0 due "a lower-case size"
early 'RUNTIME_MAX_USE=1G\n' 800000 - 5000 0 not "1G is far from full"
early 'RUNTIME_MAX_USE=20971520\n' 16384 - 5000 0 due "a size in bytes, exactly 80 %"
early '' 80000 1000000 5000 0 due "journald's default, 10 % of a 1G /run, 80 % used"
early '' 70000 1000000 5000 0 not "journald's default, 70 % used"
early '' 3400000 100000000 5000 0 due "journald's default is at most 4G"
early '' 80000 - 5000 0 not "no limit readable"
early 'RUNTIME_MAX_USE=16M\n' - - 5000 0 not "no usage readable"
early 'RUNTIME_MAX_USE=lots\n' 16384 - 5000 0 not "a limit that is not a size"

# the loop with a fake clock: its sleep moves the uptime on instead of waiting, and journalctl notes
# the uptime of every copy's rotate
mkdir -p "$T/bin"
printf '#!/bin/sh\nu=$(cut -d. -f1 "$OCCU_UPTIME")\necho "$((u + $1)).00 0.00" > "$OCCU_UPTIME"\n' > "$T/bin/sleep"
printf '#!/bin/sh\n[ "$1" = --rotate ] && echo "$(cut -d. -f1 "$OCCU_UPTIME")" >> "$OCCU_TEST_ROTATES"\nexit 0\n' > "$T/journalctl-clock"
chmod +x "$T/bin/sleep" "$T/journalctl-clock"
loop() {  # loop <du KiB> <copies>: the uptimes of the first <copies> copies, from a start at 100 s
  setup
  rm -f "$T/rotates"
  echo "100.00 0.00" > "$T/uptime"
  printf 'STORAGE=ram-sync\nSYNC_INTERVAL=1h\nRUNTIME_MAX_USE=16M\n' > "$T/journal"
  PATH="$T/bin:$PATH" OCCU_UPTIME="$T/uptime" OCCU_JOURNALCTL="$T/journalctl-clock" OCCU_TEST_ROTATES="$T/rotates" \
    OCCU_TEST_DU_KIB=$1 sh "$TOOL" run > "$T/loop.out" 2>&1 &
  pid=$!
  i=0
  while [ "$(cat "$T/rotates" 2>/dev/null | wc -l)" -lt "$2" ] && [ "$i" -lt 400 ]; do
    sleep 0.05
    i=$((i + 1))
  done
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  head -n "$2" "$T/rotates" 2>/dev/null | tr '\n' ' '
}
got=$(loop 15000 2)
[ "$got" = "1000 1900 " ] && ok "the loop copies early at 91 %, 15 minutes after its start and then every 15 minutes" || bad "early copies at: '$got'"
grep -q 'the RAM journal is at 91 % of its limit: an early copy' "$T/loop.out" && ok "the loop says why it copies early" || bad "loop output: $(cat "$T/loop.out")"
grep -qx 'LAST_REASON=early' "$T/state/sync.state" && ok "the state says early" || bad "state: $(cat "$T/state/sync.state")"
got=$(loop 10000 1)
[ "$got" = "3700 " ] && ok "below 80 % the loop copies at the interval only" || bad "copies at: '$got'"
grep -qx 'LAST_REASON=interval' "$T/state/sync.state" && ok "the state says interval" || bad "state: $(cat "$T/state/sync.state")"

# B-124: the loop's own copy kept the lock for the rest of the loop's life, so the unit's stop waited
# 120 s for it and copied nothing. Now: the early copy happened, then the stop copies within a few
# seconds. The loop's clock moves 60 s per 0.2 s of real time; RAM is at 91 % until the loop's first
# copy and far below it afterwards, so the loop sleeps towards its interval while the stop comes.
REAL_SLEEP=$(command -v sleep)
mkdir -p "$T/bin-slow"
printf '#!/bin/sh\nu=$(cut -d. -f1 "$OCCU_UPTIME")\necho "$((u + $1)).00 0.00" > "$OCCU_UPTIME"\nexec %s 0.2\n' "$REAL_SLEEP" > "$T/bin-slow/sleep"
printf '#!/bin/sh\nif [ -s "$OCCU_TEST_ROTATES" ]; then k=100; else k=15000; fi\nprintf "%%s\\t%%s\\n" "$k" "$2"\n' > "$T/du-once"
chmod +x "$T/bin-slow/sleep" "$T/du-once"
waitfor() {  # waitfor <tenths of a second> <command...>: 0 once the command succeeds
  n=$1
  shift
  while ! "$@"; do
    [ "$n" -le 0 ] && return 1
    sleep 0.1
    n=$((n - 1))
  done
}
setup
rm -f "$T/rotates"
echo "100.00 0.00" > "$T/uptime"
printf 'STORAGE=ram-sync\nSYNC_INTERVAL=1h\nRUNTIME_MAX_USE=16M\n' > "$T/journal"
PATH="$T/bin-slow:$PATH" OCCU_UPTIME="$T/uptime" OCCU_JOURNALCTL="$T/journalctl-clock" OCCU_TEST_ROTATES="$T/rotates" OCCU_DU="$T/du-once" \
  sh "$TOOL" run > "$T/loop.out" 2>&1 &
pid=$!
if waitfor 300 grep -qx 'LAST_REASON=early' "$T/state/sync.state" 2>/dev/null; then
  ok "the loop copied early by itself"
  OCCU_UPTIME="$T/uptime" OCCU_JOURNALCTL="$T/journalctl-clock" OCCU_TEST_ROTATES="$T/rotates" OCCU_TEST_SYSTEM_STATE=stopping \
    sh "$TOOL" copy stop > "$T/stop.out" 2>&1 &
  spid=$!
  if waitfor 50 sh -c "! kill -0 $spid 2>/dev/null"; then
    wait "$spid"
    rc=$?
    [ "$rc" -eq 0 ] && ok "after the loop's copy the stop copies within 5 s" || bad "the stop's copy exited $rc: $(cat "$T/stop.out")"
  else
    bad "the stop still waits 5 s after the loop's copy (the loop keeps the lock): $(cat "$T/stop.out")"
    kill "$spid" 2>/dev/null
    wait "$spid" 2>/dev/null
  fi
  grep -qx 'LAST_REASON=shutdown' "$T/state/sync.state" && ok "the state says shutdown" || bad "state after the stop: $(cat "$T/state/sync.state")"
  [ "$(wc -l < "$T/rotates")" -eq 2 ] && ok "the stop rotated and copied" || bad "rotates: $(tr '\n' ' ' < "$T/rotates")"
  [ -e "$T/state/stopping" ] && ok "the stop left its mark for the loop" || bad "no stop mark"
else
  bad "the loop did not copy early: $(cat "$T/loop.out")"
fi
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

# a new loop removes the stop's mark and copies again
rm -f "$T/rotates"
echo "100.00 0.00" > "$T/uptime"
PATH="$T/bin:$PATH" OCCU_UPTIME="$T/uptime" OCCU_JOURNALCTL="$T/journalctl-clock" OCCU_TEST_ROTATES="$T/rotates" OCCU_TEST_DU_KIB=15000 \
  sh "$TOOL" run > "$T/loop.out" 2>&1 &
pid=$!
waitfor 200 test -s "$T/rotates" && [ ! -e "$T/state/stopping" ] && ok "a new loop removes the stop's mark and copies" || bad "a new loop: mark $(ls "$T/state"), rotates $(cat "$T/rotates" 2>/dev/null)"
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

# once the stop has begun, the loop's own copies step aside; a manual copy does not
setup
mkdir -p "$T/state"
: > "$T/state/stopping"
printf 'STORAGE=ram-sync\n' > "$T/journal"
out=$(sh "$TOOL" copy early); rc=$?
[ "$rc" -eq 0 ] && ! grep -qx -- '--rotate' "$T/calls" 2>/dev/null && [ ! -e "$T/state/sync.state" ] && ok "the loop copies nothing once the stop began" || bad "an early copy while stopping: rc=$rc $out $(cat "$T/calls" 2>/dev/null)"
case "$out" in *"the unit is stopping"*) ok "and says so" ;; *) bad "output: $out" ;; esac
sh "$TOOL" copy manual >/dev/null
grep -qx 'LAST_REASON=manual' "$T/state/sync.state" && ok "a manual copy still copies while stopping" || bad "manual while stopping: $(cat "$T/state/sync.state" 2>/dev/null)"

# a copy that runs is waited for; one that holds the lock past LOCK_WAIT does not cost the stop's copy
if command -v flock >/dev/null 2>&1; then
  held() { ! flock -n "$T/state/lock" true; }
  setup
  mkdir -p "$T/state"
  printf 'STORAGE=ram-sync\n' > "$T/journal"
  flock "$T/state/lock" "$REAL_SLEEP" 2 &
  hpid=$!
  waitfor 50 held
  start=$(date +%s)
  out=$(OCCU_TEST_SYSTEM_STATE=stopping sh "$TOOL" copy stop); rc=$?
  took=$(( $(date +%s) - start ))
  [ "$rc" -eq 0 ] && [ "$took" -ge 1 ] && grep -qx 'LAST_REASON=shutdown' "$T/state/sync.state" && ok "the stop waits for a copy that runs (${took} s), then copies" || bad "stop behind a running copy: rc=$rc took=$took $out"
  case "$out" in *"without it"*) bad "the stop did not wait: $out" ;; *) ok "and takes the lock" ;; esac
  wait "$hpid"

  setup
  mkdir -p "$T/state"
  printf 'STORAGE=ram-sync\n' > "$T/journal"
  flock "$T/state/lock" "$REAL_SLEEP" 8 &
  hpid=$!
  waitfor 50 held
  out=$(OCCU_JOURNAL_LOCK_WAIT=1 sh "$TOOL" copy early); rc=$?
  [ "$rc" -eq 0 ] && [ ! -e "$T/state/sync.state" ] && ok "a loop copy behind a held lock is left out" || bad "early behind a held lock: rc=$rc $out"
  start=$(date +%s)
  out=$(OCCU_JOURNAL_LOCK_WAIT=1 OCCU_TEST_SYSTEM_STATE=stopping sh "$TOOL" copy stop); rc=$?
  took=$(( $(date +%s) - start ))
  [ "$rc" -eq 0 ] && [ "$took" -le 5 ] && grep -qx 'LAST_REASON=shutdown' "$T/state/sync.state" && ok "the stop copies without a lock held past the wait (${took} s)" || bad "stop behind a held lock: rc=$rc took=$took $out"
  case "$out" in *"without it"*) ok "and says so" ;; *) bad "output: $out" ;; esac
  kill "$hpid" 2>/dev/null
  wait "$hpid" 2>/dev/null
else
  echo "skip the lock cases: no flock"
fi

# B-205: the next copy's first stamp waits for a trusted clock. The unit is after the saved clock,
# not after the gate (which would hold the radio daemons it is Before= behind NTP).
after_words=$(sed -n 's/^After=//p' "$UNIT" | tr ' ' '\n')
echo "$after_words" | grep -qx occu-clock-save.service && ok "the unit starts after the saved clock is back" || bad "occu-journal-sync.service must order After=occu-clock-save.service"
echo "$after_words" | grep -qx 'occu-clock-valid.service\|time-sync.target\|chrony.service' && bad "the unit orders after the clock gate or NTP: the daemons it is Before= would wait for it" || ok "the unit does not wait for NTP itself"
# the loop runs <passes> passes against a fake sleep that moves the uptime on; the last one waits
# (real) 60 s, so the stamps can be read before the kill ends the loop - its trap removes them
stamp_look() {  # stamp_look <clock-state or -> <container> <uptime> <passes> -> "<due>|<next>|<sleeps>"
  setup
  rm -rf "$T/state"
  if [ "$1" = - ]; then rm -f "$T/gate"; else printf '%s\n' "$1" > "$T/gate"; fi
  if [ "$2" = 1 ]; then : > "$T/container"; else rm -f "$T/container"; fi
  echo "$3.00 0.00" > "$T/uptime"
  printf 'STORAGE=ram-sync\nSYNC_INTERVAL=1h\n' > "$T/journal"
  rm -f "$T/sleeps"
  mkdir -p "$T/bin-count"
  printf '#!/bin/sh\necho "$1" >> "%s"\nn=$(wc -l < "%s")\nu=$(cut -d. -f1 "$OCCU_UPTIME")\n[ "$n" -ge %s ] && exec %s 60\necho "$((u + $1)).00 0.00" > "$OCCU_UPTIME"\nexit 0\n' "$T/sleeps" "$T/sleeps" "$4" "$REAL_SLEEP" > "$T/bin-count/sleep"
  chmod +x "$T/bin-count/sleep"
  PATH="$T/bin-count:$PATH" OCCU_UPTIME="$T/uptime" OCCU_CLOCK_STATE="$T/gate" OCCU_CONTAINER_FILE="$T/container" \
    OCCU_TEST_DU_KIB=10 sh "$TOOL" run > "$T/loop.out" 2>&1 &
  lpid=$!
  waitfor 100 sh -c "[ \$(cat '$T/sleeps' 2>/dev/null | wc -l) -ge $4 ]"
  r="$(cat "$T/state/sync.due" 2>/dev/null)|$(cat "$T/state/sync.next" 2>/dev/null)|$(tr '\n' ' ' < "$T/sleeps" 2>/dev/null)"
  kill "$lpid" 2>/dev/null
  wait "$lpid" 2>/dev/null
  echo "$r"
}
got=$(stamp_look - - 10 3)
case "$got" in "||5 5 5 ") ok "before the clock gate: no stamp, and the loop looks again every 5 s" ;; *) bad "before the gate: '$got'" ;; esac
got=$(stamp_look ntp - 10 1)
now=$(date +%s)
due=${got%%|*}; rest=${got#*|}; next=${rest%%|*}; sl=${rest#*|}
if [ "$due" = 3610 ] && [ "$sl" = "60 " ] && [ -n "$next" ] && [ $((next - now - 3600)) -ge -5 ] && [ $((next - now - 3600)) -le 5 ]; then
  ok "after the gate: sync.due on the boot's clock (3610), sync.next on the wall clock, a minute's sleep"
else
  bad "after the gate: '$got' (now $now)"
fi
got=$(stamp_look - 1 10 1)
case "$got" in 3610\|?*\|"60 ") ok "in a container the clock is trusted at once" ;; *) bad "container: '$got'" ;; esac
got=$(stamp_look - - 250 1)
case "$got" in 3850\|?*\|"60 ") ok "a gate that never answers: the stamp after 240 s of uptime" ;; *) bad "no gate after 250 s: '$got'" ;; esac
# the gate opens while the loop waits: the stamp comes at the next pass
printf 'STORAGE=ram-sync\nSYNC_INTERVAL=1h\n' > "$T/journal"
setup; rm -rf "$T/state" "$T/gate" "$T/container" "$T/sleeps"
echo "10.00 0.00" > "$T/uptime"
printf '#!/bin/sh\necho "$1" >> "%s"\nn=$(wc -l < "%s")\nu=$(cut -d. -f1 "$OCCU_UPTIME")\n[ "$n" -eq 2 ] && echo timeout > "%s"\n[ "$n" -ge 3 ] && exec %s 60\necho "$((u + $1)).00 0.00" > "$OCCU_UPTIME"\nexit 0\n' "$T/sleeps" "$T/sleeps" "$T/gate" "$REAL_SLEEP" > "$T/bin-count/sleep"
PATH="$T/bin-count:$PATH" OCCU_UPTIME="$T/uptime" OCCU_CLOCK_STATE="$T/gate" OCCU_CONTAINER_FILE="$T/container" \
  OCCU_TEST_DU_KIB=10 sh "$TOOL" run > "$T/loop.out" 2>&1 &
lpid=$!
waitfor 100 sh -c "[ \$(cat '$T/sleeps' 2>/dev/null | wc -l) -ge 3 ]"
got="$(cat "$T/state/sync.due" 2>/dev/null)|$(tr '\n' ' ' < "$T/sleeps")"
kill "$lpid" 2>/dev/null
wait "$lpid" 2>/dev/null
[ "$got" = "3610|5 5 60 " ] && ok "the gate opens while the loop waits: stamped at the next pass (5 s later)" || bad "gate opening: '$got'"
[ ! -e "$T/state/sync.next" ] && [ ! -e "$T/state/sync.due" ] && ok "the loop's stop removes both stamps" || bad "stamps left after the stop: $(ls "$T/state")"

[ "$fails" -eq 0 ] && echo "lite-journal-sync-test: all passed" || echo "lite-journal-sync-test: $fails failed"
[ "$fails" -eq 0 ]
