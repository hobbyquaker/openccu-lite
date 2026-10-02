#!/bin/sh
# openccu-lite (task 310): lite-qemu-test.sh's addon e2e lost dev.35's and dev.36's runs to GitHub's
# unauthenticated rate limit (60 calls an hour per public address, which the guest shares with the
# runner and everything behind it). github_budget reads the address's budget before the e2e and
# waits for the reset when too little is left, within a bound. Here the function is taken from the
# script (awk) and runs against a stub curl that answers GET /rate_limit from a script of
# "<remaining> <seconds to the reset>" lines (the last one repeats) and a stub sleep that only
# counts: enough left at once, too little and a reset within the bound (it waits, then goes on),
# a reset past the bound (it fails and says when), an unreadable answer (it goes on).
#
# Usage: sh scripts/testcases/lite-qemu-ratelimit-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S="$HERE/scripts/lite-qemu-test.sh"
[ -f "$S" ] || { echo "lite-qemu-test.sh not found at $S"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

awk '/^github_budget\(\) \{$/ {p=1} p {print} p && /^\}$/ {p=0}' "$S" >"$T/fn.sh"
grep -q '^github_budget() {$' "$T/fn.sh" && ok "github_budget found in lite-qemu-test.sh" || { bad "github_budget() not found in lite-qemu-test.sh"; echo "failures: $fails"; exit 1; }

mkdir -p "$T/bin"
cat >"$T/bin/curl" <<EOS
#!/bin/sh
n=\$(cat "$T/calls" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"$T/calls"
l=\$(sed -n "\${n}p" "$T/answers"); [ -n "\$l" ] || l=\$(tail -n 1 "$T/answers")
case "\$l" in
  garbage) echo "<html>no</html>";;
  *) set -- \$l; printf '{"resources":{"core":{"limit":60,"remaining":%s,"reset":%s,"used":0}}}\n' "\$1" "\$((\$(date +%s) + \$2))";;
esac
EOS
cat >"$T/bin/sleep" <<EOS
#!/bin/sh
n=\$(cat "$T/sleeps" 2>/dev/null || echo 0); echo \$((n + \$1)) >"$T/sleeps"
EOS
chmod +x "$T/bin/curl" "$T/bin/sleep"

run() { # <need> <max wait> <answers...>: $out, $rc, $calls, $slept
  need=$1; max=$2; shift 2
  rm -f "$T/calls" "$T/sleeps"; : >"$T/answers"; for a in "$@"; do echo "$a" >>"$T/answers"; done
  out=$(PATH="$T/bin:$PATH" sh -c ". '$T/fn.sh'; qemu_check() { :; }; github_budget $need $max" 2>"$T/err")
  rc=$?
  calls=$(cat "$T/calls" 2>/dev/null || echo 0); slept=$(cat "$T/sleeps" 2>/dev/null || echo 0)
}

run 30 3900 "57 2000"
[ "$rc" = 0 ] && [ "$out" = "GitHub: 57 of 60 calls left (need 30)" ] && ok "enough left: '$out'" || bad "enough left: rc $rc '$out'"
[ "$slept" = 0 ] && [ "$calls" = 1 ] && ok "and no waiting" || bad "enough left, but slept ${slept}s in $calls calls"

run 30 3900 "5 100" "60 3600"
[ "$rc" = 0 ] && ok "too little, reset within the bound: goes on after the reset: '$out'" || bad "reset within the bound: rc $rc '$out'"
case "$out" in *"60 of 60 calls left after waiting"*) ok "and says it waited";; *) bad "no 'after waiting' in '$out'";; esac
[ "$slept" -ge 100 ] && [ "$slept" -le 180 ] && ok "waited for the reset (${slept}s)" || bad "waited ${slept}s for a reset 100 s away"
grep -q "waiting 10[0-9]s for the reset\|waiting 9[0-9]s for the reset" "$T/err" && ok "and announced the wait" || bad "the wait was not announced: $(cat "$T/err")"

run 30 3900 "5 5000"
[ "$rc" = 1 ] && ok "reset past the bound: refused" || bad "reset past the bound: rc $rc '$out'"
case "$out" in *"more than the 3900s"*) ok "and says when: '$out'";; *) bad "no reason in '$out'";; esac
[ "$slept" = 0 ] && ok "without waiting first" || bad "slept ${slept}s before refusing"

run 30 3900 "5 100" "5 3600"
[ "$rc" = 1 ] && ok "still too little after the reset (another user of the address): refused" || bad "still too little after the reset: rc $rc '$out'"

run 30 3900 garbage
[ "$rc" = 0 ] && case "$out" in *"could not be read; going on"*) true;; *) false;; esac && ok "unreadable answer: goes on: '$out'" || bad "unreadable answer: rc $rc '$out'"

run 0 0 "12 3000"
[ "$rc" = 0 ] && [ "$out" = "GitHub: 12 of 60 calls left (need 0)" ] && ok "the count after the e2e: '$out'" || bad "the count after the e2e: rc $rc '$out'"

# the e2e asks before its catalogue refresh, with room for the refresh and the installs
grep -q 'R=$(github_budget "${LITE_QEMU_GITHUB_NEED:-[2-9][0-9]}" "${LITE_QEMU_GITHUB_WAIT:-[0-9]*}") || fail' "$S" \
  && ok "the addon e2e checks the budget first (20 calls or more)" || bad "the addon e2e does not call github_budget with a need of 20 or more"
awk '/github_budget "\$\{LITE_QEMU_GITHUB_NEED/ {b=NR} /catalog\/refresh/ && !r {r=NR} END {exit !(b && r && b < r)}' "$S" \
  && ok "before the catalogue refresh" || bad "github_budget is not called before the catalogue refresh"

echo "failures: $fails"
[ "$fails" = 0 ]
