#!/bin/sh
# openccu-lite (task 308): lite-qemu-test.sh must leave nothing behind, however it ends. On dev.35's
# round QEMU was OOM-killed mid-run; the script's guest driver was then restarted against the dead
# socket for minutes until its bash segfaulted, and the work dir (a 4.5 GB sparse disk copy) stayed
# in the runner's tmpfs /tmp - and so did the fresh probe's after a pass. Here the script runs
# against a stub qemu-system-x86_64 (and a fake image without rootfs.ext4, so the busybox path) in
# a work dir of its own (LITE_QEMU_WORKDIR):
#   - QEMU fails to start: rc 1, the work dir gone;
#   - QEMU dies after the start: the script says so within seconds (no waiting out the HTTP loop),
#     rc 1, the work dir gone;
#   - the script is terminated while QEMU runs: QEMU is stopped, rc 143, the work dir gone;
#   - the work dir lands in LITE_QEMU_WORKDIR, and the default avoids a tmpfs /tmp.
#
# Usage: sh scripts/testcases/lite-qemu-cleanup-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S="$HERE/scripts/lite-qemu-test.sh"
[ -f "$S" ] || { echo "lite-qemu-test.sh not found at $S"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

mkdir -p "$T/bin" "$T/img"
head -c 65536 /dev/zero >"$T/img/disk.img"
# the stub: QEMU_STUB=fail exits 1; otherwise it "daemonizes": a sleeper of QEMU_STUB seconds whose
# pid goes into the -pidfile, as QEMU's own would. The sleeper's pid is also kept for the test.
cat >"$T/bin/qemu-system-x86_64" <<EOS
#!/bin/sh
[ "\${QEMU_STUB:-}" = fail ] && exit 1
pf=
while [ \$# -gt 0 ]; do [ "\$1" = -pidfile ] && pf=\$2; shift; done
sleep "\${QEMU_STUB:-300}" >/dev/null 2>&1 </dev/null &
echo \$! >"\$pf"
echo \$! >"$T/qemu.pid"
exit 0
EOS
chmod +x "$T/bin/qemu-system-x86_64"

leftover() { # what is left in the work dir's parent besides serial logs
  find "$T/work" -mindepth 1 -maxdepth 1 ! -name '*.serial.log' 2>/dev/null | head -5
}
run() { # <stub> [timeout]: runs the script in the foreground; $rc, $out, $took
  rm -rf "$T/work" "$T/qemu.pid"
  t0=$(date +%s)
  out=$(PATH="$T/bin:$PATH" QEMU_STUB="$1" LITE_QEMU_WORKDIR="$T/work" LITE_QEMU_ADDONS="" \
    timeout "${2:-120}" bash "$S" "$T/img/disk.img" 18099 2>&1)
  rc=$?
  took=$(( $(date +%s) - t0 ))
}

run fail
[ "$rc" = 1 ] && ok "QEMU that fails to start: rc 1" || bad "QEMU that fails to start: rc $rc: $out"
printf '%s\n' "$out" | grep -q 'qemu failed to start' && ok "and it says so" || bad "no 'qemu failed to start' in: $out"
[ -z "$(leftover)" ] && ok "and the work dir is gone" || bad "work dir left behind: $(leftover)"
printf '%s\n' "$out" | grep -q "work dir $T/work/lite-qemu\." && ok "the work dir is in LITE_QEMU_WORKDIR" || bad "the work dir is not in LITE_QEMU_WORKDIR: $out"

run 2
[ "$rc" = 1 ] && ok "QEMU that dies after the start: rc 1" || bad "QEMU that dies: rc $rc: $out"
printf '%s\n' "$out" | grep -q "QEMU's process (pid [0-9]*) is gone" && ok "and it says QEMU is gone" || bad "no 'QEMU's process is gone' in: $out"
[ "$took" -le 30 ] && ok "within seconds (${took}s), not after the HTTP wait" || bad "QEMU's death took ${took}s to notice"
[ -z "$(leftover)" ] && ok "and the work dir is gone" || bad "work dir left behind: $(leftover)"

# terminated while QEMU runs: start in the background, wait for the stub's pid, TERM the script
rm -rf "$T/work" "$T/qemu.pid"
PATH="$T/bin:$PATH" QEMU_STUB=300 LITE_QEMU_WORKDIR="$T/work" LITE_QEMU_ADDONS="" \
  bash "$S" "$T/img/disk.img" 18099 >"$T/term.log" 2>&1 &
SP=$!
for _ in $(seq 1 50); do [ -s "$T/qemu.pid" ] && break; sleep 0.2; done
QP=$(cat "$T/qemu.pid" 2>/dev/null)
[ -n "$QP" ] && kill -0 "$QP" 2>/dev/null && ok "the stub QEMU runs (pid $QP)" || bad "the stub QEMU did not start: $(cat "$T/term.log")"
sleep 1
kill -TERM "$SP"
wait "$SP"; rc=$?
[ "$rc" = 143 ] && ok "terminated: rc 143" || bad "terminated: rc $rc: $(cat "$T/term.log")"
grep -q terminated "$T/term.log" && ok "and it says so" || bad "no 'terminated' in: $(cat "$T/term.log")"
gone=1; for _ in $(seq 1 20); do kill -0 "$QP" 2>/dev/null || { gone=0; break; }; sleep 0.5; done
[ "$gone" = 0 ] && ok "QEMU stopped with the script" || { bad "QEMU (pid $QP) outlived the script"; kill "$QP" 2>/dev/null; }
[ -z "$(leftover)" ] && ok "and the work dir is gone" || bad "work dir left behind: $(leftover)"

# the default work dir: /var/tmp when TMPDIR is a tmpfs, never the tmpfs itself
grep -q 'mktemp -d /var/tmp/lite-qemu' "$S" && grep -q 'stat -f -c %T "${TMPDIR:-/tmp}"' "$S" \
  && ok "the default work dir avoids a tmpfs TMPDIR" || bad "the default work dir does not check for a tmpfs"
# no path of the script removes the work dir by hand any more (the trap does, on every exit)
grep -n 'rm -rf "\$WORK"' "$S" | grep -v '^ *[0-9]*: *rm -rf "\$WORK"$' >/dev/null \
  && bad "an exit path still removes \$WORK itself: $(grep -n 'rm -rf "\$WORK"' "$S")" || ok "only the cleanup trap removes the work dir"

echo "failures: $fails"
[ "$fails" = 0 ]
