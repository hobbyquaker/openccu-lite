#!/bin/sh
# openccu-lite: the addons' web ingress sockets (task 406) - the fork's side of a facility occulited
# renders: an addon whose manifest declares runtime.web_ingress gets a lighttpd Unix socket speaking
# the PROXY protocol, /run/lighttpd-addons/<id>/proxy.sock, whose $SERVER["socket"] block occulited
# writes into the drop-in directory as occulite-ingress-<id>.conf. Checked here against the files as
# they are:
#   - the lite modules.conf loads mod_extforward after mod_openssl (lighttpd's rule for hap-PROXY) and
#     sets no extforward directive itself; no lite or base lighttpd file does - the blocks are
#     occulited's, and none is hard-coded for an addon;
#   - occulite-session-header.lua removes a client-sent X-Occulite-Ingress, the header those blocks set;
#   - lite-lighttpd-addon-socket, the safety net in lighttpd-prepare.service, makes the directory of
#     every fragment it finds - www-data's with the addon's group when the group exists, www-data's own
#     when not, 0750 - and nothing for a name without a fragment; run on a scratch tree with chown/chmod
#     stubs on the PATH (nothing needs root);
#   - the tmpfiles entry for the base, lighttpd.service's ReadWritePaths, the step in
#     lighttpd-prepare.service.
# The socket on a real lighttpd is scripts/lite-lighttpd-redirect-test.sh's last section (docker).
#
# Usage: sh scripts/testcases/lite-lighttpd-addon-socket-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
L="$HERE/buildroot-external/overlay/lite"
MODULES="$L/etc/lighttpd/modules.conf"
LUA="$L/etc/lighttpd/occulite-session-header.lua"
HELPER="$L/usr/libexec/occu/lite-lighttpd-addon-socket"
TMPF="$L/usr/lib/tmpfiles.d/lite-lighttpd-addons.conf"
UNIT="$L/usr/lib/systemd/system/lighttpd.service"
PREP="$L/usr/lib/systemd/system/lighttpd-prepare.service"
for f in "$MODULES" "$LUA" "$HELPER" "$TMPF" "$UNIT" "$PREP"; do
  [ -f "$f" ] || { echo "not found: $f"; exit 2; }
done
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

echo "---- modules.conf and the lighttpd tree"
mods=$(grep -v '^[[:space:]]*#' "$MODULES")
printf '%s\n' "$mods" | grep -q '"mod_extforward"' && ok "mod_extforward is loaded" || bad "the lite modules.conf must load mod_extforward"
order=$(printf '%s\n' "$mods" | grep -n '"mod_openssl"\|"mod_extforward"' | sed 's/:.*"\(mod_[a-z]*\)".*/ \1/' | sort -n | awk '{print $2}' | tr '\n' ' ')
[ "$order" = "mod_openssl mod_extforward " ] && ok "mod_extforward comes after mod_openssl" || bad "server.modules must name mod_openssl before mod_extforward (is: $order)"
others=$(grep -rl 'extforward\.\|hap-PROXY' "$HERE/buildroot-external/overlay/base/etc/lighttpd" "$HERE/buildroot-external/overlay/lite/etc/lighttpd" 2>/dev/null | grep -v "/modules.conf$")
[ -z "$others" ] && ok "no lighttpd file of the fork sets an extforward directive (the blocks are occulited's)" || bad "extforward appears in: $others"
printf '%s\n' "$mods" | grep -q 'extforward\.' && bad "modules.conf sets an extforward directive at global scope" || ok "modules.conf sets no extforward directive"
[ -f "$L/etc/lighttpd/conf.d/wireguard-socket.conf" ] && bad "a hard-coded socket block for one addon is still there" || ok "no hard-coded socket block for one addon"
grep -q 'X_OCCULITE_INGRESS = true' "$LUA" && ok "the global script removes a client-sent X-Occulite-Ingress" || bad "occulite-session-header.lua must list X_OCCULITE_INGRESS"
grep -q 'X_FORWARDED_FOR = true' "$LUA" && ok "and still X-Forwarded-For" || bad "occulite-session-header.lua lost X_FORWARDED_FOR"
grep -q 'lighttpd%-addons/(\[%w_.%-\]+)/proxy%.sock' "$LUA" && grep -q 'r.req_header\["X-Occulite-Ingress"\] = id' "$LUA" && ok "the global script sets X-Occulite-Ingress from the ingress socket's path" || bad "occulite-session-header.lua must set X-Occulite-Ingress from request.server-addr"

echo "---- lite-lighttpd-addon-socket on a scratch tree"
[ -x "$HELPER" ] && ok "the helper is executable" || bad "the helper is not executable"
sh -n "$HELPER" && ok "the helper parses" || bad "the helper does not parse"
grep -q '^BASE=/run/lighttpd-addons$' "$HELPER" && ok "the helper's base is /run/lighttpd-addons" || bad "the helper must set BASE=/run/lighttpd-addons on a line of its own"
grep -q '^FRAGMENTS=/etc/config/lighttpd$' "$HELPER" && ok "the helper reads the drop-in directory" || bad "the helper must set FRAGMENTS=/etc/config/lighttpd"
grep -q '^PREFIX=occulite-ingress-$' "$HELPER" && ok "the fragments are occulite-ingress-<id>.conf" || bad "the helper must set PREFIX=occulite-ingress-"
grep -q '^GROUP_FILE=/etc/group$' "$HELPER" && ok "the helper reads /etc/group" || bad "the helper must set GROUP_FILE=/etc/group on a line of its own"
grep -q '^WWW=www-data$' "$HELPER" && ok "the web server's user is www-data" || bad "the helper must set WWW=www-data"
if grep -q 'BASE:-\|GROUP_FILE:-\|FRAGMENTS:-\|PREFIX:-\|WWW:-' "$HELPER"; then bad "the helper's paths can be set from the environment (it runs as root)"; else ok "the helper's paths are fixed"; fi
H="$T/helper"
sed "s|^BASE=.*|BASE=$T/run/lighttpd-addons|; s|^GROUP_FILE=.*|GROUP_FILE=$T/group|; s|^FRAGMENTS=.*|FRAGMENTS=$T/lighttpd|" "$HELPER" >"$H"
mkdir -p "$T/bin" "$T/lighttpd"
printf '#!/bin/sh\necho "chown $*" >>"%s/calls"\nexit 0\n' "$T" >"$T/bin/chown"
printf '#!/bin/sh\necho "chmod $*" >>"%s/calls"\nexit 0\n' "$T" >"$T/bin/chmod"
chmod 755 "$T/bin/chown" "$T/bin/chmod"
run() { : >"$T/calls"; PATH="$T/bin:$PATH" sh "$H" "$@"; }
D="$T/run/lighttpd-addons"

printf 'root:x:0:\nwww-data:x:33:\naddon-nut:x:30007:\n' >"$T/group"
run; rc=$?
[ "$rc" = 0 ] && [ ! -s "$T/calls" ] && [ ! -d "$D/wireguard" ] && ok "no fragment: nothing made, exit 0" || bad "no fragment: exit $rc, calls '$(cat "$T/calls")'"
: >"$T/lighttpd/occulite-ingress-wireguard.conf"
: >"$T/lighttpd/nut.conf"
: >"$T/lighttpd/occulite-accesslog.conf"
run; rc=$?
[ "$rc" = 0 ] && ok "one fragment: exit 0" || bad "one fragment: exit $rc"
[ -d "$D/wireguard" ] && ok "the fragment's directory is made" || bad "no directory for the fragment"
[ "$(ls "$D")" = "wireguard" ] && ok "only the fragment's directory (not nut.conf's, not the access log's)" || bad "directories: $(ls "$D")"
grep -qx "chown www-data:www-data $D/wireguard" "$T/calls" && ok "without the group the directory is www-data's own" || bad "calls without the group: $(cat "$T/calls")"
grep -qx "chmod 0750 $D/wireguard" "$T/calls" && ok "mode 0750" || bad "no chmod 0750: $(cat "$T/calls")"

printf 'root:x:0:\nwww-data:x:33:\naddon-wireguard:x:30008:\n' >"$T/group"
run
grep -qx "chown www-data:addon-wireguard $D/wireguard" "$T/calls" && ok "with the group the directory is www-data:addon-wireguard" || bad "calls with the group: $(cat "$T/calls")"
run wireguard
grep -qx "chown www-data:addon-wireguard $D/wireguard" "$T/calls" && ok "the id as an argument" || bad "argument wireguard: $(cat "$T/calls")"
run nut; rc=$?
[ "$rc" = 0 ] && [ ! -s "$T/calls" ] && [ ! -d "$D/nut" ] && ok "an id without a fragment: nothing made, exit 0" || bad "id nut: exit $rc, calls '$(cat "$T/calls")', dir $(ls "$D")"
run "../../etc"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$T/calls" ] && ok "a path as the id: nothing made" || bad "a path as the id: exit $rc, calls '$(cat "$T/calls")'"
: >"$T/lighttpd/occulite-ingress-tailscale.conf"
printf 'root:x:0:\nwww-data:x:33:\naddon-wireguard:x:30008:\naddon-wireguardx:x:30009:\n' >"$T/group"
run
grep -qx "chown www-data:addon-wireguard $D/wireguard" "$T/calls" && grep -qx "chown www-data:www-data $D/tailscale" "$T/calls" && ok "two fragments: each its own group, addon-wireguardx is not wireguard's" || bad "two fragments: $(cat "$T/calls")"
rm -f "$T/group"
run; rc=$?
[ "$rc" = 0 ] && grep -qx "chown www-data:www-data $D/wireguard" "$T/calls" && ok "no group file: www-data's own, exit 0" || bad "no group file: exit $rc, $(cat "$T/calls")"
printf '#!/bin/sh\nexit 1\n' >"$T/bin/chown"
err=$(PATH="$T/bin:$PATH" sh "$H" 2>&1 >/dev/null); rc=$?
[ "$rc" = 0 ] && echo "$err" | grep -q 'cannot give' && ok "a refused chown: said on stderr, exit 0" || bad "refused chown: exit $rc, '$err'"

echo "---- the tmpfiles entry and the units"
grep -v '^#' "$TMPF" | grep -qx 'd /run/lighttpd-addons 0755 root root -' && ok "tmpfiles makes /run/lighttpd-addons root 0755" || bad "$TMPF must hold: d /run/lighttpd-addons 0755 root root -"
if grep -v '^#' "$TMPF" | grep -q '/run/lighttpd-addons/'; then bad "tmpfiles names an addon's directory (they are occulited's to make)"; else ok "tmpfiles makes no addon's directory"; fi
grep -qx 'ReadWritePaths=-/run/lighttpd-addons' "$UNIT" && ok "lighttpd.service may write /run/lighttpd-addons" || bad "lighttpd.service must carry ReadWritePaths=-/run/lighttpd-addons"
grep -qx 'RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6' "$UNIT" && ok "lighttpd.service allows AF_UNIX" || bad "lighttpd.service must allow AF_UNIX"
grep -qx 'ExecStart=-/usr/libexec/occu/lite-lighttpd-addon-socket' "$PREP" && ok "lighttpd-prepare runs the helper" || bad "lighttpd-prepare.service must run ExecStart=-/usr/libexec/occu/lite-lighttpd-addon-socket"
# after occulited's render, so the fragments exist when the helper looks
dropins=$(grep -n '^ExecStart=-/usr/bin/occulited -lighttpd-dropins' "$PREP" | cut -d: -f1)
helper=$(grep -n '^ExecStart=-/usr/libexec/occu/lite-lighttpd-addon-socket' "$PREP" | cut -d: -f1)
[ -n "$dropins" ] && [ -n "$helper" ] && [ "$helper" -gt "$dropins" ] && ok "the helper runs after occulited rendered the fragments" || bad "lite-lighttpd-addon-socket must come after occulited -lighttpd-dropins in lighttpd-prepare.service"

[ "$fails" = 0 ] && echo "lite-lighttpd-addon-socket: all cases passed" || { echo "lite-lighttpd-addon-socket: $fails case(s) failed"; exit 1; }
