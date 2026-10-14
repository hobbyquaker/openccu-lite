#!/bin/sh
# openccu-lite (task 346): lite-irqbalance hands irqbalance the IRQs whose affinity the kernel fixes
# as --banirq, and only those; the unit's drop-in runs it.
#   - a made-up /proc/irq: IRQ 3 and 7 take their mask back, IRQ 36 and 37 refuse the write (their
#     smp_affinity is /proc/version, which nobody, root included, can write), default_smp_affinity
#     and an IRQ without smp_affinity are skipped;
#   - an IRQ that takes the write keeps its mask;
#   - no refusing IRQ: irqbalance runs with --foreground alone and nothing is said;
#   - irqbalance.service's drop-in replaces ExecStart with the wrapper.
#
# Usage: sh scripts/testcases/lite-irqbalance-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-irqbalance"
DROPIN="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/irqbalance.service.d/20-lite.conf"
[ -f "$TOOL" ] || { echo "lite-irqbalance not found under $HERE"; exit 2; }
[ -r /proc/version ] || { echo "skip: no /proc/version here"; exit 0; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# irqbalance's stand-in prints its arguments
printf '#!/bin/sh\necho "irqbalance $*"\n' >"$T/irqbalance"
chmod +x "$T/irqbalance"

P="$T/irq"
mkdir -p "$P/3" "$P/7" "$P/36" "$P/37" "$P/40"
echo f >"$P/3/smp_affinity"
echo 2 >"$P/7/smp_affinity"
ln -s /proc/version "$P/36/smp_affinity"
ln -s /proc/version "$P/37/smp_affinity"
echo f >"$P/default_smp_affinity"
out=$(LITE_IRQ_PROC="$P" IRQBALANCE="$T/irqbalance" sh "$TOOL" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "it runs irqbalance" || bad "rc $rc: $out"
printf '%s\n' "$out" | grep -qx "irqbalance --foreground --banirq=36 --banirq=37" && ok "the refusing IRQs are banned, the others not" || bad "irqbalance's arguments: $out"
printf '%s\n' "$out" | grep -q "fixes the affinity of IRQ 36 37;" && ok "and it says which" || bad "no note: $out"
[ "$(cat "$P/3/smp_affinity")" = f ] && [ "$(cat "$P/7/smp_affinity")" = 2 ] && ok "a movable IRQ keeps its mask" || bad "masks changed: $(cat "$P/3/smp_affinity") $(cat "$P/7/smp_affinity")"

rm -f "$P/36/smp_affinity" "$P/37/smp_affinity"
out=$(LITE_IRQ_PROC="$P" IRQBALANCE="$T/irqbalance" sh "$TOOL" 2>&1)
[ "$out" = "irqbalance --foreground" ] && ok "without a refusing IRQ: --foreground alone, nothing said" || bad "without a refusing IRQ: $out"

if grep -qx 'ExecStart=' "$DROPIN" && grep -qx 'ExecStart=/usr/libexec/occu/lite-irqbalance' "$DROPIN"; then ok "the drop-in runs the wrapper"; else bad "the drop-in does not replace ExecStart with the wrapper"; fi

[ "$fails" = 0 ] && echo "all ok" || echo "$fails failed"
[ "$fails" = 0 ]
