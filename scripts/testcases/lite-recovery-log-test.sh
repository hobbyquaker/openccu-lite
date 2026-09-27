#!/bin/sh
# openccu-lite: the recovery system keeps its install log for the next boot (task 145, D-64).
#
#   - S90AutoUpdate's save_install_log() in a sandbox (its two absolute paths rewritten): with a
#     log it writes /usr/local/var/recovery/<UTC time>.log, 0644, byte-identical; without one it
#     does nothing; with a directory it cannot create it still exits 0 - nothing there may fail
#     the update or the reboot;
#   - both unattended update paths call it after the update, between the marker's removal and the
#     userfs remount, so the file lands while the userfs is read-write;
#   - the recovery's busybox has what the function uses (date, cp, chmod, mkdir);
#   - the boot's log inventory and occulited's storage hint agree on the exception's path.
#
# Nothing needs root, systemd or the recovery image.
#
# Usage: sh scripts/testcases/lite-recovery-log-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$HERE/buildroot-external"
S90="$EXT/package/recovery-system/external/overlay/base/etc/init.d/S90AutoUpdate"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

sh -n "$S90" && ok "S90AutoUpdate parses" || bad "S90AutoUpdate does not parse"

# --- the function, in a sandbox ------------------------------------------------------------------
# the function's body with the two absolute paths under the sandbox; the recovery's shell is
# busybox's ash, whose [[ ]] dash lacks, so the extract runs under bash
sed -n '/^save_install_log() {$/,/^}$/p' "$S90" | sed "s|/tmp/fwinstall.log|$T/fwinstall.log|g; s|/usr/local/var/recovery|$T/userfs/var/recovery|g" >"$T/fn.sh"
[ -s "$T/fn.sh" ] && ok "save_install_log() found" || bad "save_install_log() is not in S90AutoUpdate"
run_fn() { bash -c "umask 077; . '$T/fn.sh'; save_install_log; echo rc=\$?"; }

# with a log: the file, its name, its mode, its content
mkdir -p "$T/userfs/var"
printf 'Starting firmware update (DO NOT INTERRUPT!!!):<br/>\n[1/5] Validate update directory... OK<br/>\nFinished firmware update successfully.<br/>\n' >"$T/fwinstall.log"
out=$(run_fn)
[ "$out" = "rc=0" ] && ok "with a log: exit 0" || bad "with a log: $out"
f=$(ls "$T/userfs/var/recovery/" 2>/dev/null | head -1)
case "$f" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]-[0-9][0-9]-[0-9][0-9]Z.log) ok "the file is named after the UTC time: $f" ;;
  *) bad "the file's name: '$f'" ;;
esac
if [ -n "$f" ]; then
  cmp -s "$T/fwinstall.log" "$T/userfs/var/recovery/$f" && ok "the copy is byte-identical" || bad "the copy differs"
  m=$(stat -c %a "$T/userfs/var/recovery/$f"); [ "$m" = 644 ] && ok "the copy is 0644 (readable to occulited)" || bad "the copy's mode is $m"
  d=$(stat -c %a "$T/userfs/var/recovery"); [ "$d" = 755 ] && ok "the directory is 0755 whatever the umask (occulited lists it)" || bad "the directory's mode is $d"
  [ "$(ls "$T/userfs/var/recovery/" | wc -l)" -eq 1 ] && ok "one file per run" || bad "more than one file"
fi
# a second run a second later: a second file, the first untouched
sleep 1; echo "more" >>"$T/fwinstall.log"; run_fn >/dev/null
[ "$(ls "$T/userfs/var/recovery/" | wc -l)" -eq 2 ] && ok "a later update is a second file" || bad "the second run did not add a file"
# without a log: nothing, exit 0
rm -rf "$T/userfs/var/recovery" "$T/fwinstall.log"
out=$(run_fn); [ "$out" = "rc=0" ] && [ ! -e "$T/userfs/var/recovery" ] && ok "without a log: nothing written, exit 0" || bad "without a log: $out, $(ls "$T/userfs/var" 2>&1)"
# the directory cannot be made (its parent is a file): exit 0, the update goes on
printf 'x' >"$T/fwinstall.log"; rm -rf "$T/userfs/var"; : >"$T/userfs/var"
out=$(run_fn); [ "$out" = "rc=0" ] && ok "unwritable target: exit 0 all the same" || bad "unwritable target: $out"
rm -f "$T/userfs/var"

# --- the call sites -------------------------------------------------------------------------------
# both unattended paths (USB and staged update) end in finish_update(), which calls it once
n=$(grep -c '^ *finish_update$' "$S90")
[ "$n" -eq 2 ] && ok "finish_update is called twice (USB and staged update)" || bad "finish_update is called $n times, want 2"
n=$(grep -c '^ *save_install_log$' "$S90")
[ "$n" -eq 1 ] && ok "save_install_log is called once, in finish_update" || bad "save_install_log is called $n times, want 1"
# the call sits between the markers' removal and the userfs remount to read-only
awk '
  /rm -f \/usr\/local\/.firmwareUpdate$/ { want=1; next }
  want==1 && /^ *save_install_log$/ { want=2; next }
  want==2 && /mount -o ro,remount \/userfs/ { seq++; want=0; next }
  want && /mount -o ro,remount \/userfs/ { want=0 }
  END { print seq+0 }' "$S90" >"$T/seq"
[ "$(cat "$T/seq")" -eq 1 ] && ok "the call sits between the marker removal and the ro remount" || bad "call site out of place: $(cat "$T/seq") in sequence"
grep -q 'mount -o rw,remount /userfs' "$S90" && ok "the userfs is read-write there" || bad "no rw remount in S90AutoUpdate"
# what the function uses is in the recovery's busybox
BB=$(ls "$EXT"/package/recovery-system/external/board/*/busybox.config "$EXT"/package/recovery-system/external/package/*/busybox*.config 2>/dev/null | head -1)
if [ -n "$BB" ]; then
  for a in DATE CP CHMOD MKDIR; do grep -q "^CONFIG_$a=y" "$BB" && ok "recovery busybox has $a" || bad "recovery busybox lacks $a ($BB)"; done
else
  ok "no separate busybox config for the recovery (buildroot's default has date, cp, chmod, mkdir)"
fi

# --- the exception's path, in one place -------------------------------------------------------------
grep -q '/usr/local/var/recovery/\*.log) echo OK' "$HERE/scripts/lite-log-inventory.sh" && ok "lite-log-inventory.sh accepts /usr/local/var/recovery/*.log" || bad "lite-log-inventory.sh does not accept the recovery log's path"
grep -q 'usr/local/tmp/recovery' "$HERE/scripts/lite-log-inventory.sh" && bad "lite-log-inventory.sh still names the old /usr/local/tmp path" || ok "no stale /usr/local/tmp path in lite-log-inventory.sh"

echo; [ "$fails" -eq 0 ] && { echo "lite-recovery-log-test: all checks passed"; exit 0; }
echo "lite-recovery-log-test: $fails check(s) failed"; exit 1
