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
#   - fwinstall.sh itself in a container (debian, no privileges): a file of no known type below
#     /usr/local/tmp and /userfs/tmp is removed with its directory, one elsewhere stays, and an
#     update that fwprepare accepted keeps its directory when the install after it fails. Skipped
#     with a note when docker is not available.
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
fw() { bash /fw/fwinstall.sh "$1" >/tmp/run.log 2>&1; echo $?; }
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
[ "$f" = 0 ]'
  # file(1) and tar come from apt; no privileges, no network beyond the package mirror
  if docker run --rm -v "$FW:/fw/fwinstall.sh:ro" debian:trixie-slim \
       sh -c "export DEBIAN_FRONTEND=noninteractive; apt-get -qq update >/dev/null 2>&1 && apt-get -qq install -y --no-install-recommends file >/dev/null 2>&1 || { echo 'apt failed'; exit 3; }; bash -c '$inner'" \
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
