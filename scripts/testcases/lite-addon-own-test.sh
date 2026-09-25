#!/bin/sh
# openccu-lite: lite-addon-own runs `occulited -addon-own <name>` before a confined addon's unit starts,
# passes on what it says and how it ended, and says nothing and lets the start go on when the
# occulited on the box is older than that subcommand. Fake occulited binaries in a temporary
# directory; nothing needs root.
#
# Usage: sh scripts/testcases/lite-addon-own-test.sh    (from the fork's checkout)
#        OCCULITED_OLD=/path/to/an/occulited/without/the/subcommand sh scripts/testcases/lite-addon-own-test.sh
#        also runs the wrapper against that real binary.
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SRC="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-addon-own"
[ -f "$SRC" ] || { echo "wrapper not found at $SRC"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

[ -x "$SRC" ] && ok "the wrapper is executable" || bad "the wrapper is not executable"
sh -n "$SRC" && ok "the wrapper parses" || bad "the wrapper does not parse"

# the wrapper with the binary's path pointed at the fake (a line of its own, never an environment
# variable: the step runs as root)
W="$T/lite-addon-own"
sed "s|^OCCULITED=/usr/bin/occulited\$|OCCULITED=$T/occulited|" "$SRC" > "$W"
grep -q "^OCCULITED=$T/occulited\$" "$W" || { echo "the wrapper does not name /usr/bin/occulited on a line of its own"; exit 2; }
if grep -q 'OCCULITED:-\|OCCULITED=\${' "$SRC"; then bad "the binary's path can be set from the environment"; else ok "the binary's path is fixed"; fi

fake() { printf '#!/bin/sh\n%s\n' "$1" > "$T/occulited"; chmod 755 "$T/occulited"; }

# an occulited with the subcommand: its journal line passes, its exit code too, and it got the name
fake 'echo "args: $*"; echo "addon-own: $2: 12 of 345 entries given to addon-$2 (30000) in 0.25 s"; exit 0'
out=$(sh "$W" redmatic 2>"$T/err"); rc=$?
[ "$rc" = 0 ] && ok "a current occulited: exit 0" || bad "a current occulited: exit $rc"
echo "$out" | grep -qx 'args: -addon-own redmatic' && ok "it runs occulited -addon-own <name>" || bad "arguments: $out"
echo "$out" | grep -q '12 of 345 entries given to addon-redmatic' && ok "the journal line is on stdout" || bad "stdout: $out"
[ ! -s "$T/err" ] && ok "nothing on stderr" || bad "stderr: $(cat "$T/err")"

# a problem: its exit code and its words
fake 'echo "addon-own: x: 1 error(s)"; echo "occulited: something went wrong" >&2; exit 1'
out=$(sh "$W" x 2>"$T/err"); rc=$?
[ "$rc" = 1 ] && ok "a failure keeps its exit code" || bad "failure: exit $rc"
echo "$out" | grep -q '1 error(s)' && ok "a failure's journal line is passed on" || bad "failure stdout: $out"
grep -q 'something went wrong' "$T/err" && ok "a failure's stderr is passed on" || bad "failure stderr: $(cat "$T/err")"

# an occulited older than the subcommand: Go's flag package refuses the flag with exit 2
fake 'echo "flag provided but not defined: -addon-own" >&2; echo "Usage of /usr/bin/occulited:" >&2; exit 2'
out=$(sh "$W" redmatic 2>"$T/err"); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ] && [ ! -s "$T/err" ]; then ok "an older occulited: nothing said, exit 0"; else bad "older: exit $rc, out '$out', err '$(cat "$T/err")'"; fi

# exit 2 for another reason is not mistaken for that
fake 'echo "panic: runtime error" >&2; exit 2'
sh "$W" redmatic >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 2 ] && grep -q 'panic: runtime error' "$T/err" && ok "another exit 2 is passed on" || bad "another exit 2: exit $rc, err $(cat "$T/err")"

# no occulited at all
rm -f "$T/occulited"
sh "$W" redmatic >"$T/out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -s "$T/out" ] && ok "no occulited: nothing said, exit 0" || bad "no occulited: exit $rc, $(cat "$T/out")"

# exactly one name
sh "$W" >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "no name: refused" || bad "no name: accepted"
sh "$W" a b >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "two names: refused" || bad "two names: accepted"

# the real thing, when a binary without the subcommand is given: it must not start a daemon
if [ -n "${OCCULITED_OLD:-}" ]; then
  cp "$OCCULITED_OLD" "$T/occulited" && chmod 755 "$T/occulited"
  out=$(timeout 20 sh "$W" redmatic 2>"$T/err"); rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ] && [ ! -s "$T/err" ]; then ok "a real older occulited: nothing said, exit 0"; else bad "real older occulited: exit $rc, out '$out', err '$(cat "$T/err")'"; fi
fi

[ "$fails" = 0 ] && echo "lite-addon-own: all cases passed" || { echo "lite-addon-own: $fails case(s) failed"; exit 1; }
