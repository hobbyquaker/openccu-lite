#!/bin/sh
# openccu-lite: lite-lighttpd-reload signals lighttpd only when its configuration changed.
#
# On a fake tree (LITE_LIGHTTPD is a stand-in for "lighttpd -p" that prints a file of the test's):
# a reload right after "record" sends nothing; the per-run lines var.PID and var.CWD are no change;
# a changed line is, and so is new content in a file the configuration names (a renewed certificate
# under the same path), while a pid file named in it is not; after a signalling reload the next one
# with nothing new is quiet again; a configuration lighttpd cannot print signals (the old
# behaviour) and leaves no fingerprint; a pid that is not a number is refused. The unit calls it
# for ExecReload and records at the start; the classic RPC configuration no longer depends on
# startupFinished (lite-classic-rpc-conf-test.sh checks its output).
#
# Usage: sh scripts/testcases/lite-lighttpd-reload-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-lighttpd-reload"
UNIT="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/lighttpd.service"
[ -x "$SCRIPT" ] || { echo "lite-lighttpd-reload not found (or not executable) under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
sleeper=""
trap '[ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null; rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# the stand-in: "-p -f <conf>" prints <conf>, with a fresh var.PID every call; exit 1 on "broken"
cat >"$T/lighttpd" <<'EOS'
#!/bin/sh
[ "$1" = -p ] || exit 2
grep -q '^broken' "$3" && exit 1
echo "config {"
echo "    var.CWD                          = \"/root\""
echo "    var.PID                          = $$"
cat "$3"
echo "}"
EOS
chmod +x "$T/lighttpd"
echo 'CERT ONE' >"$T/server.pem"
echo '123' >"$T/lighttpd.pid"
cat >"$T/conf" <<EOS
    server.port = 80
    ssl.pemfile = "$T/server.pem"
    server.pid-file = "$T/lighttpd.pid"
EOS

# a process that counts the USR1 it gets
( trap 'echo x >>"$T/usr1"' USR1; while :; do sleep 1; done ) &
sleeper=$!
sleep 1
usr1() { [ -f "$T/usr1" ] && wc -l <"$T/usr1" | tr -d ' ' || echo 0; }
wait_usr1() { n=0; while [ "$(usr1)" != "$1" ] && [ $n -lt 30 ]; do sleep 0.1; n=$((n+1)); done; }
run() { LITE_LIGHTTPD="$T/lighttpd" LITE_LIGHTTPD_CONF="$T/conf" LITE_LIGHTTPD_STATE="$T/config.sum" sh "$SCRIPT" "$@"; }

run record
check "record writes a fingerprint" '[ -s "$T/config.sum" ]'
out=$(run reload "$sleeper"); rc=$?
sleep 0.3
check "unchanged: exit 0, no signal" '[ $rc = 0 ] && [ "$(usr1)" = 0 ]'
check "unchanged: says so" 'echo "$out" | grep -q "unchanged"'

echo '999' >"$T/lighttpd.pid"
run reload "$sleeper" >/dev/null; sleep 0.3
check "a changed pid file is no change" '[ "$(usr1)" = 0 ]'

echo '    server.max-connections = 10' >>"$T/conf"
run reload "$sleeper" >/dev/null; wait_usr1 1
check "a changed line signals" '[ "$(usr1)" = 1 ]'
run reload "$sleeper" >/dev/null; sleep 0.3
check "and the next reload without a change is quiet" '[ "$(usr1)" = 1 ]'

echo 'CERT TWO' >"$T/server.pem"
run reload "$sleeper" >/dev/null; wait_usr1 2
check "a renewed certificate under the same path signals" '[ "$(usr1)" = 2 ]'

cp "$T/conf" "$T/conf.good"
echo 'broken' >"$T/conf"
run reload "$sleeper" >/dev/null; wait_usr1 3
check "a configuration lighttpd cannot print signals" '[ "$(usr1)" = 3 ]'
check "and leaves no fingerprint" '[ ! -f "$T/config.sum" ]'
run record
check "record on a broken configuration leaves none either" '[ ! -f "$T/config.sum" ]'
cp "$T/conf.good" "$T/conf"
run reload "$sleeper" >/dev/null; wait_usr1 4
check "without a fingerprint the next reload signals" '[ "$(usr1)" = 4 ]'

run reload "12x" >/dev/null 2>&1; rc=$?
check "a pid that is not a number is refused" '[ $rc != 0 ] && [ "$(usr1)" = 4 ]'
run bogus >/dev/null 2>&1; rc=$?
check "an unknown action is a usage error" '[ $rc = 2 ]'

check "the unit reloads through it" 'grep -qx "ExecReload=/usr/libexec/occu/lite-lighttpd-reload reload \$MAINPID" "$UNIT"'
check "the unit records at the start" 'grep -qx "ExecStartPost=-/usr/libexec/occu/lite-lighttpd-reload record" "$UNIT"'
check "the unit signals the angel nowhere else" '! grep -q "^ExecReload=.*kill" "$UNIT"'
check "the not-ready Lua checks startupFinished per request" 'grep -q "/var/status/startupFinished" "$HERE/buildroot-external/overlay/lite/etc/lighttpd/classic-rpc-notready.lua"'

echo "failures: $fails"
[ "$fails" = 0 ]
