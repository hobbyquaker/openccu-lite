#!/bin/sh
# openccu-lite: lite-machine-id - the install of a stored ID, the first boot that derives it from
# the board serial, and B-182: the journal written under the transient ID moves into the final
# ID's directory as archived files (journald's own archive names, from the header) instead of
# being removed; a second boot changes nothing; no journal directory (RAM) is no error. And B-340:
# the boot that changes the ID restarts the syslog forwarder, whose journalctl -f reads the old
# ID's directory only (on the userfs), once the files have moved. And B-341: the boot that applies
# a restore finds the backup's stored ID while journald runs on the previous one, and switches the
# same way.
#
# Usage: sh scripts/testcases/lite-machine-id-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-machine-id"
[ -f "$TOOL" ] || { echo "lite-machine-id not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

mkdir -p "$T/bin" "$T/userfs/etc" "$T/var" "$T/run" "$T/journal"
# mountpoint says the userfs is mounted; systemctl logs and marks the restart; journalctl answers
# a header for system.journal only, and only once journald was restarted (the files are closed then)
cat > "$T/bin/mountpoint" <<'EOS'
#!/bin/sh
exit 0
EOS
cat > "$T/bin/systemctl" <<'EOS'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
case "$*" in
  *occu-syslog-forward.service) [ -e "$FAKE_OLD_DIR" ] && echo "forwarder restarted before the files moved" >> "$FAKE_LOG" ;;
esac
touch "$FAKE_RESTARTED"
EOS
cat > "$T/bin/journalctl" <<'EOS'
#!/bin/sh
[ -e "$FAKE_RESTARTED" ] || { echo "journalctl asked before the restart" >> "$FAKE_LOG"; exit 1; }
case "$3" in
  */system.journal)
    printf 'File path: %s\nMachine ID: 0123\nSequential number ID: 0f8f63d9c1cf440c86f9d5c43ed7b6bf\nState: OFFLINE\nHead sequential number: 16965234 (102de72)\nTail sequential number: 17013915 (1039c9b)\nHead realtime timestamp: Thu 2026-09-24 08:55:03 CEST (65c35144897c8)\n' "$3" ;;
  *) exit 1 ;;
esac
EOS
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" FAKE_LOG="$T/log" FAKE_RESTARTED="$T/restarted"
export LITE_MACHINE_ID_STORE="$T/userfs/etc/machine-id" LITE_BOARD_SERIAL="$T/var/board_serial" \
  LITE_ETC_MACHINE_ID="$T/run/machine-id" LITE_RUN_MACHINE_ID="$T/run/machine-id" \
  LITE_JOURNAL_DIR="$T/journal" LITE_JOURNALCTL="$T/bin/journalctl" LITE_SYSTEMCTL="$T/bin/systemctl"
: > "$T/log"

# install without a stored ID: nothing, the transient ID stays
OLD=1c1cd3f9d70f4b9f9a0d3c8b6e5f4a3b
printf '%s\n' "$OLD" > "$T/run/machine-id"
out=$(sh "$TOOL" install); rc=$?
[ $rc = 0 ] && [ "$(cat "$T/run/machine-id")" = "$OLD" ] && ok "install without a store: transient ID kept ($out)" || bad "install without a store: rc $rc ($out)"

# the first boot: the ID is derived from the serial and stored, journald restarted, the transient
# ID's journal adopted
printf 'NEQ0123456\n' > "$T/var/board_serial"
WANT=$(printf 'openccu-lite-machine-id:NEQ0123456' | sha256sum | cut -c1-32)
WANT="$(printf %s "$WANT" | cut -c1-12)4$(printf %s "$WANT" | cut -c14-16)8$(printf %s "$WANT" | cut -c18-32)"
mkdir -p "$T/journal/$OLD"
export FAKE_OLD_DIR="$T/journal/$OLD"
printf 'live' > "$T/journal/$OLD/system.journal"
printf 'user' > "$T/journal/$OLD/user-8100.journal"
printf 'old' > "$T/journal/$OLD/system@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-0000000000000001-0005f00000000000.journal"
printf 'bad' > "$T/journal/$OLD/system.journal~"
out=$(sh "$TOOL" store); rc=$?
[ $rc = 0 ] && ok "store: rc 0" || bad "store: rc $rc ($out)"
[ "$(cat "$T/userfs/etc/machine-id")" = "$WANT" ] && ok "store: the ID from the serial is stored" || bad "store: stored '$(cat "$T/userfs/etc/machine-id")', want $WANT"
[ "$(cat "$T/run/machine-id")" = "$WANT" ] && ok "store: installed in place" || bad "store: run id '$(cat "$T/run/machine-id")'"
grep -qx "try-restart systemd-journald.service" "$T/log" && ok "store: journald restarted" || bad "store: no restart: $(cat "$T/log")"
grep -q "asked before the restart" "$T/log" && bad "store: the header was read before journald closed the file" || ok "store: journald restarted before the files moved"
NEW="$T/journal/$WANT"
[ -f "$NEW/system@0f8f63d9c1cf440c86f9d5c43ed7b6bf-000000000102de72-00065c35144897c8.journal" ] && ok "store: system.journal archived under its header's name" || bad "store: system.journal not archived: $(ls "$NEW" 2>&1)"
[ "$(cat "$NEW/system@0f8f63d9c1cf440c86f9d5c43ed7b6bf-000000000102de72-00065c35144897c8.journal")" = live ] && ok "store: the file's content moved" || bad "store: content"
u=$(find "$NEW" -maxdepth 1 -name 'user-8100@*' -printf '%f\n' | head -n1)
case "$u" in
  user-8100@????????????????????????????????-0000000000000000-????????????????.journal) ok "store: a user journal without a readable header still gets the archive shape ($u)" ;;
  *) bad "store: user journal: '$u'" ;;
esac
[ -f "$NEW/system@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-0000000000000001-0005f00000000000.journal" ] && ok "store: an archived file keeps its name" || bad "store: archived name changed"
[ -f "$NEW/system.journal~" ] && ok "store: a .journal~ keeps its name" || bad "store: .journal~"
[ ! -e "$T/journal/$OLD" ] && ok "store: the transient ID's directory is gone" || bad "store: old dir left: $(ls "$T/journal/$OLD")"
echo "$out" | grep -q "4 file(s) moved" && ok "store: says what it moved" || bad "store: output: $out"
# B-340: the forwarder's journalctl -f started under the old ID and reads nothing from here on
grep -qx "try-restart --no-block occu-syslog-forward.service" "$T/log" && ok "store: the syslog forwarder is restarted, without waiting for it" || bad "store: the forwarder is not restarted: $(cat "$T/log")"
grep -q "before the files moved" "$T/log" && bad "store: the forwarder was restarted before the adoption" || ok "store: the forwarder is restarted after the adoption"
[ "$(tail -n1 "$T/log")" = "try-restart --no-block occu-syslog-forward.service" ] && ok "store: journald first, the forwarder last" || bad "store: order: $(cat "$T/log")"

# the second boot: the stored ID is installed, nothing else happens
: > "$T/log"; rm -f "$T/restarted"
printf 'other\n' > "$T/run/machine-id"
out=$(sh "$TOOL" install); rc=$?
[ $rc = 0 ] && [ "$(cat "$T/run/machine-id")" = "$WANT" ] && ok "install: the stored ID ($out)" || bad "install: rc $rc '$(cat "$T/run/machine-id")'"
out=$(sh "$TOOL" store); rc=$?
[ $rc = 0 ] && [ ! -s "$T/log" ] && [ "$(cat "$T/userfs/etc/machine-id")" = "$WANT" ] && ok "store again: nothing to do" || bad "store again: rc $rc, log '$(cat "$T/log")'"

# B-341: the boot that applies a restore. "install" ran before S05CheckBackupRestore, so the
# running ID is the one the system had before (a factory reset's); the restore brought the backup's
# stored ID. store installs it and switches like a derived one: journald, the adoption, the forwarder
: > "$T/log"; rm -f "$T/restarted"
RESET=9e330afb0c2d4e6f8a1b3c5d7e9f0a1b
BACKUP=3cf25f520c2d4e6f8a1b3c5d7e9f0a1b
printf '%s\n' "$RESET" > "$T/run/machine-id"
printf '%s\n' "$BACKUP" > "$T/userfs/etc/machine-id"
mkdir -p "$T/journal/$RESET"
export FAKE_OLD_DIR="$T/journal/$RESET"
printf 'live' > "$T/journal/$RESET/system.journal"
out=$(sh "$TOOL" store); rc=$?
[ $rc = 0 ] && ok "restore: rc 0" || bad "restore: rc $rc ($out)"
[ "$(cat "$T/userfs/etc/machine-id")" = "$BACKUP" ] && ok "restore: the backup's stored ID stays" || bad "restore: stored '$(cat "$T/userfs/etc/machine-id")'"
[ "$(cat "$T/run/machine-id")" = "$BACKUP" ] && ok "restore: the backup's ID is installed in place" || bad "restore: run id '$(cat "$T/run/machine-id")'"
grep -qx "try-restart systemd-journald.service" "$T/log" && ok "restore: journald restarted on the backup's ID" || bad "restore: journald not restarted: '$(cat "$T/log")'"
[ -f "$T/journal/$BACKUP/system@0f8f63d9c1cf440c86f9d5c43ed7b6bf-000000000102de72-00065c35144897c8.journal" ] && [ ! -e "$T/journal/$RESET" ] && ok "restore: the boot's journal adopted into the backup's ID's directory" || bad "restore: not adopted: $(ls "$T/journal/$BACKUP" "$T/journal/$RESET" 2>&1)"
grep -q "before the files moved" "$T/log" && bad "restore: the forwarder was restarted before the adoption" || ok "restore: the forwarder is restarted after the adoption"
[ "$(tail -n1 "$T/log")" = "try-restart --no-block occu-syslog-forward.service" ] && ok "restore: the syslog forwarder is restarted last" || bad "restore: forwarder: '$(cat "$T/log")'"
rm -rf "$T/journal/$BACKUP"

# a RAM journal: no directory under the transient ID, no error, journald still restarted
: > "$T/log"; rm -rf "$T/journal" "$T/userfs/etc/machine-id"; mkdir -p "$T/journal"
printf '%s\n' "$OLD" > "$T/run/machine-id"
out=$(sh "$TOOL" store); rc=$?
[ $rc = 0 ] && grep -qx "try-restart systemd-journald.service" "$T/log" && [ ! -e "$T/journal/$WANT" ] && ok "store without a journal directory: restart only ($out)" || bad "store without a journal directory: rc $rc ($out)"
grep -qx "try-restart --no-block occu-syslog-forward.service" "$T/log" && ok "store without a journal directory: the forwarder is restarted all the same" || bad "store without a journal directory: the forwarder is not restarted"

# the unit says what it does
grep -q "as archived files" "$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/occu-machine-id-store.service" && ok "the store unit's comment names the adoption" || bad "unit comment"

[ $fails = 0 ] && echo "all ok" || { echo "$fails failed"; exit 1; }
