#!/bin/sh
# openccu-lite: every test the GitHub workflow lite-check.yml runs is run by the check job of
# lite-build.yml on the project's own runner as well, so a commit whose check is green there is
# not red on GitHub for a test the own runner never ran. The other way round is fine: the own
# runner runs more (the lighttpd tests in containers, buildroot's consistency check).
#
# Usage: sh scripts/testcases/lite-ci-parity-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
GH="$HERE/.github/workflows/lite-check.yml"
OWN="$HERE/.github/workflows/lite-build.yml"
[ -f "$GH" ] && [ -f "$OWN" ] || { echo "lite-check.yml or lite-build.yml not found under $HERE"; exit 2; }
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# the check job of lite-build.yml: from "  check:" to the next job at the same indentation
own_check=$(awk '/^  check:$/ {p=1; next} p && /^  [A-Za-z0-9_-]+:$/ {p=0} p' "$OWN")
[ -n "$own_check" ] && ok "lite-build.yml has a check job" || bad "no check job in lite-build.yml"

tests=$(grep -oE '(sh|bash) scripts/[A-Za-z0-9/_.-]+' "$GH" | sed 's/^[a-z]* //' | sort -u)
n=$(printf '%s\n' "$tests" | grep -c .)
[ "$n" -ge 10 ] && ok "lite-check.yml runs $n scripts" || bad "lite-check.yml runs only $n scripts: the pattern no longer matches"
missing=0
for t in $tests; do
  printf '%s\n' "$own_check" | grep -qE "(sh|bash) $t( |\$)" || { bad "lite-check.yml runs $t, lite-build.yml's check job does not"; missing=$((missing+1)); }
done
[ "$missing" -eq 0 ] && ok "every one of them runs in lite-build.yml's check job"

# the self-test: a test only GitHub runs is found
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf 'jobs:\n  check:\n    steps:\n      - run: sh scripts/a.sh\n  build:\n    steps:\n      - run: sh scripts/b.sh\n' >"$tmp/own"
t_check=$(awk '/^  check:$/ {p=1; next} p && /^  [A-Za-z0-9_-]+:$/ {p=0} p' "$tmp/own")
printf '%s\n' "$t_check" | grep -qE "(sh|bash) scripts/a.sh( |\$)" && ok "self-test: a script in the check job counts" || bad "self-test: the check job's script is not found"
printf '%s\n' "$t_check" | grep -qE "(sh|bash) scripts/b.sh( |\$)" && bad "self-test: a script of another job counts" || ok "self-test: a script of another job does not count"

echo; [ "$fails" -eq 0 ] && { echo "lite-ci-parity-test: all passed"; exit 0; }
echo "lite-ci-parity-test: $fails check(s) failed"; exit 1
