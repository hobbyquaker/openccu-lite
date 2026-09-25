#!/bin/sh
# openccu-lite: lite-dhcp6 (udhcpc6's script) against stand-ins for ip and resolvconf - it sets
# and notes the leased address, replaces it on a new lease, drops it and the nameservers on
# deconfig, and never runs an IPv4 command.
#
# Usage: sh scripts/testcases/lite-dhcp6-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-dhcp6"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }
printf '#!/bin/sh\necho "ip $*" >> %s/log\n' "$T" > "$T/ip"
printf '#!/bin/sh\necho "resolvconf $*" >> %s/log\nwhile read -r l; do echo "  $l" >> %s/log; done\n' "$T" "$T" > "$T/resolvconf"
chmod +x "$T/ip" "$T/resolvconf"
run() { : > "$T/log"; env -i PATH=/usr/bin:/bin IP="$T/ip" RESOLVCONF="$T/resolvconf" STATE_DIR="$T/state" interface=eth0 "$@" sh "$S" "$A" < /dev/null; }
want() { if [ "$(cat "$T/log")" = "$2" ]; then ok "$1"; else fail "$1"; echo "--- got"; cat "$T/log"; echo "--- want"; echo "$2"; fi; }

A=deconfig run
want "deconfig without a lease: only the nameserver record" "resolvconf -d eth0.dhcp6"
A=bound run ipv6=2001:db8::77 dns="2001:db8::53 2001:db8::54" search=lan
want "bound: the /128, noted; the nameservers" "ip -6 addr replace 2001:db8::77/128 dev eth0
resolvconf -a eth0.dhcp6
  search lan
  nameserver 2001:db8::53
  nameserver 2001:db8::54"
[ "$(cat "$T/state/dhcp6-eth0")" = "2001:db8::77/128" ] && ok "the address is noted" || fail "the address is not noted"
A=renew run ipv6=2001:db8::77
want "renew, the same address" "ip -6 addr replace 2001:db8::77/128 dev eth0"
A=renew run ipv6=2001:db8::78
want "renew, another address: the old one goes" "ip -6 addr del 2001:db8::77/128 dev eth0
ip -6 addr replace 2001:db8::78/128 dev eth0"
A=deconfig run
want "deconfig: the address and the record" "ip -6 addr del 2001:db8::78/128 dev eth0
resolvconf -d eth0.dhcp6"
[ -e "$T/state/dhcp6-eth0" ] && fail "the note stayed" || ok "the note is gone"
A=bound run ipv6=2001:db8::79
A=nak run
grep -q -- "-4\|inet \|flush" "$T/log" && fail "an IPv4 command or a flush" || ok "no IPv4 command, no flush"
want "nak: the address and the record" "ip -6 addr del 2001:db8::79/128 dev eth0
resolvconf -d eth0.dhcp6"
[ "$fails" -eq 0 ] && echo "all pass" || { echo "$fails FAILED"; exit 1; }
