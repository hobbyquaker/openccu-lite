#!/bin/sh
# openccu-lite: every out-of-tree kernel module in the image must be signed with the key of the
# kernel it ships with.
#
# The lite kernels enforce module signatures (CONFIG_MODULE_SIG_FORCE) with the key the kernel build
# generates. A kernel tree that is rebuilt from scratch (linux-dirclean) gets a new key, but buildroot
# does not rebuild the packages that build external modules (generic_raw_uart and the others under
# /lib/modules/<kernel>/updates) when the kernel is rebuilt: they keep the old signature, the kernel
# refuses them ("Key was rejected by service"), and the image boots without its radio drivers. The
# files are all there, so no check that looks for files notices.
#
# The check: for every /lib/modules/<kernel>/ of the image, the signing key of every module under
# updates/ (modinfo -F sig_key; kmod reads .ko.xz/.ko.gz/.ko.zst) must equal the key of the in-tree
# modules under kernel/, which must all agree. A kernel without modules, or without updates/, passes.
#
# Usage: scripts/lite-module-sig-guard.sh <target root>     exit 1 with one line per finding
#        MODINFO=<path> overrides the modinfo used (the test's stand-in)
set -u

ROOT=${1:?usage: lite-module-sig-guard.sh <target root>}
# The host's modinfo, not buildroot's: the post-build's PATH starts with output/host, whose kmod is
# built without xz and reads no .ko.xz (every key comes back empty). The first candidate that reads
# a key off an in-tree module of the image is taken.
MODINFO=${MODINFO:-}
pick_modinfo() {
	[ -n "$MODINFO" ] && return 0
	probe=$(find "$ROOT"/lib/modules/*/kernel -type f -name '*.ko*' 2>/dev/null | head -n 1)
	for m in /usr/sbin/modinfo /sbin/modinfo /usr/bin/modinfo "$(command -v modinfo 2>/dev/null)"; do
		[ -n "$m" ] && [ -x "$m" ] || continue
		if [ -z "$probe" ] || [ -n "$("$m" -F sig_key "$probe" 2>/dev/null)" ]; then
			MODINFO=$m
			return 0
		fi
	done
	return 1
}

[ -d "$ROOT/lib/modules" ] || exit 0
found=0
for kdir in "$ROOT"/lib/modules/*/; do
	[ -d "$kdir" ] || continue
	kver=$(basename "$kdir")
	[ -d "$kdir/updates" ] || continue
	ups=$(find "$kdir/updates" -type f -name '*.ko*' | sort)
	[ -n "$ups" ] || continue
	pick_modinfo
	if [ -z "$MODINFO" ] || [ ! -x "$MODINFO" ]; then
		echo "lite-module-sig-guard: ERROR: no modinfo on this host reads these modules (kmod with xz: ${MODINFO:-none found}), the module signatures of $kver cannot be checked" >&2
		exit 1
	fi
	# the kernel's own key, from its in-tree modules
	keys=$(find "$kdir/kernel" -type f -name '*.ko*' 2>/dev/null | while read -r f; do "$MODINFO" -F sig_key "$f" 2>/dev/null; done | sort -u)
	nkeys=$(printf '%s\n' "$keys" | grep -c .)
	if [ "$nkeys" -eq 0 ]; then
		echo "lite-module-sig-guard: ERROR: $kver: the in-tree modules carry no signature, the updates/ modules cannot be checked against them" >&2
		found=1
		continue
	fi
	if [ "$nkeys" -gt 1 ]; then
		echo "lite-module-sig-guard: ERROR: $kver: the in-tree modules carry $nkeys different keys:" $keys >&2
		found=1
		continue
	fi
	for f in $ups; do
		k=$("$MODINFO" -F sig_key "$f" 2>/dev/null)
		if [ "$k" != "$keys" ]; then
			echo "lite-module-sig-guard: ERROR: $kver: ${f#"$kdir"} is signed with '${k:-nothing}', the kernel's modules with '$keys' - the kernel refuses it (rebuild the package that builds it after a kernel rebuild)" >&2
			found=1
		fi
	done
done
[ "$found" -eq 0 ] && echo "lite-module-sig-guard: the out-of-tree modules carry the kernel's key"
exit "$found"
