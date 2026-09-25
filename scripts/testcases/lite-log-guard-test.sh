#!/bin/sh
# openccu-lite: scripts/lite-log-guard.sh against fake image roots - it must fail on a configuration
# that names a log file and pass on the look-alikes and the documented exceptions.
#
# Usage: sh scripts/testcases/lite-log-guard-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
GUARD="$HERE/scripts/lite-log-guard.sh"
[ -f "$GUARD" ] || { echo "lite-log-guard.sh not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# a root that passes: look-alikes, comments, scripts and the inittab exception
clean() {
  rm -rf "$T/root"; mkdir -p "$T/root/etc/lighttpd/conf.d" "$T/root/usr/lib/systemd/system" "$T/root/etc/init.d"
  printf '%s\n' 'server.errorlog-use-syslog = "enable"' '#server.errorlog = log_root + "/lighttpd-error.log"' > "$T/root/etc/lighttpd/lighttpd.conf"
  printf '%s\n' 'debug.log-request-handling = "enable"' > "$T/root/etc/lighttpd/conf.d/debug.conf"
  printf '%s\n' '  ".log"          =>      "text/plain",' > "$T/root/etc/lighttpd/conf.d/mime.conf"
  printf '%s\n' '# Output goes to the journal instead of /var/log/hmlangw.log' '[Service]' 'ExecStart=/bin/hmlangw' > "$T/root/usr/lib/systemd/system/hmlangw.service"
  printf '%s\n' '#!/bin/sh' 'echo x >> /var/log/addon-uninstall-error.log' > "$T/root/etc/init.d/S99script"
  printf '%s\n' '::sysinit:/etc/init.d/rcS 2>&1 | /usr/bin/tee -a /tmp/boot.log' > "$T/root/etc/inittab"
  printf '%s\n' 'Log Destination = Syslog' 'Log Identifier = rfd' > "$T/root/etc/rfd.conf"
}
run() { sh "$GUARD" "$T/root" > "$T/out" 2>&1; }

clean
if run; then ok "a clean root passes ($(tail -1 "$T/out"))"; else fail "a clean root fails:"; cat "$T/out"; fi

clean; printf '%s\n' 'server.errorlog = log_root + "/lighttpd-error.log"' >> "$T/root/etc/lighttpd/lighttpd.conf"
if run; then fail "lighttpd's error log file passes"; else grep -q 'lighttpd.conf:3:' "$T/out" && ok "lighttpd's error log file fails, with file and line" || { fail "no file:line in the output"; cat "$T/out"; }; fi

clean; mkdir -p "$T/root/etc/config_templates"
printf '%s\n' '<File name="File" fileName="/var/log/hmserver.log" append="true">' > "$T/root/etc/config_templates/log4j2.xml"
if run; then fail "a log4j2 File appender passes"; else ok "a log4j2 File appender fails"; fi

clean; printf '%s\n' '[Service]' 'ExecStart=/bin/sh -c "exec /bin/foo >>/var/log/foo.log.1 2>&1"' > "$T/root/usr/lib/systemd/system/foo.service"
if run; then fail "a unit writing foo.log.1 passes"; else ok "a unit writing foo.log.1 fails"; fi

clean; printf '%s\n' 'LOGFILE=${LOGDIR}/${NAME}.log' > "$T/root/etc/default-foo"
if run; then fail "\${NAME}.log passes"; else ok "\${NAME}.log fails"; fi

clean; rm -rf "$T/root/etc"
if run; then fail "a root without etc/ passes"; else ok "a root without etc/ is refused"; fi

[ "$fails" -eq 0 ] && echo "lite-log-guard-test: all passed" || echo "lite-log-guard-test: $fails failed"
[ "$fails" -eq 0 ]
