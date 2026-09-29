#!/bin/sh
# openccu-lite: the addon unit generator (occu-addons) runs every addon through rc.d/<name>.
#
# With the addon-rc wrapper in front, rc.d/<name> is the wrapper and the addon's own script is
# rc.d/<name>.script. The unit must run the wrapper, which runs the script inside the unit with $0 set
# to rc.d/<name>; a unit that ran <name>.script directly handed the script the wrong name. A fake root
# with a wrapped and an unwrapped addon, the generator run against it; nothing needs root.
#
# Every run points the generator's journal line at a file (OCCU_ADDONS_KMSG), never at the host's
# /dev/kmsg.
#
# Usage: sh scripts/testcases/occu-addons-generator-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
GEN="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system-generators/occu-addons"
[ -f "$GEN" ] || { echo "generator not found at $GEN"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
R="$T/root"; E="$T/early"
mkdir -p "$R/usr/local/etc/config/rc.d" "$R/usr/local/addons" "$E"
RCD="$R/usr/local/etc/config/rc.d"
printf '#!/bin/sh\n# openccu-lite addon-rc wrapper (stand-in)\n' > "$RCD/wrapped"
printf '#!/bin/sh\necho wrapped script\n' > "$RCD/wrapped.script"
printf '#!/bin/sh\necho plain script\n' > "$RCD/plain"
chmod 755 "$RCD/wrapped" "$RCD/wrapped.script" "$RCD/plain"

OCCU_ADDONS_KMSG="$T/kmsg" OCCU_ADDONS_ROOT="$R" sh "$GEN" "$T/normal" "$E" "$T/late" > "$T/out" 2>&1
rc=$?
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
[ "$rc" = 0 ] && ok "the generator exits 0" || { bad "the generator exits $rc: $(cat "$T/out")"; }
[ -s "$T/kmsg" ] && bad "a journal line without an addon's own unit file: $(cat "$T/kmsg")" || ok "no journal line when no addon ships a unit file"

U="$E/addon-wrapped.service"
if [ -f "$U" ]; then ok "a unit for the wrapped addon"; else bad "no unit for the wrapped addon"; fi
grep -q "^ExecStart=/bin/sh -c '. /etc/profile; exec /usr/local/etc/config/rc.d/wrapped start'$" "$U" 2>/dev/null \
  && ok "the wrapped addon starts through rc.d/wrapped" || bad "ExecStart of the wrapped addon: $(grep ^ExecStart "$U" 2>/dev/null)"
grep -q "^ExecStop=/bin/sh -c '. /etc/profile; exec /usr/local/etc/config/rc.d/wrapped stop'$" "$U" 2>/dev/null \
  && ok "the wrapped addon stops through rc.d/wrapped" || bad "ExecStop of the wrapped addon: $(grep ^ExecStop "$U" 2>/dev/null)"
if grep -q '\.script' "$U" 2>/dev/null; then bad "the wrapped addon's unit names a .script: $(grep '\.script' "$U")"; else ok "no .script in the wrapped addon's unit"; fi

P="$E/addon-plain.service"
grep -q "^ExecStart=/bin/sh -c '. /etc/profile; exec /usr/local/etc/config/rc.d/plain start'$" "$P" 2>/dev/null \
  && ok "an addon without a wrapper starts through its own script" || bad "ExecStart of the plain addon: $(grep ^ExecStart "$P" 2>/dev/null)"

if [ -e "$E/addon-wrapped.script.service" ]; then bad "a .script got a unit of its own"; else ok "no unit for a .script"; fi
[ -L "$E/addons.target.wants/addon-wrapped.service" ] && [ -L "$E/addons.target.wants/addon-plain.service" ] \
  && ok "both units are wanted by addons.target" || bad "addons.target.wants: $(ls "$E/addons.target.wants" 2>/dev/null)"

# what an addon needs, from occulited's addon-policy/<name>.needs
A="$T/needs"; RA="$A/root"; EA="$A/early"
mkdir -p "$RA/usr/local/etc/config/rc.d" "$RA/usr/local/etc/config/addon-policy" "$RA/usr/local/addons/own/etc/systemd" "$EA"
for n in broker consumer junk later own; do
  printf '#!/bin/sh\n' > "$RA/usr/local/etc/config/rc.d/$n"; chmod 755 "$RA/usr/local/etc/config/rc.d/$n"
done
printf '[Unit]\nDescription=own\n' > "$RA/usr/local/addons/own/etc/systemd/own.service"
echo none > "$RA/usr/local/etc/config/addon-policy/broker.needs"
echo "rfd hmipserver" > "$RA/usr/local/etc/config/addon-policy/consumer.needs"
echo "rfd ReGaHSS" > "$RA/usr/local/etc/config/addon-policy/junk.needs"
echo hmipserver > "$RA/usr/local/etc/config/addon-policy/own.needs"
OCCU_ADDONS_KMSG="$A/kmsg" OCCU_ADDONS_ROOT="$RA" sh "$GEN" "$A/normal" "$EA" "$A/late" > "$A/out" 2>&1 || bad "the generator with needs files exits $?: $(cat "$A/out")"
aft() { sed -n 's/^After=//p' "$EA/$1" | tr ' ' '\n'; }
has() { aft "$1" | grep -qx "$2"; }
if has addon-broker.service rfd.service || has addon-broker.service hmipserver.service; then
  bad "an addon that needs nothing still waits for the interfaces: $(grep ^After "$EA/addon-broker.service")"
else ok "needs none: not after rfd or hmipserver"; fi
has addon-broker.service network.target && has addon-broker.service occu-addons.service \
  && ok "needs none: after the network and occu-addons" || bad "needs none: $(grep ^After "$EA/addon-broker.service")"
grep -q '^Wants=' "$EA/addon-broker.service" && bad "needs none: a Wants= line" || ok "needs none: no Wants="
has addon-consumer.service rfd.service && has addon-consumer.service hmipserver.service \
  && ok "declared interfaces: after rfd and hmipserver" || bad "declared: $(grep ^After "$EA/addon-consumer.service")"
grep -qx 'Wants=rfd.service hmipserver.service' "$EA/addon-consumer.service" \
  && ok "declared interfaces: wanted" || bad "declared Wants: $(grep ^Wants "$EA/addon-consumer.service")"
has addon-junk.service rfd.service && has addon-junk.service hmipserver.service && ! grep -q '^Wants=' "$EA/addon-junk.service" \
  && ok "an unknown id falls back to the safe default" || bad "unknown id: $(grep '^After\|^Wants' "$EA/addon-junk.service")"
has addon-later.service rfd.service && has addon-later.service hmipserver.service \
  && ok "no needs file: the safe default" || bad "no needs file: $(grep ^After "$EA/addon-later.service")"
# no order between addons: a slow or hanging start script holds back no other addon
chained=
for f in "$EA"/addon-*.service; do
  sed -n 's/^\(After\|Before\|Requires\|Wants\)=//p' "$f" | tr ' ' '\n' | grep -q '^addon-' && chained="$chained ${f##*/}"
done
[ -z "$chained" ] && ok "no addon unit is ordered against another addon" || bad "addon units ordered against other addons:$chained"
has addon-later.service addon-broker.service && bad "a consumer waits for an early addon" || ok "a consumer does not wait for an early addon"
has addon-broker.service network.target && has addon-broker.service lighttpd.service && has addon-broker.service occulited.service \
  && ok "needs none: after the network, lighttpd and occulited as before" || bad "needs none base order: $(grep ^After "$EA/addon-broker.service")"
has addon-later.service network.target && has addon-later.service lighttpd.service && has addon-later.service occulited.service && has addon-later.service occu-addons.service \
  && ok "undeclared: after the network, lighttpd, occulited and occu-addons as before" || bad "undeclared base order: $(grep ^After "$EA/addon-later.service")"
grep -q '^Before=addons.target$' "$EA/addon-later.service" && grep -q '^PartOf=addons.target$' "$EA/addon-later.service" \
  && ok "each addon still before and part of addons.target" || bad "addons.target: $(grep '^Before\|^PartOf' "$EA/addon-later.service")"
# an addon that ships a unit file gets the generated unit all the same, with its declared interfaces
if [ -f "$EA/addon-own.service" ] && [ ! -L "$EA/addon-own.service" ] && grep -q '^# generated by' "$EA/addon-own.service"; then
  ok "an addon that ships a unit file gets the generated unit"
else
  bad "addon-own.service is not the generated unit: $(ls -l "$EA/addon-own.service" 2>&1)"
fi
has addon-own.service hmipserver.service && grep -qx 'Wants=hmipserver.service' "$EA/addon-own.service" \
  && ok "that unit has the interfaces the entry declares" || bad "own: $(grep '^After\|^Wants' "$EA/addon-own.service")"
[ -e "$EA/addon-own.service.d/05-order.conf" ] && bad "an order drop-in for a shipped unit is still written" || ok "no order drop-in for a shipped unit"
empty=$(grep -c '^$' "$EA/addon-broker.service")
[ "$empty" -le 2 ] && ok "no stray blank lines in [Unit]" || bad "blank lines: $empty"

# task 119: an addon occulited lets start early (addon-policy/<name>.start = early) wants its
# interfaces but is not ordered after them
Y="$T/early-start"; RY="$Y/root"; EY="$Y/early"
mkdir -p "$RY/usr/local/etc/config/rc.d" "$RY/usr/local/etc/config/addon-policy" "$EY"
for n in eundeclared edeclared enone ewired ejunk eempty eblank late; do
  printf '#!/bin/sh\n' > "$RY/usr/local/etc/config/rc.d/$n"; chmod 755 "$RY/usr/local/etc/config/rc.d/$n"
done
PD="$RY/usr/local/etc/config/addon-policy"
for n in eundeclared edeclared enone ewired late; do echo early > "$PD/$n.start"; done
printf ' early \r\n' > "$PD/eblank.start"
echo late > "$PD/ejunk.start"
: > "$PD/eempty.start"
echo "rfd hmipserver" > "$PD/edeclared.needs"
echo none > "$PD/enone.needs"
echo hs485d > "$PD/ewired.needs"
echo "rfd hmipserver" > "$PD/ejunk.needs"
echo "rfd hmipserver" > "$PD/eempty.needs"
rm "$PD/late.start"   # switched off since: the file is gone
echo hmipserver > "$PD/late.needs"
OCCU_ADDONS_KMSG="$Y/kmsg" OCCU_ADDONS_ROOT="$RY" sh "$GEN" "$Y/normal" "$EY" "$Y/late" > "$Y/out" 2>&1 || bad "the generator with start files exits $?: $(cat "$Y/out")"
yaft() { sed -n 's/^After=//p' "$EY/$1" | tr ' ' '\n'; }
yhas() { yaft "$1" | grep -qx "$2"; }
base_only() {  # the unit is after exactly the base units
  [ "$(yaft "$1" | sort | tr '\n' ' ')" = "lighttpd.service network.target occu-addons.service occulited.service " ]
}
for n in eundeclared edeclared enone ewired eblank; do
  base_only "addon-$n.service" && ok "early $n: after the network, lighttpd, occulited and occu-addons only" \
    || bad "early $n: After=$(yaft "addon-$n.service" | tr '\n' ' ')"
done
grep -qx 'Wants=rfd.service hmipserver.service' "$EY/addon-eundeclared.service" \
  && ok "early, needs undeclared: wants rfd and hmipserver" || bad "early undeclared: $(grep ^Wants "$EY/addon-eundeclared.service")"
grep -qx 'Wants=rfd.service hmipserver.service' "$EY/addon-edeclared.service" \
  && ok "early, needs declared: wants the declared units" || bad "early declared: $(grep ^Wants "$EY/addon-edeclared.service")"
grep -qx 'Wants=hs485d.service' "$EY/addon-ewired.service" \
  && ok "early, needs hs485d: wants hs485d" || bad "early wired: $(grep ^Wants "$EY/addon-ewired.service")"
grep -q '^Wants=' "$EY/addon-enone.service" && bad "early, needs none: a Wants= line" || ok "early, needs none: no Wants="
grep -qx 'Wants=rfd.service hmipserver.service' "$EY/addon-eblank.service" \
  && ok "early with blanks and a CR around the word: still early" || bad "early blank: $(grep '^After\|^Wants' "$EY/addon-eblank.service")"
for n in ejunk eempty; do
  yhas "addon-$n.service" rfd.service && yhas "addon-$n.service" hmipserver.service \
    && ok "$n: a .start without \"early\" keeps the ordering after the needs" || bad "$n: After=$(yaft "addon-$n.service" | tr '\n' ' ')"
done
yhas addon-late.service hmipserver.service && grep -qx 'Wants=hmipserver.service' "$EY/addon-late.service" \
  && ok "no .start (switched off): after its needs as before" || bad "switched off: $(grep '^After\|^Wants' "$EY/addon-late.service")"
for n in eundeclared edeclared enone; do
  grep -q '^Before=addons.target$' "$EY/addon-$n.service" && grep -q '^PartOf=addons.target$' "$EY/addon-$n.service" \
    && ok "early $n: still before and part of addons.target" || bad "early $n addons.target: $(grep '^Before\|^PartOf' "$EY/addon-$n.service")"
done
ychained=
for f in "$EY"/addon-*.service; do
  sed -n 's/^\(After\|Before\|Requires\|Wants\)=//p' "$f" | tr ' ' '\n' | grep -q '^addon-' && ychained="$ychained ${f##*/}"
done
[ -z "$ychained" ] && ok "early: no addon unit is ordered against another addon" || bad "early: chained:$ychained"
if grep -rqs '^Requires=\|^BindsTo=\|^Requisite=' "$EY"; then bad "early: a hard dependency on an interface: $(grep -rs '^Requires=\|^BindsTo=\|^Requisite=' "$EY")"; else ok "early: Wants= only, no hard dependency"; fi

# the ownership step: a confined addon's unit gives the addon's files to its user before every start
# (an addon that ships a unit file among them); a root addon's unit and one without a policy get none
O="$T/own"; RO="$O/root"; EO="$O/early"
mkdir -p "$RO/usr/local/etc/config/rc.d" "$RO/usr/local/etc/config/addon-policy" "$RO/usr/local/addons/shipped/etc/systemd" "$EO"
for n in confined rootaddon nopolicy shipped; do
  printf '#!/bin/sh\n' > "$RO/usr/local/etc/config/rc.d/$n"; chmod 755 "$RO/usr/local/etc/config/rc.d/$n"
done
printf '[Unit]\nDescription=shipped\n' > "$RO/usr/local/addons/shipped/etc/systemd/shipped.service"
for n in confined shipped; do
  printf '# mode=confined uid=30000\n[Service]\nUser=addon-%s\nGroup=addon-%s\n' "$n" "$n" > "$RO/usr/local/etc/config/addon-policy/$n.conf"
done
printf '# openccu-lite addon policy for rootaddon\n# mode=root\n' > "$RO/usr/local/etc/config/addon-policy/rootaddon.conf"
printf '# mode=root\n[Service]\nCapabilityBoundingSet=~CAP_SYS_ADMIN\n' > "$RO/usr/local/etc/config/addon-policy/rootcaps.conf"
printf '#!/bin/sh\n' > "$RO/usr/local/etc/config/rc.d/rootcaps"; chmod 755 "$RO/usr/local/etc/config/rc.d/rootcaps"
OCCU_ADDONS_KMSG="$O/kmsg" OCCU_ADDONS_ROOT="$RO" sh "$GEN" "$O/normal" "$EO" "$O/late" > "$O/out" 2>&1 || bad "the generator with policies exits $?: $(cat "$O/out")"
for n in confined shipped; do
  f="$EO/addon-$n.service.d/20-addon-own.conf"
  if grep -qx "ExecStartPre=+-/usr/libexec/occu/lite-addon-own $n" "$f" 2>/dev/null && grep -qx '\[Service\]' "$f"; then
    ok "a confined addon's unit ($n) runs the ownership step as root before its start"
  else
    bad "no ownership step for $n: $(cat "$f" 2>/dev/null)"
  fi
  [ "$(grep -c '^ExecStartPre=' "$f" 2>/dev/null)" = 1 ] && ok "one step for $n" || bad "steps for $n: $(grep -c '^ExecStartPre=' "$f" 2>/dev/null)"
  # a confined addon's init runs in its unit as the addon's user (no "+"), after the ownership step
  i="$EO/addon-$n.service.d/30-addon-init.conf"
  if grep -qx "ExecStartPre=-/bin/sh -c '. /etc/profile; exec /usr/local/etc/config/rc.d/$n init'" "$i" 2>/dev/null && grep -qx '\[Service\]' "$i"; then
    ok "a confined addon's unit ($n) runs init as the addon's user before its start"
  else
    bad "no init step for $n: $(cat "$i" 2>/dev/null)"
  fi
  [ "$(grep -c '^ExecStartPre=' "$i" 2>/dev/null)" = 1 ] && ok "one init step for $n" || bad "init steps for $n: $(grep -c '^ExecStartPre=' "$i" 2>/dev/null)"
  grep -q '^ExecStartPre=+' "$i" 2>/dev/null && bad "the init step of $n runs as root" || ok "the init step of $n is not privileged"
done
for n in rootaddon nopolicy rootcaps; do
  if [ -e "$EO/addon-$n.service.d/20-addon-own.conf" ] || grep -rqs 'lite-addon-own' "$EO/addon-$n.service" "$EO/addon-$n.service.d"; then
    bad "$n runs as root and got the ownership step"
  else
    ok "no ownership step for $n (it runs as root)"
  fi
  if [ -e "$EO/addon-$n.service.d/30-addon-init.conf" ] || grep -rqs ' init' "$EO/addon-$n.service" "$EO/addon-$n.service.d"; then
    bad "$n runs as root and got an init step (S55InitAddons runs its init)"
  else
    ok "no init step for $n (S55InitAddons runs it as root, as before)"
  fi
done
# a root policy with a [Service] section - the bounding set without CAP_SYS_ADMIN - is a drop-in like
# a confined one; a root policy without one installs nothing
if grep -qx 'CapabilityBoundingSet=~CAP_SYS_ADMIN' "$EO/addon-rootcaps.service.d/10-policy.conf" 2>/dev/null; then
  ok "a root policy with a [Service] section is installed as the policy drop-in"
else
  bad "the root policy's drop-in: $(cat "$EO/addon-rootcaps.service.d/10-policy.conf" 2>/dev/null)"
fi
[ -e "$EO/addon-rootaddon.service.d/10-policy.conf" ] && bad "a root policy without [Service] got a drop-in" || ok "a root policy without a [Service] section installs no drop-in"
# a root addon without CAP_SYS_ADMIN: mount's 32 from its refused remount counts as success; no other
# unit gets that (a confined one, a root one that may mount, one without a policy)
if grep -qx 'SuccessExitStatus=32' "$EO/addon-rootcaps.service.d/40-remount-refused.conf" 2>/dev/null && grep -qx '\[Service\]' "$EO/addon-rootcaps.service.d/40-remount-refused.conf"; then
  ok "a root addon without CAP_SYS_ADMIN takes exit 32 as success"
else
  bad "no SuccessExitStatus=32 for rootcaps: $(cat "$EO/addon-rootcaps.service.d/40-remount-refused.conf" 2>/dev/null)"
fi
for n in confined shipped rootaddon nopolicy; do
  [ -e "$EO/addon-$n.service.d/40-remount-refused.conf" ] && bad "$n got SuccessExitStatus=32" || ok "no exit-32 drop-in for $n"
done

# A confined addon plants a unit file in its own directory, which its user can write: User=root, "+"
# commands, a drop-in beside it. The unit systemd gets is the generated one with the addon's policy;
# nothing of the planted files reaches the generator's output, and the journal says so once per addon.
L="$T/planted"; RL="$L/root"; EL="$L/early"
SD="$RL/usr/local/addons/planted/etc/systemd"
mkdir -p "$RL/usr/local/etc/config/rc.d" "$RL/usr/local/etc/config/addon-policy" "$SD/planted.service.d" \
  "$RL/usr/local/addons/dangling/etc/systemd" "$RL/usr/local/addons/dropin/etc/systemd/dropin.service.d" "$EL"
for n in planted dangling dropin clean; do
  printf '#!/bin/sh\n' > "$RL/usr/local/etc/config/rc.d/$n"; chmod 755 "$RL/usr/local/etc/config/rc.d/$n"
  printf '# mode=confined uid=30001\n[Service]\nUser=addon-%s\nGroup=addon-%s\nNoNewPrivileges=yes\n' "$n" "$n" > "$RL/usr/local/etc/config/addon-policy/$n.conf"
done
cat > "$SD/planted.service" <<'PLANTED'
[Unit]
Description=planted
[Service]
User=root
ExecStartPre=+/bin/sh -c 'id > /tmp/planted-root'
ExecStart=/bin/sh -c 'exec /usr/local/addons/planted/bin/daemon'
ExecStartPost=+/bin/sh -c 'echo post'
ExecStopPost=!/bin/sh -c 'echo stop'
PLANTED
printf '[Service]\nUser=root\nExecStartPre=+/bin/sh -c "id > /tmp/planted-dropin"\n' > "$SD/planted.service.d/override.conf"
ln -s /nowhere/dangling.service "$RL/usr/local/addons/dangling/etc/systemd/dangling.service"
printf '[Service]\nUser=root\n' > "$RL/usr/local/addons/dropin/etc/systemd/dropin.service.d/override.conf"
OCCU_ADDONS_KMSG="$L/kmsg" OCCU_ADDONS_ROOT="$RL" sh "$GEN" "$L/normal" "$EL" "$L/late" > "$L/out" 2>&1
rc=$?
[ "$rc" = 0 ] && ok "planted unit files: the generator exits 0" || bad "planted unit files: exit $rc: $(cat "$L/out")"
PU="$EL/addon-planted.service"
if [ -f "$PU" ] && [ ! -L "$PU" ] && grep -q '^# generated by /usr/lib/systemd/system-generators/occu-addons' "$PU"; then
  ok "planted: the unit is the generated one, not a link"
else
  bad "planted: addon-planted.service is not the generated unit: $(ls -l "$PU" 2>&1)"
fi
grep -qx "ExecStart=/bin/sh -c '. /etc/profile; exec /usr/local/etc/config/rc.d/planted start'" "$PU" 2>/dev/null \
  && ok "planted: it runs rc.d/planted" || bad "planted: ExecStart $(grep ^ExecStart "$PU" 2>/dev/null)"
grep -qx 'User=addon-planted' "$EL/addon-planted.service.d/10-policy.conf" 2>/dev/null \
  && ok "planted: the stored policy's User= applies" || bad "planted: no policy drop-in: $(ls "$EL/addon-planted.service.d" 2>&1)"
if grep -rqs -e 'User=root' -e '/tmp/planted' -e 'Description=planted$' -e 'ExecStartPost=' -e 'ExecStopPost=' "$EL"; then
  bad "planted: a line of the planted files reached the output: $(grep -rs -e 'User=root' -e '/tmp/planted' -e 'Description=planted$' -e 'ExecStartPost=' -e 'ExecStopPost=' "$EL")"
else
  ok "planted: no User=root and no planted command in the generator's output"
fi
# every Exec line with a "+" or "!" prefix (systemd's run-with-full-privileges markers) in the output
plus=$(grep -rhs -e '^Exec[A-Za-z]*=[-+!@:]*[+!]' "$EL" | sort)
want=$( (for n in clean dangling dropin planted; do echo "ExecCondition=+/usr/libexec/occu/lite-addon-payload $n"; echo "ExecStartPre=+-/usr/libexec/occu/lite-addon-own $n"; done) | sort)
[ "$plus" = "$want" ] && ok "planted: the only commands run as root are the program check (B-267) and the ownership steps" || bad "planted: privileged commands: $plus"
[ "$(ls "$EL/addon-planted.service.d" 2>/dev/null | tr '\n' ' ')" = "10-policy.conf 20-addon-own.conf 30-addon-init.conf " ] \
  && ok "planted: only the policy, the ownership step and the init step as drop-ins" || bad "planted: drop-ins $(ls "$EL/addon-planted.service.d" 2>&1)"
if find "$EL" -type l ! -path "$EL/addons.target.wants/*" | grep -q .; then
  bad "planted: a link outside addons.target.wants: $(find "$EL" -type l ! -path "$EL/addons.target.wants/*")"
elif find "$EL/addons.target.wants" -type l -exec readlink {} \; | grep -v '^\.\./addon-[a-z]*\.service$' | grep -q .; then
  bad "planted: a wants link that leads elsewhere: $(find "$EL/addons.target.wants" -type l -exec readlink {} \;)"
else
  ok "planted: no link into an addon's directory"
fi
for n in dangling dropin; do
  [ -f "$EL/addon-$n.service" ] && [ ! -L "$EL/addon-$n.service" ] && ok "$n: the generated unit" || bad "$n: $(ls -l "$EL/addon-$n.service" 2>&1)"
done
MSG='ships its own unit file; ignored since openccu-lite 1.0.0-alpha.0, the generated unit is used'
for n in planted dangling dropin; do
  [ "$(grep -cx "<4>occu-addons: addon $n $MSG" "$L/kmsg" 2>/dev/null)" = 1 ] \
    && ok "journal: one line for $n" || bad "journal for $n: $(cat "$L/kmsg" 2>/dev/null)"
done
[ "$(wc -l < "$L/kmsg" 2>/dev/null)" = 3 ] && ok "journal: nothing for the addon without a unit file" || bad "journal lines: $(cat "$L/kmsg" 2>/dev/null)"
[ -s "$L/out" ] && bad "planted: output beside the journal lines: $(cat "$L/out")" || ok "planted: nothing on stdout or stderr"
# /dev/kmsg not writable (a container): the same line on stderr, the unit generated all the same
EL2="$L/early2"; mkdir -p "$EL2"
OCCU_ADDONS_KMSG="$L/missing/kmsg" OCCU_ADDONS_ROOT="$RL" sh "$GEN" "$L/normal" "$EL2" "$L/late" > "$L/out2" 2>"$L/err2"
rc=$?
[ "$rc" = 0 ] && grep -qx "occu-addons: addon planted $MSG" "$L/err2" && [ -f "$EL2/addon-planted.service" ] && [ ! -L "$EL2/addon-planted.service" ] \
  && ok "no /dev/kmsg: the line on stderr, the generated unit" || bad "no /dev/kmsg: exit $rc, stderr $(cat "$L/err2")"
[ "$(grep -c 'ships its own unit file' "$L/err2")" = 3 ] && ok "no /dev/kmsg: one line per addon" || bad "no /dev/kmsg: $(cat "$L/err2")"

[ "$fails" = 0 ] && echo "occu-addons generator: all cases passed" || { echo "occu-addons generator: $fails case(s) failed"; exit 1; }
