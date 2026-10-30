#!/bin/sh
# openccu-lite (B-279): lite-qemu-test.sh judged an addon's unit 5 s after its install, and hm2mqtt
# (Node.js on an emulated CPU) was still "activating" then on two build rounds running - a flake
# that cost a QEMU run each time. Now the check is settle_snippet's one-liner in the guest: it
# polls "systemctl is-active" every 2 s while the unit is activating, up to a bound, and prints the
# state, the seconds waited and the unit's Result. Here the function is taken from the script
# (awk) and its snippet runs against a stub systemctl that answers from a script of states:
# active at once, activating then active, failed at once (no waiting on a failure), and a unit
# that never settles within the bound. The install check must read the snippet's answer.
#
# B-287: the same for page_wait, the host-side wait for an addon's page behind the gate - hmm's
# lighttpd proxy answered 503 when probed 2 s after the install (its Node.js server was not
# listening yet), 200 in the runs that probed 8 s after. Here it runs against a stub curl that
# answers a script of status codes: 200 at once, 503 twice then 200, 404 at once (no waiting on
# an answer that is not the proxy's), and a 503 that never ends within the bound. The install
# check must fail on 502/503 after the wait and want 200 from hmm and hm2mqtt.
#
# B-334: the same for lighttpd's restart checks. kill_restart_snippet (the B-3 kill) and
# initscript_restart_snippet (the hand-invoked S50lighttpd restart) run against stubs of
# systemctl, pgrep, the init script and sleep, whose answers follow a script of states by the
# number of sleeps (no real waiting): the dev.4 shapes under load (still activating after 8 s; the
# old daemon's "active" right after a --no-block restart) must settle, a daemon that is not
# restarted, comes back on its old PID or with two angels must not.
#
# Usage: sh scripts/testcases/lite-qemu-settle-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S="$HERE/scripts/lite-qemu-test.sh"
[ -f "$S" ] || { echo "lite-qemu-test.sh not found at $S"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

awk '/^settle_snippet\(\) \{$/ {p=1} p {print} p && /^\}$/ {p=0}' "$S" >"$T/fn.sh"
grep -q '^settle_snippet() {$' "$T/fn.sh" && ok "settle_snippet found in lite-qemu-test.sh" || { bad "settle_snippet() not found in lite-qemu-test.sh"; echo "failures: $fails"; exit 1; }

# the stub: "is-active <unit>" answers the next line of $T/states (the last line repeats), and
# counts its calls; "show -p Result --value <unit>" answers $T/result
mkdir -p "$T/bin"
cat >"$T/bin/systemctl" <<EOS
#!/bin/sh
case "\$1" in
  is-active) n=\$(cat "$T/calls" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"$T/calls"
             l=\$(sed -n "\${n}p" "$T/states"); [ -n "\$l" ] || l=\$(tail -n 1 "$T/states"); echo "\$l";;
  show) cat "$T/result";;
  *) echo "stub: \$*" >&2; exit 2;;
esac
EOS
chmod +x "$T/bin/systemctl"
run() { # <bound> <result> <states...>: the snippet for addon-x.service, output and the seconds it took
  bound=$1; echo "$2" >"$T/result"; shift 2
  rm -f "$T/calls"; : >"$T/states"; for st in "$@"; do echo "$st" >>"$T/states"; done
  snippet=$(. "$T/fn.sh"; settle_snippet addon-x.service "$bound")
  t0=$(date +%s)
  out=$(PATH="$T/bin:$PATH" sh -c "$snippet" 2>&1)
  took=$(( $(date +%s) - t0 ))
  calls=$(cat "$T/calls")
}

run 60 success active
[ "$out" = "active after 0s, result success" ] && ok "active at once: '$out'" || bad "active at once: '$out'"
[ "$calls" = 1 ] && [ "$took" -le 1 ] && ok "and no waiting ($calls call, ${took}s)" || bad "active at once waited: $calls calls, ${took}s"

run 60 success activating activating activating active
[ "$out" = "active after 6s, result success" ] && ok "activating three times, then active: '$out'" || bad "activating then active: '$out'"
[ "$calls" = 4 ] && [ "$took" -ge 5 ] && [ "$took" -le 8 ] && ok "polled every 2 s ($calls calls, ${took}s)" || bad "activating then active: $calls calls, ${took}s"

run 60 exit-code failed
[ "$out" = "failed after 0s, result exit-code" ] && ok "failed at once, with the Result: '$out'" || bad "failed: '$out'"
[ "$calls" = 1 ] && ok "a failure is not waited for" || bad "a failure was polled $calls times"

run 4 success activating
[ "$out" = "activating after 4s, result success" ] && ok "never settling: the bound ends the wait: '$out'" || bad "never settling: '$out'"
[ "$calls" = 3 ] && [ "$took" -ge 3 ] && [ "$took" -le 6 ] && ok "within the bound ($calls calls, ${took}s)" || bad "never settling: $calls calls, ${took}s"

run 60 success inactive
[ "$out" = "inactive after 0s, result success" ] && ok "inactive is reported as it is" || bad "inactive: '$out'"

# the install check reads the snippet's answer, with a bound of at least 60 s, and the fixed sleep is gone
grep -q 'guest "\$(settle_snippet "addon-\$id.service" [6-9][0-9])"' "$S" && ok "the install check waits with settle_snippet, 60 s or more" || bad "the install check does not call settle_snippet with a bound of 60 s or more"
grep -q "\*'| active after'\*" "$S" && ok "and reads its answer" || bad "the install check does not read the snippet's 'active after'"
grep -q 'guest "sleep 5; systemctl is-active addon-\$id' "$S" && bad "the fixed 5 s sleep before the install check is still there" || ok "the fixed sleep before the install check is gone"

# --- page_wait (B-287) ---
awk '/^page_wait\(\) \{$/ {p=1} p {print} p && /^\}$/ {p=0}' "$S" >"$T/pw.sh"
grep -q '^page_wait() {$' "$T/pw.sh" && ok "page_wait found in lite-qemu-test.sh" || { bad "page_wait() not found in lite-qemu-test.sh"; echo "failures: $fails"; exit 1; }
# the stub curl answers the next line of $T/codes (the last line repeats) and counts its calls
cat >"$T/bin/curl" <<EOS
#!/bin/sh
n=\$(cat "$T/pwcalls" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"$T/pwcalls"
l=\$(sed -n "\${n}p" "$T/codes"); [ -n "\$l" ] || l=\$(tail -n 1 "$T/codes"); printf '%s' "\$l"
EOS
chmod +x "$T/bin/curl"
pwrun() { # <bound> <codes...>
  bound=$1; shift
  rm -f "$T/pwcalls"; : >"$T/codes"; for c in "$@"; do echo "$c" >>"$T/codes"; done
  t0=$(date +%s)
  out=$(PATH="$T/bin:$PATH" sh -c ". '$T/pw.sh'; page_wait http://127.0.0.1:1/addons/x/ occulite_gate=s $bound" 2>&1)
  took=$(( $(date +%s) - t0 ))
  calls=$(cat "$T/pwcalls")
}
pwrun 60 200
[ "$out" = "200 after 0s" ] && [ "$calls" = 1 ] && [ "$took" -le 1 ] && ok "page 200 at once: '$out', $calls call" || bad "page 200 at once: '$out', $calls calls, ${took}s"
pwrun 60 503 503 200
[ "$out" = "200 after 4s" ] && [ "$calls" = 3 ] && [ "$took" -ge 3 ] && [ "$took" -le 6 ] && ok "503 twice, then 200: '$out', $calls calls" || bad "503 then 200: '$out', $calls calls, ${took}s"
pwrun 60 404
[ "$out" = "404 after 0s" ] && [ "$calls" = 1 ] && ok "404 is an answer, not waited on: '$out'" || bad "404: '$out', $calls calls"
pwrun 60 302
[ "$out" = "302 after 0s" ] && [ "$calls" = 1 ] && ok "the gate's redirect is not waited on: '$out'" || bad "302: '$out', $calls calls"
pwrun 4 503
[ "$out" = "503 after 4s" ] && [ "$calls" = 3 ] && ok "a proxy that never answers: the bound ends the wait: '$out'" || bad "never answering: '$out', $calls calls, ${took}s"
pwrun 60 502 200
[ "$out" = "200 after 2s" ] && ok "502 (the connection refused) is waited on too: '$out'" || bad "502: '$out'"
# the install check waits with page_wait for 60 s or more, fails on 502/503 after it, and wants 200 from hmm and hm2mqtt
grep -q 'page_wait "\$BASE/addons/\$id/" "occulite_gate=\$SID" [6-9][0-9])' "$S" && ok "the install check waits with page_wait, 60 s or more" || bad "the install check does not call page_wait with a bound of 60 s or more"
grep -q '502|503) fail' "$S" && ok "and fails on 502/503 after the wait" || bad "the install check does not fail on 502/503 after the wait"
grep -q 'hmm|hm2mqtt) \[ "\$code" = 200 \]' "$S" && ok "and wants 200 from hmm and hm2mqtt" || bad "the install check does not want 200 from hmm and hm2mqtt"

# --- kill_restart_snippet and initscript_restart_snippet (B-334) ---
for f in kill_restart_snippet initscript_restart_snippet; do
  awk -v f="$f" '$0 == f "() {" {p=1} p {print} p && /^\}$/ {p=0}' "$S" >>"$T/rs.sh"
  grep -q "^$f() {\$" "$T/rs.sh" && ok "$f found in lite-qemu-test.sh" || bad "$f() not found in lite-qemu-test.sh"
done
# stubs on a clock of sleeps: line <ticks+1> of $T/rs (the last line repeats) is
# "<is-active> <NRestarts> <MainPID> <lighttpd-angels>"; sleep only counts. The PIDs are above any
# pid_max, so the snippet's kill -9 meets no process.
mkdir -p "$T/rsbin"
cat >"$T/rsbin/state" <<EOS
#!/bin/sh
t=\$(cat "$T/ticks" 2>/dev/null || echo 0); t=\$((t+1))
l=\$(sed -n "\${t}p" "$T/rs"); [ -n "\$l" ] || l=\$(tail -n 1 "$T/rs"); echo "\$l"
EOS
cat >"$T/rsbin/sleep" <<EOS
#!/bin/sh
t=\$(cat "$T/ticks" 2>/dev/null || echo 0); echo \$((t+1)) >"$T/ticks"
EOS
cat >"$T/rsbin/systemctl" <<EOS
#!/bin/sh
set -- \$("$T/rsbin/state") "\$@"
case "\$5" in
  is-active) echo "\$1";;
  show) case "\$7" in NRestarts) echo "\$2";; MainPID) echo "\$3";; *) echo "\$1"; echo x; echo "\$2";; esac;;
  *) echo "stub: \$*" >&2; exit 2;;
esac
EOS
cat >"$T/rsbin/pgrep" <<EOS
#!/bin/sh
set -- \$("$T/rsbin/state"); i=0; while [ \$i -lt "\$4" ]; do echo 1\$i; i=\$((i+1)); done
EOS
cat >"$T/rsbin/S50x" <<EOS
#!/bin/sh
echo "restart at tick \$(cat "$T/ticks" 2>/dev/null || echo 0)" >>"$T/initcalls"
EOS
chmod +x "$T/rsbin/"*
rsrun() { # <snippet> <state lines...>
  snip=$1; shift
  rm -f "$T/ticks" "$T/initcalls"; : >"$T/rs"; for st in "$@"; do echo "$st" >>"$T/rs"; done
  out=$(PATH="$T/rsbin:$PATH" sh -c "$snip" 2>/dev/null)
}
K=$(. "$T/rs.sh"; kill_restart_snippet lighttpd.service 90)
K5=$(. "$T/rs.sh"; kill_restart_snippet lighttpd.service 5)
I=$(. "$T/rs.sh"; initscript_restart_snippet lighttpd.service "$T/rsbin/S50x" lighttpd-angel 90)
I5=$(. "$T/rs.sh"; initscript_restart_snippet lighttpd.service "$T/rsbin/S50x" lighttpd-angel 5)

rsrun "$K" "active 0 9999901 1" "activating 1 0 0" "activating 1 0 0" "active 1 9999902 1"
[ "$out" = "restarted=yes: active after 3s, restarts 0 -> 1, main pid 9999901 -> 9999902" ] && ok "kill: restarted within 3 s: '$out'" || bad "kill, quick restart: '$out'"
# dev.4 runs 1 and 2: still activating (NRestarts 1) when the old check looked after 8 s
rsrun "$K" "active 0 9999901 1" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "active 1 9999902 1"
[ "$out" = "restarted=yes: active after 13s, restarts 0 -> 1, main pid 9999901 -> 9999902" ] && ok "kill: still activating after 8 s (dev.4 under load) is waited for: '$out'" || bad "kill, slow restart: '$out'"
# systemd has not noticed the kill yet: the old "active" is not taken for the restart
rsrun "$K5" "active 0 9999901 1"
[ "$out" = "restarted=no: active after 5s, restarts 0 -> 0, main pid 9999901 -> 9999901" ] && ok "kill: no restart counted, the old daemon's active fails at the bound: '$out'" || bad "kill, never restarted: '$out'"
rsrun "$K5" "active 0 9999901 1" "activating 1 0 0"
[ "$out" = "restarted=no: activating after 5s, restarts 0 -> 1, main pid 9999901 -> 0" ] && ok "kill: never active again fails at the bound: '$out'" || bad "kill, stuck activating: '$out'"
rsrun "$K" "active 0 9999901 1" "failed 1 0 0"
[ "$out" = "restarted=no: failed after 1s, restarts 0 -> 1, main pid 9999901 -> 0" ] && ok "kill: a failed unit fails at once: '$out'" || bad "kill, failed: '$out'"
rsrun "$K5" "active 0 9999901 1" "active 1 9999901 1"
case "$out" in restarted=no:*) ok "kill: active on the old main PID is no restart: '$out'";; *) bad "kill, old pid: '$out'";; esac

# dev.4 run 1: right after the --no-block restart the unit still said active on the old PID
rsrun "$I" "active 1 9999901 1" "active 1 9999901 1" "activating 1 0 0" "active 1 9999902 2" "active 1 9999902 1"
case "$out" in *"settled=yes: active, main pid 9999901 -> 9999902, 1 lighttpd-angel, after 4s"*) ok "init script: the old daemon's active is not taken, settled after 4 s";; *) bad "init script, restart: '$out'";; esac
case "$out" in "active before the restart after 0s: "*) ok "init script: active before the restart at once";; *) bad "init script, before: '$out'";; esac
[ "$(cat "$T/initcalls" 2>/dev/null)" = "restart at tick 0" ] && ok "init script: restart called once, after the unit was active" || bad "init script calls: $(cat "$T/initcalls" 2>/dev/null)"
rsrun "$I" "activating 1 0 0" "activating 1 0 0" "activating 1 0 0" "active 1 9999901 1" "activating 1 0 0" "active 1 9999902 1"
case "$out" in "active before the restart after 3s: "*"settled=yes: active, main pid 9999901 -> 9999902, 1 lighttpd-angel, after 2s"*) ok "init script: waits for active before the restart (3 s), then settles";; *) bad "init script, activating first: '$out'";; esac
[ "$(cat "$T/initcalls" 2>/dev/null)" = "restart at tick 3" ] && ok "init script: the restart came after the wait" || bad "init script calls: $(cat "$T/initcalls" 2>/dev/null)"
rsrun "$I5" "active 1 9999901 1"
case "$out" in *"settled=no: active, main pid 9999901 -> 9999901, 1 lighttpd-angel, after 5s"*) ok "init script: no new main PID fails at the bound";; *) bad "init script, no restart: '$out'";; esac
rsrun "$I5" "active 1 9999901 1" "active 1 9999902 2"
case "$out" in *"settled=no: active, main pid 9999901 -> 9999902, 2 lighttpd-angel, after 5s"*) ok "init script: two angels fail at the bound";; *) bad "init script, two angels: '$out'";; esac

# the boot test uses them, with bounds of 60 s or more, reads their verdicts, and the fixed sleeps are gone
grep -q 'guest "\$(kill_restart_snippet lighttpd\.service [6-9][0-9])"' "$S" && ok "the kill check waits with kill_restart_snippet, 60 s or more" || bad "the kill check does not call kill_restart_snippet with a bound of 60 s or more"
grep -q "\*'| restarted=yes'\*" "$S" && ok "and reads restarted=yes" || bad "the kill check does not read restarted=yes"
grep -q 'guest "\$(initscript_restart_snippet lighttpd\.service /etc/init\.d/S50lighttpd lighttpd-angel [6-9][0-9])"' "$S" && ok "the init-script check waits with initscript_restart_snippet, 60 s or more" || bad "the init-script check does not call initscript_restart_snippet with a bound of 60 s or more"
grep -q "\*'| settled=yes'\*" "$S" && ok "and reads settled=yes" || bad "the init-script check does not read settled=yes"
grep -q 'kill -9 \$P; sleep 8' "$S" && bad "the fixed 8 s sleep after the kill is still there" || ok "the fixed 8 s sleep after the kill is gone"

echo "failures: $fails"
[ "$fails" = 0 ]
