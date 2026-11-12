#!/bin/sh
# openccu-lite: the recovery system's lighttpd while it installs an update (B-343, issue #21).
#
# The recovery answers every unknown path with a 301 to its own page. A client of the running
# system - Home Assistant's Loom client on /addons/loom/api/v1/events - took that 301 for a final
# answer and stopped reconnecting. So the paths the running system's clients poll answer 503 with
# Retry-After there, and browsers keep the redirect:
#
#   - static: the recovery's lighttpd.conf sends /api/, /addons/ and /.well-known/acme-challenge/
#     to lite_unavailable.cgi, which is executable in git and parses; with an occulited checkout,
#     every URL prefix its lighttpd fragment proxies is among them (a new one fails here);
#   - a real lighttpd (Alpine's, in a container; docker and apk over the network): the recovery's
#     configuration parses (-tt) and, with the recovery's /www, curl gets 503 + Retry-After + JSON
#     on the API (GET, POST with a body, HEAD, a WebSocket upgrade), 503 + text on the addons and
#     the ACME challenge, and the 301 to / on a browser path, a near miss (/apix) and /api itself,
#     while / is the recovery's page. Skipped with a note when docker is not available.
#
# The recovery's conf.d lacks access_log.conf, debug.conf and dirlisting.conf (Buildroot's
# lighttpd package installs them); the container takes the fork's base overlay's copies, and drops
# mod_openssl, which Alpine's lighttpd has built in.
#
# Usage: sh scripts/testcases/lite-recovery-lighttpd-test.sh [occulited checkout]   (default: ../occulited)
#        ALPINE_IMAGE=alpine:3.22 is the default image.
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
REC="$HERE/buildroot-external/package/recovery-system/external"
CONF="$REC/overlay/base/etc/lighttpd/lighttpd.conf"
CGI_REL="buildroot-external/package/recovery-system/external/overlay/base/www/cgi-bin/lite_unavailable.cgi"
CGI="$HERE/$CGI_REL"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# --- static -------------------------------------------------------------------------------------
pat=$(sed -n 's/^\$HTTP\["url"\] =~ "\(.*\)" {$/\1/p' "$CONF" | head -1)
[ "$pat" = '^/(api|addons|\.well-known/acme-challenge)/' ] && ok "lighttpd.conf: the URL block is $pat" || bad "lighttpd.conf: the URL block is '$pat'"
awk '/^\$HTTP\["url"\] =~ / { b=1; next } b && /server\.error-handler-404 = "\/cgi-bin\/lite_unavailable\.cgi"/ { f=1 } b && /^}/ { b=0 } END { exit !f }' "$CONF" &&
  ok "lighttpd.conf: the block's 404 handler is lite_unavailable.cgi" || bad "lighttpd.conf: lite_unavailable.cgi is not the block's 404 handler"
grep -q '^server.error-handler-404 = "/notexisting"$' "$CONF" && ok "lighttpd.conf: other paths still go to /notexisting (the 301 to /)" || bad "lighttpd.conf: the global 404 redirect is gone"
[ -f "$CGI" ] && sh -n "$CGI" && ok "lite_unavailable.cgi parses" || bad "lite_unavailable.cgi is missing or does not parse"
mode=$(git -C "$HERE" ls-files -s -- "$CGI_REL" 2>/dev/null | cut -d' ' -f1)
case "$mode" in
  100755) ok "lite_unavailable.cgi is executable in git" ;;
  "") if [ -x "$CGI" ]; then ok "lite_unavailable.cgi is executable (not in git yet)"; else bad "lite_unavailable.cgi is not executable"; fi ;;
  *) bad "lite_unavailable.cgi has mode $mode in git" ;;
esac

OCC=$(cd "${1:-$HERE/../occulited}" 2>/dev/null && pwd) || OCC=""
if [ -n "$OCC" ] && [ -f "$OCC/deploy/lighttpd/occulited.conf" ]; then
  # the prefixes occulited's fragment proxies: $HTTP["url"] =~ "^/<prefix>/" (the negated catch-all
  # for the shell is a browser path and stays redirected)
  prefixes=$(sed -n 's|^\$HTTP\["url"\] =~ "^/\([^"]*\)/" {$|\1|p' "$OCC/deploy/lighttpd/occulited.conf" | sort -u)
  [ -n "$prefixes" ] && ok "occulited's fragment proxies: $(echo $prefixes)" || bad "no URL prefix found in occulited's fragment"
  ours="|$(printf '%s' "$pat" | sed 's/^\^\/(\(.*\))\/$/\1/')|"
  for p in $prefixes; do
    case "$ours" in
      *"|$p|"*) ok "the recovery answers 503 on occulited's /$p/" ;;
      *) bad "occulited's fragment proxies /$p/, the recovery redirects it" ;;
    esac
  done
else
  echo "skip the prefix comparison: no occulited checkout at ${1:-$HERE/../occulited}"
fi

# --- a real lighttpd ------------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "skip the container part: docker is not available"
else
  out="${TMPDIR:-/tmp}/lite-recovery-lighttpd.$$"
  if docker run --rm -i \
       -v "$REC/overlay/base/etc/lighttpd:/src/lighttpd:ro" \
       -v "$REC/overlay/base/www:/src/www-lite:ro" \
       -v "$REC/package/hm-platform/rootfs-overlay/www:/src/www-platform:ro" \
       -v "$HERE/buildroot-external/overlay/base/etc/lighttpd/conf.d:/src/conf.d-base:ro" \
       "${ALPINE_IMAGE:-alpine:3.22}" sh -s >"$out" 2>&1 <<'INNER'
set -u
apk add --no-cache lighttpd curl >/tmp/apk.log 2>&1 || { cat /tmp/apk.log; exit 3; }
lighttpd -v
f=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; f=$((f+1)); }
rm -rf /etc/lighttpd && cp -a /src/lighttpd /etc/lighttpd
for c in access_log.conf debug.conf dirlisting.conf; do cp /src/conf.d-base/$c /etc/lighttpd/conf.d/; done
sed -i '/"mod_openssl"/d' /etc/lighttpd/modules.conf
mkdir -p /www /var/log /var/run /var/lib/lighttpd /var/cache/lighttpd /usr/local/tmp /dev/shm
cp -a /src/www-platform/. /www/ && cp -a /src/www-lite/. /www/
lighttpd -tt -f /etc/lighttpd/lighttpd.conf >/tmp/tt.log 2>&1 && ok "lighttpd -tt parses the recovery's configuration" || { cat /tmp/tt.log; bad "lighttpd -tt"; }
lighttpd -D -f /etc/lighttpd/lighttpd.conf >/tmp/run.log 2>&1 &
pid=$!
i=0; until curl -s -o /dev/null http://127.0.0.1/ || [ $i -ge 50 ]; do i=$((i+1)); sleep 0.1; done
H=/tmp/h; B=/tmp/b
req() { rm -f $H $B; curl -s -D $H -o $B "$@" >/dev/null; sed -n '1s/^HTTP\/[0-9.]* \([0-9]*\).*/\1/p' $H; }
hdr() { sed -n "s/^$1: *\(.*\)\r\$/\1/Ip" $H | head -1; }

# the API: 503, Retry-After, JSON, no redirect - every method and the change stream's upgrade
for m in GET POST HEAD WS; do
  case $m in
    GET)  s=$(req http://127.0.0.1/api/system/v1/status) ;;
    POST) s=$(req -X POST -H 'Content-Type: application/json' --data '{"username":"a","password":"b"}' http://127.0.0.1/api/auth/v1/login) ;;
    HEAD) s=$(req -I http://127.0.0.1/api/meta/v1/channels) ;;
    WS)   s=$(req -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' http://127.0.0.1/api/meta/v1/events) ;;
  esac
  [ "$s" = 503 ] && ok "/api/ $m: 503" || bad "/api/ $m: $s ($(tr '\r\n' '  ' <$H))"
  [ "$(hdr Retry-After)" = 30 ] && ok "/api/ $m: Retry-After: 30" || bad "/api/ $m: Retry-After '$(hdr Retry-After)'"
  [ -z "$(hdr Location)" ] && ok "/api/ $m: no Location" || bad "/api/ $m: Location $(hdr Location)"
  case "$(hdr Content-Type)" in application/json*) ok "/api/ $m: JSON" ;; *) bad "/api/ $m: Content-Type '$(hdr Content-Type)'" ;; esac
  if [ $m != HEAD ]; then grep -q '^{"error":"updating"' $B && ok "/api/ $m: the body says updating" || bad "/api/ $m: body '$(cat $B)'"; fi
done

# the addons and the ACME challenge: 503, Retry-After, text - the Loom client's event stream first
for p in /addons/loom/api/v1/events /addons/red/ /addons/xmlapi/statelist.cgi /.well-known/acme-challenge/token; do
  if [ $p = /addons/loom/api/v1/events ]; then
    s=$(req -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' http://127.0.0.1$p)
  else
    s=$(req http://127.0.0.1$p)
  fi
  [ "$s" = 503 ] && [ "$(hdr Retry-After)" = 30 ] && [ -z "$(hdr Location)" ] && ok "$p: 503, Retry-After: 30, no Location" || bad "$p: $s ($(tr '\r\n' '  ' <$H))"
  case "$(hdr Content-Type)" in text/plain*) ok "$p: text" ;; *) bad "$p: Content-Type '$(hdr Content-Type)'" ;; esac
done

# browser paths and near misses: still the 301 to the recovery's page
for p in /index.htm /webui/index.htm /api /apix/x /addonsx /config/xmlapi/statelist.cgi; do
  s=$(req http://127.0.0.1$p)
  loc=$(hdr Location)
  [ "$s" = 301 ] && [ "$loc" = / -o "$loc" = http://127.0.0.1/ ] && ok "$p: 301 to /" || bad "$p: $s Location '$loc'"
done
s=$(req http://127.0.0.1/)
[ "$s" != 301 ] && [ "$s" != 503 ] && ok "/: the recovery's page ($s)" || bad "/: $s"

kill $pid 2>/dev/null; wait $pid 2>/dev/null
grep -i 'error\|fail' /var/log/lighttpd-error.log 2>/dev/null | grep -v 'server started\|server stopped' | sed 's/^/     error log: /'
[ "$f" = 0 ]
INNER
  then
    sed 's/^/     /' "$out"
    ok "the recovery's lighttpd (container)"
  else
    sed 's/^/     /' "$out"
    bad "the recovery's lighttpd (container)"
  fi
  rm -f "$out"
fi

echo; [ "$fails" -eq 0 ] && { echo "lite-recovery-lighttpd-test: all checks passed"; exit 0; }
echo "lite-recovery-lighttpd-test: $fails check(s) failed"; exit 1
