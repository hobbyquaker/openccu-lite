#!/usr/bin/env bash
# Validate the rootfs patch series openccu-lite applies (only OpenCCU's sections on what it builds
# and ships, lite_series.py checks that) against a rootfs staged from OpenCCU-Base pruned to
# openccu-base-paths.txt, with zero fuzz (tasks 329, 331, 335, 388, 389). The check-openccu-base
# target runs it; it is the series' only validation since task 389 retired the complete-stack
# refresh (update_patchfiles.sh, validate_patches.sh).
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $# == 2 ]] || die "usage: ${0##*/} PRISTINE_ROOTFS OPENCCU_BASE_SOURCE"
patch --version 2>/dev/null | grep -q '^GNU patch ' || die "GNU patch is required"
pristine_rootfs=$(cd "$1" && pwd -P)
openccu_base_source=$(cd "$2" && pwd -P)
python=${PYTHON:-python3}
tclsh=${TCLSH:-$(command -v tclsh || true)}
[[ -n $tclsh && -x $tclsh ]] || die "Tcl interpreter not found; set TCLSH=/absolute/path/to/tclsh"

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/openccu-validate-lite-patches.XXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT
state=${temp_dir}/rootfs
mkdir -p "$state"
cp -a "${pristine_rootfs}/." "$state/"

# Stage what openccu-base.mk's pre-build hook stages: the static firmware files next to the
# generated device types (a generated file wins). The ReGaHss hooks bin/hm_* are neither staged
# nor shipped (task 388).
mkdir -p "${state}/firmware"
(cd "${openccu_base_source}/firmware" && find . \( -type f -o -type l \) -print0) |
  while IFS= read -r -d '' source_file; do
    destination_file=${state}/firmware/${source_file#./}
    if [[ ! -e $destination_file && ! -L $destination_file ]]; then
      mkdir -p "$(dirname "$destination_file")"
      cp -a "${openccu_base_source}/firmware/${source_file#./}" "$destination_file"
    fi
  done

# and the WebUI's files for addons, as the pre-build hook stages them (task 331)
"${script_dir}/stage_lite_www.sh" "$openccu_base_source" "$state" "$tclsh" "$python"

"${script_dir}/create_patches.sh" --check

"$python" "${script_dir}/lite_series.py" "$script_dir"
applied=0
while IFS= read -r patch_name || [[ -n $patch_name ]]; do
  [[ -n $patch_name && $patch_name != \#* ]] || continue
  patch -s -t -d "$state" -p1 -F0 -N <"${script_dir}/${patch_name}" || \
    die "patch does not apply with zero fuzz: $patch_name"
  applied=$((applied + 1))
done <"${script_dir}/series"

for marker in \
  firmware/rftypes/rf_cfm_tw.xml \
  usr/lib/tcl8.2/homematic/homematic.tcl \
  www/config/devdescr/DEVDB.tcl \
  www/config/stringtable_de.txt \
  www/webui/js/lang/de/translate.lang.js \
  www/webui/js/lang/en/translate.lang.js; do
  [[ -s ${state}/${marker} ]] || die "patched rootfs is missing: $marker"
done

if find "$state" -type f -name '*.rej' -print -quit | grep -q .; then
  die "patched rootfs contains rejected hunks"
fi

for tcl_file in usr/lib/tcl8.2/homematic/homematic.tcl www/config/devdescr/DEVDB.tcl; do
  "$tclsh" /dev/stdin "${state}/${tcl_file}" <<'TCL'
set file_name [lindex $argv 0]
set channel [open $file_name r]
set contents [read $channel]
close $channel
if {![info complete $contents]} {
    puts stderr "incomplete Tcl script: $file_name"
    exit 1
}
TCL
done

printf 'Validated %s of %s patches against %s\n' \
  "$applied" "$(grep -Ec '^[^#[:space:]]' "${script_dir}/series")" "$pristine_rootfs"
