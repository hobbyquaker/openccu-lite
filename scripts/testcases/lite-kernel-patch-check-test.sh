#!/bin/sh
# openccu-lite (task 332): scripts/lite-kernel-patch-check.sh, the build's warning for a kernel
# patch path that applies nothing. The recovery configs' board/<board>/kernel-patches (OpenCCU's,
# kept as they are) must be named; a directory with patches, a patch file and a URL must not; a
# missing file, an empty directory and a path that cannot be resolved are named; nothing fails.
# And the Makefile's build runs it on the product's .config without letting it stop the build.
#
# Usage: sh scripts/testcases/lite-kernel-patch-check-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
CHECK="$HERE/scripts/lite-kernel-patch-check.sh"
EXT="$HERE/buildroot-external"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
run() { out=$(sh "$CHECK" "$@" 2>&1); rc=$?; nw=$(printf '%s\n' "$out" | grep -c '^WARNING: lite-kernel-patch-check: '); }

# the real recovery configs: every product that builds a recovery names its dead kernel-patches
for c in aarch64-rpi3 aarch64-rpi4 aarch64-rpi5 x86_64-ova rpi3 rpi4 rpi5; do
  frag=$(sed -n 's/^BR2_PACKAGE_RECOVERY_SYSTEM_CONFIG_FRAGMENT_FILE="\(.*\)"$/\1/p' "$EXT/configs/$c.config")
  board=$(sed -n 's|^BR2_LINUX_KERNEL_PATCH=".*/board/\([^/]*\)/kernel-patches"$|\1|p' "$EXT/package/recovery-system/external/configs/$frag")
  run "$EXT/configs/$c.config" "$EXT"
  case "$out" in
    *"WARNING: lite-kernel-patch-check: recovery ($frag): BR2_LINUX_KERNEL_PATCH entry \$(BR2_EXTERNAL_EQ3_PATH)/board/$board/kernel-patches ($EXT/board/$board/kernel-patches) does not exist"*)
      [ "$rc" = 0 ] && [ "$nw" = 1 ] && ok "$c: the recovery's board/$board/kernel-patches is named, exit 0" || bad "$c: rc $rc, $nw warnings: $out";;
    *) bad "$c: no warning for the recovery's kernel-patches: $out";;
  esac
done

# a .config as buildroot writes it, with the default empty value
printf 'BR2_LINUX_KERNEL=y\nBR2_LINUX_KERNEL_PATCH=""\n' >"$T/empty.config"
run "$T/empty.config" "$EXT"
[ "$rc" = 0 ] && [ -z "$out" ] && ok "no patch configured, no recovery: silent" || bad "empty: rc $rc: $out"

# valid entries: the board's patch directory, one patch file, a URL
p=$(ls "$EXT/board/rpi5/patches/linux/"*.patch | head -n 1)
printf 'BR2_LINUX_KERNEL_PATCH="$(BR2_EXTERNAL_EQ3_PATH)/board/rpi5/patches/linux %s https://example.org/x.patch"\n' "$p" >"$T/valid.config"
run "$T/valid.config" "$EXT"
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a directory with patches, a patch file and a URL: no warning" || bad "valid: rc $rc: $out"

# a missing file, an empty directory, an unresolvable variable, a relative path - one warning each
mkdir -p "$T/ext/board/x/empty"
printf 'BR2_LINUX_KERNEL_PATCH="$(BR2_EXTERNAL_EQ3_PATH)/board/x/missing.patch $(BR2_EXTERNAL_EQ3_PATH)/board/x/empty $(OTHER)/p board/x"\n' >"$T/bad.config"
run "$T/bad.config" "$T/ext"
[ "$rc" = 0 ] && [ "$nw" = 4 ] && ok "four dead entries, four warnings, exit 0" || bad "dead entries: rc $rc, $nw warnings: $out"
case "$out" in *"board/x/missing.patch ($T/ext/board/x/missing.patch) does not exist"*) ok "the missing file is named";; *) bad "missing file: $out";; esac
case "$out" in *"board/x/empty ($T/ext/board/x/empty) holds no *.patch"*) ok "the empty directory is named";; *) bad "empty directory: $out";; esac
case "$out" in *'$(OTHER)/p cannot be resolved'*) ok "an unknown variable is named, not guessed";; *) bad "unknown variable: $out";; esac
case "$out" in *"board/x is not an absolute path"*) ok "a relative path is named";; *) bad "relative path: $out";; esac

# the last assignment counts (a fragment over Buildroot.config, a .config edited twice)
printf 'BR2_LINUX_KERNEL_PATCH="/nonexistent/kernel-patches"\nBR2_LINUX_KERNEL_PATCH="%s"\n' "$EXT/board/rpi5/patches/linux" >"$T/twice.config"
run "$T/twice.config" "$EXT"
[ -z "$out" ] && ok "the last assignment counts" || bad "last assignment: $out"

# a recovery fragment that points at the board's patches (what OpenCCU could change to): no warning
mkdir -p "$T/rext/package/recovery-system/external/configs" "$T/rext/board/rpi5"
ln -s "$EXT/board/rpi5/patches" "$T/rext/board/rpi5/patches"
printf 'BR2_GLOBAL_PATCH_DIR="x"\n' >"$T/rext/package/recovery-system/external/Buildroot.config"
printf 'BR2_LINUX_KERNEL_PATCH="$(BR2_EXTERNAL_EQ3_PATH)/board/rpi5/patches/linux"\n' >"$T/rext/package/recovery-system/external/configs/recovery_x.config"
printf 'BR2_PACKAGE_RECOVERY_SYSTEM=y\nBR2_PACKAGE_RECOVERY_SYSTEM_CONFIG_FRAGMENT_FILE="recovery_x.config"\n' >"$T/rec.config"
run "$T/rec.config" "$T/rext"
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a recovery fragment with a valid patch path: no warning" || bad "valid recovery: rc $rc: $out"

# unreadable inputs warn, never fail
run "$T/nonexistent.config" "$EXT"
[ "$rc" = 0 ] && [ "$nw" = 1 ] && ok "an unreadable config warns, exit 0" || bad "unreadable config: rc $rc: $out"
printf 'BR2_PACKAGE_RECOVERY_SYSTEM=y\nBR2_PACKAGE_RECOVERY_SYSTEM_CONFIG_FRAGMENT_FILE="recovery_none.config"\n' >"$T/norec.config"
run "$T/norec.config" "$EXT"
[ "$rc" = 0 ] && [ "$nw" = 1 ] && ok "a missing recovery fragment warns, exit 0" || bad "missing fragment: rc $rc: $out"

# the build runs it before buildroot, on the product's .config, and goes on whatever it says
grep -q 'sh scripts/lite-kernel-patch-check\.sh \$(shell pwd)/build-\$(PRODUCT)/\.config \$(shell pwd)/\$(BUILDROOT_EXTERNAL) || true' "$HERE/Makefile" \
  && ok "the Makefile's build runs it on build-\$(PRODUCT)/.config, never failing" || bad "the Makefile does not run lite-kernel-patch-check.sh on the product's .config with || true"

[ "$fails" = 0 ] && { echo "lite-kernel-patch-check-test: all checks passed"; exit 0; }
echo "lite-kernel-patch-check-test: $fails failed"; exit 1
