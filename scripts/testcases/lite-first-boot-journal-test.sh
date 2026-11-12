#!/bin/sh
# openccu-lite (task 341): lite-first-boot-journal keeps the journal of the first boot after a
# switch to openccu-lite once on the userfs. Against a stand-in journalctl:
#   - mark: only with the CCU's ReGa database on the userfs and no first-boot import recorded by
#     occulited, and only while no copy exists; an earlier mark goes;
#   - save: only with the mark; the boot's journal gzipped, cut at the cap, the mark gone - a
#     second save (the timer, then the shutdown) changes nothing; a failed copy keeps the mark;
#   - the units: the mark before occulited, the copy at the stop and from the timer, both enabled.
#
# Usage: sh scripts/testcases/lite-first-boot-journal-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-first-boot-journal"
UNITS="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system"
PRESET="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system-preset/50-openccu-lite.preset"
[ -x "$TOOL" ] || { echo "lite-first-boot-journal not found (or not executable) under $HERE"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

mkdir -p "$T/config" "$T/state" "$T/run" "$T/var/log"
cat >"$T/journalctl" <<'EOS'
#!/bin/sh
[ -e "$FAKE_FAIL" ] && exit 1
[ "$*" = "-b 0 --no-pager -o short-iso-precise" ] || { echo "journalctl called as: $*" >&2; exit 2; }
i=0; while [ $i -lt 2000 ]; do echo "2026-11-11T22:00:00.000000+0100 box occulited[1]: line $i of the first boot"; i=$((i+1)); done
EOS
chmod +x "$T/journalctl"
export OCCU_FIRST_BOOT_CONFIG="$T/config" OCCU_FIRST_BOOT_STATE="$T/state" OCCU_FIRST_BOOT_MARK="$T/run/first-boot" \
  OCCU_FIRST_BOOT_OUT="$T/var/log/first-boot-journal.txt.gz" OCCU_JOURNALCTL="$T/journalctl" FAKE_FAIL="$T/fail"
OUT=$OCCU_FIRST_BOOT_OUT MARK=$OCCU_FIRST_BOOT_MARK

sh "$TOOL" mark >/dev/null
[ ! -e "$MARK" ] && ok "no ReGa database (a fresh image, a factory reset): no mark" || bad "marked without a ReGa database"
: >"$T/config/homematic.regadom"
out=$(sh "$TOOL" mark)
[ -e "$MARK" ] && ok "the CCU's ReGa database, no import recorded: the first boot after a switch is marked" || bad "not marked: $out"
echo "$out" | grep -q "first boot after a switch" && ok "and it says so" || bad "silent: $out"
sh "$TOOL" save >/dev/null
[ -s "$OUT" ] && [ ! -e "$MARK" ] && ok "save: the copy is there, the mark gone" || bad "save: $(ls -l "$T/var/log" "$T/run")"
[ "$(gzip -dc "$OUT" | wc -l)" = 2000 ] && gzip -dc "$OUT" | head -n1 | grep -q "line 0 of the first boot" && ok "the copy is the boot's journal, from its start" || bad "copy content"
m=$(stat -c %Y "$OUT"); sleep 1
sh "$TOOL" save >/dev/null
[ "$(stat -c %Y "$OUT")" = "$m" ] && ok "a second save (the timer, then the shutdown) changes nothing" || bad "the copy was rewritten"
# the next boot: occulited recorded its import
: >"$T/state/regadom-imported.json"; rm -f "$OUT"
sh "$TOOL" mark >/dev/null
[ ! -e "$MARK" ] && ok "the next boot (import recorded): no mark, and a deleted copy is not made again" || bad "marked after the import"
rm -f "$T/state/regadom-imported.json"
: >"$OUT"
sh "$TOOL" mark >/dev/null
[ ! -e "$MARK" ] && ok "a copy that exists is not made again" || bad "marked with a copy there"
rm -f "$OUT"
: >"$MARK"
sh "$TOOL" mark >/dev/null; sh "$TOOL" save >/dev/null
[ -s "$OUT" ] && ok "mark then save once more" || bad "second round"
# the cap
rm -f "$OUT"; sh "$TOOL" mark >/dev/null
OCCU_FIRST_BOOT_CAP=4096 sh "$TOOL" save >/dev/null
[ "$(gzip -dc "$OUT" | wc -c)" = 4096 ] && ok "cut at the cap (4096 bytes here, 8 MiB by default)" || bad "cap: $(gzip -dc "$OUT" | wc -c)"
grep -q '^CAP=${OCCU_FIRST_BOOT_CAP:-8388608}$' "$TOOL" && ok "the default cap is 8 MiB" || bad "the default cap"
# a failed copy keeps the mark for the next try
rm -f "$OUT"; sh "$TOOL" mark >/dev/null; : >"$FAKE_FAIL"
out=$(sh "$TOOL" save)
[ -e "$MARK" ] && [ ! -e "$OUT" ] && [ ! -e "$OUT.tmp" ] && echo "$out" | grep -q ERROR && ok "a failed copy: no file, the mark stays, it says so" || bad "failed copy: $out $(ls "$T/var/log")"
rm -f "$FAKE_FAIL"
# the units
grep -q '^Before=occulited.service$' "$UNITS/occu-first-boot-journal.service" && grep -q 'lite-first-boot-journal mark$' "$UNITS/occu-first-boot-journal.service" \
  && grep -q '^ExecStop=/usr/libexec/occu/lite-first-boot-journal save$' "$UNITS/occu-first-boot-journal.service" && ok "the unit marks before occulited and copies at its stop" || bad "occu-first-boot-journal.service"
grep -q '^OnBootSec=30min$' "$UNITS/occu-first-boot-journal-save.timer" && grep -q '^ConditionPathExists=/run/occu-journal/first-boot$' "$UNITS/occu-first-boot-journal-save.service" \
  && ok "the timer copies 30 minutes in, only with the mark" || bad "the timer or its service"
grep -q '^enable occu-first-boot-journal.service$' "$PRESET" && grep -q '^enable occu-first-boot-journal-save.timer$' "$PRESET" && ok "both enabled by the preset" || bad "preset"
grep -q '^MARK=${OCCU_FIRST_BOOT_MARK:-/run/occu-journal/first-boot}$' "$TOOL" && ok "the script's mark is the condition's path" || bad "mark path"

echo "failures: $fails"
[ "$fails" = 0 ]
