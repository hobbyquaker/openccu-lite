#!/bin/sh
# openccu-lite (task 333): the Raspberry Pi kernel must map USB buffers directly, which B-91's
# dwc_otg patch assumes.
#
# B-91 (board/rpi5/patches/linux/0006-usb-dwc_otg-bounce-IN-transfers-…, docs/upstream-delta.md
# entry 53) takes IN transfers of a length that is not a multiple of 4 through the driver's align
# buffer and copies the received bytes into the URB's CPU buffer, below the DMA mapping layer. That
# is correct only while the URB buffer is mapped directly. With arm64's
# CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC (Linux 6.5) a small kmalloc buffer is bounced through swiotlb,
# and the unmap syncs the stale bounce slot over the bytes the patch copied: the device descriptors
# and hub status reads come back as garbage (the likely cause of raspberrypi/linux#5775). Raspberry
# Pi compiled the bouncing out in February 2024 (a07564753639); a kernel bump that brings it back
# must not ship without revisiting the patch.
#
# The check: every kernel .config of the build (<build dir>/linux-*/.config, not the headers,
# the firmware or the tools) that has the dwc_otg driver (CONFIG_USB_DWCOTG) must not have
# CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC=y. A kernel without dwc_otg passes. A build that has a kernel
# (BR2_LINUX_KERNEL=y in $BR2_CONFIG) but no kernel .config is an error, not a pass.
#
# Usage: scripts/lite-kernel-dma-guard.sh <build dir>     exit 1 with one line per finding
#        BR2_CONFIG=<buildroot .config> (the post-build has it) makes a missing kernel config an error
set -u

BUILD=${1:?usage: lite-kernel-dma-guard.sh <build dir>}
[ -d "$BUILD" ] || { echo "lite-kernel-dma-guard: $BUILD is not a directory" >&2; exit 2; }

found=0
checked=0
for c in "$BUILD"/linux-*/.config; do
	[ -f "$c" ] || continue
	case "$(basename "$(dirname "$c")")" in linux-headers-*|linux-firmware-*|linux-tools) continue ;; esac
	checked=$((checked + 1))
	grep -Eq '^CONFIG_USB_DWCOTG=[ym]$' "$c" || continue
	if grep -q '^CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC=y$' "$c"; then
		echo "lite-kernel-dma-guard: ERROR: $c has CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC=y beside dwc_otg: B-91's patch (board/rpi5/patches/linux/0006-…) copies below the DMA mapping layer and would deliver stale data for bounced buffers; revisit the patch (upstream-delta entry 53) before shipping this kernel" >&2
		found=1
	fi
done

if [ "$checked" = 0 ] && [ -n "${BR2_CONFIG:-}" ] && grep -q '^BR2_LINUX_KERNEL=y$' "$BR2_CONFIG" 2>/dev/null; then
	echo "lite-kernel-dma-guard: ERROR: the build has a kernel (BR2_LINUX_KERNEL=y) but no kernel .config under $BUILD/linux-*/" >&2
	exit 1
fi
exit "$found"
