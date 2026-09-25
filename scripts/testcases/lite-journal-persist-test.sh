#!/bin/sh
# openccu-lite: lite-journal-persist's decision - the storage mode and target per product and per
# /etc/config/journal, including the older PERSIST= key, a USB stick as the target, and what is refused.
#
# Usage: sh scripts/testcases/lite-journal-persist-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-journal-persist"
[ -f "$TOOL" ] || { echo "lite-journal-persist not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0

# case <name> <platform or -> <config lines, \n separated, or -> <expected "storage=… target=…" prefix>
case_() {
  name=$1 platform=$2 config=$3 want=$4
  rm -f "$T/VERSION" "$T/journal"
  [ "$platform" = - ] || printf 'PRODUCT=x\nPLATFORM=%s\n' "$platform" > "$T/VERSION"
  [ "$config" = - ] || printf '%b\n' "$config" > "$T/journal"
  got=$(OCCU_JOURNAL_CONFIG="$T/journal" OCCU_VERSION_FILE="$T/VERSION" sh "$TOOL" decide)
  case "$got" in
    "$want"*) echo "ok   $name: $got" ;;
    *) echo "FAIL $name: want '$want…', got '$got'"; fails=$((fails+1)) ;;
  esac
}

case_ "rpi4 default"                 rpi4 -                       "storage=ram target=userfs platform=rpi4 default=ram source=the product default"
case_ "rpi3 default"                 rpi3 -                       "storage=ram target=userfs platform=rpi3 default=ram"
case_ "ova default"                  ova  -                       "storage=persistent target=userfs platform=ova default=persistent source=the product default"
case_ "lxc default"                  lxc  -                       "storage=persistent target=userfs platform=lxc default=persistent"
case_ "no /VERSION"                  -    -                       "storage=ram target=userfs platform=unknown default=ram"
case_ "PERSIST=1 on rpi4"            rpi4 "PERSIST=1"             "storage=persistent target=userfs platform=rpi4 default=ram source=PERSIST=1"
case_ "PERSIST=0 on ova"             ova  "PERSIST=0"             "storage=ram target=userfs platform=ova default=persistent source=PERSIST=0"
case_ "STORAGE wins over PERSIST"    rpi4 "STORAGE=ram\nPERSIST=1" "storage=ram target=userfs platform=rpi4 default=ram source=STORAGE=ram"
case_ "STORAGE=persistent on rpi4"   rpi4 "STORAGE=persistent"    "storage=persistent target=userfs"
case_ "STORAGE=ram on lxc"           lxc  "STORAGE=ram"           "storage=ram target=userfs platform=lxc default=persistent source=STORAGE=ram"
case_ "empty STORAGE = default"      ova  "STORAGE="              "storage=persistent target=userfs platform=ova default=persistent source=the product default"
case_ "TARGET=userfs"                rpi4 "STORAGE=persistent\nTARGET=userfs" "storage=persistent target=userfs"
case_ "ram-sync"                     rpi4 "STORAGE=ram-sync"      "storage=ram-sync target=userfs platform=rpi4 default=ram source=STORAGE=ram-sync"
case_ "ram-sync on ova"              ova  "STORAGE=ram-sync\nSYNC_INTERVAL=1h\nTARGET_MAX_USE=128M" "storage=ram-sync target=userfs platform=ova default=persistent source=STORAGE=ram-sync"
case_ "a plain path is no target"    ova  "STORAGE=persistent\nTARGET=/media/usb0/journal" "storage=ram target=/media/usb0/journal platform=ova default=persistent source=STORAGE=persistent note=the target /media/usb0/journal is neither the userfs, a USB stick"
case_ "ram-sync to a path: RAM"      rpi4 "STORAGE=ram-sync\nTARGET=/media/usb0/journal" "storage=ram target=/media/usb0/journal platform=rpi4 default=ram source=STORAGE=ram-sync note=the target"
# a USB stick by its label: ram-sync only; persistent there is refused, and RAM keeps the target
case_ "ram-sync to a stick"          rpi4 "STORAGE=ram-sync\nTARGET=usb:LOGSTICK/journal" "storage=ram-sync target=usb:LOGSTICK/journal platform=rpi4 default=ram source=STORAGE=ram-sync"
case_ "a stick, a deeper directory"  rpi4 "STORAGE=ram-sync\nTARGET=usb:LOG-2_x.y/ccu/journal" "storage=ram-sync target=usb:LOG-2_x.y/ccu/journal platform=rpi4"
case_ "persistent on a stick: RAM"   ova  "STORAGE=persistent\nTARGET=usb:LOGSTICK/journal" "storage=ram target=usb:LOGSTICK/journal platform=ova default=persistent source=STORAGE=persistent note=persistent on the USB stick LOGSTICK is not possible"
case_ "the default on ova, a stick"  ova  "TARGET=usb:LOGSTICK/journal" "storage=ram target=usb:LOGSTICK/journal platform=ova default=persistent source=the product default note=persistent on the USB stick"
case_ "ram with a stick target"      rpi4 "STORAGE=ram\nTARGET=usb:LOGSTICK/journal" "storage=ram target=usb:LOGSTICK/journal platform=rpi4 default=ram source=STORAGE=ram"
case_ "a stick with .. in its path"  rpi4 "STORAGE=ram-sync\nTARGET=usb:LOGSTICK/../x" "storage=ram target=usb:LOGSTICK/../x platform=rpi4 default=ram source=STORAGE=ram-sync note=the target usb:LOGSTICK/../x is not a directory on a USB stick"
case_ "a stick without a directory"  rpi4 "STORAGE=ram-sync\nTARGET=usb:LOGSTICK" "storage=ram target=usb:LOGSTICK platform=rpi4 default=ram source=STORAGE=ram-sync note=the target"
# task 228: a network share of occulited's by its name - ram-sync only, like a stick
case_ "ram-sync to a share"          rpi4 "STORAGE=ram-sync\nTARGET=share:nas/ccu/journal" "storage=ram-sync target=share:nas/ccu/journal platform=rpi4 default=ram source=STORAGE=ram-sync"
case_ "persistent on a share: RAM"   ova  "STORAGE=persistent\nTARGET=share:nas/journal" "storage=ram target=share:nas/journal platform=ova default=persistent source=STORAGE=persistent note=persistent on the network share nas is not possible"
case_ "the default on ova, a share"  ova  "TARGET=share:nas/journal" "storage=ram target=share:nas/journal platform=ova default=persistent source=the product default note=persistent on the network share nas"
case_ "a share with .. in its path"  rpi4 "STORAGE=ram-sync\nTARGET=share:nas/../x" "storage=ram target=share:nas/../x platform=rpi4 default=ram source=STORAGE=ram-sync note=the target share:nas/../x is not a directory on a network share"
case_ "a bogus STORAGE"              rpi4 "STORAGE=disk"          "storage=ram target=userfs platform=rpi4 default=ram source=the product default note=STORAGE=disk is not"
case_ "sizes do not change the mode" ova  "RUNTIME_MAX_USE=8M\nSYSTEM_MAX_USE=64M" "storage=persistent target=userfs"

# the box's drop-in in /run carries the overrides (Storage=volatile for ram-sync, the sizes): journald
# applies drop-ins by file name across directories, so the image's own must sort before it
DROPIN=$(sed -n 's|^DROPIN=/run/systemd/journald.conf.d/||p' "$TOOL")
IMG_DIR="$HERE/buildroot-external/overlay/lite/etc/systemd/journald.conf.d"
for f in "$IMG_DIR"/*.conf; do
  n=${f##*/}
  last=$(printf '%s\n%s\n' "$n" "$DROPIN" | LC_ALL=C sort | tail -1)
  if [ -n "$DROPIN" ] && [ "$last" = "$DROPIN" ]; then echo "ok   the image's $n sorts before the box's $DROPIN"
  else echo "FAIL the image's $n sorts after the box's drop-in '$DROPIN': its settings would win"; fails=$((fails+1)); fi
done

# the flush wait: done when no journal file is left in RAM - journald removes the runtime journal
# but keeps /run/log/journal itself, so waiting for the directory ran into the limit on every boot
R="$T/run-journal"
flush_case() {
  name=$1 steps=$2 want=$3 maxs=$4
  start=$(date +%s)
  OCCU_JOURNAL_RUNTIME="$R" OCCU_JOURNAL_FLUSH_STEPS="$steps" sh "$TOOL" wait-flushed
  rc=$? took=$(( $(date +%s) - start ))
  if [ "$rc" = "$want" ] && [ "$took" -le "$maxs" ]; then echo "ok   $name: exit $rc after ${took}s"
  else echo "FAIL $name: want exit $want within ${maxs}s, got exit $rc after ${took}s"; fails=$((fails+1)); fi
}
rm -rf "$R"; mkdir -p "$R"
flush_case "the directory stays, the files are gone: no wait" 50 0 1
rm -rf "$R"
flush_case "no runtime journal at all: no wait"               50 0 1
mkdir -p "$R/0123456789abcdef"; : > "$R/0123456789abcdef/system.journal"
flush_case "a file that stays: the limit, and a failure"       5 1 3
( sleep 1; rm -rf "$R/0123456789abcdef" ) &
flush_case "the files go while waiting: the wait ends"        50 0 4
wait

# B-216: one journal file, not one per user - nine active 4M files filled SystemMaxUse=32M on the VM
# and the vacuum removed every archive at each rotation
IMG_CONF="$IMG_DIR/10-openccu-lite.conf"
grep -qx 'SplitMode=none' "$IMG_CONF" && echo "ok   journald writes one file (SplitMode=none)" || { echo "FAIL 10-openccu-lite.conf must set SplitMode=none"; fails=$((fails+1)); }
um=$(sed -n 's/^SystemMaxUse=\([0-9]*\)M$/\1/p' "$IMG_CONF")
[ -n "$um" ] && [ "$um" -ge 16 ] && echo "ok   SystemMaxUse=${um}M leaves room for archives beside the one active file (${um}/8 M each)" || { echo "FAIL SystemMaxUse: '$um'"; fails=$((fails+1)); }

# the per-user files an earlier image left are given archive names, so the vacuum can take them
J="$T/split"
rm -rf "$J"; mkdir -p "$J/mid" "$T/fds"
for n in system.journal user-8111.journal user-30000.journal user-30001.journal user-30002.journal 'user-8100@0f8f63d9c1cf440c86f9d5c43ed7b6bf-0000000000000001-0000000000000002.journal'; do : > "$J/mid/$n"; done
touch -d @1790000000 "$J/mid/user-30002.journal"
cat > "$T/jctl" <<'JC'
#!/bin/sh
case "$*" in
  *user-8111.journal*) printf 'File path: x\nSequential number ID: 0f8f63d9c1cf440c86f9d5c43ed7b6bf\nState: OFFLINE\nHead sequential number: 17037448 (103f888)\nHead realtime timestamp: Fri 2026-09-25 12:52:23 CEST (65c4c82e0242c)\n' ;;
  *user-30000.journal*) printf 'Sequential number ID: 0f8f63d9c1cf440c86f9d5c43ed7b6bf\nHead sequential number: 5 (5)\nHead realtime timestamp: Fri 2026-09-25 12:52:23 CEST (65c4c82e0242c)\n' ;;
  *user-30002.journal*) echo "File corrupted" >&2; exit 1 ;;
  *) exit 1 ;;
esac
JC
chmod +x "$T/jctl"
ln -s "$J/mid/user-30001.journal" "$T/fds/7"
out=$(OCCU_JOURNALCTL="$T/jctl" OCCU_JOURNALD_FDS="$T/fds" sh "$TOOL" archive-split "$J")
got=$(ls "$J/mid" | LC_ALL=C sort | tr '\n' ' ')
want="system.journal user-30000@0f8f63d9c1cf440c86f9d5c43ed7b6bf-0000000000000005-00065c4c82e0242c.journal user-30001.journal user-30002@00065bfeda25e000-0000000000000000.journal~ user-8100@0f8f63d9c1cf440c86f9d5c43ed7b6bf-0000000000000001-0000000000000002.journal user-8111@0f8f63d9c1cf440c86f9d5c43ed7b6bf-000000000103f888-00065c4c82e0242c.journal "
if [ "$got" = "$want" ]; then echo "ok   per-user files archived by their headers, an unreadable one disposed, an open one and system.journal left"
else echo "FAIL archive-split: got '$got'"; fails=$((fails+1)); fi
case "$out" in *"3 per-user journal file(s)"*"archived"*) echo "ok   and it says how many" ;; *) echo "FAIL archive-split output: $out"; fails=$((fails+1)) ;; esac
case "$out" in *"user-30001.journal is open in journald"*) echo "ok   and names the open one" ;; *) echo "FAIL the open file not named: $out"; fails=$((fails+1)) ;; esac
out=$(OCCU_JOURNALCTL="$T/jctl" OCCU_JOURNALD_FDS="$T/fds" sh "$TOOL" archive-split "$J")
[ "$(ls "$J/mid" | LC_ALL=C sort | tr '\n' ' ')" = "$want" ] && [ -z "$(echo "$out" | grep archived)" ] && echo "ok   a second run changes nothing" || { echo "FAIL second run: $out $(ls "$J/mid")"; fails=$((fails+1)); }
grep -q '^archive_split /var/log/journal$' "$TOOL" && echo "ok   the userfs target archives them after its mount" || { echo "FAIL lite-journal-persist does not archive the per-user files after the mount"; fails=$((fails+1)); }

[ "$fails" -eq 0 ] && echo "lite-journal-persist-test: all passed" || echo "lite-journal-persist-test: $fails failed"
[ "$fails" -eq 0 ]
