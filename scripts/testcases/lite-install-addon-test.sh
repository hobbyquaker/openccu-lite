#!/bin/sh
# openccu-lite: /bin/install_addon's hand-over to occulited (openccu-lite B-274).
#
# Outside occulited's install scope, with the install token and curl, the archive goes to
# occulited's POST /api/system/v1/addons/install/local and the script exits with the installer's
# code from the answer; inside the scope, without a token, or when occulited does not take it
# (not listening, 401, 404) the base install runs as always - seen here as the script's test stop
# right before it (exit 99), with the archive put back where it was. A 409 or a
# connection that broke after the upload installs nothing (exit 1). curl is a fake on PATH that
# records its arguments and answers what the case asks for; nothing needs root.
#
# Usage: sh scripts/testcases/lite-install-addon-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$HERE/buildroot-external/overlay/lite/bin/install_addon"
BASE="$HERE/buildroot-external/overlay/base/bin/install_addon"
[ -f "$SCRIPT" ] || { echo "install_addon not found at $SCRIPT"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tmp" "$T/bin"
LOG="$T/calls"
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# the fake curl: records its arguments and the uploaded file's content, writes the headers and
# the body the case sets, exits with FAKE_CURL_RC
cat > "$T/bin/curl" <<'CURL'
#!/bin/sh
echo "curl $*" >> "$FAKE_LOG"
out= hdr= up=
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift ;;
    -D) hdr=$2; shift ;;
    -T) up=$2; shift ;;
  esac
  shift
done
[ -n "$up" ] && echo "uploaded $(cat "$up")" >> "$FAKE_LOG"
[ -n "$hdr" ] && printf "$FAKE_HEADERS" > "$hdr"
[ -n "$out" ] && printf "$FAKE_BODY" > "$out"
exit "${FAKE_CURL_RC:-0}"
CURL
chmod 755 "$T/bin/curl"
printf 'secret\n' > "$T/token"
printf '0::/system.slice/sshd.service\n' > "$T/cg-ssh"
printf '0::/system.slice/occulite-addon-08e4e24f.scope\n' > "$T/cg-scope"

run() { # cgroup token rc headers body -> $code, $stdout, $stderr
  : > "$LOG"
  printf 'ARCHIVE' > "$T/tmp/new_addon.tar.gz"
  OCCU_INSTALL_TEST_STOP=99 OCCU_INSTALL_TMP="$T/tmp" OCCU_INSTALL_TOKEN_FILE="$2" OCCU_INSTALL_CGROUP="$1" \
    FAKE_LOG="$LOG" FAKE_CURL_RC="$3" FAKE_HEADERS="$4" FAKE_BODY="$5" PATH="$T/bin:$PATH" \
    sh "$SCRIPT" > "$T/stdout" 2> "$T/stderr"
  code=$?
}
leftover() { # the first entry of the tmp directory other than the archive, "" for none
  for f in "$T/tmp"/* "$T/tmp"/.[!.]*; do
    [ -e "$f" ] || continue
    [ "${f##*/}" = new_addon.tar.gz ] || { echo "${f##*/}"; return; }
  done
}

# 1. from ssh with the token: handed over, the installer's code and output are the script's
run "$T/cg-ssh" "$T/token" 0 'HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nX-Occulite-Addon-Exit: 10\r\nContent-Type: text/plain\r\n\r\n' '[manifest] hmm: applied\n'
[ "$code" = 10 ] && ok "handed over: the installer's exit code" || fail "handed over: exit $code"
grep -q '^\[manifest\] hmm: applied$' "$T/stdout" && ok "handed over: occulited's output on stdout" || fail "handed over: stdout $(cat "$T/stdout")"
grep -q 'Authorization: Bearer secret' "$LOG" && grep -q -- '-X POST' "$LOG" && grep -q 'addons/install/local' "$LOG" && ok "handed over: POST with the token to the local route" || fail "handed over: $(cat "$LOG")"
grep -q '^uploaded ARCHIVE$' "$LOG" && ok "handed over: the archive is the body" || fail "handed over: upload $(cat "$LOG")"
[ ! -e "$T/tmp/new_addon.tar.gz" ] && [ -z "$(leftover)" ] && ok "handed over: nothing left in the tmp directory" || fail "handed over: left $(ls "$T/tmp")"

# 2. a failed install: 422 with its code
run "$T/cg-ssh" "$T/token" 0 'HTTP/1.1 422 Unprocessable Entity\r\nX-Occulite-Addon-Exit: 104\r\n\r\n' ''
[ "$code" = 104 ] && ok "a failed install: its exit code" || fail "a failed install: exit $code"

# 3. inside occulited's install scope: no hand-over, the base install runs
run "$T/cg-scope" "$T/token" 0 '' ''
[ ! -s "$LOG" ] && ok "in the install scope: curl is not called" || fail "in the install scope: $(cat "$LOG")"
[ "$code" = 99 ] && [ -f "$T/tmp/new_addon.tar.gz" ] && ok "in the install scope: the base install runs" || fail "in the install scope: exit $code"

# 4. without the token: the base install runs
run "$T/cg-ssh" "$T/none" 0 '' ''
[ ! -s "$LOG" ] && [ "$code" = 99 ] && ok "without a token: the base install" || fail "without a token: exit $code, $(cat "$LOG")"

# 5. occulited not listening (curl 7), or refusing the token (401), or an older one without the
#    route (404): the archive goes back and the base install runs
for c in "curl 7|7|" "HTTP 401|0|HTTP/1.1 401 Unauthorized\r\n\r\n" "HTTP 404|0|HTTP/1.1 404 Not Found\r\n\r\n"; do
  label=${c%%|*} rest=${c#*|}
  run "$T/cg-ssh" "$T/token" "${rest%%|*}" "${rest#*|}" ''
  [ "$code" = 99 ] && [ "$(cat "$T/tmp/new_addon.tar.gz" 2>/dev/null)" = ARCHIVE ] && [ -z "$(leftover)" ] \
    && ok "not taken ($label): back to the base install" || fail "not taken ($label): exit $code, $(ls "$T/tmp")"
  grep -q 'installing without it' "$T/stderr" || fail "not taken ($label): no note on stderr"
done

# 6. another install runs (409), or the connection broke after the upload (curl 52): nothing here
for c in "HTTP 409|0|HTTP/1.1 409 Conflict\r\n\r\n" "curl 52|52|"; do
  label=${c%%|*} rest=${c#*|}
  run "$T/cg-ssh" "$T/token" "${rest%%|*}" "${rest#*|}" ''
  [ "$code" = 1 ] && [ ! -e "$T/tmp/new_addon.tar.gz" ] && [ -z "$(leftover)" ] \
    && ok "refused ($label): exit 1, nothing installed" || fail "refused ($label): exit $code, $(ls "$T/tmp")"
done

# 7. everything below the hand-over is the base copy unchanged
if [ "$(sed -n '/^# check if we have an update archive/,$p' "$SCRIPT")" = "$(sed -n '/^# check if we have an update archive/,$p' "$BASE")" ]; then
  ok "the install itself is the base copy's"
else
  fail "the lite install_addon's body differs from overlay/base/bin/install_addon"
fi

[ "$fails" -eq 0 ] && { echo "lite-install-addon-test: all passed"; exit 0; }
echo "lite-install-addon-test: $fails failed"; exit 1
