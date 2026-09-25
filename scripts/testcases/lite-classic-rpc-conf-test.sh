#!/bin/sh
# openccu-lite: the classic RPC sockets lite-classic-rpc-conf writes for S50lighttpd (task 143).
#
# On a fake tree (LITE_ROOT): both switches off writes no socket; plain alone the three plain
# sockets, TLS alone the three TLS ones, each for IPv4 and [::] and with its backend on the
# loopback; 2000/42000 only with hs485d's marker; the pair adds basic auth (realm theRealm, the
# htpasswd file, loopback exempt) to every socket and an empty file adds none; every socket runs
# the session-header strip and the not-ready Lua in front of its backend, and the output is the
# same before and after startupFinished (the Lua decides per request, so the end of the boot needs
# no reload); no ReGa socket (1999, 8181, 41999, 48181) in any output; S50lighttpd calls the
# script on lite.
#
# Usage: sh scripts/testcases/lite-classic-rpc-conf-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-classic-rpc-conf"
S50="$HERE/buildroot-external/overlay/base/etc/init.d/S50lighttpd"
[ -x "$SCRIPT" ] || { echo "lite-classic-rpc-conf not found (or not executable) under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# gen <markers...>: a fresh tree with the named files, then the script; the output in $T/out
gen() {
  rm -rf "$T/r"; mkdir -p "$T/r/etc/config" "$T/r/var/etc" "$T/r/var/status" "$T/r/run/occulite/radio"
  for m in "$@"; do
    case "$m" in
      plain) : >"$T/r/etc/config/classicRpcPlain" ;;
      tls) : >"$T/r/etc/config/classicRpcTLS" ;;
      pair) echo 'ccu:$6$salt$hash' >"$T/r/etc/config/classic-rpc.htpasswd" ;;
      emptypair) : >"$T/r/etc/config/classic-rpc.htpasswd" ;;
      hs485d) : >"$T/r/run/occulite/radio/hs485d.enabled" ;;
      ready) : >"$T/r/var/status/startupFinished" ;;
    esac
  done
  LITE_ROOT="$T/r" sh "$SCRIPT" "$T/out"
}
sockets() { grep -c '^else \$SERVER\["socket"\]' "$T/out"; }
has() { grep -q -F -- "$1" "$T/out"; }
noreg() { ! grep -q -E ':(1999|8181|41999|48181)"' "$T/out"; }

gen ready
check "both off: no socket" '[ "$(sockets)" = 0 ]'

gen plain ready
check "plain: 3 ports x 2 sockets" '[ "$(sockets)" = 6 ]'
check "plain: 2001 -> 32001" 'has "== \":2001\" {" && has "\"port\" => 32001"'
check "plain: [::]:2010" 'has "== \"[::]:2010\" {"'
check "plain: 9292 -> 39292" 'has "== \":9292\" {" && has "\"port\" => 39292"'
check "plain: ssl off" '! has "ssl.engine = \"enable\""'
check "plain: no TLS port" '! has ":42001\""'
check "plain: no 2000 without hs485d" '! has ":2000\""'
check "plain: no auth without the pair" '! has "auth.require"'
check "plain: no ReGa socket" noreg

gen tls ready
check "tls: 3 ports x 2 sockets" '[ "$(sockets)" = 6 ]'
check "tls: 42010 with ssl on" 'has "== \":42010\" {" && has "ssl.engine = \"enable\"" && ! has "ssl.engine = \"disable\""'
check "tls: no plain port" '! has ":2001\""'

gen plain tls hs485d ready
check "both with hs485d: 4 + 4 ports x 2" '[ "$(sockets)" = 16 ]'
check "hs485d: 2000 and 42000 -> 32000" 'has ":2000\"" && has ":42000\"" && has "\"port\" => 32000"'
check "both: no ReGa socket" noreg

gen plain tls pair ready
check "pair: auth on every socket" '[ "$(grep -c "auth.require" "$T/out")" = 12 ]'
check "pair: htpasswd, basic, theRealm" 'has "auth.backend = \"htpasswd\"" && has "\"/etc/config/classic-rpc.htpasswd\"" && has "\"method\" => \"basic\", \"realm\" => \"theRealm\""'
check "pair: the loopback exempt" 'has "\$HTTP[\"remoteip\"] !~ \"^(127\\.0\\.0\\.1|::ffff:127\\.0\\.0\\.1|::1)\$\" {"'
check "pair: cached 600 s" 'has "auth.cache = ( \"max-age\" => \"600\" )"'

gen plain emptypair ready
check "an empty htpasswd file adds no auth" '! has "auth.require"'

gen plain tls pair hs485d ready
cp "$T/out" "$T/out.ready"
gen plain tls pair hs485d
check "the output does not depend on startupFinished" 'cmp -s "$T/out" "$T/out.ready"'
check "every socket: the Lua list in front of the backend" '[ "$(grep -c "magnet.attract-raw-url-to = ( \"/etc/lighttpd/occulite-session-header.lua\", \"/etc/lighttpd/classic-rpc-notready.lua\" )" "$T/out")" = 16 ] && [ "$(grep -c "proxy.server" "$T/out")" = 16 ]'

check "braces balance" '[ "$(gen plain tls pair hs485d ready; tr -cd "{" <"$T/out" | wc -c)" = "$(tr -cd "}" <"$T/out" | wc -c)" ]'
check "S50lighttpd calls the script" 'grep -q "/usr/libexec/occu/lite-classic-rpc-conf /var/etc/lighttpd_webui_remoteapi.conf" "$S50"'
check "S50lighttpd: start and reload both use remoteapi_conf" '[ "$(grep -c "^  remoteapi_conf$" "$S50")" = 2 ]'
check "the lite modules load mod_authn_file" 'grep -q "\"mod_authn_file\"" "$HERE/buildroot-external/overlay/lite/etc/lighttpd/modules.conf"'
check "the not-ready Lua answers 503 until startupFinished, then passes on" 'L="$HERE/buildroot-external/overlay/lite/etc/lighttpd/classic-rpc-notready.lua"; grep -q "^return 503" "$L" && grep -q "stat(\"/var/status/startupFinished\")" "$L" && grep -q "^    return 0" "$L"'

echo "failures: $fails"
[ "$fails" = 0 ]
