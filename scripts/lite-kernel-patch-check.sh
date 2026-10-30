#!/bin/sh
# openccu-lite (task 332): warn when a configured kernel patch path applies nothing.
#
# buildroot's linux package applies BR2_LINUX_KERNEL_PATCH entry by entry: a directory with its
# *.patch files, a file as it is, a URL from the download. A directory that does not exist is
# taken for a file, apply-patches.sh finds no file of that name and returns 0 without a word -
# so a dead path is a silent no-op. OpenCCU's recovery_rpi{3,4,5}.config name
# board/<board>/kernel-patches, which has never existed: the recovery kernels carry none of the
# board's kernel patches. The recovery stays as OpenCCU's (task 332); this check only makes such a
# path visible in the build log. It never fails the build.
#
# Usage: scripts/lite-kernel-patch-check.sh <.config or defconfig> [<br2-external dir>]
#   Checks the config's BR2_LINUX_KERNEL_PATCH (the last assignment counts) and, when it builds
#   the recovery (BR2_PACKAGE_RECOVERY_SYSTEM=y), the recovery's: its Buildroot.config merged with
#   the configured fragment (package/recovery-system/external/configs/<fragment>).
#   <br2-external dir> replaces $(BR2_EXTERNAL_EQ3_PATH); default $BR2_EXTERNAL_EQ3_PATH, else this
#   checkout's buildroot-external. $(BR2_EXTERNAL_RECOVERY_SYSTEM_PATH) is its
#   package/recovery-system/external.
#   Prints one "WARNING: lite-kernel-patch-check: ..." line per entry that does not exist, is a
#   directory without a *.patch file, or cannot be resolved; nothing when every entry applies.
#   Exit 0 always - a warning, never a failure (2 only for a missing argument).
set -u
me=lite-kernel-patch-check
CONFIG=${1:-}
[ -n "$CONFIG" ] || { echo "usage: lite-kernel-patch-check.sh <config> [<br2-external dir>]" >&2; exit 2; }
EXT=${2:-${BR2_EXTERNAL_EQ3_PATH:-$(cd "$(dirname "$0")/.." && pwd)/buildroot-external}}
REC="$EXT/package/recovery-system/external"
warn() { echo "WARNING: $me: $*"; }

# value <name> <file...>: the last assignment of <name> across the files, quotes stripped
value() {
  n=$1; shift
  sed -n "s/^$n=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$@" 2>/dev/null | tail -n 1
}

# check <label> <value>
check() {
  label=$1
  for entry in $2; do
    case "$entry" in ftp://*|http://*|https://*) continue;; esac
    p=$(printf '%s' "$entry" | sed -e "s|\$(BR2_EXTERNAL_EQ3_PATH)|$EXT|g" -e "s|\$(BR2_EXTERNAL_RECOVERY_SYSTEM_PATH)|$REC|g")
    case "$p" in
      *'$('*|*'${'*) warn "$label: BR2_LINUX_KERNEL_PATCH entry $entry cannot be resolved here - not checked"; continue;;
      /*) ;;
      *) warn "$label: BR2_LINUX_KERNEL_PATCH entry $entry is not an absolute path - not checked"; continue;;
    esac
    if [ -d "$p" ]; then
      ls "$p"/*.patch >/dev/null 2>&1 || warn "$label: BR2_LINUX_KERNEL_PATCH entry $entry ($p) holds no *.patch - buildroot applies no kernel patch from it"
    elif [ ! -f "$p" ]; then
      warn "$label: BR2_LINUX_KERNEL_PATCH entry $entry ($p) does not exist - buildroot applies no kernel patch from it, and says nothing"
    fi
  done
}

if [ ! -r "$CONFIG" ]; then warn "cannot read $CONFIG - kernel patch paths not checked"; exit 0; fi
check "$(basename "$CONFIG")" "$(value BR2_LINUX_KERNEL_PATCH "$CONFIG")"

[ "$(value BR2_PACKAGE_RECOVERY_SYSTEM "$CONFIG")" = y ] || exit 0
frag=$(value BR2_PACKAGE_RECOVERY_SYSTEM_CONFIG_FRAGMENT_FILE "$CONFIG")
[ -n "$frag" ] || exit 0
if [ ! -r "$REC/configs/$frag" ]; then warn "recovery: cannot read $REC/configs/$frag - its kernel patch paths not checked"; exit 0; fi
check "recovery ($frag)" "$(value BR2_LINUX_KERNEL_PATCH "$REC/Buildroot.config" "$REC/configs/$frag")"
exit 0
