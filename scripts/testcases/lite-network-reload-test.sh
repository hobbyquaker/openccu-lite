#!/bin/sh
# openccu-lite: occu-network.service's reload renews the DHCP lease under the current host name,
# against stand-ins (no network, no root):
#   - a DHCP setup with a running client: the client is stopped, a new one started with the new
#     host name and eQ3StartNetwork's arguments, the pid file renewed;
#   - a static setup: nothing runs, exit 0;
#   - no HOSTNAME: nothing runs, a warning, exit 0;
#   - a stale pid file (no process): the client is started all the same;
#   - a client that fails to start: exit 1 with an error line;
#   - the unit carries the ExecReload;
#   - the DHCP vendor class (option 60) is openccu-lite's own, from /etc/dhcp-vendor-class, which
#     eQ3StartNetwork and checkDHCP read too (B-243).
#
# Usage: sh scripts/testcases/lite-network-reload-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-network-reload"
UNIT="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/occu-network.service"
VENDOR="$HERE/buildroot-external/overlay/lite/etc/dhcp-vendor-class"
BASE="$HERE/buildroot-external/overlay/base"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

sh -n "$SCRIPT" && ok "lite-network-reload parses" || bad "lite-network-reload does not parse"
[ -x "$SCRIPT" ] && ok "lite-network-reload is executable" || bad "lite-network-reload is not executable"
grep -q '^ExecReload=/usr/libexec/occu/lite-network-reload$' "$UNIT" && ok "occu-network.service reloads with it" || bad "no ExecReload in occu-network.service"

# the vendor class: lite's file names openccu-lite, the upstream senders read it (their default stays a CCU3's)
grep -qx 'DHCP_VENDOR_ID=openccu-lite' "$VENDOR" && ok "dhcp-vendor-class: openccu-lite" || bad "dhcp-vendor-class does not set DHCP_VENDOR_ID=openccu-lite"
for f in etc/network/if-up.d/eQ3StartNetwork bin/checkDHCP; do
  if grep -q '\. /etc/dhcp-vendor-class' "$BASE/$f" && grep -q -- '-V "${DHCP_VENDOR_ID}"' "$BASE/$f" && ! grep -q -- '-V eQ3-CCU3' "$BASE/$f"; then
    ok "$f sends the vendor class from dhcp-vendor-class"
  else
    bad "$f does not take the vendor class from /etc/dhcp-vendor-class"
  fi
done

mkdir -p "$T/run" "$T/bin"
cat > "$T/bin/udhcpc" <<'STUB'
#!/bin/sh
echo "$*" >> "$UDHCPC_LOG"
[ -n "${UDHCPC_FAIL:-}" ] && exit 1
# -p <pidfile> is the last pair: write a pid as the daemon would
while [ $# -gt 0 ]; do [ "$1" = -p ] && printf '4242\n' > "$2"; shift; done
exit 0
STUB
chmod 755 "$T/bin/udhcpc"
run() { OCCU_DHCP_VENDOR_FILE="${VENDOR_FILE:-$VENDOR}" OCCU_NETCONFIG="$T/netconfig" OCCU_RUNDIR="$T/run" OCCU_UDHCPC="$T/bin/udhcpc" OCCU_DHCP_SCRIPT=/bin/dhcp.script UDHCPC_LOG="$T/udhcpc.log" sh "$SCRIPT" > "$T/out" 2>&1; echo $?; }

# a DHCP setup with a running client: a sleeping process stands in for udhcpc
printf 'HOSTNAME=attic\nMODE=DHCP\n' > "$T/netconfig"
sleep 300 & spid=$!
echo "$spid" > "$T/run/udhcpc_eth0.pid"
: > "$T/udhcpc.log"
rc=$(run)
if [ "$rc" = 0 ] && ! kill -0 "$spid" 2>/dev/null && grep -q -- '-b -t 20 -T 3 -S -x hostname:attic -i eth0 -F attic -V openccu-lite -s /bin/dhcp.script -p '"$T"'/run/udhcpc_eth0.pid' "$T/udhcpc.log" && [ "$(cat "$T/run/udhcpc_eth0.pid")" = 4242 ] && grep -q 'eth0: DHCP client restarted as attic' "$T/out"; then
  ok "DHCP: the client stopped and started again as attic ($(cat "$T/out"))"
else
  bad "DHCP: rc $rc, out '$(cat "$T/out")', log '$(cat "$T/udhcpc.log")', pid '$(cat "$T/run/udhcpc_eth0.pid" 2>&1)'"
fi
kill "$spid" 2>/dev/null

# a stale pid file: the client starts all the same
echo 999999 > "$T/run/udhcpc_eth0.pid"; : > "$T/udhcpc.log"
rc=$(run)
[ "$rc" = 0 ] && grep -q 'hostname:attic' "$T/udhcpc.log" && ok "a stale pid file: started anyway" || bad "stale pid: rc $rc, $(cat "$T/out")"

# another vendor class in the file: the client sends that one
printf 'DHCP_VENDOR_ID=example-class\n' > "$T/vendor"; echo 999999 > "$T/run/udhcpc_eth0.pid"; : > "$T/udhcpc.log"
rc=$(VENDOR_FILE="$T/vendor" run)
[ "$rc" = 0 ] && grep -q -- '-V example-class -s' "$T/udhcpc.log" && ok "the vendor class comes from the file" || bad "vendor file: rc $rc, log '$(cat "$T/udhcpc.log")'"

# no vendor file: openccu-lite all the same
echo 999999 > "$T/run/udhcpc_eth0.pid"; : > "$T/udhcpc.log"
rc=$(VENDOR_FILE="$T/none" run)
[ "$rc" = 0 ] && grep -q -- '-V openccu-lite -s' "$T/udhcpc.log" && ok "no vendor file: openccu-lite" || bad "no vendor file: rc $rc, log '$(cat "$T/udhcpc.log")'"

# a static setup: nothing runs
printf 'HOSTNAME=attic\nMODE=MANUAL\n' > "$T/netconfig"; : > "$T/udhcpc.log"
rc=$(run)
[ "$rc" = 0 ] && [ ! -s "$T/udhcpc.log" ] && grep -q 'static setup' "$T/out" && ok "static: nothing to tell ($(cat "$T/out"))" || bad "static: rc $rc, $(cat "$T/out"), log '$(cat "$T/udhcpc.log")'"

# no host name: a warning, nothing runs
printf 'MODE=DHCP\n' > "$T/netconfig"; : > "$T/udhcpc.log"
rc=$(run)
[ "$rc" = 0 ] && [ ! -s "$T/udhcpc.log" ] && grep -q '^<4>no HOSTNAME' "$T/out" && ok "no HOSTNAME: a warning, nothing run" || bad "no HOSTNAME: rc $rc, $(cat "$T/out")"

# the client fails to start: exit 1 with an error line
printf 'HOSTNAME=attic\nMODE=DHCP\n' > "$T/netconfig"; echo 999999 > "$T/run/udhcpc_eth0.pid"; : > "$T/udhcpc.log"
rc=$(UDHCPC_FAIL=1 OCCU_NETCONFIG="$T/netconfig" OCCU_RUNDIR="$T/run" OCCU_UDHCPC="$T/bin/udhcpc" UDHCPC_LOG="$T/udhcpc.log" sh "$SCRIPT" > "$T/out" 2>&1; echo $?)
[ "$rc" = 1 ] && grep -q '^<3>eth0: the DHCP client could not be started' "$T/out" && ok "a failing client: exit 1, an error line" || bad "failing client: rc $rc, $(cat "$T/out")"

# no client at all on a DHCP setup: a warning, exit 0
rm -f "$T"/run/udhcpc_*.pid; : > "$T/udhcpc.log"
rc=$(run)
[ "$rc" = 0 ] && grep -q '^<4>no DHCP client running' "$T/out" && ok "no client: a warning, exit 0" || bad "no client: rc $rc, $(cat "$T/out")"

if [ "$fails" = 0 ]; then echo "lite network reload: all cases passed"; exit 0; fi
echo "lite network reload: $fails case(s) failed"; exit 1
