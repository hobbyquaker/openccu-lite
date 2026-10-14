#!/bin/sh
# openccu-lite (task 333): lite-kernel-dma-guard.sh against made-up build dirs:
#   - the Pi kernel as it is (dwc_otg, no DMA_BOUNCE_UNALIGNED_KMALLOC): passes;
#   - dwc_otg with CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC=y: fails and says why;
#   - the same option in a kernel without dwc_otg (the ova's): passes;
#   - the headers', firmware's and tools' dirs are not kernels;
#   - a build with BR2_LINUX_KERNEL=y and no kernel .config fails; one without a kernel passes.
#
# Usage: sh scripts/testcases/lite-kernel-dma-guard-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
G="$HERE/scripts/lite-kernel-dma-guard.sh"
[ -f "$G" ] || { echo "lite-kernel-dma-guard.sh not found at $G"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

kconf() { # <build dir> <linux dir name> <lines…>
	d="$1/$2"; shift 2
	mkdir -p "$d"
	printf '%s\n' "$@" >"$d/.config"
}
run() { out=$(sh "$G" "$@" 2>&1); rc=$?; }

kconf "$T/pi" linux-custom CONFIG_USB_DWCOTG=y CONFIG_USB_DWC2=y CONFIG_SWIOTLB=y '# CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC is not set'
kconf "$T/pi" linux-headers-custom CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC=y CONFIG_USB_DWCOTG=y
run "$T/pi"
[ "$rc" = 0 ] && ok "the Pi kernel as it is passes (the headers' dir is no kernel)" || bad "the Pi kernel: rc $rc: $out"

kconf "$T/bounce" linux-custom CONFIG_USB_DWCOTG=y CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC=y
run "$T/bounce"
[ "$rc" = 1 ] && ok "dwc_otg with DMA_BOUNCE_UNALIGNED_KMALLOC fails" || bad "dwc_otg with bouncing: rc $rc: $out"
printf '%s\n' "$out" | grep -q "B-91" && ok "and it names B-91's patch" || bad "no B-91 in: $out"

kconf "$T/module" linux-custom CONFIG_USB_DWCOTG=m CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC=y
run "$T/module"
[ "$rc" = 1 ] && ok "dwc_otg as a module counts too" || bad "dwc_otg=m with bouncing: rc $rc: $out"

kconf "$T/ova" linux-6.18.52 CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC=y CONFIG_SWIOTLB=y
run "$T/ova"
[ "$rc" = 0 ] && ok "a kernel without dwc_otg passes" || bad "a kernel without dwc_otg: rc $rc: $out"

mkdir -p "$T/empty/linux-firmware-20260810" "$T/empty/linux-tools"
echo CONFIG_USB_DWCOTG=y >"$T/empty/linux-firmware-20260810/.config"
printf 'BR2_LINUX_KERNEL=y\n' >"$T/br-kernel.config"
printf '# BR2_LINUX_KERNEL is not set\n' >"$T/br-none.config"
out=$(BR2_CONFIG="$T/br-kernel.config" sh "$G" "$T/empty" 2>&1); rc=$?
[ "$rc" = 1 ] && ok "a build with a kernel but no kernel .config fails" || bad "no kernel .config: rc $rc: $out"
out=$(BR2_CONFIG="$T/br-none.config" sh "$G" "$T/empty" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "a build without a kernel (lxc) passes" || bad "a build without a kernel: rc $rc: $out"

grep -v '^[[:space:]]*#' "$HERE/buildroot-external/board/lite/post-build.sh" | grep -q 'lite-kernel-dma-guard\.sh' \
	&& ok "the lite post-build runs the guard" || bad "the lite post-build does not run lite-kernel-dma-guard.sh"

[ "$fails" = 0 ] && echo "all ok" || echo "$fails failed"
[ "$fails" = 0 ]
