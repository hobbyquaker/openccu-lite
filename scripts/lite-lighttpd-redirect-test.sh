#!/bin/bash
# openccu-lite: the lighttpd redirects on a real lighttpd, in an Alpine container. S50lighttpd's
# reload turns the userfs markers into /var/etc/lighttpd_*.conf, `lighttpd -tt` parses the whole
# configuration of the base and lite overlays with occulited's fragment, and curl checks who is
# redirected where: the HTTP -> HTTPS redirect, HSTS and the redirect from the bare host name to
# <host>.<domain>, with their markers present and absent. The box's own lighttpd is the one to
# parse it on hardware; this is the version Alpine ships, for the match logic. Needs docker and
# the network (apk).
#
# lighttpd runs as the sandboxed unit runs it, as far as a container without CAP_SYS_ADMIN can:
# as an unprivileged user with CAP_NET_BIND_SERVICE alone and no new privileges (setpriv), the
# certificate through a certs group, the pid file in /run/lighttpd (its runtime directory; the
# lite post-build points server.pid-file there, mirrored here), the upload overflow directory the
# one writable place under /usr/local, conf.d/cgi.conf gone as the post-build removes it (the lite
# modules.conf loads no mod_cgi), and every apply runs the steps of lighttpd-prepare.service that
# exist here, as root, taken from the unit file. At the end: the error log shows no refused write,
# and the user created nothing outside its pid directory, the upload directories and the log. The
# mount namespace, seccomp and the capability bounding set of the real unit need systemd and are
# the lab system's check.
#
# The last section is the session header (B-94, D-65): echo backends report which
# X-Occulite-Session reached them - an addon under /addons/ (plain, HTTP/2, WebSocket over HTTP/1.1
# and HTTP/2 extended CONNECT), a CGI through occulited, occulited's API and shell, an addon path
# outside /addons/ and an addon's own socket - with and without a session and with forged headers.
# The gate half needs an occulited checkout whose gate sets the header; with an older one those
# checks are skipped and only the fork's global removal is checked. The session file is written as
# the checkout's gate looks it up: by the SHA-256 of the id (occulited B-102) or by the id. The ids
# have the shapes the gate accepts since occulited task 125 (D-77): a session id is 26 characters
# of base32 and is taken from a cookie or ?sid=; the legacy alias is ten alphanumerics, lives in
# the legacy-sessions mirror and is taken from ?sid= under /addons/ alone, never from a cookie.
# The cookie the gate reads is the gate cookie occulite_gate / __Secure-occulite_gate at
# Path=/addons/ (openccu-lite task 259, D-78); the API's occulite_session is scoped to /api and is
# no credential at the gate - checked below. (The shell's Content-Security-Policy is occulited's
# own header, internal/ui/csp.txt, not lighttpd's; the echo stand-in here does not send it.)
#
# Usage: scripts/lite-lighttpd-redirect-test.sh [occulited checkout]     (default: ../occulited)
#        ALPINE_IMAGE=alpine:3.22 is the default image.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OCC=$(cd "${1:-$ROOT/../occulited}" 2>/dev/null && pwd) || { echo "no occulited checkout at ${1:-$ROOT/../occulited}" >&2; exit 2; }
[ -f "$OCC/deploy/lighttpd/occulited.conf" ] || { echo "no deploy/lighttpd/occulited.conf under $OCC" >&2; exit 2; }
# the stand-in listens where the checkout's fragment proxies to (8183 since occulited task 182; 2121
# before it): read it from the fragment, so the test follows the port and never answers 503 for a
# port it guessed (B-179)
OCC_PORT=$(sed -n 's/.*"port" => \([0-9][0-9]*\).*/\1/p' "$OCC/deploy/lighttpd/occulited.conf" | sort -u)
case "$OCC_PORT" in
  *[!0-9]*|"") echo "cannot read one proxy port from $OCC/deploy/lighttpd/occulited.conf: '$OCC_PORT'" >&2; exit 2 ;;
esac
echo "occulited's port in the fragment: $OCC_PORT"

exec docker run --rm -i -e "OCC_PORT=$OCC_PORT" \
  -v "$ROOT/buildroot-external/overlay:/src/overlay:ro" \
  -v "$OCC/deploy/lighttpd:/src/occulited:ro" \
  "${ALPINE_IMAGE:-alpine:3.22}" sh -s <<'INNER'
set -u
apk add --no-cache lighttpd lighttpd-mod_auth openssl curl python3 py3-h2 setpriv >/tmp/apk.log 2>&1 || { cat /tmp/apk.log; exit 1; }
lighttpd -v
CHECKS=0
FAILS=0
ok() { CHECKS=$((CHECKS + 1)); echo "ok    $*"; }
bad() { CHECKS=$((CHECKS + 1)); FAILS=$((FAILS + 1)); echo "FAIL  $*"; }

# ---- the box's lighttpd tree, as the base and lite overlays and package/occulited install it
mkdir -p /etc/lighttpd /etc/config/lighttpd /etc/init.d /var/etc /var/log /var/run /var/status /www /usr/local/tmp /backend
cp -r /src/overlay/base/etc/lighttpd/. /etc/lighttpd/
cp -r /src/overlay/lite/etc/lighttpd/. /etc/lighttpd/
cp /src/occulited/occulited.conf /etc/lighttpd/conf.d/occulited.conf
cp /src/occulited/occulite-gate.lua /etc/lighttpd/occulite-gate.lua
[ ! -f /src/occulited/occulite-starting.lua ] || cp /src/occulited/occulite-starting.lua /etc/lighttpd/occulite-starting.lua
[ ! -f /src/occulited/occulite-starting.html ] || cp /src/occulited/occulite-starting.html /etc/lighttpd/occulite-starting.html
cp /src/overlay/base/etc/init.d/S50lighttpd /etc/init.d/S50lighttpd
chmod +x /etc/init.d/S50lighttpd
# lighttpd-prepare.service's steps run through their unit-file names: the script under its .script
# name, the lite helpers where the unit has them (occulited itself is not here)
ln -s /etc/init.d/S50lighttpd /etc/init.d/S50lighttpd.script
mkdir -p /usr/libexec/occu
for h in lite-starting-page lite-cert-perms; do
  cp "/src/overlay/lite/usr/libexec/occu/$h" /usr/libexec/occu/$h && chmod +x /usr/libexec/occu/$h
done
PREP_UNIT=/src/overlay/lite/usr/lib/systemd/system/lighttpd-prepare.service
echo "HM_MODE=NORMAL" >/var/hm_mode
echo "LITE=test" >/VERSION
printf '#!/bin/sh\nexit 0\n' >/usr/local/bin/start-stop-daemon # the reload's USR1 to the angel
chmod +x /usr/local/bin/start-stop-daemon

# as the lite post-build leaves the image: no conf.d/cgi.conf (the lite modules.conf loads no
# mod_cgi), and the pid file in the unit's runtime directory
rm -f /etc/lighttpd/conf.d/cgi.conf
if grep -q '^server\.pid-file[[:space:]]*=' /etc/lighttpd/lighttpd.conf; then
  sed -i 's|^server\.pid-file[[:space:]]*=.*$|server.pid-file = "/run/lighttpd/lighttpd.pid"|' /etc/lighttpd/lighttpd.conf
  ok "lighttpd.conf: server.pid-file replaced as the post-build does"
  # and the body handling as the post-build leaves it: every body streams, the overflow directory is
  # the web server's own on the userfs
  sed -i '/^\$REQUEST_HEADER\["Content-Length"\] == "" { server\.stream-request-body = 0 }/d' /etc/lighttpd/lighttpd.conf
  sed -i 's|^server\.upload-dirs[[:space:]]*=.*$|server.upload-dirs = ( "/usr/local/tmp/lighttpd" )|' /etc/lighttpd/lighttpd.conf
else
  bad "lighttpd.conf: no server.pid-file line for the post-build to replace"
fi
if grep -v '^[[:space:]]*#' /etc/lighttpd/modules.conf | grep -q 'mod_cgi\|cgi\.conf'; then bad "the lite modules.conf loads mod_cgi"; else ok "the lite modules.conf loads no mod_cgi"; fi
PIDFILE=/run/lighttpd/lighttpd.pid

# the sandboxed unit's user and groups: www-data on the system, Alpine's lighttpd user here, with
# the certs group that reads the certificate (root:certs 0640, lite-cert-perms) - and the places
# it writes: its runtime directory, the upload overflow directory, and here the error log file
# (the image logs to syslog instead)
addgroup -S certs
WWW=lighttpd
mkdir -p /run/lighttpd && chown $WWW:$WWW /run/lighttpd
chmod 1777 /usr/local/tmp
mkdir -p /usr/local/tmp/lighttpd && chown $WWW:$WWW /usr/local/tmp/lighttpd && chmod 0700 /usr/local/tmp/lighttpd # as lighttpd-prepare.service makes it
: >/var/log/lighttpd-error.log && chown $WWW:$WWW /var/log/lighttpd-error.log
CERTS_GID=$(getent group certs | cut -d: -f3)
# lighttpd as the unit runs it: the user, the certs group, CAP_NET_BIND_SERVICE and nothing else in
# the bounding set, ambient so the ports survive the exec, no new privileges
as_www() {
  setpriv --reuid=$WWW --regid=$WWW --groups=$CERTS_GID --bounding-set=-all,+net_bind_service \
    --inh-caps=+net_bind_service --ambient-caps=+net_bind_service --no-new-privs "$@"
}
touch /tmp/www-marker

# a certificate for ccu.example.org and ccu, marked as installed by occulited so that
# check_certificate leaves it alone
openssl req -new -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 30 \
  -keyout /tmp/key.pem -out /tmp/crt.pem -subj /CN=ccu.example.org \
  -addext "subjectAltName=DNS:ccu.example.org,DNS:ccu" >/dev/null 2>&1
cat /tmp/key.pem /tmp/crt.pem >/etc/config/server.pem
chmod 0600 /etc/config/server.pem # as check_certificate writes it; lite-cert-perms opens it to the certs group
echo "acme test" >/etc/config/server.pem.managed

# occulited's port: a plain lighttpd that answers 200 for the shell and 404 for everything else,
# and for /addons/ (the CGIs lighttpd hands to occulited), /api/echo and /echo an echo of the
# session header it received (B-94)
echo backend >/backend/index.html
cat >/tmp/echo.lua <<'EOF'
local seen = {}
for k, v in pairs(lighty.r.req_header) do
  if v ~= "" and (k:upper():gsub("[^%w]", "_")) == "X_OCCULITE_SESSION" then seen[#seen + 1] = v end
end
lighty.r.resp_header["X-Echo-Session"] = #seen > 0 and table.concat(seen, " | ") or "-"
-- B-230: the forwarding headers as the backend received them
local h = lighty.r.req_header
lighty.r.resp_header["X-Echo-Forwarded"] = "for=" .. (h["X-Forwarded-For"] or "-") .. ";proto=" .. (h["X-Forwarded-Proto"] or "-") .. ";host=" .. (h["X-Forwarded-Host"] or "-") .. ";fwd=" .. (h["Forwarded"] or "-")
lighty.r.resp_header["Content-Type"] = "text/plain"
lighty.r.resp_body:set({ "echo\n" })
return 200
EOF
cat >/tmp/backend.conf <<EOF
server.modules = ( "mod_magnet" )
server.document-root = "/backend"
server.bind = "127.0.0.1"
server.port = $OCC_PORT
server.pid-file = "/var/run/backend.pid"
index-file.names = ("index.html")
\$HTTP["url"] =~ "^/(addons/|api/echo\$|echo\$)" {
  magnet.attract-raw-url-to = ( "/tmp/echo.lua" )
}
EOF
lighttpd -f /tmp/backend.conf || { echo "backend did not start"; exit 1; }

IP=$(ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1)
echo "container address $IP (not the loopback)"

# apply the markers as the box does - lighttpd-prepare.service's steps, as root, each one the unit
# names that exists here (S50lighttpd reload, the starting page, the certificate group) - parse,
# restart lighttpd as its user
prepare() {
  sed -n 's/^ExecStart=-//p' "$PREP_UNIT" | while IFS= read -r step; do
    [ -x "${step%% *}" ] || continue
    $step >>/tmp/prepare.log 2>&1 || echo "prepare: $step exited $?" >>/tmp/prepare.log
  done
}
apply() {
  prepare
  if lighttpd -tt -f /etc/lighttpd/lighttpd.conf >/tmp/tt.log 2>&1; then ok "lighttpd -tt ($1)"; else bad "lighttpd -tt ($1)"; cat /tmp/tt.log; fi
  if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE")
    kill "$pid"
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 0.3; done
  fi
  as_www lighttpd -f /etc/lighttpd/lighttpd.conf >/tmp/start.log 2>&1 || { bad "lighttpd start ($1)"; cat /tmp/start.log; }
  sleep 0.5
}

# expect <label> <status> <location or -> curl arguments...
expect() {
  label=$1 want_code=$2 want_loc=$3
  shift 3
  head=$(curl -sk -o /dev/null -D - --max-time 5 "$@" | tr -d '\r')
  code=$(echo "$head" | sed -n '1s/^HTTP\/[0-9.]* \([0-9]*\).*/\1/p')
  loc=$(echo "$head" | sed -n 's/^[Ll]ocation: //p')
  [ -n "$loc" ] || loc=-
  if [ "$code" = "$want_code" ] && [ "$loc" = "$want_loc" ]; then ok "$label: $code $loc"; else bad "$label: got $code $loc, want $want_code $want_loc"; fi
}

# a header on the answer: header <label> <regex> curl arguments...
header() {
  label=$1 re=$2
  shift 2
  if curl -sk -o /dev/null -D - --max-time 5 "$@" | tr -d '\r' | grep -Eiq "$re"; then ok "$label"; else bad "$label"; fi
}

included() { grep -q 'include' /var/etc/lighttpd_fqdnredirect.conf; }

S=https://ccu
R="--resolve ccu:443:$IP --resolve ccu:80:$IP --resolve ccu.example.org:443:$IP --resolve ccu.example.org:80:$IP"

echo "---- no markers"
apply "no markers"
if included; then bad "no marker: the include is empty"; else ok "no marker: the include is empty"; fi
# the prepared tree as the unit leaves it for the user
if [ "$(stat -c '%U:%G %a' /etc/config/server.pem)" = "root:certs 640" ]; then ok "the certificate is root:certs 0640 after lite-cert-perms"; else bad "the certificate: $(stat -c '%U:%G %a' /etc/config/server.pem)"; fi
[ -s /var/etc/occulite-starting.html ] && ok "the starting page is rendered into /var/etc" || bad "no /var/etc/occulite-starting.html after lite-starting-page"
pid=$(cat "$PIDFILE" 2>/dev/null)
if [ -n "$pid" ] && [ "$(stat -c %U "/proc/$pid")" = "$WWW" ]; then ok "lighttpd runs as $WWW (pid $pid, pid file in /run/lighttpd)"; else bad "lighttpd is not running as $WWW: pid '${pid:-none}'"; fi
case "$(grep '^CapEff:' "/proc/$pid/status" 2>/dev/null)" in
  *0000000000000400) ok "lighttpd's effective capabilities: CAP_NET_BIND_SERVICE alone" ;;
  *) bad "lighttpd's capabilities: $(grep '^Cap' "/proc/$pid/status" | tr '\n' ' ')" ;;
esac
grep -q '^NoNewPrivs:[[:space:]]*1' "/proc/$pid/status" && ok "lighttpd runs with no new privileges" || bad "lighttpd: NoNewPrivs is not set"
# shellcheck disable=SC2086
expect "https://ccu/ stays" 200 - $R $S/
# shellcheck disable=SC2086
expect "http://ccu/ stays" 200 - $R http://ccu/
# shellcheck disable=SC2086
expect "https://ccu/addons/x/ without a session: the gate asks for a login" 302 "/login?return=/addons/x/" $R -H "Accept: text/html" $S/addons/x/

echo "---- the FQDN marker alone"
echo "ccu.example.org" >/etc/config/fqdnRedirect
apply "fqdn marker"
if [ "$(cat /var/etc/lighttpd_fqdnredirect.conf)" = "$(printf 'var.fqdn_redirect_host = "ccu"\nvar.fqdn_redirect_target = "ccu.example.org"\ninclude "/etc/lighttpd/conf.d/fqdnredirect.conf"')" ]; then ok "the include names host and target"; else bad "the include:"; cat /var/etc/lighttpd_fqdnredirect.conf; fi
if grep -q fqdnredirect /var/etc/lighttpd_httpsredirect.conf; then bad "port 80 without the HTTPS redirect"; else ok "port 80 untouched without the HTTPS redirect"; fi
# shellcheck disable=SC2086
{
expect "GET https://ccu/x?y=1" 302 "https://ccu.example.org/x?y=1" $R "$S/x?y=1"
expect "HEAD https://ccu/" 302 "https://ccu.example.org/" $R -I $S/
expect "Host: CCU:443 (capitals, a port)" 302 "https://ccu.example.org/a%20b" -H "Host: CCU:443" "https://$IP/a%20b"
expect "Host: ccu:8443 (another port)" 302 "https://ccu.example.org/" -H "Host: ccu:8443" "https://$IP/"
expect "https://ccu.example.org/ (the FQDN)" 200 - $R https://ccu.example.org/
expect "https://<IPv4>/" 200 - "https://$IP/"
expect "Host: [fe80::1]:443 (an IPv6 literal)" 200 - -H "Host: [fe80::1]:443" "https://$IP/"
expect "Host: ccu.example (another name)" 200 - -H "Host: ccu.example" "https://$IP/"
expect "Host: xccu" 200 - -H "Host: xccu" "https://$IP/"
expect "Host: ccu-2" 200 - -H "Host: ccu-2" "https://$IP/"
expect "POST https://ccu/x" 404 - $R -X POST -d a=b $S/x
expect "PUT https://ccu/" 501 - $R -X PUT -d a=b $S/
expect "GET https://ccu/api/system/v1/health" 404 - $R $S/api/system/v1/health
expect "GET https://ccu/api" 404 - $R $S/api
expect "POST https://ccu/api/auth/v1/login" 404 - $R -X POST -d a=b $S/api/auth/v1/login
expect "https://ccu/.well-known/acme-challenge/x" 404 - $R $S/.well-known/acme-challenge/x
expect "http://ccu/.well-known/acme-challenge/x" 404 - $R http://ccu/.well-known/acme-challenge/x
expect "https://ccu/ from the loopback" 200 - --resolve ccu:443:127.0.0.1 $S/
expect "http://ccu/ is not redirected without the HTTPS redirect" 200 - $R http://ccu/
expect "https://ccu/apix (only /api itself is left alone)" 302 "https://ccu.example.org/apix" $R $S/apix
expect "https://ccu.example.org/addons/x/ without a session: the gate asks for a login" 302 "/login?return=/addons/x/" $R -H "Accept: text/html" https://ccu.example.org/addons/x/
expect "https://ccu.example.org/addons/x/ without a session, not a browser: 401" 401 - $R https://ccu.example.org/addons/x/
}
# the short name's /addons/ ends on the FQDN either way: redirected at once, or through the login
gate=$(curl -sk -o /dev/null -w '%{http_code} %{redirect_url}' $R -H "Accept: text/html" $S/addons/x/)
case "$gate" in
  "302 https://ccu.example.org/addons/x/" | "302 https://ccu/login?return=/addons/x/") ok "https://ccu/addons/x/ without a session: $gate" ;;
  *) bad "https://ccu/addons/x/ without a session: $gate" ;;
esac
host_dot=$(curl -sk -o /dev/null -w '%{http_code} %{redirect_url}' -H "Host: ccu." "https://$IP/")
echo "info  Host: ccu. (a trailing dot) -> $host_dot"

echo "---- the FQDN marker with the HTTPS redirect and HSTS"
touch /etc/config/httpsRedirectEnabled
echo 31536000 >/etc/config/hstsEnabled
apply "fqdn, https redirect, hsts"
if grep -q 'include "/var/etc/lighttpd_fqdnredirect.conf"' /var/etc/lighttpd_httpsredirect.conf; then ok "port 80 includes the FQDN redirect after the HTTPS one"; else bad "port 80:"; cat /var/etc/lighttpd_httpsredirect.conf; fi
# shellcheck disable=SC2086
{
expect "http://ccu/p?q=1: one hop to the FQDN" 302 "https://ccu.example.org/p?q=1" $R "http://ccu/p?q=1"
hops=$(curl -sk -o /dev/null -L --max-redirs 5 -w '%{num_redirects} %{url_effective}' $R "http://ccu/p?q=1")
if [ "$hops" = "1 https://ccu.example.org/p?q=1" ]; then ok "a browser follows one redirect: $hops"; else bad "the chain: $hops"; fi
expect "http://ccu.example.org/ (the HTTPS redirect as before)" 301 "https://ccu.example.org/" $R http://ccu.example.org/
expect "http://<IPv4>/" 301 "https://$IP/" "http://$IP/"
post=$(curl -sk -o /dev/null -w '%{http_code} %{redirect_url}' $R -X POST -d a=b http://ccu/api/x)
case "$post" in # lighttpd keeps the method with 308 where it can
  "301 https://ccu/api/x" | "308 https://ccu/api/x") ok "POST http://ccu/api/x (the HTTPS redirect as before): $post" ;;
  *) bad "POST http://ccu/api/x: $post" ;;
esac
expect "http://ccu/.well-known/acme-challenge/x" 404 - $R http://ccu/.well-known/acme-challenge/x
expect "http://ccu/ from the loopback" 200 - --resolve ccu:80:127.0.0.1 http://ccu/
expect "GET https://ccu/" 302 "https://ccu.example.org/" $R $S/
header "the short name's redirect carries HSTS" '^strict-transport-security: max-age=31536000' $R $S/
header "the FQDN carries HSTS" '^strict-transport-security: max-age=31536000' $R https://ccu.example.org/
if curl -sk -o /dev/null -D - --max-time 5 $R http://ccu/ | tr -d '\r' | grep -Eiq '^strict-transport-security:'; then bad "port 80 sends no HSTS"; else ok "port 80 sends no HSTS"; fi
}

# no Strict-Transport-Security header at all: nohsts <label> curl arguments...
nohsts() {
  label=$1
  shift
  if curl -sk -o /dev/null -D - --max-time 5 "$@" | tr -d '\r' | grep -Eiq '^strict-transport-security:'; then bad "$label"; else ok "$label"; fi
}
hsts_include() { [ "$(cat /var/etc/lighttpd_hsts.conf)" = "$(printf 'var.hsts_max_age = "%s"\ninclude "/etc/lighttpd/conf.d/hsts.conf"' "$1")" ]; }

echo "---- HSTS: a week by default, and max-age=0 for a while when switched off (task 96)"
# shellcheck disable=SC2086
{
printf 'yes\n' >/etc/config/hstsEnabled
apply "an HSTS marker without digits"
if hsts_include 604800; then ok "a marker without digits: the include sets a week"; else bad "no digits:"; cat /var/etc/lighttpd_hsts.conf; fi
header "a marker without digits: max-age=604800" '^strict-transport-security: max-age=604800$' $R https://ccu.example.org/
echo 0 >/etc/config/hstsEnabled
rm -f /etc/config/hstsClearUntil
apply "HSTS clearing without a deadline"
if hsts_include 0; then ok "clearing without a deadline: the include sets 0"; else bad "clearing without a deadline:"; cat /var/etc/lighttpd_hsts.conf; fi
header "clearing without a deadline: max-age=0" '^strict-transport-security: max-age=0$' $R https://ccu.example.org/
header "clearing: the short name's redirect carries max-age=0" '^strict-transport-security: max-age=0$' $R $S/
nohsts "clearing: port 80 sends no HSTS" $R http://ccu/
echo "$(($(date +%s) + 86400))" >/etc/config/hstsClearUntil
apply "HSTS clearing until tomorrow"
if hsts_include 0; then ok "clearing until tomorrow: the include sets 0"; else bad "clearing until tomorrow:"; cat /var/etc/lighttpd_hsts.conf; fi
header "clearing until tomorrow: max-age=0" '^strict-transport-security: max-age=0$' $R https://ccu.example.org/
printf '00\n' >/etc/config/hstsEnabled
apply "HSTS clearing, marker 00"
if hsts_include 0; then ok "marker 00: the include sets 0"; else bad "marker 00:"; cat /var/etc/lighttpd_hsts.conf; fi
echo 0 >/etc/config/hstsEnabled
echo "$(($(date +%s) - 1))" >/etc/config/hstsClearUntil
apply "HSTS clearing, the deadline passed"
if [ -z "$(tr -d ' \n' </var/etc/lighttpd_hsts.conf)" ]; then ok "the deadline passed: the include is empty"; else bad "the deadline passed:"; cat /var/etc/lighttpd_hsts.conf; fi
nohsts "the deadline passed: no header" $R https://ccu.example.org/
echo 604800 >/etc/config/hstsEnabled
apply "HSTS on beside a stale deadline file"
if hsts_include 604800; then ok "on beside a stale deadline: the include sets 604800"; else bad "on beside a stale deadline:"; cat /var/etc/lighttpd_hsts.conf; fi
header "on beside a stale deadline: max-age=604800" '^strict-transport-security: max-age=604800$' $R https://ccu.example.org/
rm -f /etc/config/hstsEnabled /etc/config/hstsClearUntil
apply "the HSTS marker removed"
nohsts "the marker removed: no header" $R https://ccu.example.org/
}

echo "---- the marker the box does not accept"
rm -f /etc/config/httpsRedirectEnabled /etc/config/hstsEnabled
for m in "lite.example.org" "ccu" 'ccu.example.org" + "x' "-ccu.example.org" "ccu..example.org"; do
  printf '%s\n' "$m" >/etc/config/fqdnRedirect
  apply "marker $m"
  if included; then bad "marker '$m': no include"; else ok "marker '$m': no include"; fi
done
# shellcheck disable=SC2086
expect "https://lite/ with a certificate for ccu only" 200 - --resolve lite:443:$IP https://lite/
printf 'CCU.Example.ORG\r\n' >/etc/config/fqdnRedirect
apply "marker in capitals with CRLF"
if included; then ok "marker in capitals with CRLF: included"; else bad "marker in capitals with CRLF"; fi
# shellcheck disable=SC2086
expect "GET https://ccu/ (capital marker)" 302 "https://ccu.example.org/" $R $S/
mv /etc/lighttpd/conf.d/fqdnredirect.conf /tmp/fqdnredirect.conf
apply "marker without the fragment"
if included; then bad "no fragment: no include"; else ok "no fragment: no include"; fi
mv /tmp/fqdnredirect.conf /etc/lighttpd/conf.d/fqdnredirect.conf

echo "---- switched off again"
rm -f /etc/config/fqdnRedirect
apply "marker removed"
# shellcheck disable=SC2086
expect "https://ccu/ after the marker went" 200 - $R $S/

echo "---- the session header X-Occulite-Session (B-94, D-65)"
# an addon backend: answers every request with the session headers it received in X-Echo-Session
# ("-" for none), a WebSocket upgrade with 101, and logs one line per request it saw
cat >/tmp/echo.py <<'EOF'
import http.server, socketserver, sys
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        def cgi(name):
            return "".join(c if c.isalnum() else "_" for c in name.upper())
        seen = [v for k, v in self.headers.items() if cgi(k) == "X_OCCULITE_SESSION" and v != ""]
        seen = " | ".join(seen) or "-"
        h = self.headers
        fwd = "for=%s;proto=%s;host=%s;fwd=%s" % (h.get("X-Forwarded-For", "-"), h.get("X-Forwarded-Proto", "-"), h.get("X-Forwarded-Host", "-"), h.get("Forwarded", "-"))
        # the identity headers of the addon ingress token (occulited's gate): what reached the addon, any spelling
        auth = " | ".join(v for k, v in self.headers.items() if cgi(k) == "X_OCCULITE_AUTH" and v != "") or "-"
        tok = " | ".join(v for k, v in self.headers.items() if cgi(k) == "X_OCCULITE_TOKEN" and v != "") or "-"
        ident = "auth=%s;token=%s" % (auth, tok)
        with open("/tmp/echo.log", "a") as log:
            log.write(self.path + " " + seen + "\n")
        if self.headers.get("Upgrade", "").lower() == "websocket":
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("X-Echo-Session", seen)
            self.end_headers()
            self.close_connection = True
            return
        self.send_response(200)
        self.send_header("X-Echo-Session", seen)
        self.send_header("X-Echo-Forwarded", fwd)
        self.send_header("X-Echo-Identity", ident)
        self.send_header("Content-Length", "5")
        self.end_headers()
        self.wfile.write(b"echo\n")
    do_POST = do_GET
    def log_message(self, *a):
        pass
class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
S(("127.0.0.1", 2122), H).serve_forever()
EOF
# an HTTP/2 WebSocket handshake (RFC 8441 extended CONNECT), which curl cannot send: prints the
# status and the backend's X-Echo-Session ("none" when the answer has no such header)
cat >/tmp/h2ws.py <<'EOF'
import socket, ssl, sys, h2.connection, h2.config, h2.events
host, path = sys.argv[1], sys.argv[2]
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
ctx.set_alpn_protocols(["h2"])
s = ctx.wrap_socket(socket.create_connection((host, 443), timeout=5), server_hostname="ccu")
if s.selected_alpn_protocol() != "h2":
    print("no-h2 none")
    sys.exit(0)
c = h2.connection.H2Connection(h2.config.H2Configuration(client_side=True, header_encoding="utf-8"))
c.initiate_connection()
s.sendall(c.data_to_send())
hdrs = [(":method", "CONNECT"), (":protocol", "websocket"), (":scheme", "https"), (":path", path), (":authority", "ccu"), ("sec-websocket-version", "13")]
for e in sys.argv[3:]:
    k, v = e.split(":", 1)
    hdrs.append((k.strip().lower(), v.strip()))
sent = False
while True:
    data = s.recv(65535)
    if not data:
        break
    for ev in c.receive_data(data):
        if isinstance(ev, h2.events.RemoteSettingsChanged) and not sent:
            c.send_headers(1, hdrs)
            sent = True
        if isinstance(ev, h2.events.ResponseReceived):
            h = dict(ev.headers)
            print(h.get(":status", "?"), h.get("x-echo-session", "none"))
            sys.exit(0)
    s.sendall(c.data_to_send())
print("closed none")
EOF
python3 /tmp/echo.py &
ECHO_PID=$!
: >/tmp/echo.log
# the addon's drop-in: its frontend under /addons/ like RedMatic's and homematic-manager's, a path
# outside /addons/ like RedMatic's Amazon Echo hub (no gate there), and a socket of its own
cat >/etc/config/lighttpd/echo.conf <<'EOF'
$HTTP["url"] =~ "^/addons/echo/" {
  proxy.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 2122 ) ) )
  proxy.header = ( "upgrade" => "enable" )
}
$HTTP["url"] =~ "(^/description.xml)|(^/api/.*/lights)" {
  proxy.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 2122 ) ) )
}
$SERVER["socket"] == ":8282" {
  ssl.engine = "disable"
  proxy.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 2122 ) ) )
  proxy.header = ( "upgrade" => "enable" )
}
EOF
# a session's file in occulited's mirror: named by the SHA-256 of its id where the gate hashes it
# (occulited B-102: the gate calls lighty.c.md), by the id itself before; so the checks below run
# against either occulited checkout
session_file() {
  if grep -q 'lighty.c.md' /etc/lighttpd/occulite-gate.lua; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
  else
    echo "$1"
  fi
}
# the ids: a session id (26 base32 characters), a stale one of the same shape, a legacy alias (ten
# alphanumerics, task 125) - the gate matches the shape before it looks for the file
SID=LIVESESSION2345A2B3C4D5E6F
STALE=STALESESSION2345A2B3C4D5E6
ALIAS=LIVEALIAS1
mkdir -p /var/run/occulite/sessions /var/run/occulite/legacy-sessions
echo admin >"/var/run/occulite/sessions/$(session_file $SID)"
echo admin >"/var/run/occulite/legacy-sessions/$(session_file $ALIAS)"
apply "the session header"

# echoed <label> <status> <X-Echo-Session: the id, - (reached, no header) or none (not reached)> curl arguments...
echoed() {
  label=$1 want_code=$2 want_seen=$3
  shift 3
  head=$(curl -sk -o /dev/null -D - --max-time 3 "$@" | tr -d '\r')
  code=$(echo "$head" | sed -n '1s/^HTTP\/[0-9.]* \([0-9]*\).*/\1/p')
  seen=$(echo "$head" | sed -n 's/^[Xx]-[Ee]cho-[Ss]ession: //p')
  [ -n "$seen" ] || seen=none
  if [ "$code" = "$want_code" ] && [ "$seen" = "$want_seen" ]; then ok "$label: $code $seen"; else bad "$label: got $code $seen, want $want_code $want_seen"; fi
}
# h2ws <label> <status> <X-Echo-Session> <path> headers...
h2ws() {
  label=$1 want=$2
  shift 2
  got=$(python3 /tmp/h2ws.py 127.0.0.1 "$@" 2>&1)
  if [ "$got" = "$want" ]; then ok "$label: $got"; else bad "$label: got '$got', want '$want'"; fi
}
reached() { wc -l </tmp/echo.log | tr -d ' '; }

WS="-H Connection:Upgrade -H Upgrade:websocket -H Sec-WebSocket-Version:13 -H Sec-WebSocket-Key:dGhlIHNhbXBsZSBub25jZQ=="
FORGED="-H X-Occulite-Session:FORGED0000 -H x-occulite-session:FORGED1111 -H X_Occulite_Session:FORGED2222 -H x.occulite.session:FORGED3333"
# the cookie the gate reads: occulite_gate since occulited task 259 (the API's occulite_session is
# scoped to /api then), occulite_session before - the checks below follow the checkout's gate, as the
# CI runs this against the pinned occulited until the pin moves
if grep -q 'occulite_gate' /etc/lighttpd/occulite-gate.lua; then GC=occulite_gate; else GC=occulite_session; fi
echo "the gate's cookie in this checkout: $GC"
HC="Cookie: $GC=$SID"
SC="Cookie: theme=dark; __Secure-$GC=@$SID@"

if grep -q 'X-Occulite-Session' /etc/lighttpd/occulite-gate.lua; then
# shellcheck disable=SC2086
{
echoed "an addon, HTTP cookie: the validated id" 200 $SID $R -H "$HC" http://ccu/addons/echo/
echoed "an addon, HTTPS cookie over HTTP/2: the validated id" 200 $SID $R --http2 -H "$SC" $S/addons/echo/
echoed "an addon, ?sid=@..@ with the legacy alias: the validated alias" 200 $ALIAS $R "$S/addons/echo/?sid=@$ALIAS@"
echoed "an addon, ?sid=@..@ with the session id: the validated id" 200 $SID $R "$S/addons/echo/?sid=@$SID@"
echoed "an addon, the legacy alias in a cookie: 401 (an alias is taken from ?sid= alone)" 401 none $R -H "Cookie: $GC=$ALIAS" $S/addons/echo/
if [ "$GC" = occulite_gate ]; then
echoed "an addon, a live id under the API's cookie name: 401 (task 259: the gate reads the gate cookie alone)" 401 none $R -H "Cookie: occulite_session=$SID" $S/addons/echo/
echoed "an addon, a live id under the API's HTTPS cookie name: 401" 401 none $R -H "Cookie: __Secure-occulite_session=$SID" $S/addons/echo/
else
  echo "skip  the API's cookie name at the gate: this occulited's gate still reads it (before task 259)"
fi
echoed "an addon, a live cookie and four forged headers: only the validated id" 200 $SID $R -H "$HC" $FORGED $S/addons/echo/
echoed "an addon, ?sid= and forged headers over HTTP/2: only the validated id" 200 $SID $R --http2 $FORGED "$S/addons/echo/x?a=1&sid=$SID"
echoed "an addon, a live cookie and an empty forged header" 200 $SID $R -H "$HC" -H "X-Occulite-Session;" $S/addons/echo/
before=$(reached)
echoed "an addon, forged headers, no session: 401, not passed on" 401 none $R $FORGED $S/addons/echo/
echoed "an addon, forged headers, a stale cookie: 401" 401 none $R -H "Cookie: $GC=$STALE" $FORGED $S/addons/echo/
echoed "an addon, forged headers, a browser without a session: the login" 302 none $R -H "Accept: text/html" $FORGED $S/addons/echo/
echoed "a WebSocket upgrade, forged headers, no session: 401" 401 none $R --http1.1 $WS $FORGED http://ccu/addons/echo/ws
h2ws "an HTTP/2 WebSocket, forged headers, no session: 401" "401 none" /addons/echo/ws "x-occulite-session: FORGED0000" "x_occulite_session: FORGED2222"
if [ "$(reached)" = "$before" ]; then ok "the rejected requests never reached the addon"; else bad "the rejected requests reached the addon:"; tail -n +$((before + 1)) /tmp/echo.log; fi
echoed "a WebSocket upgrade over HTTP/1.1, cookie and forged headers: the validated id" 101 $SID $R --http1.1 -H "$HC" $WS $FORGED http://ccu/addons/echo/ws
echoed "a WebSocket upgrade over TLS HTTP/1.1, cookie and forged headers" 101 $SID $R --http1.1 -H "$SC" $WS $FORGED $S/addons/echo/ws
h2ws "an HTTP/2 WebSocket (extended CONNECT), cookie and forged headers: the validated id" "200 $SID" /addons/echo/ws "cookie: __Secure-$GC=$SID" "x-occulite-session: FORGED0000" "x_occulite_session: FORGED2222" "x.occulite.session: FORGED3333"
h2ws "an HTTP/2 WebSocket with ?sid= and the legacy alias: the validated alias" "200 $ALIAS" "/addons/echo/ws?sid=@$ALIAS@" "x-occulite-session: FORGED0000"
echoed "a CGI through occulited, cookie and forged headers: the validated id" 200 $SID $R -H "$HC" $FORGED http://ccu/addons/cgi/settings.cgi
echoed "a CGI through occulited, ?sid= with the legacy alias over HTTP/2" 200 $ALIAS $R --http2 $FORGED "$S/addons/cgi/settings.cgi?sid=@$ALIAS@"
echoed "a CGI, forged headers, no session: 401" 401 none $R $FORGED $S/addons/cgi/settings.cgi
rm -f "/var/run/occulite/sessions/$(session_file $SID)"
echoed "an addon, the cookie of a session that ended: 401" 401 none $R -H "$HC" $FORGED $S/addons/echo/
echo admin >"/var/run/occulite/sessions/$(session_file $SID)"
rm -f "/var/run/occulite/legacy-sessions/$(session_file $ALIAS)"
echoed "an addon, ?sid=@..@ of an alias that ended: 401" 401 none $R "$S/addons/echo/?sid=@$ALIAS@"
echo admin >"/var/run/occulite/legacy-sessions/$(session_file $ALIAS)"
if grep -q 'lighty.c.md' /etc/lighttpd/occulite-gate.lua; then
  # B-102: only the digest names a session - the old mirror's file named by the id is none, and the
  # digest itself is no credential; this lighttpd's lighty.c.md computes it
  RAW=RAWSESSION2345A2B3C4D5E6FG
  echo admin >"/var/run/occulite/sessions/$RAW"
  echoed "an addon, a file named by the id itself (the old mirror): 401" 401 none $R -H "Cookie: $GC=$RAW" $S/addons/echo/
  echoed "an addon, ?sid= of a file named by the id itself: 401" 401 none $R "$S/addons/echo/?sid=@$RAW@"
  rm -f "/var/run/occulite/sessions/$RAW"
  echoed "an addon, a live session's digest as the cookie: 401" 401 none $R -H "Cookie: $GC=$(session_file $SID)" $S/addons/echo/
  echoed "an addon, a forged id: 401" 401 none $R -H "Cookie: $GC=FORGED0000" $FORGED $S/addons/echo/
fi
if grep -q 'gate-tokens' /etc/lighttpd/occulite-gate.lua; then
  echo "---- an API token at the gate (the addon ingress scope addon:<id>, GitHub issue openccu-lite#3)"
  # occulited mirrors every stored token into /var/run/occulite/gate-tokens by the SHA-256 of its
  # secret: the token's name, the segments under /addons/ its scopes open, an expiry, address ranges.
  # The gate takes the token from Authorization: Bearer alone, answers 401 for one it does not know,
  # 403 for another addon or an address outside the ranges, and hands the addon the token in the
  # session header with X-Occulite-Auth: token and X-Occulite-Token: <name>; a session carries
  # X-Occulite-Auth: session. Forged copies of the identity headers never reach the addon.
  TOK=olt_0123456789abcdef0123456789abcdef
  TOK2=olt_fedcba9876543210fedcba9876543210
  TOKX=olt_00000000000000000000000000000000
  TOKR=olt_11111111111111111111111111111111
  mkdir -p /var/run/occulite/gate-tokens
  printf 'name loom\naddons echo cgi\n' >"/var/run/occulite/gate-tokens/$(session_file $TOK)"
  printf 'name other\naddons other\n' >"/var/run/occulite/gate-tokens/$(session_file $TOK2)"
  printf 'name old\naddons echo\nexpires 1000000000\n' >"/var/run/occulite/gate-tokens/$(session_file $TOKX)"
  printf 'name ranged\naddons echo\nip 192.0.2.0/24\n' >"/var/run/occulite/gate-tokens/$(session_file $TOKR)"
  FORGED_ID="-H X-Occulite-Auth:session -H x_occulite_token:admin -H X-Occulite-Token:root"
  # identity <label> <status> <X-Echo-Identity or none> curl arguments...
  identity() {
    label=$1 want_code=$2 want_id=$3
    shift 3
    head=$(curl -sk -o /dev/null -D - --max-time 3 "$@" | tr -d '\r')
    code=$(echo "$head" | sed -n '1s/^HTTP\/[0-9.]* \([0-9]*\).*/\1/p')
    id=$(echo "$head" | sed -n 's/^[Xx]-[Ee]cho-[Ii]dentity: //p')
    [ -n "$id" ] || id=none
    if [ "$code" = "$want_code" ] && [ "$id" = "$want_id" ]; then ok "$label: $code $id"; else bad "$label: got $code $id, want $want_code $want_id"; fi
  }
  echoed "an addon, the token as Bearer: the token in the session header" 200 $TOK $R -H "Authorization: Bearer $TOK" $S/addons/echo/
  identity "an addon, the token as Bearer: X-Occulite-Auth token and its name" 200 "auth=token;token=loom" $R -H "Authorization: Bearer $TOK" $S/addons/echo/x
  identity "an addon, the token over HTTP/2 with forged identity headers: only the gate's" 200 "auth=token;token=loom" $R --http2 -H "Authorization: Bearer $TOK" $FORGED $FORGED_ID $S/addons/echo/
  identity "an addon, a session cookie: X-Occulite-Auth session, no token" 200 "auth=session;token=-" $R -H "$HC" $FORGED_ID $S/addons/echo/
  identity "an addon, ?sid= with the alias: X-Occulite-Auth session" 200 "auth=session;token=-" $R "$S/addons/echo/?sid=@$ALIAS@"
  echoed "a CGI through occulited, the token as Bearer" 200 $TOK $R -H "Authorization: Bearer $TOK" http://ccu/addons/cgi/settings.cgi
  echoed "a WebSocket upgrade with the token as Bearer" 101 $TOK $R --http1.1 -H "Authorization: Bearer $TOK" $WS $S/addons/echo/ws
  before=$(reached)
  echoed "an addon, a token of another addon: 403" 403 none $R -H "Authorization: Bearer $TOK2" $S/addons/echo/
  echoed "an addon, a token nobody has: 401" 401 none $R -H "Authorization: Bearer $TOKX$TOKX" $S/addons/echo/
  echoed "an addon, an expired token: 401" 401 none $R -H "Authorization: Bearer $TOKX" $S/addons/echo/
  echoed "an addon, a token from outside its address range: 403" 403 none $R -H "Authorization: Bearer $TOKR" $S/addons/echo/
  echoed "an addon, a token nobody has beside a live cookie: the token's answer" 401 none $R -H "Authorization: Bearer $TOKX$TOKX" -H "$HC" $S/addons/echo/
  echoed "an addon, the token in ?sid=: no credential" 401 none $R "$S/addons/echo/?sid=$TOK"
  echoed "an addon, the token in the gate cookie: no credential" 401 none $R -H "Cookie: $GC=$TOK" $S/addons/echo/
  echoed "an addon, forged identity headers alone: 401" 401 none $R $FORGED_ID $S/addons/echo/
  if [ "$(reached)" = "$before" ]; then ok "the refused token requests never reached the addon"; else bad "a refused token request reached the addon:"; tail -n +$((before + 1)) /tmp/echo.log; fi
  if grep -q 'token refused: token=other addon=echo' /var/log/lighttpd-error.log; then ok "the 403 is logged with the token's name and the addon"; else bad "no log line for the refused token"; fi
  rm -f "/var/run/occulite/gate-tokens/$(session_file $TOK)"
  echoed "an addon, the token once it was deleted: 401" 401 none $R -H "Authorization: Bearer $TOK" $S/addons/echo/
else
  echo "skip  the token half: this occulited's gate reads no token mirror"
fi
}
else
  echo "skip  the gate half: this occulited's gate does not set X-Occulite-Session"
fi

# the requests the gate does not see: no header, however they are sent, session or not
# shellcheck disable=SC2086
{
echoed "an addon path outside /addons/ (/description.xml), forged headers: none" 200 - $R $FORGED $S/description.xml
identity "an addon path outside /addons/, forged identity headers: none reach it" 200 "auth=-;token=-" $R -H "X-Occulite-Auth: token" -H "X_Occulite_Token: admin" $S/description.xml
echoed "an addon path outside /addons/, a live cookie: no header without the gate" 200 - $R -H "$HC" $FORGED http://ccu/description.xml
echoed "an addon path inside /api/ (/api/x/lights), a live cookie and forged headers" 200 - $R --http2 -H "$SC" $FORGED $S/api/x/lights
echoed "an addon's own socket :8282, forged headers" 200 - $FORGED "http://$IP:8282/"
echoed "an addon's own socket, a WebSocket upgrade with forged headers" 101 - --http1.1 $WS $FORGED "http://$IP:8282/ws"
echoed "occulited's API, a live cookie and forged headers: none" 200 - $R -H "$SC" $FORGED $S/api/echo
echoed "occulited's shell, a live cookie and forged headers: none" 200 - $R -H "$HC" $FORGED http://ccu/echo
echoed "occulited's shell over HTTP/2, forged headers" 200 - $R --http2 $FORGED $S/echo
}
echo "---- the forwarding headers (B-230)"
# lighttpd's mod_proxy appends the client's address to a client-sent X-Forwarded-For instead of
# replacing it; the global magnet script (and occulited's gate under /addons/) removes the client's
# copy, so a backend receives lighttpd's own element alone: the client's address, never a forged
# loopback or range; Forwarded likewise (lighttpd appends to it too), X-Forwarded-Proto and
# X-Forwarded-Host lighttpd sets itself.
# forwarded <label> <for> <proto> curl arguments...: the X-Forwarded-For and -Proto the backend saw,
# and no forged value anywhere in the four headers
forwarded() {
  label=$1 want_for=$2 want_proto=$3
  shift 3
  got=$(curl -sk -o /dev/null -D - --max-time 3 "$@" | tr -d '\r' | sed -n 's/^[Xx]-[Ee]cho-[Ff]orwarded: //p')
  f=$(echo "$got" | sed -n 's/^for=\([^;]*\);.*/\1/p')
  p=$(echo "$got" | sed -n 's/.*;proto=\([^;]*\);.*/\1/p')
  case "$got" in
    *evil*|*10.99.*|*127.0.0.9*) bad "$label: a forged value reached the backend: $got" ;;
    *) if [ "$f" = "$want_for" ] && [ "$p" = "$want_proto" ]; then ok "$label: $got"; else bad "$label: got '$got', want for=$want_for proto=$want_proto"; fi ;;
  esac
}
XFF="-H X-Forwarded-For:127.0.0.9 -H x-forwarded-for:10.99.1.1 -H X_Forwarded_For:10.99.2.2 -H X-Forwarded-Proto:evil -H X-Forwarded-Host:evil.example -H Forwarded:for=127.0.0.9;host=evil.example"
# shellcheck disable=SC2086
{
forwarded "occulited's API over HTTPS, forged forwarding headers" "$IP" https $R $XFF $S/api/echo
forwarded "occulited's API over HTTP/2, forged forwarding headers" "$IP" https $R --http2 $XFF $S/api/echo
forwarded "occulited's shell over HTTP, forged forwarding headers" "$IP" http $R $XFF http://ccu/echo
forwarded "occulited's API, no forwarding header of the client's" "$IP" https $R $S/api/echo
if grep -q 'X_FORWARDED_FOR' /etc/lighttpd/occulite-gate.lua; then
forwarded "a CGI through occulited behind the gate, forged forwarding headers" "$IP" https $R -H "$HC" $XFF $S/addons/cgi/settings.cgi
forwarded "an addon behind the gate, forged forwarding headers" "$IP" https $R -H "$HC" $XFF $S/addons/echo/
else
  echo "skip  the gate half: this occulited's gate does not remove the forwarding headers"
fi
}
kill "$ECHO_PID"
rm -f /etc/config/lighttpd/echo.conf

echo "---- the WebUI's files for addons: device pictures, DEVDB.tcl, translations (task 331)"
# package/openccu-base installs them under /www at the CCU's paths (root, 0644); the lite
# webui.conf serves exactly these read-only from the document root, without a session, and
# everything else under /config/ and /webui/ stays the shell's (the stand-in: 404)
mkdir -p /www/config/img/devices/250/coupling /www/config/img/devices/50 /www/config/devdescr /www/webui/js/lang/de /www/webui/js/lang/en
printf '\211PNG\r\n\032\n250' >/www/config/img/devices/250/131_hmip-wrc6.png
printf '\211PNG\r\n\032\ncpl' >/www/config/img/devices/250/coupling/c_1.png
printf '\211PNG\r\n\032\n50' >/www/config/img/devices/50/131_hmip-wrc6_thumb.png
printf '#!/bin/tclsh\nset DEV_LIST {HmIP-WRC6}\n' >/www/config/devdescr/DEVDB.tcl
printf 'stringtable\n' >/www/config/stringtable_de.txt
printf 'jQuery.extend(true, langJSON, {"de": {}});\n' >/www/webui/js/lang/de/translate.lang.js
printf 'jQuery.extend(true, langJSON, {"en": {}});\n' >/www/webui/js/lang/en/translate.lang.extension.js
printf 'not served\n' >/www/webui/js/lang/translate.js
printf 'not served\n' >/www/config/devdescr/other.tcl
chmod 0644 /www/config/img/devices/250/*.png /www/config/img/devices/250/coupling/*.png /www/config/img/devices/50/*.png \
  /www/config/devdescr/*.tcl /www/config/stringtable_de.txt /www/webui/js/lang/translate.js /www/webui/js/lang/*/*.js
apply "the WebUI's files"
# served <label> <path> <content type>: 200 with that type and the file's bytes, over https and http, no session
served() {
  label=$1 path=$2 type=$3
  for url in "$S$path" "http://ccu$path"; do
    # shellcheck disable=SC2086
    got=$(curl -sk --max-time 5 -o /tmp/got -w '%{http_code} %{content_type}' $R "$url")
    if [ "$got" = "200 $type" ] && cmp -s /tmp/got "/www$path"; then ok "$label ($url): $got"; else bad "$label ($url): got '$got', want '200 $type' and the file"; fi
  done
}
served "a device picture, 250 px" /config/img/devices/250/131_hmip-wrc6.png image/png
served "a coupling picture" /config/img/devices/250/coupling/c_1.png image/png
served "a device picture, 50 px" /config/img/devices/50/131_hmip-wrc6_thumb.png image/png
served "DEVDB.tcl" /config/devdescr/DEVDB.tcl text/x-tcl
served "stringtable_de.txt" /config/stringtable_de.txt text/plain
served "translate.lang.js (de)" /webui/js/lang/de/translate.lang.js text/javascript
served "translate.lang.extension.js (en)" /webui/js/lang/en/translate.lang.extension.js text/javascript
# shellcheck disable=SC2086
{
expect "HEAD a device picture" 200 - $R -I $S/config/img/devices/250/131_hmip-wrc6.png
expect "a missing picture: 404" 404 - $R $S/config/img/devices/250/missing.png
expect "the pictures' directory: no listing" 403 - $R $S/config/img/devices/
expect "the 250 px directory: no listing" 403 - $R $S/config/img/devices/250/
expect "an encoded way out of the pictures: 404" 404 - $R "$S/config/img/devices/250/..%2f..%2fdevdescr%2fother.tcl"
expect "another file next to DEVDB.tcl stays the shell's" 404 - $R $S/config/devdescr/other.tcl
expect "the translations' loader stays the shell's" 404 - $R $S/webui/js/lang/translate.js
expect "/config/devdescr/ stays the shell's" 404 - $R $S/config/devdescr/
expect "a POST to DEVDB.tcl: 403" 403 - $R -X POST -d a=b $S/config/devdescr/DEVDB.tcl
expect "a PUT to a picture: 403" 403 - $R -X PUT -d a=b $S/config/img/devices/250/131_hmip-wrc6.png
}
if curl -sk --max-time 5 $R $S/config/img/devices/250/ | grep -qi 'index of'; then bad "the 250 px directory is listed"; else ok "the 250 px directory is not listed"; fi

echo "---- what the unprivileged lighttpd touched"
# the sandboxed unit lets lighttpd write its runtime directory and the upload directories, nothing
# else: here the user, running with root's file system view, must not have created a file anywhere
# else either, and its error log must show no write the system refused
stray=$(find / -path /proc -prune -o -path /sys -prune -o -path /run/lighttpd -prune -o -path /usr/local/tmp -prune -o -path /dev/shm -prune -o \
  -user "$WWW" -newer /tmp/www-marker ! -path /var/log/lighttpd-error.log -print 2>/dev/null)
if [ -z "$stray" ]; then ok "lighttpd created nothing outside /run/lighttpd, /usr/local/tmp and /dev/shm"; else bad "lighttpd created files elsewhere:"; echo "$stray"; fi
if grep -Ei 'permission denied|read-only file system|operation not permitted' /var/log/lighttpd-error.log; then bad "the error log shows a refused operation (above)"; else ok "the error log shows no refused operation"; fi
if [ -s /tmp/prepare.log ]; then echo "info  the preparation's output:"; cat /tmp/prepare.log; fi

echo "$CHECKS checks, $FAILS failed"
[ "$FAILS" -eq 0 ]
INNER
