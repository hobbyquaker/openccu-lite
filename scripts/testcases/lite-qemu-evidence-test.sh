#!/bin/sh
# openccu-lite (B-321): a failed QEMU boot test keeps its evidence. hmipserver's JVM aborted in its
# first minute under TCG on three build rounds, and each time the hs_err file, the core and the
# guest's journal went with the work dir. lite-qemu-test.sh now has the guest move them onto its
# userfs and copies that directory out of the disk copy (debugfs, no mount). Here, with the
# functions taken from the script (awk):
#   - the kernel command line's credential decodes to hmipserver's drop-in (the hs_err file, the
#     core pipe cut at LITE_QEMU_CORE_MB);
#   - stash_snippet, run against a made-up /var/hmipserver and /usr/local, moves hs_err files and
#     cores with the boot's ID and makes nothing on a clean boot;
#   - part_offset reads partition 3 of an MBR disk;
#   - evidence_extract on a made-up disk (an MBR, an ext4 userfs as partition 3): the evidence
#     directory and a core the guest did not move come out, the cores gzipped; without a journal
#     export the raw journal comes out; over LITE_QEMU_EVIDENCE_MB the cores go first; a userfs
#     without anything leaves no directory.
#
# Usage: sh scripts/testcases/lite-qemu-evidence-test.sh    (from the fork's checkout; needs
# e2fsprogs' mke2fs and debugfs, python3)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S="$HERE/scripts/lite-qemu-test.sh"
[ -f "$S" ] || { echo "lite-qemu-test.sh not found at $S"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
PATH="$PATH:/usr/sbin:/sbin"
for c in mke2fs debugfs python3 gzip base64; do
  command -v "$c" >/dev/null 2>&1 || { echo "FAIL $c is missing"; exit 1; }
done

# the functions and the variables they read
for f in stash_snippet part_offset evidence_extract; do
  awk -v f="$f" '$0 == f "() {" {p=1} p {print} p && /^\}$/ {p=0}' "$S" >>"$T/fn.sh"
  grep -q "^$f() {\$" "$T/fn.sh" && ok "$f found in lite-qemu-test.sh" || bad "$f() not found in lite-qemu-test.sh"
done
awk '/^EVID_CORE_MB=/ {p=1} p && /^only_quota\(\)/ {p=0} p {print}' "$S" >"$T/vars.sh"
grep -q '^EVID_CMDLINE=' "$T/vars.sh" && ok "the evidence variables found" || bad "EVID_CMDLINE not found"

# the credential: base64 of a drop-in for hmipserver.service, the core cut at LITE_QEMU_CORE_MB
cmd=$(LITE_QEMU_CORE_MB=128 sh -c ". '$T/vars.sh'; echo \"\$EVID_CMDLINE\"")
case "$cmd" in *' '*) bad "the command line word has a space inside: $cmd";; esac
case "$cmd" in 'systemd.set_credential_binary=systemd.unit-dropin.hmipserver.service~lite-qemu-evidence:'*) ok "a drop-in credential for hmipserver.service";; *) bad "not a drop-in credential: $cmd";; esac
printf '%s' "${cmd##*:}" | base64 -d >"$T/dropin.conf"
printf '%s\n' '[Service]' 'Environment=JAVA_TOOL_OPTIONS=-XX:ErrorFile=/var/hmipserver/hs_err_pid%%p.log' \
  "ExecStartPre=-+/bin/sh -c 'echo \"|/bin/dd of=/usr/local/lite-qemu-core.%%e bs=4096 count=32768\" >/proc/sys/kernel/core_pattern'" >"$T/dropin.want"
cmp -s "$T/dropin.conf" "$T/dropin.want" && ok "the drop-in: hs_err into /var/hmipserver, the core pipe at 128 MB, % as %%" || bad "the drop-in is: $(cat "$T/dropin.conf")"

# stash_snippet against a made-up root
snip=$(. "$T/fn.sh"; stash_snippet | sed "s|/var/hmipserver|$T/root/var/hmipserver|g; s|/usr/local|$T/root/usr/local|g")
mkdir -p "$T/root/var/hmipserver" "$T/root/usr/local"
out=$(sh -c "$snip" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/root/usr/local/lite-qemu-evidence" ] && ok "a clean boot: nothing made (rc 0)" || bad "a clean boot: rc $rc, $(ls "$T/root/usr/local")"
echo crash >"$T/root/var/hmipserver/hs_err_pid954.log"
echo core >"$T/root/usr/local/lite-qemu-core.java"
out=$(sh -c "$snip" 2>&1); rc=$?
b=$(cut -c1-8 /proc/sys/kernel/random/boot_id)
[ "$rc" = 0 ] && [ -f "$T/root/usr/local/lite-qemu-evidence/boot-$b-hs_err_pid954.log" ] && ok "the hs_err file copied with the boot's ID" || bad "hs_err: rc $rc, $out"
[ -f "$T/root/usr/local/lite-qemu-evidence/boot-$b-lite-qemu-core.java" ] && [ ! -e "$T/root/usr/local/lite-qemu-core.java" ] && ok "the core moved with the boot's ID" || bad "core: $out"

# a disk: 1 MiB, then an ext4 userfs made from <tree> as MBR partition 3 at sector 2048
mkdisk() { # <tree> <disk>
  rm -f "$T/part.img" "$2"
  mke2fs -q -F -t ext4 -d "$1" "$T/part.img" 16M >/dev/null 2>&1 || { bad "mke2fs failed"; return 1; }
  python3 - "$T/part.img" "$2" <<'PY'
import struct, sys
part = open(sys.argv[1], "rb").read()
mbr = bytearray(512)
mbr[446 + 32:446 + 48] = struct.pack("<B3sB3sII", 0, b"\0\0\0", 0x83, b"\0\0\0", 2048, len(part) // 512)
mbr[510:512] = b"\x55\xaa"
with open(sys.argv[2], "wb") as f:
    f.write(mbr); f.write(b"\0" * (2048 * 512 - 512)); f.write(part)
PY
}
extract() { # <tree> [max MB]: runs evidence_extract on a disk made of <tree>; $out, $EV
  rm -rf "$T/work" "$T/work.evidence"; mkdir -p "$T/work"
  mkdisk "$1" "$T/work/disk.img" || return 1
  out=$(SYSTEMD=1 DEBUGFS=$(command -v debugfs) WORK="$T/work" EVID_MAX_MB=${2:-512} sh -c "say() { echo \"\$*\"; }; . '$T/fn.sh'; evidence_extract" 2>&1)
  EV="$T/work.evidence"
}

mkdir -p "$T/u1/lite-qemu-evidence" "$T/u1/var/log/journal/x"
echo crash >"$T/u1/lite-qemu-evidence/boot-aa-hs_err_pid954.log"
echo journal | gzip >"$T/u1/lite-qemu-evidence/journal-b0.txt.gz"
head -c 200000 /dev/zero >"$T/u1/lite-qemu-evidence/boot-aa-lite-qemu-core.java"
head -c 100000 /dev/zero >"$T/u1/lite-qemu-core.rfd"
echo raw >"$T/u1/var/log/journal/x/system.journal"
o=$(. "$T/fn.sh"; mkdisk "$T/u1" "$T/d.img" && part_offset "$T/d.img" 3)
[ "$o" = $((2048 * 512)) ] && ok "part_offset: partition 3 at byte $o" || bad "part_offset: '$o'"
o=$(. "$T/fn.sh"; part_offset "$T/d.img" 2)
[ -z "$o" ] && ok "part_offset: no partition 2, empty" || bad "part_offset 2: '$o'"

extract "$T/u1"
[ -f "$EV/boot-aa-hs_err_pid954.log" ] && [ -f "$EV/journal-b0.txt.gz" ] && ok "the evidence directory came out" || bad "evidence: $(ls -la "$EV" 2>&1) / $out"
[ -f "$EV/boot-aa-lite-qemu-core.java.gz" ] && [ ! -e "$EV/boot-aa-lite-qemu-core.java" ] && ok "the moved core, gzipped" || bad "the moved core: $(ls "$EV" 2>&1)"
[ -f "$EV/lite-qemu-core.rfd.gz" ] && ok "a core the guest did not move, gzipped" || bad "the stray core: $(ls "$EV" 2>&1)"
[ ! -e "$EV/journal" ] && ok "with a journal export, no raw journal" || bad "a raw journal next to the export"
[ "$(gzip -dc "$EV/boot-aa-lite-qemu-core.java.gz" | wc -c)" = 200000 ] && ok "the core is whole" || bad "the core lost bytes"
printf '%s\n' "$out" | grep -q "evidence kept at $EV" && ok "and it says where" || bad "no 'evidence kept at' in: $out"

mkdir -p "$T/u2/var/log/journal/x"
echo raw >"$T/u2/var/log/journal/x/system.journal"
extract "$T/u2"
[ -f "$EV/journal/x/system.journal" ] && ok "no export (QEMU died): the raw journal came out" || bad "raw journal: $(ls -R "$EV" 2>&1) / $out"

mkdir -p "$T/u3/lite-qemu-evidence"
echo crash >"$T/u3/lite-qemu-evidence/boot-aa-hs_err_pid954.log"
echo journal | gzip >"$T/u3/lite-qemu-evidence/journal-b0.txt.gz"
head -c 3000000 /dev/urandom >"$T/u3/lite-qemu-evidence/boot-aa-lite-qemu-core.java"
extract "$T/u3" 1
[ ! -e "$EV/boot-aa-lite-qemu-core.java.gz" ] && [ -f "$EV/boot-aa-hs_err_pid954.log" ] && ok "over the cap: the core dropped, the hs_err file kept" || bad "cap: $(ls -l "$EV" 2>&1) / $out"
printf '%s\n' "$out" | grep -q "dropped boot-aa-lite-qemu-core.java.gz" && ok "and it says so" || bad "no 'dropped' in: $out"

mkdir -p "$T/u4/etc"
extract "$T/u4"
[ ! -e "$EV" ] && printf '%s\n' "$out" | grep -q "nothing found" && ok "an empty userfs: no evidence directory" || bad "empty: $(ls -la "$EV" 2>&1) / $out"

echo "failures: $fails"
[ "$fails" = 0 ]
