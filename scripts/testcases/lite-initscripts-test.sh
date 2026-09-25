#!/bin/sh
# openccu-lite: /etc/init.d on the systemd products is the compatibility entry point and nothing
# else (task 115, D-80).
#
#   - board/post-build.sh removes the init script of an optional package on a platform whose
#     configuration does not build the package, and keeps it where it does (upstream-shaped: the
#     Kconfig symbol decides);
#   - board/lite/post-build-initscripts.sh, on a fake target: rcS and rcK go, the radio chain's
#     scripts go (task 129), every script with a unit is wrapped, a "-" row is the wrapper alone
#     without a script (also on an incremental build that still has one), an orphaned .script goes,
#     and it fails without the table or the wrapper;
#   - the wrapper answers "ignored" for a "-" row's start|stop|restart|reload although the script
#     is not there, and exits 1 for any other action of such a row;
#   - the table: the two "-" rows, no radio row, and every other row's unit exists in the overlay.
#
# Nothing needs root or systemd.
#
# Usage: sh scripts/testcases/lite-initscripts-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$HERE/buildroot-external"
TABLE="$EXT/overlay/lite/usr/lib/systemd/openccu-lite-initscripts"
WRAPPER="$EXT/overlay/lite/usr/libexec/occu/initscript-wrapper"
PBI="$EXT/board/lite/post-build-initscripts.sh"
PB="$EXT/board/post-build.sh"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

stub() { printf '#!/bin/sh\nexit 0\n' >"$1"; chmod 755 "$1"; }

# --- board/post-build.sh: optional packages' scripts follow their Kconfig symbol -----------------
PKG_SCRIPTS="S40bluetoothd S49xinetd S50ser2net S51nut S59snmpd S60openvpn"
pb_case() {
  # $1 label, $2 the .config's content, $3 the scripts expected to stay
  d="$T/pb-$1"; mkdir -p "$d/target/etc/init.d"
  for s in $PKG_SCRIPTS S50crond S01InitHost; do stub "$d/target/etc/init.d/$s"; done
  printf '%b' "$2" >"$d/config"
  if ! env TARGET_DIR="$d/target" BR2_CONFIG="$d/config" PRODUCT_VERSION=0 PRODUCT=t PRODUCT_PLATFORM=t sh "$PB" >"$d/log" 2>&1; then
    bad "post-build.sh failed ($1): $(tail -2 "$d/log")"; return
  fi
  left=""; for s in $PKG_SCRIPTS; do [ -e "$d/target/etc/init.d/$s" ] && left="$left $s"; done
  want=""; for s in $3; do want="$want $s"; done
  [ "$left" = "$want" ] && ok "post-build.sh ($1): left [${left# }]" || bad "post-build.sh ($1): left [${left# }], expected [${want# }]"
  [ -e "$d/target/etc/init.d/S01InitHost" ] && ok "post-build.sh ($1): an unrelated script stays" || bad "post-build.sh ($1): S01InitHost removed"
  [ -e "$d/target/etc/init.d/S50crond" ] && bad "post-build.sh ($1): buildroot's S50crond stays" || ok "post-build.sh ($1): buildroot's S50crond removed as before"
}
pb_case lite '# BR2_PACKAGE_BLUEZ5_UTILS is not set\n# BR2_PACKAGE_XINETD is not set\n# BR2_PACKAGE_NUT is not set\nBR2_PACKAGE_LIGHTTPD=y\n' ""
pb_case classic 'BR2_PACKAGE_BLUEZ5_UTILS=y\nBR2_PACKAGE_XINETD=y\nBR2_PACKAGE_SER2NET=y\nBR2_PACKAGE_NUT=y\nBR2_PACKAGE_NETSNMP=y\nBR2_PACKAGE_OPENVPN=y\n' "$PKG_SCRIPTS"
pb_case mixed 'BR2_PACKAGE_OPENVPN=y\nBR2_PACKAGE_NUT_DRIVERS=y\n# BR2_PACKAGE_NUT is not set\nBR2_PACKAGE_XINETD=y\n' "S49xinetd S60openvpn"
# every symbol the loop names is a real one the product configs know
for sym in BR2_PACKAGE_BLUEZ5_UTILS BR2_PACKAGE_XINETD BR2_PACKAGE_SER2NET BR2_PACKAGE_NUT BR2_PACKAGE_NETSNMP BR2_PACKAGE_OPENVPN; do
  grep -rqE "^(# )?$sym(=| )" "$EXT/Buildroot.config" "$EXT/configs/" && ok "post-build.sh: $sym is a symbol the configs know" || bad "post-build.sh: $sym appears in no config"
done

# --- the table ------------------------------------------------------------------------------------
rows() { grep -v '^[[:space:]]*#' "$TABLE" | grep -v '^[[:space:]]*$'; }
[ "$(rows | awk '$2 == "-" { print $1 }' | sort | tr '\n' ' ')" = "S07logging S11InitLEDs " ] && ok "table: the - rows are S07logging and S11InitLEDs" || bad "table: the - rows are $(rows | awk '$2 == "-" { print $1 }' | tr '\n' ' ')"
for s in S47InitRFHardware S48UpdateRFHardware S49hs485d S60hs485d S60multimacd S61rfd S62HMServer S58LGWFirmwareUpdate S59SetLGWKey rcS rcK; do
  rows | awk '{ print $1 }' | grep -qx "$s" && bad "table: $s must have no row" || ok "table: no row for $s"
done
# (a for loop, not "| while read": bad() must count in this shell, not in a pipeline's subshell)
for u in $(rows | awk '$2 != "-" { print $2 }'); do
  case "$u" in
    *.service|*.target)
      if [ -e "$EXT/overlay/lite/usr/lib/systemd/system/$u" ]; then ok "table: $u is in the overlay"
      else case "$u" in irqbalance.service) ok "table: $u comes from its package" ;; *) bad "table: $u is in no overlay" ;; esac; fi ;;
    *) bad "table: $u is not a unit name" ;;
  esac
done

# --- the units: no daemon is started through its script any more (part 2, D-80) -------------------
U="$EXT/overlay/lite/usr/lib/systemd/system"
for f in "$U"/*.service; do
  u=$(basename "$f")
  if grep -q '^ExecStart=/etc/init.d/.*\.script' "$f"; then
    grep -q '^Type=oneshot$' "$f" && ok "units: $u runs its script as a oneshot" || bad "units: $u starts a daemon through its init script"
  fi
done
for u in sshd.service crond.service; do
  grep -q '^Type=exec$' "$U/$u" && ok "units: $u is Type=exec" || bad "units: $u must be Type=exec"
  grep -q '^PIDFile=' "$U/$u" && bad "units: $u still names a pid file" || ok "units: $u without PIDFile="
  grep -q '^ExecStop=' "$U/$u" && bad "units: $u still stops through the script" || ok "units: $u without ExecStop="
done
grep -q '^ExecCondition=/etc/init.d/S50sshd.script init$' "$U/sshd.service" && ok "units: sshd runs the script's init as its condition" || bad "units: sshd.service must run S50sshd.script init as ExecCondition="
grep -q '^ExecStart=/usr/sbin/sshd -D$' "$U/sshd.service" && ok "units: sshd starts the daemon in the foreground" || bad "units: sshd.service must start /usr/sbin/sshd -D"
grep -q '^ExecReload=/bin/kill -s HUP \$MAINPID$' "$U/sshd.service" && ok "units: sshd reloads with HUP" || bad "units: sshd.service must keep its ExecReload"
grep -q '^ExecStartPre=/etc/init.d/S98crond.script init$' "$U/crond.service" && ok "units: crond runs the script's init first" || bad "units: crond.service must run S98crond.script init as ExecStartPre="
grep -q '^ExecStart=/usr/sbin/crond -f -l 9$' "$U/crond.service" && ok "units: crond starts with the script's command line" || bad "units: crond.service must start /usr/sbin/crond -f -l 9"
# the scripts: an init action, and start() still goes through it (busybox init unchanged)
S="$EXT/overlay/base/etc/init.d"
grep -q '^  init)$' "$S/S50sshd" && grep -q '^    init || exit 1$' "$S/S50sshd" && ok "S50sshd: an init action that exits 1 when sshd must not start" || bad "S50sshd: init) case with 'init || exit 1' expected"
grep -q '^  init || return$' "$S/S50sshd" && ok "S50sshd: start() goes through init" || bad "S50sshd: start() must call init first"
grep -q "^    ${S##*/}" /dev/null; grep -q '^  init)$' "$S/S98crond" && ok "S98crond: an init action" || bad "S98crond: init) case expected"
grep -q -- '--exec /usr/sbin/crond -- -f -l 9$' "$S/S98crond" && ok "S98crond: the unit's command line is the script's" || bad "S98crond: the script's crond line changed - follow it in crond.service"
grep -q -- '--exec "${DAEMON}"; then$' "$S/S50sshd" && grep -q '^DAEMON=/usr/sbin/sshd$' "$S/S50sshd" && ok "S50sshd: the unit's daemon path is the script's" || bad "S50sshd: the script's sshd line changed - follow it in sshd.service"

# --- post-build-initscripts.sh on a fake target ---------------------------------------------------
mk_target() {
  d="$1"; mkdir -p "$d/etc/init.d" "$d/usr/lib/systemd/system" "$d/usr/libexec/occu" "$d/bin"
  cp "$TABLE" "$d/usr/lib/systemd/openccu-lite-initscripts"
  cp "$WRAPPER" "$d/usr/libexec/occu/initscript-wrapper"; chmod 755 "$d/usr/libexec/occu/initscript-wrapper"
  rows | awk '$2 != "-" { print $2 }' | while read -r u; do : >"$d/usr/lib/systemd/system/$u"; done
  for s in rcS rcK S47InitRFHardware S48UpdateRFHardware S49hs485d S60hs485d S60multimacd S61rfd S62HMServer S58LGWFirmwareUpdate S59SetLGWKey; do stub "$d/etc/init.d/$s"; done
  rows | awk '{ print $1 }' | while read -r s; do stub "$d/etc/init.d/$s"; done
  stub "$d/bin/setlgwkey.sh"
}
TD="$T/target"; mk_target "$TD"
stub "$TD/etc/init.d/S99Gone.script"		# a renamed original whose script left an overlay (B-101)
if sh "$PBI" "$TD" >"$T/pbi.log" 2>&1; then
  ok "post-build-initscripts.sh runs on the fake target"
  left=""; for s in rcS rcK S47InitRFHardware S48UpdateRFHardware S49hs485d S60hs485d S60multimacd S61rfd S62HMServer S58LGWFirmwareUpdate S59SetLGWKey; do
    { [ -e "$TD/etc/init.d/$s" ] || [ -e "$TD/etc/init.d/$s.script" ]; } && left="$left $s"; done
  [ -e "$TD/bin/setlgwkey.sh" ] && left="$left setlgwkey.sh"
  [ -z "$left" ] && ok "post-build: rcS, rcK, the radio chain's scripts and setlgwkey.sh are gone" || bad "post-build left:$left"
  for s in S07logging S11InitLEDs; do
    [ -L "$TD/etc/init.d/$s" ] && [ ! -e "$TD/etc/init.d/$s.script" ] && ok "post-build: $s is the wrapper alone, no script" || bad "post-build: $s must be a wrapper symlink without a .script"
  done
  rows | awk '$2 != "-" { print $1 }' | while read -r s; do
    [ -L "$TD/etc/init.d/$s" ] && [ -f "$TD/etc/init.d/$s.script" ] || echo "$s"; done >"$T/unwrapped"
  [ ! -s "$T/unwrapped" ] && ok "post-build: every other row is wrapped with its .script" || bad "post-build: not wrapped: $(tr '\n' ' ' <"$T/unwrapped")"
  [ -e "$TD/etc/init.d/S99Gone.script" ] && bad "post-build: the orphaned S99Gone.script stays" || ok "post-build: the orphaned .script is removed"
  grep -q "WARNING" "$T/pbi.log" && bad "post-build: warned on a complete target: $(grep WARNING "$T/pbi.log" | head -1)" || ok "post-build: no warning on a complete target"
  # what is left is wrappers and .script files only
  stray=$(cd "$TD/etc/init.d" && for f in *; do [ -L "$f" ] && continue; case "$f" in *.script) ;; *) echo "$f" ;; esac; done)
  [ -z "$stray" ] && ok "post-build: /etc/init.d holds only wrappers and .script files" || bad "post-build: stray files in /etc/init.d: $(echo "$stray" | tr '\n' ' ')"
  # a second run (incremental build) changes nothing
  before=$(cd "$TD/etc/init.d" && ls -l | sed 1d | awk '{ print $1, $NF }' | sort)
  sh "$PBI" "$TD" >"$T/pbi2.log" 2>&1 && [ "$(cd "$TD/etc/init.d" && ls -l | sed 1d | awk '{ print $1, $NF }' | sort)" = "$before" ] && ok "post-build: a second run is a no-op" || bad "post-build: the second run changed /etc/init.d or failed"
else
  bad "post-build-initscripts.sh failed on the fake target: $(tail -3 "$T/pbi.log")"
fi
# an incremental build that still has a - row's renamed script from before task 115
TD3="$T/target3"; mk_target "$TD3"; sh "$PBI" "$TD3" >/dev/null 2>&1
stub "$TD3/etc/init.d/S07logging.script"
sh "$PBI" "$TD3" >/dev/null 2>&1 && [ -L "$TD3/etc/init.d/S07logging" ] && [ ! -e "$TD3/etc/init.d/S07logging.script" ] && ok "post-build: a - row's stale .script from a previous build goes" || bad "post-build: S07logging.script survived the incremental run"
# without the table or the wrapper the build fails
TD4="$T/target4"; mk_target "$TD4"; rm "$TD4/usr/lib/systemd/openccu-lite-initscripts"
sh "$PBI" "$TD4" >/dev/null 2>&1 && bad "post-build: ran without the table" || ok "post-build: fails without the table"
TD5="$T/target5"; mk_target "$TD5"; rm "$TD5/usr/libexec/occu/initscript-wrapper"
sh "$PBI" "$TD5" >/dev/null 2>&1 && bad "post-build: ran without the wrapper" || ok "post-build: fails without the wrapper"
# a row whose unit is not in the image warns, a listed script missing from /etc/init.d warns
TD6="$T/target6"; mk_target "$TD6"; rm "$TD6/usr/lib/systemd/system/crond.service" "$TD6/etc/init.d/S98StartAddons"
sh "$PBI" "$TD6" >"$T/pbi6.log" 2>&1 && grep -q "S98crond maps to crond.service, which is not in the image" "$T/pbi6.log" && grep -q "S98StartAddons is in the unit table but not in /etc/init.d" "$T/pbi6.log" && ok "post-build: warns about a missing unit and a missing script" || bad "post-build: the two warnings: $(cat "$T/pbi6.log")"

# --- the wrapper on a - row whose script is not there ---------------------------------------------
W="$T/wrap"; mkdir -p "$W/etc/init.d" "$W/usr/lib/systemd" "$W/usr/libexec/occu" "$W/usr/bin"
cp "$WRAPPER" "$W/usr/libexec/occu/initscript-wrapper"; chmod 755 "$W/usr/libexec/occu/initscript-wrapper"
# the wrapper reads the table at its absolute path: a copy with the same rows, read through a
# rewritten table variable, keeps the test off the host's /usr/lib
sed "s|^table=.*|table=$W/usr/lib/systemd/openccu-lite-initscripts|" "$WRAPPER" >"$W/usr/libexec/occu/initscript-wrapper"
cp "$TABLE" "$W/usr/lib/systemd/openccu-lite-initscripts"
ln -s ../../usr/libexec/occu/initscript-wrapper "$W/etc/init.d/S07logging"
for a in start stop restart reload; do
  out=$("$W/etc/init.d/S07logging" $a 2>&1); rc=$?
  [ "$rc" -eq 0 ] && case "$out" in *"ignored"*) ok "wrapper: S07logging $a -> ignored, exit 0" ;; *) bad "wrapper: S07logging $a said '$out'" ;; esac || bad "wrapper: S07logging $a exited $rc: $out"
done
out=$("$W/etc/init.d/S07logging" status 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "wrapper: S07logging status -> exit 1 (no unit, no script)" || bad "wrapper: S07logging status exited $rc: $out"
# a wrapped script whose .script is missing is still an error
ln -s ../../usr/libexec/occu/initscript-wrapper "$W/etc/init.d/S50lighttpd"
out=$("$W/etc/init.d/S50lighttpd" restart 2>&1); rc=$?
[ "$rc" -eq 1 ] && case "$out" in *"is missing"*) ok "wrapper: a wrapped script without its .script is an error" ;; *) bad "wrapper: S50lighttpd said '$out'" ;; esac || bad "wrapper: S50lighttpd without its script exited $rc"
# a name not in the table runs its script
stub "$W/etc/init.d/S99Other.script"; ln -s ../../usr/libexec/occu/initscript-wrapper "$W/etc/init.d/S99Other"
"$W/etc/init.d/S99Other" start >/dev/null 2>&1 && ok "wrapper: a script without a row runs as it is" || bad "wrapper: S99Other start failed"

echo; [ "$fails" -eq 0 ] && { echo "lite-initscripts-test: all checks passed"; exit 0; }
echo "lite-initscripts-test: $fails check(s) failed"; exit 1
