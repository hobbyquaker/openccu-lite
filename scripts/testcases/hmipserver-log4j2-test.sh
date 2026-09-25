#!/bin/sh
# openccu-lite: S62HMServer's setupLog4j2 against the lite and the upstream log4j2 template.
#
# The function is cut out of the init script and run on temporary files, so what is tested is the
# script's own code, not a copy of its sed lines:
#   - lite: only the stdout appender, every level from LOGLEVEL_HMIP, and with LOGHOST set still
#     no SYSLOG appender and no file (HMIP_LOG_STDOUT=1);
#   - upstream: unchanged - LOGHOST adds the SYSLOG reference and replaces the host.
#
# Usage: sh scripts/testcases/hmipserver-log4j2-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$HERE/buildroot-external/overlay/base/etc/init.d/S62HMServer"
LITE="$HERE/buildroot-external/overlay/lite/etc/config_templates/log4j2.xml"
BASE="$HERE/buildroot-external/overlay/base/etc/config_templates/log4j2.xml"
for f in "$SCRIPT" "$LITE" "$BASE"; do [ -f "$f" ] || { echo "missing $f"; exit 2; }; done

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
sed -n '/^setupLog4j2() {/,/^}/p' "$SCRIPT" > "$T/fn.sh"
grep -q '^setupLog4j2() {' "$T/fn.sh" || { echo "setupLog4j2 not found in $SCRIPT"; exit 2; }

fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# run <template> <syslog file content> <HMIP_LOG_STDOUT>: the output in $T/out.xml
run() {
  printf '%s\n' "$2" > "$T/syslog"
  rm -f "$T/out.xml"
  # the function needs [[ ]] - busybox ash on the box, bash here (dash has neither)
  HMIP_LOG_STDOUT="$3" ${HMIP_TEST_SHELL:-bash} -c 'LOGLEVEL_HMIP=error; LOGHOST=""; . "$1"; setupLog4j2 "$2" "$3" "$4"' sh "$T/fn.sh" "$1" "$T/out.xml" "$T/syslog"
}
levels() { grep -o 'level="[a-z]*"' "$T/out.xml" | sort -u | tr '\n' ' '; }

run "$LITE" "LOGLEVEL_HMIP=DEBUG" 1
[ "$(levels)" = 'level="debug" ' ] && ok "lite: every level is debug" || fail "lite levels: $(levels)"
grep -q '<Console name="JOURNAL" target="SYSTEM_OUT"' "$T/out.xml" && ok "lite: the stdout appender" || fail "lite: no Console appender"
[ "$(grep -c '<AppenderRef' "$T/out.xml")" = 1 ] && ok "lite: one appender reference" || fail "lite: $(grep -c '<AppenderRef' "$T/out.xml") appender references"
grep -qE 'SYSLOG|<File|<Syslog|\.log"' "$T/out.xml" && fail "lite: a file or syslog appender" || ok "lite: no file and no syslog appender"
grep -q '&lt;3&gt;' "$T/out.xml" && ok "lite: the error prefix is there" || fail "lite: no <3> prefix"

run "$LITE" "$(printf 'LOGLEVEL_HMIP=INFO\nLOGHOST=192.0.2.10')" 1
[ "$(levels)" = 'level="info" ' ] && ok "lite + LOGHOST: every level is info" || fail "lite + LOGHOST levels: $(levels)"
grep -qE 'SYSLOG|192\.0\.2\.10' "$T/out.xml" && fail "lite + LOGHOST: a SYSLOG reference or the host" || ok "lite + LOGHOST: no SYSLOG reference"

run "$BASE" "$(printf 'LOGLEVEL_HMIP=WARN\nLOGHOST=192.0.2.10')" ""
grep -q '<AppenderRef ref="SYSLOG"/>' "$T/out.xml" && grep -q 'host="192.0.2.10"' "$T/out.xml" && ok "upstream + LOGHOST: SYSLOG added, host replaced" || fail "upstream + LOGHOST changed"
[ "$(levels)" = 'level="warn" ' ] && ok "upstream: every level is warn" || fail "upstream levels: $(levels)"

run "$BASE" "LOGLEVEL_HMIP=ERROR" ""
grep -q 'SYSLOG"/>' "$T/out.xml" && fail "upstream without LOGHOST: a SYSLOG reference" || ok "upstream without LOGHOST: no SYSLOG reference"

[ "$fails" -eq 0 ] && echo "hmipserver-log4j2-test: all passed" || echo "hmipserver-log4j2-test: $fails failed"
[ "$fails" -eq 0 ]
