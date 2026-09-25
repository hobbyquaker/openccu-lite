#!/bin/sh
# openccu-lite: the boot screen.
#
#   - lite-psplash: "boot" writes and notes the unit's message; "done" shows a unit still starting
#     (the HmIP server first) with one systemctl call; "finish" empties the bar and ends every later
#     write; nothing is written without psplash or its FIFO; the write needs no timeout (psplash-write opens the FIFO non-blocking), so no watcher is left over.
#   - lite-boot-message: psplash-systemd stopped (it would quit the splash), the splash keeps the
#     hint without the bar, the console line only where a getty on tty2 is enabled, the console
#     and /run/issue.
#   - The units: every "boot" has its "done"; the getty is enabled and ordered after the message;
#     psplash's text height patch is there.
#
# B-126: the bar stayed over the end-of-boot hint, and the splash showed whichever unit had started
# last ("Starting rfd..." for 45 s while hmipserver's JVM was starting).
#
# Nothing needs root, a framebuffer, psplash or systemd: pidof, psplash-write, systemctl, hostname,
# ip and the cgroup file are fakes.
#
# Usage: sh scripts/testcases/lite-boot-screen-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$HERE/buildroot-external"
OCC="$EXT/overlay/lite/usr/libexec/occu"
MSG="$OCC/lite-boot-message"
PSP="$OCC/lite-psplash"
U="$EXT/overlay/lite/usr/lib/systemd/system"
PRESET="$EXT/overlay/lite/usr/lib/systemd/system-preset/50-openccu-lite.preset"
[ -f "$MSG" ] && [ -f "$PSP" ] || { echo "lite-boot-message or lite-psplash not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

mkdir -p "$T/bin" "$T/dev"
printf '#!/bin/sh\n[ "$1" = psplash ] && [ -e "$OCCU_T/running" ] && { echo 4242; exit 0; }\nexit 1\n' > "$T/bin/pidof"
printf '#!/bin/sh\necho testbox\n' > "$T/bin/hostname"
printf '#!/bin/sh\necho "2: eth0    inet 192.0.2.10/24 brd 192.0.2.255 scope global eth0"\n' > "$T/bin/ip"
# systemctl: logs its call; list-units prints $OCCU_T/activating, is-enabled asks $OCCU_T/enabled
cat > "$T/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$OCCU_T/calls"
case "$1" in
  list-units) cat "$OCCU_T/activating" 2>/dev/null; exit 0 ;;
  is-enabled) [ -e "$OCCU_T/enabled" ]; exit ;;
  stop) [ -z "${OCCU_TEST_STOP_FAIL:-}" ]; exit ;;
esac
exit 0
EOF
printf '#!/bin/sh\necho "write $*" >> "$OCCU_T/calls"\n' > "$T/write"
printf '#!/bin/sh\nexec sh %s "$@"\n' "$PSP" > "$T/lite-psplash"
chmod +x "$T/bin/"* "$T/systemctl" "$T/write" "$T/lite-psplash"
mkfifo "$T/fifo" || { echo "mkfifo failed"; exit 2; }

export OCCU_T="$T" OCCU_PSPLASH_FIFO="$T/fifo" OCCU_PSPLASH_WRITE="$T/write" OCCU_PSPLASH_STATE="$T/state"
export OCCU_PSPLASH_CGROUP="$T/cgroup" OCCU_SYSTEMCTL="$T/systemctl" OCCU_PSPLASH="$T/lite-psplash"
export OCCU_ISSUE="$T/issue" OCCU_CONSOLE="$T/console" OCCU_VT_ACTIVE="$T/vt-active" OCCU_TTY_DIR="$T/dev"
export OCCU_VERSION_FILE="$T/VERSION" OCCU_HM_MODE_FILE="$T/hm_mode"
printf 'VERSION=3.89.8.20260719\nLITE=1.0.0-test\n' > "$T/VERSION"

# psplash up, nothing noted, nothing starting, no terminals, no getty
reset() {
  rm -rf "${T:?}/state" "$T/activating" "$T/enabled" "$T/console" "$T/issue" "${T:?}/dev" "$T/vt-active"
  mkdir -p "$T/dev"
  : > "$T/calls"
  : > "$T/running"
}
in_unit() { printf '0::/system.slice/%s\n' "$1" > "$T/cgroup"; }
psp() { PATH="$T/bin:$PATH" sh "$PSP" "$@"; }
# what reached the splash, one line per line ("|"), a multi-line message spans several
writes() { grep -v '^systemctl ' "$T/calls" | sed 's/^write //' | tr '\n' '|'; }
sysctl_calls() { grep -c '^systemctl ' "$T/calls"; }
starting() { for u in "$@"; do echo "$u loaded activating start x"; done > "$T/activating"; }
note() {  # note <unit> <message> <mtime>
  mkdir -p "$T/state"
  echo "$2" > "$T/state/$1"
  touch -d "$3" "$T/state/$1"
}

# --- lite-psplash boot
reset; in_unit rfd.service
psp boot S61rfd
[ "$(writes)" = "MSG Starting rfd...|PROGRESS 62|" ] && ok "boot: the message and the progress" || bad "boot wrote: $(writes)"
[ "$(cat "$T/state/rfd.service" 2>/dev/null)" = "Starting rfd..." ] && ok "boot notes the unit's message" || bad "notes: $(ls "$T/state" 2>/dev/null)"
[ "$(sysctl_calls)" = 0 ] && ok "boot calls no systemctl" || bad "boot called systemctl"
reset; in_unit hmipserver.service
psp boot S62HMServer
[ "$(writes)" = "MSG Starting HmIP server...|PROGRESS 63|" ] && ok "S62HMServer is \"Starting HmIP server...\"" || bad "hmipserver's boot wrote: $(writes)"
# a unit that runs as a user cannot write its note: nothing on stderr (it went to the journal and the console)
reset; in_unit lighttpd.service; mkdir -p "$T/state"; chmod 555 "$T/state"
err=$(psp boot S50lighttpd 2>&1)
chmod 755 "$T/state"
[ -z "$err" ] && [ "$(writes)" = "MSG Starting lighttpd...|PROGRESS 51|" ] && ok "boot where the note cannot be written: no error output, the message still written" || bad "boot with an unwritable note: '$err' $(writes)"
reset; rm -f "$T/running"; in_unit rfd.service
psp boot S61rfd
[ -z "$(writes)" ] && [ ! -e "$T/state/rfd.service" ] && ok "boot without psplash: nothing written, nothing noted" || bad "boot without psplash: $(writes)"

# --- done
reset
note hmipserver.service "Starting HmIP server..." "2026-01-01 00:00:01"
note rfd.service "Starting rfd..." "2026-01-01 00:00:03"
note crond.service "Starting crond..." "2026-01-01 00:00:05"
starting rfd.service crond.service hmipserver.service
in_unit rfd.service
psp 'done' S61rfd
[ "$(writes)" = "MSG Starting HmIP server...|" ] && ok "done: the HmIP server first while it starts, even when another began later" || bad "done wrote: $(writes)"
[ ! -e "$T/state/rfd.service" ] && ok "done removes the unit's own note" || bad "rfd's note is left"
[ "$(sysctl_calls)" = 1 ] && grep -q '^systemctl list-units --state=activating' "$T/calls" && ok "one systemctl list-units --state=activating per done" || bad "systemctl calls: $(grep '^systemctl' "$T/calls")"

reset
note hmipserver.service "Starting HmIP server..." "2026-01-01 00:00:09"
note sshd.service "Starting sshd..." "2026-01-01 00:00:02"
note chrony.service "Starting chronyd..." "2026-01-01 00:00:04"
starting crond.service sshd.service chrony.service
in_unit crond.service
psp 'done' S98crond
[ "$(writes)" = "MSG Starting chronyd...|" ] && ok "done: the unit that began last among those still starting, not a unit that is up" || bad "done wrote: $(writes)"

reset
note hmipserver.service "Starting HmIP server..." "2026-01-01 00:00:09"
starting hmipserver.service
in_unit hmipserver.service
psp 'done' S62HMServer
[ "$(writes)" = "MSG Starting services...|" ] && ok "done: its own unit (still activating in ExecStartPost) is not shown" || bad "done wrote: $(writes)"

reset; in_unit crond.service
psp 'done' S98crond
[ "$(writes)" = "MSG Starting services...|" ] && ok "done with nothing starting: \"Starting services...\"" || bad "done wrote: $(writes)"

reset; rm -f "$T/running"; in_unit crond.service
psp 'done' S98crond
[ -z "$(writes)" ] && [ "$(sysctl_calls)" = 0 ] && ok "done without psplash: no write, no systemctl" || bad "done without psplash: $(cat "$T/calls")"

# --- finish, and nothing afterwards
reset; in_unit occu-boot-message.service
note crond.service "Starting crond..." "2026-01-01 00:00:05"
psp finish "$(printf 'line one\nline two')"
[ "$(writes)" = "PROGRESS 0|MSG line one|line two|" ] && ok "finish: the bar emptied, then the message" || bad "finish wrote: $(writes)"
[ -e "$T/state/boot-finished" ] && [ ! -e "$T/state/crond.service" ] && ok "finish marks the end of the boot and drops the notes" || bad "state after finish: $(ls "$T/state")"
: > "$T/calls"; in_unit rfd.service
psp boot S61rfd; psp 'done' S61rfd; psp msg hello; psp progress 50
[ -z "$(writes)" ] && [ "$(sysctl_calls)" = 0 ] && [ ! -e "$T/state/rfd.service" ] && ok "after finish: boot, done, msg and progress write nothing, note nothing, call no systemctl" || bad "after finish: $(cat "$T/calls")"
if grep -rq 'lite-psplash quit' "$EXT/overlay/lite"; then bad "something in the overlay quits the splash"; else ok "nothing in the overlay quits the splash"; fi

# --- the guards
reset
PATH="$T/bin:$PATH" OCCU_PSPLASH_FIFO="$T/no-fifo" sh "$PSP" msg hello
[ -z "$(writes)" ] && ok "no FIFO: nothing written" || bad "written without a FIFO: $(writes)"
# no timeout around the write: busybox's forks a watcher that outlives the step and systemd finds it
# in the unit's cgroup ("Found left-over process (timeout)"); psplash-write opens the FIFO with
# O_NONBLOCK and cannot hang on it
if grep -v '^[[:space:]]*#' "$PSP" | grep -q 'timeout'; then
  bad "lite-psplash wraps the write in a timeout (its watcher is left over in the unit's cgroup)"
else
  ok "lite-psplash writes without a timeout, so no watcher is left over"
fi
# psplash as a command: at the start of a line or after ; & | or exec - "pidof psplash" is no start
if grep -v '^[[:space:]]*#' "$PSP" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*|exec[[:space:]]+)(/usr/bin/)?psplash([[:space:]]|$)|/usr/bin/psplash([[:space:]]|$)'; then
  bad "lite-psplash starts psplash"
else
  ok "lite-psplash never starts psplash"
fi

# --- lite-boot-message
run_msg() { PATH="$T/bin:$PATH" sh "$MSG" > "$T/out" 2>&1; }
HINT1="openccu-lite 3.89.8.20260719-lite.1.0.0-test is up."

reset; : > "$T/enabled"; : > "$T/dev/tty0"; echo tty1 > "$T/vt-active"; in_unit occu-boot-message.service
run_msg; rc=$?
[ "$rc" -eq 0 ] && ok "lite-boot-message exits 0" || bad "lite-boot-message exited $rc: $(cat "$T/out")"
s=$(grep -n '^systemctl stop psplash-systemd.service$' "$T/calls" | cut -d: -f1)
p=$(grep -n '^write PROGRESS 0$' "$T/calls" | cut -d: -f1)
[ -n "$s" ] && [ -n "$p" ] && [ "$s" -lt "$p" ] && ok "psplash-systemd is stopped before the bar is emptied (it would quit the splash)" || bad "order: $(cat "$T/calls")"
[ "$(writes)" = "PROGRESS 0|MSG $HINT1|Host: testbox   Address: 192.0.2.10||Web UI: http://192.0.2.10/|Console: press Alt+F2|" ] && ok "the splash: the bar emptied, then the hint with the console line" || bad "splash writes: $(writes)"
grep -q 'QUIT' "$T/calls" && bad "the splash is quit" || ok "the splash stays (no QUIT)"
grep -q '^systemctl .*psplash-start' "$T/calls" && bad "psplash-start is touched" || ok "psplash-start is left running"
[ "$(cat "$T/dev/tty1" 2>/dev/null)" = "$(printf '\033[?25l')" ] && ok "the cursor on the splash's terminal is hidden" || bad "tty1 got: $(od -c "$T/dev/tty1" 2>/dev/null | head -n 1)"
grep -qxF "$HINT1" "$T/console" && grep -qx 'Console: press Alt+F2' "$T/console" && ok "the console has the hint and the console line" || bad "console: $(cat "$T/console" 2>/dev/null)"
grep -qxF "$HINT1" "$T/issue" && grep -qx 'Web UI: http://192.0.2.10/' "$T/issue" && ! grep -q 'Console:' "$T/issue" && ok "/run/issue has the hint without the console line (the getty shows it on that console)" || bad "issue: $(cat "$T/issue" 2>/dev/null)"
[ -e "$T/state/boot-finished" ] && ok "the end of the boot is marked" || bad "no end mark"

reset; : > "$T/dev/tty0"; echo tty1 > "$T/vt-active"
run_msg
! grep -q 'Console:' "$T/calls" "$T/console" && ok "no getty on tty2 enabled: no console line" || bad "a console line without a getty: $(cat "$T/console")"

reset; : > "$T/enabled"
run_msg
! grep -q 'Console:' "$T/calls" "$T/console" && [ -z "$(ls "$T/dev")" ] && ok "no virtual terminals (a container): no console line, no terminal written" || bad "no terminals: $(cat "$T/calls")"

reset; rm -f "$T/running"; : > "$T/enabled"; : > "$T/dev/tty0"; echo tty1 > "$T/vt-active"
run_msg
! grep -q '^systemctl stop' "$T/calls" && [ -z "$(writes)" ] && [ ! -e "$T/dev/tty1" ] && ok "no psplash: nothing stopped, nothing written to a splash, the cursor left alone" || bad "no psplash: $(cat "$T/calls")"
grep -qxF "$HINT1" "$T/console" && grep -qx 'Console: press Alt+F2' "$T/console" && grep -qxF "$HINT1" "$T/issue" && ok "no psplash: the console and /run/issue still get the hint" || bad "no psplash: console $(cat "$T/console" 2>/dev/null)"
[ -e "$T/state/boot-finished" ] && ok "no psplash: the end of the boot is still marked" || bad "no psplash: no end mark"

reset; echo tty1 > "$T/vt-active"
export OCCU_TEST_STOP_FAIL=1
run_msg
unset OCCU_TEST_STOP_FAIL
grep -q 'could not stop psplash-systemd' "$T/out" && grep -q '^write PROGRESS 0$' "$T/calls" && ok "a failed stop of psplash-systemd is said, and the hint is still drawn" || bad "failed stop: $(cat "$T/out")"

# --- the units
n=0
nbad=0
for f in "$U"/*.service; do
  b=$(grep '^ExecStartPre=[-+]*/usr/libexec/occu/lite-psplash boot ' "$f") || continue
  n=$((n+1))
  prefix=$(echo "$b" | sed 's|^ExecStartPre=\([-+]*\)/.*|\1|')
  sxx=${b##* }
  want="ExecStartPost=${prefix}/usr/libexec/occu/lite-psplash done ${sxx}"
  last_post=$(grep '^ExecStartPost=' "$f" | tail -n 1)
  ls_=$(grep -n '^ExecStart=' "$f" | tail -n 1 | cut -d: -f1)
  ld=$(grep -nxF "$want" "$f" | cut -d: -f1)
  if [ "$last_post" = "$want" ] && [ -n "$ls_" ] && [ -n "$ld" ] && [ "$ld" -gt "$ls_" ]; then
    :
  else
    bad "${f##*/}: its last ExecStartPost must be $want, after ExecStart (is: $last_post)"
    nbad=$((nbad+1))
  fi
done
[ "$n" -ge 20 ] && [ "$nbad" = 0 ] && ok "all $n units with a boot message end their start with its done, with the same prefix" || { [ "$n" -ge 20 ] || bad "only $n units with a boot message found"; }

UNIT="$U/occu-boot-message.service"
grep -qx 'ExecStart=/usr/libexec/occu/lite-boot-message' "$UNIT" && ok "occu-boot-message runs lite-boot-message" || bad "occu-boot-message's ExecStart"
sed -n 's/^After=//p' "$UNIT" | tr ' ' '\n' | grep -qx psplash-start.service && ok "occu-boot-message is after psplash-start" || bad "occu-boot-message must order after psplash-start.service"
grep -qx 'enable getty@.service tty2' "$PRESET" && ok "the preset enables the getty on tty2" || bad "the preset must enable getty@.service tty2"
cat "$U/getty@tty2.service.d/"*.conf 2>/dev/null | grep -qx 'After=occu-boot-message.service' && ok "the getty on tty2 starts after the end-of-boot message (its /etc/issue)" || bad "getty@tty2.service.d needs After=occu-boot-message.service"
# the splash starts when fb0 appears (the Pis register it after sysinit's condition check) and stops
# when it goes; a framebuffer gone before psplash opens it is no failure
PR="$EXT/overlay/lite/usr/lib/udev/rules.d/62-openccu-lite-psplash.rules"
grep -qF 'ACTION=="add", SUBSYSTEM=="graphics", KERNEL=="fb0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="psplash-start.service psplash-systemd.service"' "$PR" 2>/dev/null && ok "fb0's appearance starts the splash" || bad "62-openccu-lite-psplash.rules must pull psplash-start and psplash-systemd in on fb0's add"
grep -qF 'ACTION=="remove", SUBSYSTEM=="graphics", KERNEL=="fb0", RUN+="/usr/bin/systemctl --no-block stop psplash-start.service"' "$PR" 2>/dev/null && ok "fb0's removal stops the splash" || bad "62-openccu-lite-psplash.rules must stop psplash-start on fb0's remove"
DI="$U/psplash-start.service.d/10-openccu-lite.conf"
grep -qx 'ConditionPathExists=/dev/fb0' "$DI" && grep -qx 'SuccessExitStatus=255' "$DI" && ok "psplash-start: skipped without fb0, and a vanished fb0 (exit 255) is no failure" || bad "psplash-start's drop-in must keep ConditionPathExists=/dev/fb0 and carry SuccessExitStatus=255"
if cat "$U/psplash-start.service" "$U/psplash-start.service.d/"*.conf "$U/psplash-systemd.service.d/"*.conf 2>/dev/null | grep -q '^Restart='; then
  bad "psplash-start or psplash-systemd is restarted"
else
  ok "nothing in the overlay restarts psplash-start or psplash-systemd"
fi
grep -qxF '+  *height = h + font->height;' "$EXT/patches/psplash/0004-text-height.patch" && ok "psplash sizes a text by its lines (0004-text-height.patch)" || bad "patches/psplash/0004-text-height.patch is missing or changed"

# --- the splash logo (task 112): every lite product with psplash uses the lite logo, the post-build
# check agrees, upstream's products keep upstream's logo, and the recovery system gets the product's
LOGO_CFG='$(BR2_EXTERNAL_EQ3_PATH)/board/lite/psplash/logo.png'
CHECK="$EXT/board/lite/psplash-logo.sh"
nl=0
nlbad=0
for c in "$EXT"/configs/*.config; do
  grep -qx 'BR2_INIT_SYSTEMD=y' "$c" && grep -qx 'BR2_PACKAGE_PSPLASH=y' "$c" || continue
  nl=$((nl+1))
  if grep -qxF "BR2_PACKAGE_PSPLASH_IMAGE=\"$LOGO_CFG\"" "$c" && sh "$CHECK" "$c"; then
    :
  else
    bad "${c##*/} must use the lite splash logo"
    nlbad=$((nlbad+1))
  fi
done
[ "$nl" -ge 4 ] && [ "$nlbad" = 0 ] && ok "all $nl lite products with psplash use board/lite/psplash/logo.png, and the post-build check passes them" || { [ "$nl" -ge 4 ] || bad "only $nl lite products with psplash found"; }
grep -q 'psplash-logo.sh" "${BR2_CONFIG}"' "$EXT/board/lite/post-build.sh" && ok "the lite post-build runs the logo check" || bad "board/lite/post-build.sh must run psplash-logo.sh"
printf 'BR2_PACKAGE_PSPLASH=y\nBR2_PACKAGE_PSPLASH_IMAGE="$(BR2_EXTERNAL_EQ3_PATH)/patches/psplash/logo.png"\n' > "$T/upstream-logo.config"
sh "$CHECK" "$T/upstream-logo.config" 2>/dev/null && bad "the post-build check lets upstream's logo through" || ok "the post-build check stops a lite build that names upstream's logo"
printf '# BR2_PACKAGE_PSPLASH is not set\n' > "$T/no-splash.config"
sh "$CHECK" "$T/no-splash.config" && ok "the post-build check leaves a product without psplash alone" || bad "the post-build check fails a product without psplash"
grep -qxF 'BR2_PACKAGE_PSPLASH_IMAGE="$(BR2_EXTERNAL_EQ3_PATH)/patches/psplash/logo.png"' "$EXT/configs/rpi4.config" && ok "upstream's products keep upstream's logo" || bad "rpi4.config no longer names patches/psplash/logo.png"
grep -q 'BR2_PACKAGE_PSPLASH_IMAGE=$(BR2_PACKAGE_PSPLASH_IMAGE)' "$EXT/package/recovery-system/recovery-system.mk" && ok "the recovery system is built with the product's splash image" || bad "recovery-system.mk no longer passes BR2_PACKAGE_PSPLASH_IMAGE"
# shellcheck disable=SC2046  # the eight bytes are meant to split
png_size() { set -- $(od -An -tu1 -j16 -N8 "$1"); echo "$(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 )) $(( ($5 << 24) + ($6 << 16) + ($7 << 8) + $8 ))"; }
if [ -f "$EXT/board/lite/psplash/logo.png" ]; then
  # shellcheck disable=SC2046
  set -- $(png_size "$EXT/board/lite/psplash/logo.png"); lw=$1; lh=$2
  # shellcheck disable=SC2046
  set -- $(png_size "$EXT/patches/psplash/logo.png"); uw=$1; uh=$2
  [ "$lh" = "$uh" ] && [ "$lw" -gt "$uw" ] && [ "$lw" -le 640 ] && ok "the lite logo (${lw}x${lh}) is as tall as upstream's (${uw}x${uh}), wider by lite, and fits a 640 px screen" || bad "the lite logo is ${lw}x${lh}, upstream's ${uw}x${uh}"
else
  bad "board/lite/psplash/logo.png is missing"
fi

[ "$fails" -eq 0 ] && echo "lite-boot-screen-test: all passed" || echo "lite-boot-screen-test: $fails failed"
[ "$fails" -eq 0 ]
