#!/bin/sh
# openccu-lite: lite-chrony's generated configuration (B-242) - the user's servers, the DHCP ones,
# noDHCPNTP, the gateway fallback, the template's servers only when all of those are empty, and
# the old ntp.homematic.com default replaced by the template.
#
# Usage: sh scripts/testcases/lite-chrony-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-chrony"
TEMPLATE="$HERE/buildroot-external/overlay/base/etc/config_templates/ntpclient"
[ -f "$TOOL" ] || { echo "lite-chrony not found under $HERE"; exit 2; }
[ -f "$TEMPLATE" ] || { echo "the ntpclient template not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

mkdir -p "$T/templates" "$T/config"
cp "$TEMPLATE" "$T/templates/ntpclient"
printf 'driftfile /var/lib/chrony/drift\nmakestep 1.0 3\n' > "$T/chrony.conf"
# an ip that prints the route table in $FAKE_ROUTES
cat > "$T/ip" <<'EOS'
#!/bin/sh
[ "$1" = route ] && cat "$FAKE_ROUTES"
EOS
chmod +x "$T/ip"
export LITE_CHRONY_TEMPLATES="$T/templates" LITE_CHRONY_CONFIG="$T/config" LITE_CHRONY_BASE="$T/chrony.conf" \
  LITE_CHRONY_DHCP="$T/ntp-dhcp.conf" LITE_CHRONY_IP="$T/ip" FAKE_ROUTES="$T/routes"
GW='default via 192.0.2.1 dev eth0 proto dhcp src 192.0.2.10 metric 1024
192.0.2.0/24 dev eth0 proto kernel scope link src 192.0.2.10'

# reset: no user file, no DHCP servers, no noDHCPNTP, a gateway
reset() {
  rm -f "$T/config/ntpclient" "$T/config/noDHCPNTP" "$T/ntp-dhcp.conf"
  echo "$GW" > "$T/routes"
}
# servers <description> <expected server names...>: the generated list, in this order, nothing else
servers() {
  what=$1; shift
  out=$(sh "$TOOL" config); rc=$?
  got=$(echo "$out" | sed -n 's/^server \([^ ]*\) iburst$/\1/p' | tr '\n' ' ' | sed 's/ $//')
  want=$*
  if [ $rc = 0 ] && [ "$got" = "$want" ] && [ "$(echo "$out" | grep -c '^server ')" = "$#" ]; then
    ok "$what: $want"
  else
    bad "$what: rc $rc, want '$want', got '$got'"
  fi
  case "$out" in *"makestep 1.0 3"*) ;; *) bad "$what: /etc/chrony.conf not in front" ;; esac
}
# the template's servers, split into arguments on purpose where $POOL stands unquoted
POOL="0.de.pool.ntp.org 1.de.pool.ntp.org 2.de.pool.ntp.org 3.de.pool.ntp.org"

# the user's servers replace the pool
reset
echo "NTPSERVERS='ntp.example.org 198.51.100.7'" > "$T/config/ntpclient"
servers "user servers" ntp.example.org 198.51.100.7
case "$(sh "$TOOL" config)" in *pool.ntp.org*) bad "user servers: the pool is still asked" ;; *) ok "user servers: no pool server" ;; esac

# the DHCP servers in front of the user's, a doubled one written once
reset
echo "NTPSERVERS='ntp.example.org'" > "$T/config/ntpclient"
echo "NTPSERVERS_DHCP='198.51.100.1 ntp.example.org'" > "$T/ntp-dhcp.conf"
servers "DHCP and user servers" 198.51.100.1 ntp.example.org

# DHCP servers alone (the user's list empty): no gateway, no pool
reset
echo "NTPSERVERS=''" > "$T/config/ntpclient"
echo "NTPSERVERS_DHCP='198.51.100.1'" > "$T/ntp-dhcp.conf"
servers "DHCP servers only" 198.51.100.1

# noDHCPNTP: the DHCP servers are ignored
reset
echo "NTPSERVERS='ntp.example.org'" > "$T/config/ntpclient"
echo "NTPSERVERS_DHCP='198.51.100.1'" > "$T/ntp-dhcp.conf"
: > "$T/config/noDHCPNTP"
servers "noDHCPNTP" ntp.example.org

# noDHCPNTP and an empty user list: the gateway
reset
echo "NTPSERVERS=''" > "$T/config/ntpclient"
echo "NTPSERVERS_DHCP='198.51.100.1'" > "$T/ntp-dhcp.conf"
: > "$T/config/noDHCPNTP"
servers "noDHCPNTP, empty list: the gateway" 192.0.2.1

# an empty list and no DHCP servers: the gateway, not the pool
reset
echo "NTPSERVERS=''" > "$T/config/ntpclient"
servers "gateway fallback" 192.0.2.1

# empty everything, no gateway: the template's servers
reset
echo "NTPSERVERS=''" > "$T/config/ntpclient"
: > "$T/routes"
# shellcheck disable=SC2086
servers "empty: the pool" $POOL

# no ntpclient at all: the template is copied in and is the user's list
reset
# shellcheck disable=SC2086
servers "no ntpclient: the template's" $POOL
[ -f "$T/config/ntpclient" ] && ok "no ntpclient: the template copied" || bad "no ntpclient: not copied"

# the old default ntp.homematic.com is replaced by the template
reset
echo "NTPSERVERS=ntp.homematic.com" > "$T/config/ntpclient"
# shellcheck disable=SC2086
servers "ntp.homematic.com replaced" $POOL
grep -q pool.ntp.org "$T/config/ntpclient" && ok "ntp.homematic.com: the file rewritten" || bad "ntp.homematic.com: file kept"

if [ "$fails" -eq 0 ]; then echo "lite-chrony-test: all passed"; exit 0; fi
echo "lite-chrony-test: $fails failed"; exit 1
