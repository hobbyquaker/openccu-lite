#!/bin/sh
# openccu-lite (B-261): S50lighttpd's check_certificate on a system without an address. Its
# self-signed certificate named "IP:<address>" unconditionally; at a start without an IPv4 route
# (no lease yet: a DHCP server that is late or absent, a container without one) the address is
# empty, openssl refuses "IP:" and writes nothing, and the web server does not start until a
# lease arrives and its restarts bring it back. Now the address goes into the subjectAltName only
# when there is one, and the one certificate that was made without it is made again once an
# address exists - one repair; a certificate that names an address, even an old one, and a user's
# own certificate are left as they are.
#
# The three certificate functions are taken from the script as it is (awk, between their names
# and the closing brace), /etc/config and /var/board_serial are pointed into a scratch tree, and
# ip and hostname are stubs on the PATH; the real openssl makes and reads the certificates. bash
# runs them (the script uses process substitution, as busybox ash does on the system).
#
# Usage: sh scripts/testcases/lite-lighttpd-cert-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S="$HERE/buildroot-external/overlay/base/etc/init.d/S50lighttpd"
[ -f "$S" ] || { echo "S50lighttpd not found at $S"; exit 2; }
command -v openssl >/dev/null 2>&1 || { echo "openssl is not installed"; exit 2; }
command -v bash >/dev/null 2>&1 || { echo "bash is not installed"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

mkdir -p "$T/etc/config" "$T/var" "$T/bin"
echo LITE0TEST01 >"$T/var/board_serial"
PEM="$T/etc/config/server.pem"

# the functions, their absolute paths moved into the scratch tree
awk '/^(create_certificate|certificate_without_address|check_certificate)\(\) \{$/ {p=1} p {print} p && /^\}$/ {p=0}' "$S" \
  | sed "s|/etc/config/|$T/etc/config/|g; s|/var/board_serial|$T/var/board_serial|g; s|/usr/bin/openssl|openssl|g" >"$T/functions.sh"
grep -q '^check_certificate() {$' "$T/functions.sh" && grep -q '^create_certificate() {$' "$T/functions.sh" \
  && grep -q '^certificate_without_address() {$' "$T/functions.sh" \
  && ok "the three functions found in S50lighttpd" || { bad "the certificate functions were not found in S50lighttpd"; echo "failures: $fails"; exit 1; }

# the stubs: ip prints busybox's line (two spaces before src, the address is field 8) when
# LITE_TEST_IP is set, and fails as on a system without a route otherwise
cat >"$T/bin/ip" <<'EOS'
#!/bin/sh
if [ -n "${LITE_TEST_IP:-}" ]; then echo "1.0.0.0 via 192.0.2.1 dev eth0  src ${LITE_TEST_IP} "; else echo "RTNETLINK answers: Network is unreachable" >&2; exit 2; fi
EOS
printf '#!/bin/sh\necho ccu-test\n' >"$T/bin/hostname"
chmod +x "$T/bin/ip" "$T/bin/hostname"

# run check_certificate with or without an address; its output goes to the log
run() { # [address]
  LITE_TEST_IP="${1:-}" PATH="$T/bin:$PATH" bash -c ". '$T/functions.sh'; check_certificate" >"$T/run.log" 2>&1
}
san() { openssl x509 -noout -ext subjectAltName -in "$PEM" 2>/dev/null | tail -n +2 | tr -d ' \n'; }
fp() { openssl x509 -noout -fingerprint -sha256 -in "$PEM" 2>/dev/null; }
asides() { n=0; for f in "$T"/etc/config/server.pem_*; do [ -e "$f" ] && n=$((n+1)); done; echo $n; }

# ---- 1. no route, no certificate: made with the host name alone
run
[ -s "$PEM" ] && ok "without a route a certificate is written" || bad "without a route no certificate was written: $(cat "$T/run.log")"
openssl x509 -noout -in "$PEM" 2>/dev/null && ok "and openssl reads it" || bad "the file is not a certificate"
[ "$(san)" = "DNS:ccu-test" ] && ok "its subjectAltName is the host name alone ($(san))" || bad "subjectAltName without a route: $(san), want DNS:ccu-test"
grep -q 'RTNETLINK' "$T/run.log" && bad "the route lookup's error is printed: $(cat "$T/run.log")" || ok "the route lookup without a route is quiet"
grep -q 'creating new SSL cert' "$T/run.log" && ok "the script said it made one" || bad "no 'creating new SSL cert' line: $(cat "$T/run.log")"
openssl x509 -noout -issuer -nameopt RFC2253 -in "$PEM" | grep -q ',O=HomeMatic,C=DE$' && ok "the issuer is the script's own" || bad "issuer: $(openssl x509 -noout -issuer -nameopt RFC2253 -in "$PEM")"
F1=$(fp)

# ---- 2. the same certificate, a route now: made again with the address, once
run 192.0.2.10
[ "$(san)" = "DNS:ccu-test,IPAddress:192.0.2.10" ] && ok "with an address the certificate is made again and names it ($(san))" || bad "subjectAltName after the repair: $(san), want DNS:ccu-test,IPAddress:192.0.2.10"
[ "$(fp)" != "$F1" ] && ok "a new certificate (the fingerprint changed)" || bad "the fingerprint did not change"
[ "$(asides)" = 1 ] && ok "the one without the address is kept aside" || bad "$(asides) server.pem_* files after the repair, want 1"
F2=$(fp)

# ---- 3. a route and a certificate that names an address: untouched
run 192.0.2.10
[ "$(fp)" = "$F2" ] && ok "a certificate that names the address stays (same fingerprint)" || bad "the certificate was made again although it names the address"
grep -q 'creating new SSL cert' "$T/run.log" && bad "the script made one anyway: $(cat "$T/run.log")" || ok "and the script is quiet"
run 192.0.2.99
[ "$(fp)" = "$F2" ] && ok "a certificate that names an old address stays too (no repair after an address change)" || bad "the certificate was made again after an address change"

# ---- 4. no route and a certificate that names an address: untouched as well (nothing to repair with)
run
[ "$(fp)" = "$F2" ] && ok "without a route a valid certificate stays" || bad "without a route the certificate was made again"

# ---- 5. a user's own certificate without the markers (a system upgraded with its certificate),
# DNS only: not the script's issuer, so never made again
openssl req -new -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 30 \
  -keyout "$T/user.key" -out "$T/user.crt" -subj "/C=DE/O=Example/CN=ccu.example.org" \
  -addext "subjectAltName=DNS:ccu.example.org,DNS:ccu" >/dev/null 2>&1
cat "$T/user.key" "$T/user.crt" >"$PEM"
FU=$(fp)
run 192.0.2.10
[ "$(fp)" = "$FU" ] && ok "a user's own DNS-only certificate is left alone" || bad "a user's own certificate was replaced"

# ---- 6. the markers: occulited's certificate is never touched, address or not
openssl req -new -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 30 \
  -keyout "$T/m.key" -out "$T/m.crt" -subj "/C=DE/O=HomeMatic/OU=X/CN=ccu-test" \
  -addext "subjectAltName=DNS:ccu-test" >/dev/null 2>&1
cat "$T/m.key" "$T/m.crt" >"$PEM"
: >"$PEM.managed"
FM=$(fp)
run 192.0.2.10
[ "$(fp)" = "$FM" ] && ok "a managed certificate without an address is not repaired" || bad "a managed certificate was replaced"
rm -f "$PEM.managed"

# ---- 7. a certificate that expires within a day (the old path), without a route: made again, DNS only
openssl req -new -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 1 \
  -keyout "$T/e.key" -out "$T/e.crt" -subj "/C=DE/O=HomeMatic/OU=X/CN=ccu-test" \
  -addext "subjectAltName=DNS:ccu-test,IP:192.0.2.10" >/dev/null 2>&1
cat "$T/e.key" "$T/e.crt" >"$PEM"
FE=$(fp)
run
[ "$(fp)" != "$FE" ] && [ "$(san)" = "DNS:ccu-test" ] && ok "an expiring certificate is made again without a route, host name alone ($(san))" || bad "expiring certificate without a route: $(san), fingerprint changed: $([ "$(fp)" != "$FE" ] && echo yes || echo no)"

# ---- 8. the script itself: the SAN is built from what exists, nothing hides openssl's complaint
grep -q 'DNS:\$(hostname),IP:' "$S" && bad "S50lighttpd still names IP:\${IP} unconditionally" || ok "S50lighttpd no longer names an empty IP:"
grep -q '^\s*\[\[ -n "\${IP}" \]\] && SAN=' "$S" && ok "the address is added to the SAN only when there is one" || bad "no conditional SAN line in S50lighttpd"
awk '/^create_certificate\(\) \{$/ {p=1} p && /openssl req/ {q=1} q && /-subj/ {print; exit}' "$S" | grep -q '2>/dev/null' \
  && bad "openssl req's stderr is still hidden" || ok "openssl req's complaint would reach the console and the journal"
grep -q 'route get 1 2>/dev/null' "$S" && ok "the route lookup's own complaint is hidden instead" || bad "ip route get prints its error on every start without a route"

echo "failures: $fails"
[ "$fails" = 0 ]
