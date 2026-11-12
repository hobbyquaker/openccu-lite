#!/bin/sh
# openccu-lite: the recovery removes an uploaded update that fails in fwprepare.
#
# An upload that fwinstall.sh's fwprepare refused (no space, a wrong file type, a bad checksum)
# stayed in /usr/local/tmp with its half-extracted directory beside it: on a CCU3-shaped card a
# firmware-sized file that only blocked the next attempt. Every EXIT trap of fwinstall.sh now runs
# on_exit, which removes the file fwprepare was given and its "-dir" while fwprepare has not
# succeeded - only below the upload directory (/usr/local/tmp, which is /userfs/tmp in the
# recovery) - and the lock as before. Once fwprepare has linked the update, nothing is removed.
#
#   - the static part: on_exit is there, every trap runs it, fwprepare sets and clears the file;
#   - B-328: on_exit cleans up only in the script's own shell. A progress bar is "awk ... &", and a
#     "kill" that reached the forked child before it had become awk made bash run the EXIT trap in
#     that child - it removed the update's directory under the running fwprepare (a CI run failed
#     at step 6 that way; busybox ash, the recovery's shell, does not run it). Here on_exit, taken
#     from fwinstall.sh, runs under bash's start-and-kill of 300 progress bars (fwinstall.sh's own
#     lines) and the file stays; the kills are SIGKILL, so no progress bar outlives its kill;
#   - fwinstall.sh itself in a container (debian, no privileges): a file of no known type below
#     /usr/local/tmp and /userfs/tmp is removed with its directory, one elsewhere stays, and an
#     update that fwprepare accepted keeps its directory when the install after it fails. Skipped
#     with a note when docker is not available. On a failure the container prints every run's
#     whole log and the state of the upload directories (B-328: the evidence for the next one).
#
# Usage: sh scripts/testcases/lite-fwprepare-cleanup-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
FW="$HERE/buildroot-external/package/recovery-system/external/overlay/base/bin/fwinstall.sh"

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

bash -n "$FW" && ok "fwinstall.sh parses" || bad "fwinstall.sh does not parse"
grep -q '^on_exit()$' "$FW" && ok "on_exit() found" || bad "on_exit() is not in fwinstall.sh"
fn=$(sed -n '/^on_exit()$/,/^}$/p' "$FW")
echo "$fn" | grep -q 'rm -f /tmp/.runningFirmwareUpdate' && ok "on_exit removes the lock" || bad "on_exit keeps the lock"
echo "$fn" | grep -q '/usr/local/tmp/?\*|/userfs/tmp/?\*)' && ok "only below the upload directory" || bad "on_exit's path guard is not the upload directory"
# every trap: on_exit, and none removes the lock alone any more (that would skip the cleanup)
n_trap=$(grep -c 'trap .* EXIT' "$FW")
n_on=$(grep -c 'trap .*on_exit.* EXIT' "$FW")
[ "$n_trap" -gt 0 ] && [ "$n_trap" = "$n_on" ] && ok "all $n_trap EXIT traps run on_exit" || bad "$n_on of $n_trap EXIT traps run on_exit"
grep -q "trap .*rm -f /tmp/.runningFirmwareUpdate.* EXIT" "$FW" && bad "a trap still removes only the lock" || ok "no trap bypasses on_exit"
fp=$(sed -n '/^fwprepare()$/,/^}$/p' "$FW")
echo "$fp" | sed -n '3,4p' | grep -q 'FWPREPARE_FILE="${filename}"' && ok "fwprepare names its file first" || bad "fwprepare does not set FWPREPARE_FILE at its start"
echo "$fp" | awk '/ln -sfn "\$\{TMPDIR\}" \/usr\/local\/.firmwareUpdate/ { l=NR } /^  FWPREPARE_FILE=""$/ { c=NR } END { exit !(l && c > l) }' &&
  ok "fwprepare clears it after linking the update" || bad "FWPREPARE_FILE is not cleared after the link"

# B-328: the progress bars' children must not run the cleanup
echo "$(sed -n '/^on_exit()$/,/^}$/p' "$FW")" | grep -q 'read -r self _ </proc/self/stat' && grep -q '^FWINSTALL_PID=\$\$$' "$FW" \
  && ok "on_exit checks that it runs in the script's own shell" || bad "on_exit has no own-shell guard"
# and they are stopped with SIGKILL (a child that caught the TERM ran the trap and still became awk),
# reaped so that bash prints no "Killed" notice into the update's output
sp=$(sed -n '/^stop_progress()$/,/^}$/p' "$FW")
echo "$sp" | grep -q 'kill -KILL "${PROGRESS_PID}"' && echo "$sp" | grep -q 'wait "${PROGRESS_PID}" 2>/dev/null' \
  && ok "stop_progress kills with SIGKILL and reaps (no job notice)" || bad "stop_progress: $sp"
n_kill=$(grep -c 'kill .*PROGRESS_PID' "$FW"); n_sp=$(grep -c 'stop_progress' "$FW")
[ "$n_kill" = 1 ] && [ "$n_sp" -gt 20 ] && ok "every progress bar is stopped through stop_progress ($n_sp)" || bad "progress bars killed outside stop_progress: $n_kill kill lines, $n_sp stop_progress"
if [ -r /proc/self/stat ] && command -v bash >/dev/null 2>&1; then
  R=$(mktemp -d) || exit 2
  # fwinstall.sh's own start and stop lines, with a marker in the awk program to find leftovers
  start=$(grep -m1 "^ *awk 'BEGIN{while(1)" "$FW" | sed "s/^ *//; s/BEGIN{/BEGIN{m=\"b328-$$\";/")
  { sed -n '/^FWINSTALL_PID=\$\$$/p; /^stop_progress()$/,/^}$/p; /^on_exit()$/,/^}$/p' "$FW" | sed "s|/usr/local/tmp/?\*|$R/?*|"
    echo "R='$R'"
    echo 'FWPREPARE_FILE="$R/up.bin"'
    echo 'for i in $(seq 1 300); do'
    echo "  $start"
    echo '  PROGRESS_PID=$!'
    grep -m1 '^ *trap "stop_progress; on_exit" EXIT$' "$FW"
    grep -m1 '^ *stop_progress && trap "on_exit" EXIT$' "$FW"
    echo '  [ -e "$R/up.bin" ] || { echo "removed at round $i"; break; }'
    echo 'done'
    echo 'trap - EXIT'
  } >"$R/probe.sh"
  : >"$R/up.bin"; mkdir -p "$R/up.bin-dir"
  timeout 120 bash "$R/probe.sh" >"$R/probe.log" 2>&1
  [ -e "$R/up.bin" ] && [ -d "$R/up.bin-dir" ] && ok "300 progress bars started and stopped at once: the update stays (bash)" || bad "a progress bar's child cleaned up: $(cat "$R/probe.log")"
  # a bar that became awk before its kill may have printed its dot; nothing else may appear
  [ -z "$(tr -d . <"$R/probe.log")" ] && ok "and nothing printed but progress dots (no job notice)" || bad "the stops printed: $(head -c 300 "$R/probe.log")"
  sleep 1
  left=$(pgrep -f "b328-$$" | wc -l)
  [ "$left" = 0 ] && ok "and no progress bar is left running" || { bad "$left progress bars outlived their kill"; pkill -KILL -f "b328-$$"; }
  rm -rf "$R"
fi

# --- fwinstall.sh in a container --------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "skip the container part: docker is not available"
else
  out="${TMPDIR:-/tmp}/lite-fwprepare.$$"
  # the inner script: three refused uploads and one accepted update whose install fails
  inner='
set -u
f=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; f=$((f+1)); }
mkdir -p /usr/local/tmp /userfs/tmp /root
fw() { bash /fw/fwinstall.sh "$1" >/tmp/run.log 2>&1; r=$?; { echo "== $1 -> rc $r"; cat /tmp/run.log; echo; } >>/tmp/runs.log; echo $r; }
for up in /usr/local/tmp/upload.bin /userfs/tmp/upload.bin; do
  head -c 4096 /dev/urandom >"$up"; mkdir -p "$up-dir"; touch "$up-dir/half"
  rc=$(fw "$up")
  [ "$rc" = 1 ] && ok "$up: refused (rc 1)" || bad "$up: rc $rc: $(tr "\n" " " </tmp/run.log)"
  grep -q "no valid filetype found" /tmp/run.log && ok "$up: the reason is the file type" || bad "$up: $(tr "\n" " " </tmp/run.log)"
  [ ! -e "$up" ] && [ ! -e "$up-dir" ] && ok "$up: removed with its directory" || bad "$up: left behind"
  grep -q "removed after the failure" /tmp/run.log && ok "$up: the log says so" || bad "$up: the removal is silent"
  [ ! -e /tmp/.runningFirmwareUpdate ] && ok "$up: the lock is gone" || bad "$up: the lock stayed"
done
up=/root/elsewhere.bin; head -c 4096 /dev/urandom >"$up"
rc=$(fw "$up")
[ "$rc" = 1 ] && [ -f "$up" ] && ok "a file outside the upload directory stays" || bad "$up: rc $rc, exists: $(test -f "$up" && echo yes || echo no)"
# accepted: a tar with an update_script that fails - the prepared update stays
mkdir -p /tmp/pkg; printf "#!/bin/sh\necho update_script ran\nexit 1\n" >/tmp/pkg/update_script; chmod 0755 /tmp/pkg/update_script
up=/usr/local/tmp/update.tgz; tar -C /tmp/pkg -czf "$up" update_script
rc=$(fw "$up")
[ "$rc" = 1 ] && grep -q "update_script ran" /tmp/run.log && ok "the accepted update ran its update_script" || bad "accepted: rc $rc: $(tr "\n" " " </tmp/run.log)"
[ -x "$up-dir/update_script" ] && ok "the prepared update stays after the install failed" || bad "the prepared update was removed"
grep -q "removed after the failure" /tmp/run.log && bad "the accepted update was reported removed" || ok "nothing reported removed for it"
if [ "$f" != 0 ]; then
  echo "---- evidence (B-328): every run of fwinstall.sh, whole"; cat /tmp/runs.log
  echo "---- the upload directories and the update link"
  ls -laR /usr/local/tmp /userfs/tmp 2>&1; ls -la /usr/local/.firmwareUpdate /tmp/.runningFirmwareUpdate 2>&1
  echo "---- processes left"; for p in /proc/[0-9]*; do [ -r $p/cmdline ] && printf "%s %s\n" "${p#/proc/}" "$(tr "\0" " " <$p/cmdline)"; done
  echo "---- bash $BASH_VERSION, $(. /etc/os-release; echo $PRETTY_NAME)"
fi
[ "$f" = 0 ]'
  # file(1) and tar come from apt; no privileges, no network beyond the package mirror. A mirror
  # that does not answer once is tried three times (a CI run failed on a single "apt failed"),
  # and the last try's output is shown when all fail.
  apt='export DEBIAN_FRONTEND=noninteractive; for try in 1 2 3; do
  apt-get -qq update >/tmp/apt.log 2>&1 && apt-get -qq install -y --no-install-recommends file >>/tmp/apt.log 2>&1 && break
  [ $try = 3 ] && { echo "apt failed 3 times:"; tail -n 20 /tmp/apt.log; exit 3; }
  sleep $((try * 10))
done'
  if docker run --rm -v "$FW:/fw/fwinstall.sh:ro" debian:trixie-slim \
       sh -c "$apt; bash -c '$inner'" \
       >"$out" 2>&1; then
    sed 's/^/     /' "$out"
    ok "fwinstall.sh's cleanup (container)"
  else
    sed 's/^/     /' "$out"
    bad "fwinstall.sh's cleanup (container)"
  fi
  rm -f "$out"
fi

echo; [ "$fails" -eq 0 ] && { echo "lite-fwprepare-cleanup-test: all checks passed"; exit 0; }
echo "lite-fwprepare-cleanup-test: $fails check(s) failed"; exit 1
