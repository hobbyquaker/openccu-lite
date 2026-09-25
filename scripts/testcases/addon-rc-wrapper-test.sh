#!/bin/sh
# openccu-lite: the addon-rc wrapper's "inside or outside the unit" decision (task 28.8, task 48).
#
# The wrapper sits in rc.d in front of an addon's own script. From inside addon-<name>.service it
# runs the script; from anywhere else start/stop/restart go to systemd. "Inside" is the own cgroup
# (/proc/self/cgroup ending in /addon-<name>.service), not INVOCATION_ID - systemd-run's install
# scope sets that too, and the addon's update script then stopped the daemon behind the unit's
# back (task 48). Both sides are driven here with a fake cgroup file and fake id/systemctl/wget on
# PATH; nothing needs root and nothing on the box is touched.
#
# Usage: sh scripts/testcases/addon-rc-wrapper-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
WRAPPER="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/addon-rc-wrapper"
[ -f "$WRAPPER" ] || { echo "wrapper not found at $WRAPPER"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/rc.d" "$T/bin" "$T/tokens" "$T/policies"
LOG="$T/calls"

# the addon's own script, as lite-addon-rc leaves it beside the wrapper
printf '#!/bin/sh\necho "script $*" >> "%s"\n' "$LOG" > "$T/rc.d/hmm.script"
chmod 755 "$T/rc.d/hmm.script"
cp "$WRAPPER" "$T/rc.d/hmm"
chmod 755 "$T/rc.d/hmm"

# fakes: systemctl and wget only record their arguments; id answers what the case asks for
printf '#!/bin/sh\necho "systemctl $*" >> "%s"\n' "$LOG" > "$T/bin/systemctl"
printf '#!/bin/sh\necho "wget $*" >> "%s"\n' "$LOG" > "$T/bin/wget"
printf '#!/bin/sh\necho "${FAKE_UID:-0}"\n' > "$T/bin/id"
chmod 755 "$T/bin/systemctl" "$T/bin/wget" "$T/bin/id"

fails=0
check() { # name expected-substring
  if grep -q -- "$2" "$LOG" 2>/dev/null; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got: $(tr '\n' '|' < "$LOG" 2>/dev/null)"; fails=$((fails+1)); fi
}
absent() { # name unexpected-substring
  if grep -q -- "$2" "$LOG" 2>/dev/null; then echo "FAIL $1: unexpected '$2' in: $(tr '\n' '|' < "$LOG")"; fails=$((fails+1)); else echo "ok   $1"; fi
}
run() { # cgroup-file uid action
  : > "$LOG"
  OCCU_ADDON_CGROUP="$1" OCCU_ADDON_TOKEN_DIR="$T/tokens" OCCU_ADDON_POLICY_DIR="$T/policies" FAKE_UID="$2" PATH="$T/bin:$PATH" "$T/rc.d/hmm" "$3"
}

# 1. inside the unit (cgroup v2 line): the script runs, systemd is not called
printf '0::/system.slice/addon-hmm.service\n' > "$T/cg-unit"
run "$T/cg-unit" 0 stop
check  "inside the unit runs the script" "script stop"
absent "inside the unit does not call systemctl" "systemctl"

# 2. inside the install scope as root: the unit is stopped through systemctl, the script is not run
printf '0::/system.slice/occulite-addon-08e4e24f.scope\n' > "$T/cg-scope"
run "$T/cg-scope" 0 stop
check  "in the install scope, stop goes to systemd" "systemctl stop --no-pager -- addon-hmm.service"
absent "in the install scope, the script is not run" "script"
run "$T/cg-scope" 0 start
check  "in the install scope, start goes to systemd" "systemctl start --no-pager -- addon-hmm.service"

# 3. another addon's unit is outside too (a script of hmm's called from addon-other.service)
printf '0::/system.slice/addon-other.service\n' > "$T/cg-other"
run "$T/cg-other" 0 restart
check  "another addon's unit counts as outside" "systemctl restart --no-pager -- addon-hmm.service"

# 4. lighttpd's cgroup, confined addon (not root) with a token: occulited's addonctl is called
printf '0::/system.slice/lighttpd.service\n' > "$T/cg-web"
echo "deadbeef" > "$T/tokens/hmm"
run "$T/cg-web" 30001 restart
check  "confined, outside: the control token reaches occulited" "wget .*addonctl"
absent "confined, outside: the script is not run" "script"

# 5. cgroup v1 shape: several controller lines, the path is what counts
printf '12:pids:/system.slice/addon-hmm.service\n1:name=systemd:/system.slice/addon-hmm.service\n' > "$T/cg-v1"
run "$T/cg-v1" 0 stop
check  "cgroup v1 lines are read the same" "script stop"

# 6. no cgroup file at all: outside (the safe direction - systemd is asked, nothing is left behind)
run "$T/missing" 0 stop
check  "no cgroup information means outside" "systemctl stop --no-pager -- addon-hmm.service"

# 7. anything but start/stop/restart is passed through wherever it runs
run "$T/cg-scope" 0 info
check  "info passes through from the scope" "script info"

# 8. a plain /bin/sh script sees its rc.d name as $0 (addons derive their directory from
#    `basename $0`), its arguments unchanged, and its exit status is the wrapper's
printf '#!/bin/sh\necho "name=$(basename "$0") dir=$(basename "$(dirname "$0")") args=$#:$1:$2" >> "%s"\nexit 3\n' "$LOG" > "$T/rc.d/jp.script"
chmod 755 "$T/rc.d/jp.script"; cp "$WRAPPER" "$T/rc.d/jp"; chmod 755 "$T/rc.d/jp"
printf '0::/system.slice/addon-jp.service\n' > "$T/cg-jp"
: > "$LOG"
OCCU_ADDON_CGROUP="$T/cg-jp" OCCU_ADDON_TOKEN_DIR="$T/tokens" FAKE_UID=0 PATH="$T/bin:$PATH" "$T/rc.d/jp" start "two words"
rc=$?
check "a plain sh script sees its rc.d name as \$0" "name=jp dir=rc.d args=2:start:two words"
if [ "$rc" = 3 ]; then echo "ok   the script's exit status is passed on"; else echo "FAIL the script's exit status: expected 3, got $rc"; fails=$((fails+1)); fi
: > "$LOG"
OCCU_ADDON_CGROUP="$T/cg-scope" OCCU_ADDON_TOKEN_DIR="$T/tokens" FAKE_UID=0 PATH="$T/bin:$PATH" "$T/rc.d/jp" info
check "a plain sh script sees its rc.d name for other actions too" "name=jp dir=rc.d args=1:info:"

# 9. a symlinked script is executed directly, so readlink -f $0 still resolves into the addon
mkdir -p "$T/addon/bin"
printf '#!/bin/sh\necho "link0=$(basename "$0") real=$(basename "$(readlink -f "$0")")" >> "%s"\n' "$LOG" > "$T/addon/bin/red-service"
chmod 755 "$T/addon/bin/red-service"; ln -s "$T/addon/bin/red-service" "$T/rc.d/red.script"
cp "$WRAPPER" "$T/rc.d/red"; chmod 755 "$T/rc.d/red"
: > "$LOG"
OCCU_ADDON_CGROUP="$T/cg-scope" OCCU_ADDON_TOKEN_DIR="$T/tokens" FAKE_UID=0 PATH="$T/bin:$PATH" "$T/rc.d/red" info
check "a symlinked script is executed directly" "link0=red.script real=red-service"

# 10. a script for another interpreter is executed directly (the interpreter gets its path)
printf '#!/bin/sh\necho "interp $*" >> "%s"\n' "$LOG" > "$T/bin/interp"; chmod 755 "$T/bin/interp"
printf '#!%s\n' "$T/bin/interp" > "$T/rc.d/tcl.script"; chmod 755 "$T/rc.d/tcl.script"
cp "$WRAPPER" "$T/rc.d/tcl"; chmod 755 "$T/rc.d/tcl"
: > "$LOG"
OCCU_ADDON_CGROUP="$T/cg-scope" OCCU_ADDON_TOKEN_DIR="$T/tokens" FAKE_UID=0 PATH="$T/bin:$PATH" "$T/rc.d/tcl" info
check "another interpreter runs the script file directly" "interp $T/rc.d/tcl.script info"

# 11. init of a confined addon (occulited's policy drop-in says User=addon-hmm): from root outside
#     the unit - S55InitAddons' run-parts, an installer's scope - nothing runs and the exit is 0; the
#     unit runs it as the addon's user (in_unit), and so does the addon's user itself from anywhere.
#     A root addon (no User= line, or no policy) keeps its init from run-parts.
printf '# mode=confined uid=30001\n[Service]\nUser=addon-hmm\nGroup=addon-hmm\n' > "$T/policies/hmm.conf"
run "$T/cg-scope" 0 init; rc=$?
absent "confined: init from root outside the unit runs nothing" "script"
[ "$rc" = 0 ] && echo "ok   confined: init from root outside the unit exits 0" || { echo "FAIL confined: init from root outside the unit exits $rc"; fails=$((fails+1)); }
run "$T/missing" 0 init
absent "confined: init from root without cgroup information runs nothing" "script"
run "$T/cg-unit" 0 init
check  "confined: init inside the unit runs the script" "script init"
run "$T/cg-web" 30001 init
check  "confined: init as the addon's user runs the script wherever it is" "script init"
printf '# mode=root\n' > "$T/policies/hmm.conf"
run "$T/cg-scope" 0 init
check  "root policy: init from run-parts runs the script as before" "script init"
rm -f "$T/policies/hmm.conf"
run "$T/cg-scope" 0 init
check  "no policy: init from run-parts runs the script as before" "script init"
run "$T/cg-scope" 0 info
check  "info still passes through (occulited runs it as the addon's user itself)" "script info"

[ "$fails" = 0 ] && echo "addon-rc-wrapper: all cases passed" || { echo "addon-rc-wrapper: $fails case(s) failed"; exit 1; }
