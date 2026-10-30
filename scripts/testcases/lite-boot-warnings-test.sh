#!/bin/sh
# openccu-lite: scripts/lite-boot-warnings.sh, the boot test's warning check, on made-up journals -
# and the real allowlist's syntax (every line has a reason, every expression compiles).
#
# Usage: sh scripts/testcases/lite-boot-warnings-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
CHECK="$HERE/scripts/lite-boot-warnings.sh"
ALLOW="$HERE/scripts/lite-boot-warnings.allow"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

cat > "$T/allow" <<'EOF'
# a comment, and an empty line

^kernel: Core Release: [0-9.a-z]+$ ## the Pi's USB host driver prints its banner at warning level
^lighttpd: \(\.\./src/server\.c\.[0-9]+\) reducing server\.max-connections ## lighttpd's own notice of its fd limit
EOF

# the guest driver's shape: "  | " in front, a stack trace's indented lines, the rc marker
cat > "$T/allowed" <<'EOF'
  | Oct 10 19:57:01 localhost kernel: Core Release: 2.80a
  | Oct 10 19:57:02 openccu-lite-3456 lighttpd[1018]: (../src/server.c.2035) reducing server.max-connections (1024) to 1/10 server.max-fds (2048)
[rc=0]
EOF
if out=$(sh "$CHECK" "$T/allow" "$T/allowed" 2>&1); then ok "allowed warnings pass: $(echo "$out" | tail -n1)"; else bad "allowed warnings failed: $out"; fi
case "$out" in *"2 warning(s), 0 not"*) ok "both counted";; *) bad "count: $out";; esac

cat > "$T/new" <<'EOF'
  | Oct 10 19:57:01 localhost kernel: Core Release: 2.80a
  | Oct 10 19:57:03 openccu-lite-3456 hmipserver[1192]: something new went wrong
  |         at de.example.Thing.run(Thing.java:1)
  | Oct 10 19:57:03 openccu-lite-3456 hmipserver[1192]:         at de.example.Other.run(Other.java:2)
Oct 10 19:57:04 openccu-lite-3456 dbus-daemon[258]: Failed to drop supplementary groups: Operation not permitted
EOF
out=$(sh "$CHECK" "$T/allow" "$T/new" 2>&1); rc=$?
[ "$rc" = 1 ] && ok "a new warning fails (rc 1)" || bad "a new warning: rc $rc"
case "$out" in *"new warning: hmipserver: something new went wrong"*) ok "the new line is named, pid stripped";; *) bad "the new line: $out";; esac
case "$out" in *"Thing.java"*|*"Other.java"*) bad "a continuation line was judged: $out";; *) ok "continuation lines are not judged";; esac
case "$out" in *"new warning: dbus-daemon: Failed to drop"*) ok "plain journalctl lines are read too";; *) bad "plain line: $out";; esac
case "$out" in *"3 warning(s), 2 not"*) ok "counted 3, 2 new";; *) bad "count: $out";; esac

printf '' > "$T/empty"
if sh "$CHECK" "$T/allow" "$T/empty" >/dev/null 2>&1; then ok "no warnings pass"; else bad "an empty journal failed"; fi

printf '^kernel: x$\n' > "$T/noreason"
sh "$CHECK" "$T/noreason" "$T/empty" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "an allowlist line without a reason is refused (rc 2)" || bad "no reason: rc $rc"
printf '^kernel: x$ ##   \n' > "$T/blankreason"
sh "$CHECK" "$T/blankreason" "$T/empty" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "a blank reason is refused" || bad "blank reason: rc $rc"

# the real allowlist: readable, every line with a reason, every expression valid
if sh "$CHECK" "$ALLOW" "$T/empty" > "$T/real.out" 2>&1; then ok "lite-boot-warnings.allow: every line has a reason"; else bad "lite-boot-warnings.allow: $(cat "$T/real.out")"; fi
n=$(grep -cv '^#\|^[[:space:]]*$' "$ALLOW")
[ "$n" -gt 0 ] && ok "lite-boot-warnings.allow has $n entries" || bad "lite-boot-warnings.allow is empty"
grep -v '^#\|^[[:space:]]*$' "$ALLOW" | sed 's/ ## .*//' | while IFS= read -r re; do
  printf 'x\n' | R=$re awk '{ if ($0 ~ ENVIRON["R"]) {} }' 2>/dev/null || echo "bad regex: $re"
done > "$T/regex.out"
[ -s "$T/regex.out" ] && bad "$(cat "$T/regex.out")" || ok "every expression compiles"

# the real allowlist on lines the boot test met: the timing-dependent forms of one cause pass
# (B-323: beta.4's runs 1 and 2 each met a form the list did not have), other error texts do not -
# the helper's i/o timeout among them since occulited B-71 reports it as the context's deadline
cat > "$T/timing" <<'EOF'
  | Oct 14 22:41:07 openccu-lite-3456 occulited[402]: rpc: interface down interface=BidCos-RF err="HTTP request failed on 127.0.0.1:32001: Post \"http://127.0.0.1:32001\": dial tcp 127.0.0.1:32001: connect: connection refused" retry_in=5s
  | Oct 14 22:41:07 openccu-lite-3456 occulited[402]: rpc: interface down interface=VirtualDevices err="HTTP request failed on 127.0.0.1:39292/groups: Post \"http://127.0.0.1:39292/groups\": dial tcp 127.0.0.1:39292: connect: connection refused" retry_in=5s
  | Oct 14 22:41:12 openccu-lite-3456 occulited[402]: rpc: interface down interface=BidCos-RF err="HTTP request failed on 127.0.0.1:32001: Post \"http://127.0.0.1:32001\": read tcp 127.0.0.1:47644->127.0.0.1:32001: read: connection reset by peer" retry_in=5s
  | Oct 14 23:19:30 openccu-lite-3456 occulited[402]: boot timeline: this boot could not be read err="systemctl show: context deadline exceeded"
  | Oct 14 23:19:30 openccu-lite-3456 occulited[402]: boot timeline: this boot could not be read err="systemctl show: context canceled"
EOF
out=$(sh "$CHECK" "$ALLOW" "$T/timing" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "the allowlist takes the refused, reset and context forms (B-323, occulited B-71)" || bad "timing forms: rc $rc: $out"
case "$out" in *"5 warning(s), 0 not"*) ok "all five counted";; *) bad "timing count: $out";; esac
cat > "$T/other" <<'EOF'
  | Oct 14 22:41:12 openccu-lite-3456 occulited[402]: rpc: interface down interface=BidCos-RF err="HTTP request failed on 127.0.0.1:32001: Post \"http://127.0.0.1:32001\": read tcp 127.0.0.1:47644->127.0.0.1:32001: read: connection timed out" retry_in=5s
  | Oct 14 22:41:12 openccu-lite-3456 occulited[402]: rpc: interface down interface=BidCos-RF err="HTTP request failed on 127.0.0.1:32001: Post \"http://127.0.0.1:32001\": write tcp 127.0.0.1:47644->127.0.0.1:32001: write: broken pipe" retry_in=5s
  | Oct 14 22:41:12 openccu-lite-3456 occulited[402]: rpc: interface down interface=BidCos-RF err="HTTP request failed on 192.168.1.5:2001: Post \"http://192.168.1.5:2001\": dial tcp 192.168.1.5:2001: connect: connection refused" retry_in=5s
  | Oct 14 23:19:30 openccu-lite-3456 occulited[402]: boot timeline: this boot could not be read err="systemctl show: privilege helper: read unix @->/run/occulite/helper.sock: i/o timeout"
  | Oct 14 23:19:30 openccu-lite-3456 occulited[402]: boot timeline: this boot could not be read err="systemctl show: privilege helper: write unix @->/run/occulite/helper.sock: i/o timeout"
  | Oct 14 23:19:30 openccu-lite-3456 occulited[402]: boot timeline: this boot could not be read err="systemctl show: privilege helper: read unix @->/run/occulite/helper.sock: connection reset by peer"
  | Oct 14 23:19:30 openccu-lite-3456 occulited[402]: boot timeline: this boot could not be read err="systemctl show: exit status 1"
EOF
out=$(sh "$CHECK" "$ALLOW" "$T/other" 2>&1); rc=$?
[ "$rc" = 1 ] && ok "other error texts of the same lines still fail" || bad "other texts: rc $rc: $out"
case "$out" in *"7 warning(s), 7 not"*) ok "all seven other texts named, the helper's i/o timeout among them (occulited B-71)";; *) bad "other count: $out";; esac

# B-318: TCG under a loaded runner stretches the kernel's timer once; the number varies, the line is the VM's
cat > "$T/hrtimer" <<'EOF'
  | Oct 13 10:02:11 localhost kernel: hrtimer: interrupt took 4529170 ns
  | Oct 13 10:02:11 localhost kernel: hrtimer: interrupt took 81904 ns
EOF
out=$(sh "$CHECK" "$ALLOW" "$T/hrtimer" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "the allowlist takes the QEMU boot's hrtimer line (B-318)" || bad "hrtimer: rc $rc: $out"
printf '  | Oct 13 10:02:11 localhost kernel: hrtimer: interrupt took too long\n' > "$T/hrtimer2"
sh "$CHECK" "$ALLOW" "$T/hrtimer2" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "another hrtimer text still fails" || bad "another hrtimer text: rc $rc"

# the causes task 345 removed, which the allowlist leaves out: each fix is still in place
EXT="$HERE/buildroot-external"
PBS="$EXT/board/lite/post-build-systemd.sh"
U="$EXT/overlay/lite/usr/lib/systemd/system"
has() { if grep -qF -- "$2" "$1"; then ok "$3"; else bad "$3 (${1#"$HERE"/} must carry: $2)"; fi; }
has "$EXT/package/occulited/occulited.mk" '- -1 clock 989 * - - -' "udev's clock group is in the users table"
has "$PBS" 'rm -f "${TARGET_DIR}/usr/lib/udev/rules.d/60-nfs.rules" "${TARGET_DIR}/usr/lib/udev/rules.d/99-nfs.rules"' "nfs-utils' udev rules are removed"
has "$PBS" '<user>dbus<\/user>' "dbus-daemon does not switch to its user a second time"
has "$PBS" '\/root\/\.ssh' "tmpfiles' /root/.ssh directory line is removed"
has "$PBS" '/usr/lib/clock-epoch' "the clock's floor is the image's build"
has "$EXT/overlay/lite/etc/systemd/journald.conf.d/10-openccu-lite.conf" 'Audit=no' "journald leaves the kernel audit off"
has "$EXT/overlay/lite/usr/libexec/occu/initscript-wrapper" '= stopping ] && exit 0' "the init-script wrapper starts and reloads nothing while the system stops"
has "$U/occu-zram-swap.service" '[ "$$(systemctl is-system-running)" = stopping ] ||' "the zram swap is not removed at a shutdown"
has "$U/lighttpd.service" 'LogFilterPatterns=~^\(\.\./src/gw_backend\.c\.[0-9]+\) (establishing connection failed: socket: tcp:127\.0\.0\.1:' "lighttpd's refused loopback backends are dropped"

# wired into the boot test
grep -q 'lite-boot-warnings.sh' "$HERE/scripts/lite-qemu-test.sh" && ok "lite-qemu-test.sh runs the check" || bad "lite-qemu-test.sh does not run lite-boot-warnings.sh"

# B-334: boot 2's hmipserver lines when rfd resets its request (dev.4 run 2, under runner load):
# the reset, the retry and their headers pass; another exception, another target or a header
# with another method do not
cat > "$T/b334" <<'EOF'
  | Oct 29 02:29:55 openccu-lite-3456 hmipserver[886]: de.eq3.cbcs.util.EQ3LoggerOutputStream [Timer-1] Oct 29, 2026 2:29:55 AM org.apache.http.impl.client.DefaultHttpClient tryExecute
  | Oct 29 02:29:55 openccu-lite-3456 hmipserver[886]: de.eq3.cbcs.util.EQ3LoggerOutputStream [Timer-1] INFO: I/O exception (java.net.SocketException) caught when processing request to {}->http://127.0.0.1:32001: Connection reset by peer
  | Oct 29 02:29:55 openccu-lite-3456 hmipserver[886]: de.eq3.cbcs.util.EQ3LoggerOutputStream [Timer-1] Oct 29, 2026 2:29:55 AM org.apache.http.impl.client.DefaultHttpClient tryExecute
  | Oct 29 02:29:55 openccu-lite-3456 hmipserver[886]: de.eq3.cbcs.util.EQ3LoggerOutputStream [Timer-1] INFO: Retrying request to {}->http://127.0.0.1:32001
  | Oct 29 12:01:02 openccu-lite-3456 hmipserver[886]: de.eq3.cbcs.util.EQ3LoggerOutputStream [Timer-2] Oct 9, 2026 12:01:02 PM org.apache.http.impl.client.DefaultHttpClient tryExecute
EOF
out=$(sh "$CHECK" "$ALLOW" "$T/b334" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "boot 2's hmipserver reset and retry against rfd pass (B-334)" || bad "B-334 lines: rc $rc: $out"
case "$out" in *"5 warning(s), 0 not"*) ok "all five counted";; *) bad "B-334 count: $out";; esac
cat > "$T/b334other" <<'EOF'
  | Oct 29 02:29:55 openccu-lite-3456 hmipserver[886]: de.eq3.cbcs.util.EQ3LoggerOutputStream [Timer-1] INFO: I/O exception (java.net.SocketException) caught when processing request to {}->http://127.0.0.1:32001: Broken pipe
  | Oct 29 02:29:55 openccu-lite-3456 hmipserver[886]: de.eq3.cbcs.util.EQ3LoggerOutputStream [Timer-1] INFO: I/O exception (java.net.SocketException) caught when processing request to {}->http://127.0.0.1:2010: Connection reset by peer
  | Oct 29 02:29:55 openccu-lite-3456 hmipserver[886]: de.eq3.cbcs.util.EQ3LoggerOutputStream [Timer-1] INFO: Retrying request to {}->http://192.0.2.1:80
  | Oct 29 02:29:55 openccu-lite-3456 hmipserver[886]: de.eq3.cbcs.util.EQ3LoggerOutputStream [Timer-1] Oct 29, 2026 2:29:55 AM org.apache.http.impl.client.DefaultHttpClient execute
  | Oct 29 02:29:55 openccu-lite-3456 hmipserver[886]: de.eq3.cbcs.util.EQ3LoggerOutputStream [Timer-1] SEVERE: something else
EOF
out=$(sh "$CHECK" "$ALLOW" "$T/b334other" 2>&1); rc=$?
[ "$rc" = 1 ] && ok "other hmipserver HTTP client lines still fail" || bad "B-334 other lines: rc $rc: $out"
case "$out" in *"5 warning(s), 5 not"*) ok "all five of them new";; *) bad "B-334 other count: $out";; esac

[ "$fails" = 0 ] && { echo "lite-boot-warnings-test: all checks passed"; exit 0; }
echo "lite-boot-warnings-test: $fails failed"; exit 1
