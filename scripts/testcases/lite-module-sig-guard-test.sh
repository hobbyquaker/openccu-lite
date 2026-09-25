#!/bin/sh
# openccu-lite: scripts/lite-module-sig-guard.sh against fake image roots, with a stand-in modinfo
# that reads the key out of the fake module file - an out-of-tree module signed with another key
# than the kernel's (the dev.21 image) must fail the build, a matching one must pass.
#
# Usage: sh scripts/testcases/lite-module-sig-guard-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
GUARD="$HERE/scripts/lite-module-sig-guard.sh"
[ -f "$GUARD" ] || { echo "lite-module-sig-guard.sh not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# modinfo -F sig_key <file>: the file's "key=" line, nothing for an unsigned one
printf '%s\n' '#!/bin/sh' '[ "$1" = -F ] && [ "$2" = sig_key ] || exit 9' 'sed -n "s/^key=//p" "$3"' > "$T/modinfo"
chmod +x "$T/modinfo"

mod() { mkdir -p "$(dirname "$T/root/$1")"; if [ -n "$2" ]; then echo "key=$2" > "$T/root/$1"; else echo "unsigned" > "$T/root/$1"; fi; }
run() { MODINFO="$T/modinfo" sh "$GUARD" "$T/root" > "$T/out" 2>&1; }
image() {
  rm -rf "$T/root"; mkdir -p "$T/root"
  mod lib/modules/6.18.34/kernel/net/ax25/ax25.ko.xz AA:01
  mod lib/modules/6.18.34/kernel/drivers/i2c/i2c-dev.ko.xz AA:01
}

rm -rf "$T/root"; mkdir -p "$T/root/etc"
if run; then ok "an image without /lib/modules (a container) passes"; else fail "no /lib/modules: $(cat "$T/out")"; fi

image
if run; then ok "a kernel without updates/ passes"; else fail "no updates/: $(cat "$T/out")"; fi

image; mod lib/modules/6.18.34/updates/generic_raw_uart.ko.xz AA:01; mod lib/modules/6.18.34/updates/eq3_char_loop.ko.xz AA:01
if run; then ok "updates/ signed with the kernel's key passes"; else fail "matching keys: $(cat "$T/out")"; fi

image; mod lib/modules/6.18.34/updates/generic_raw_uart.ko.xz BB:02; mod lib/modules/6.18.34/updates/eq3_char_loop.ko.xz AA:01
if ! run && grep -q 'generic_raw_uart.ko.xz is signed with .BB:02' "$T/out" && ! grep -q eq3_char_loop "$T/out"; then ok "a module signed with an old key fails, named"; else fail "old key: $(cat "$T/out")"; fi

image; mod lib/modules/6.18.34/updates/hb_rf_usb.ko.xz ""
if ! run && grep -q "hb_rf_usb.ko.xz is signed with 'nothing'" "$T/out"; then ok "an unsigned module fails"; else fail "unsigned: $(cat "$T/out")"; fi

image; mod lib/modules/6.18.34/kernel/fs/overlay.ko.xz CC:03; mod lib/modules/6.18.34/updates/x.ko.xz AA:01
if ! run && grep -q 'different keys' "$T/out"; then ok "in-tree modules with two keys fail"; else fail "two in-tree keys: $(cat "$T/out")"; fi

rm -rf "$T/root"; mod lib/modules/6.18.34/updates/x.ko.xz AA:01
if ! run && grep -q 'carry no signature' "$T/out"; then ok "updates/ without an in-tree module to compare with fails"; else fail "no in-tree: $(cat "$T/out")"; fi

image; mod lib/modules/6.18.34/updates/x.ko.xz AA:01; mod lib/modules/6.6.1/kernel/a.ko DD:04; mod lib/modules/6.6.1/updates/y.ko AA:01
if ! run && grep -q '6.6.1: /updates/y.ko\|6.6.1: updates/y.ko' "$T/out"; then ok "each kernel is checked against its own key"; else fail "two kernels: $(cat "$T/out")"; fi

image; mod lib/modules/6.18.34/updates/x.ko.xz AA:01
if ! MODINFO="$T/nonexistent-modinfo" sh "$GUARD" "$T/root" > "$T/out" 2>&1 && grep -q 'no modinfo on this host' "$T/out"; then ok "a modinfo that cannot run fails the check"; else fail "missing modinfo: $(cat "$T/out")"; fi

[ "$fails" -eq 0 ] && echo "all ok" || echo "$fails failed"
exit "$fails"
