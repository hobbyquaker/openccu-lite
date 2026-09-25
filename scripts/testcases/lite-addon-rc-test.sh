#!/bin/sh
# openccu-lite: lite-addon-rc adopt (task 28.8, task 48) against a fake rc.d.
#
# adopt puts the addon-rc wrapper in front of an addon's rc.d script. The cases here are the ones a
# box meets: a first adoption, an update that copied the addon's own script over the wrapper, a
# wrapper that is already the image's current one, and an older wrapper copy left on the userfs by a
# previous image - which must be replaced, or a fixed wrapper never reaches a box that had the old
# one (seen on the Pi 4 on 2026-09-11: only the addon whose update had replaced its rc.d entry got
# the new wrapper).
#
# Usage: sh scripts/testcases/lite-addon-rc-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-addon-rc"
WRAPPER="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/addon-rc-wrapper"
[ -f "$TOOL" ] && [ -f "$WRAPPER" ] || { echo "lite-addon-rc or the wrapper not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
RCD="$T/rc.d"
mkdir -p "$RCD"

fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }
adopt() { OCCU_ADDON_RCD="$RCD" OCCU_ADDON_RC_WRAPPER="$WRAPPER" sh "$TOOL" adopt "$@" > "$T/out" 2>&1; }
is_current_wrapper() { cmp -s "$WRAPPER" "$RCD/$1"; }

# 1. a real script is adopted: it becomes <name>.script, the wrapper takes its place
printf '#!/bin/sh\necho real\n' > "$RCD/alpha"; chmod 755 "$RCD/alpha"
adopt alpha
if is_current_wrapper alpha && grep -q "echo real" "$RCD/alpha.script"; then ok "a real script is adopted"; else fail "a real script is adopted: $(cat "$T/out")"; fi

# 2. the current wrapper is left alone: nothing is written, nothing is said
before=$(ls -li "$RCD/alpha" | awk '{print $1}')
adopt alpha
after=$(ls -li "$RCD/alpha" | awk '{print $1}')
if [ "$before" = "$after" ] && [ ! -s "$T/out" ]; then ok "the current wrapper is left alone"; else fail "the current wrapper is left alone (inode $before -> $after): $(cat "$T/out")"; fi

# 3. an older wrapper copy is replaced by the current one, its .script stays as it is
{ echo '#!/bin/sh'; echo '# openccu-lite addon-rc wrapper (task 28.8). Do not edit.'; echo 'if [ -n "${INVOCATION_ID:-}" ]; then exec "$0.script" "$@"; fi'; } > "$RCD/beta"
chmod 755 "$RCD/beta"
printf '#!/bin/sh\necho beta\n' > "$RCD/beta.script"; chmod 755 "$RCD/beta.script"
adopt beta
if is_current_wrapper beta && grep -q "echo beta" "$RCD/beta.script" && grep -q "refreshed" "$T/out"; then ok "an older wrapper copy is refreshed"; else fail "an older wrapper copy is refreshed: $(cat "$T/out")"; fi
[ -x "$RCD/beta" ] && ok "the refreshed wrapper is executable" || fail "the refreshed wrapper is executable"
[ ! -e "$RCD/beta.new" ] && ok "no temporary file is left behind" || fail "no temporary file is left behind"

# 4. an update copied the addon's own script over the wrapper: adopted again, the stale .script goes
printf '#!/bin/sh\necho updated\n' > "$RCD/alpha"; chmod 755 "$RCD/alpha"
adopt alpha
if is_current_wrapper alpha && grep -q "echo updated" "$RCD/alpha.script"; then ok "a script copied over the wrapper is adopted again"; else fail "a script copied over the wrapper is adopted again: $(cat "$T/out")"; fi

# 5. adopt without names walks every entry, skips *.script, and leaves a non-executable file alone
printf '#!/bin/sh\necho gamma\n' > "$RCD/gamma"; chmod 644 "$RCD/gamma"
adopt
if [ ! -e "$RCD/gamma.script" ] && grep -q "echo gamma" "$RCD/gamma"; then ok "a disabled (non-executable) script is not adopted"; else fail "a disabled script is not adopted"; fi
[ ! -e "$RCD/alpha.script.script" ] && ok "*.script entries are skipped" || fail "*.script entries are skipped"

# 6. a wrapper without its script is reported and not touched further
cp "$WRAPPER" "$RCD/delta"; chmod 755 "$RCD/delta"
adopt delta
if grep -q "without its script" "$T/out" && is_current_wrapper delta; then ok "a wrapper without its script is reported"; else fail "a wrapper without its script is reported: $(cat "$T/out")"; fi

[ "$fails" = 0 ] && echo "lite-addon-rc: all cases passed" || { echo "lite-addon-rc: $fails case(s) failed"; exit 1; }
