#!/bin/sh
# openccu-lite: lite-syslog-forward (B-96) runs `occulited syslog-forward` only with an occulited
# that has the subcommand, and never busybox syslogd, which takes /dev/log away from journald.
#
# Usage: sh scripts/testcases/lite-syslog-forward-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-syslog-forward"
UNIT="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/occu-syslog-forward.service"
CONF="$HERE/buildroot-external/overlay/lite/etc/systemd/journald.conf.d/10-openccu-lite.conf"
[ -f "$TOOL" ] || { echo "lite-syslog-forward not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# an occulited with the subcommand: the marker is in the binary, and the arguments reach it
printf '#!/bin/sh\n# occulited-syslog-forward-v1\necho "ran: $*"\n' > "$T/new"
chmod +x "$T/new"
got=$(OCCU_OCCULITED="$T/new" sh "$TOOL" -max-size 100)
[ "$got" = "ran: syslog-forward -max-size 100" ] && ok "a new occulited runs syslog-forward" || bad "a new occulited: got '$got'"

# an older one: it says so and ends cleanly, starting nothing
printf '#!/bin/sh\necho "daemon started: $*"\n' > "$T/old"
chmod +x "$T/old"
got=$(OCCU_OCCULITED="$T/old" sh "$TOOL"); rc=$?
case "$got" in
  *"cannot forward the journal"*) [ "$rc" -eq 0 ] && ok "an older occulited is not started" || bad "an older occulited: exit $rc" ;;
  *) bad "an older occulited: got '$got'" ;;
esac
got=$(OCCU_OCCULITED="$T/missing" sh "$TOOL"); rc=$?
[ "$rc" -eq 0 ] && ok "no occulited at all ends cleanly" || bad "no occulited: exit $rc"

# no busybox syslogd anywhere, and journald not forwarding to a socket nobody reads
if grep -q "syslogd" "$TOOL" "$UNIT" 2>/dev/null && grep -qE '^[^#]*syslogd' "$TOOL" "$UNIT"; then bad "syslogd is still started"; else ok "no syslogd is started"; fi
grep -qx 'ForwardToSyslog=no' "$CONF" && ok "journald does not forward to syslog" || bad "journald.conf must say ForwardToSyslog=no"
grep -qx 'DynamicUser=yes' "$UNIT" && grep -qx 'SupplementaryGroups=systemd-journal' "$UNIT" && ok "the unit runs as its own user in systemd-journal" || bad "the unit's user"
grep -qx 'RuntimeDirectoryPreserve=yes' "$UNIT" && ok "the cursor lasts until the reboot" || bad "RuntimeDirectoryPreserve"

# B-340: journalctl -f reads the journal directories of the moment it started, so the forwarder
# starts after the journal's move at boot, and the two that move the journal under a running one
# restart it once they are done - without waiting, both run as jobs themselves
PERSIST="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-journal-persist"
MID="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-machine-id"
RESTART='try-restart --no-block occu-syslog-forward.service'
sed -n 's/^After=//p' "$UNIT" | tr ' ' '\n' | grep -qx 'occu-persist.service' && ok "the unit starts after occu-persist" || bad "the unit must order after occu-persist.service"
flush=$(grep -n '^systemctl kill -s SIGUSR1 systemd-journald.service' "$PERSIST" | cut -d: -f1)
modes=$(grep -n '^chgrp -R systemd-journal /var/log/journal' "$PERSIST" | cut -d: -f1)
again=$(grep -n "^  systemctl ${RESTART}" "$PERSIST" | cut -d: -f1)
if [ -n "$flush" ] && [ -n "$modes" ] && [ -n "$again" ] && [ "$again" -gt "$flush" ] && [ "$again" -gt "$modes" ]; then
  ok "lite-journal-persist restarts the forwarder after the flush and the modes"
else
  bad "lite-journal-persist must restart the forwarder after the flush (flush line '$flush', modes '$modes', restart '$again')"
fi
[ "$(grep -c "occu-syslog-forward.service" "$PERSIST")" = 1 ] && ok "lite-journal-persist restarts it where the journal moves only" || bad "lite-journal-persist names the forwarder more than once"
grep -q "\"\${SYSTEMCTL}\" ${RESTART}" "$MID" && ok "lite-machine-id restarts the forwarder when the ID changes (lite-machine-id-test runs it)" || bad "lite-machine-id must restart the forwarder"

[ "$fails" -eq 0 ] && echo "lite-syslog-forward-test: all passed" || echo "lite-syslog-forward-test: $fails failed"
[ "$fails" -eq 0 ]
