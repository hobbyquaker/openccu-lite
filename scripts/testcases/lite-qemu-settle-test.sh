#!/bin/sh
# openccu-lite (B-279): lite-qemu-test.sh judged an addon's unit 5 s after its install, and hm2mqtt
# (Node.js on an emulated CPU) was still "activating" then on two build rounds running - a flake
# that cost a QEMU run each time. Now the check is settle_snippet's one-liner in the guest: it
# polls "systemctl is-active" every 2 s while the unit is activating, up to a bound, and prints the
# state, the seconds waited and the unit's Result. Here the function is taken from the script
# (awk) and its snippet runs against a stub systemctl that answers from a script of states:
# active at once, activating then active, failed at once (no waiting on a failure), and a unit
# that never settles within the bound. The install check must read the snippet's answer.
#
# Usage: sh scripts/testcases/lite-qemu-settle-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S="$HERE/scripts/lite-qemu-test.sh"
[ -f "$S" ] || { echo "lite-qemu-test.sh not found at $S"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

awk '/^settle_snippet\(\) \{$/ {p=1} p {print} p && /^\}$/ {p=0}' "$S" >"$T/fn.sh"
grep -q '^settle_snippet() {$' "$T/fn.sh" && ok "settle_snippet found in lite-qemu-test.sh" || { bad "settle_snippet() not found in lite-qemu-test.sh"; echo "failures: $fails"; exit 1; }

# the stub: "is-active <unit>" answers the next line of $T/states (the last line repeats), and
# counts its calls; "show -p Result --value <unit>" answers $T/result
mkdir -p "$T/bin"
cat >"$T/bin/systemctl" <<EOS
#!/bin/sh
case "\$1" in
  is-active) n=\$(cat "$T/calls" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"$T/calls"
             l=\$(sed -n "\${n}p" "$T/states"); [ -n "\$l" ] || l=\$(tail -n 1 "$T/states"); echo "\$l";;
  show) cat "$T/result";;
  *) echo "stub: \$*" >&2; exit 2;;
esac
EOS
chmod +x "$T/bin/systemctl"
run() { # <bound> <result> <states...>: the snippet for addon-x.service, output and the seconds it took
  bound=$1; echo "$2" >"$T/result"; shift 2
  rm -f "$T/calls"; : >"$T/states"; for st in "$@"; do echo "$st" >>"$T/states"; done
  snippet=$(. "$T/fn.sh"; settle_snippet addon-x.service "$bound")
  t0=$(date +%s)
  out=$(PATH="$T/bin:$PATH" sh -c "$snippet" 2>&1)
  took=$(( $(date +%s) - t0 ))
  calls=$(cat "$T/calls")
}

run 60 success active
[ "$out" = "active after 0s, result success" ] && ok "active at once: '$out'" || bad "active at once: '$out'"
[ "$calls" = 1 ] && [ "$took" -le 1 ] && ok "and no waiting ($calls call, ${took}s)" || bad "active at once waited: $calls calls, ${took}s"

run 60 success activating activating activating active
[ "$out" = "active after 6s, result success" ] && ok "activating three times, then active: '$out'" || bad "activating then active: '$out'"
[ "$calls" = 4 ] && [ "$took" -ge 5 ] && [ "$took" -le 8 ] && ok "polled every 2 s ($calls calls, ${took}s)" || bad "activating then active: $calls calls, ${took}s"

run 60 exit-code failed
[ "$out" = "failed after 0s, result exit-code" ] && ok "failed at once, with the Result: '$out'" || bad "failed: '$out'"
[ "$calls" = 1 ] && ok "a failure is not waited for" || bad "a failure was polled $calls times"

run 4 success activating
[ "$out" = "activating after 4s, result success" ] && ok "never settling: the bound ends the wait: '$out'" || bad "never settling: '$out'"
[ "$calls" = 3 ] && [ "$took" -ge 3 ] && [ "$took" -le 6 ] && ok "within the bound ($calls calls, ${took}s)" || bad "never settling: $calls calls, ${took}s"

run 60 success inactive
[ "$out" = "inactive after 0s, result success" ] && ok "inactive is reported as it is" || bad "inactive: '$out'"

# the install check reads the snippet's answer, with a bound of at least 60 s, and the fixed sleep is gone
grep -q 'guest "\$(settle_snippet "addon-\$id.service" [6-9][0-9])"' "$S" && ok "the install check waits with settle_snippet, 60 s or more" || bad "the install check does not call settle_snippet with a bound of 60 s or more"
grep -q "\*'| active after'\*" "$S" && ok "and reads its answer" || bad "the install check does not read the snippet's 'active after'"
grep -q 'guest "sleep 5; systemctl is-active addon-\$id' "$S" && bad "the fixed 5 s sleep before the install check is still there" || ok "the fixed sleep before the install check is gone"

echo "failures: $fails"
[ "$fails" = 0 ]
