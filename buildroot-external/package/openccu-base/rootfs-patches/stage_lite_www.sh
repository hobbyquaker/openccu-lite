#!/usr/bin/env bash
# Stage the part of the WebUI's www/ tree that openccu-lite ships for addons (task 331) into a
# rootfs, the way OpenCCU's classic build stages it, before the rootfs patches run:
#
#   www/config/img/devices/              the device pictures (50 and 250 px, coupling/), copied
#                                        from src/webui/www/ as the classic build copies them
#   www/config/devdescr/DEVDB.tcl        generated from src/webui/www_source/config/devdescr/ by
#                                        upstream's create_devdb_tcl.tcl and utf82ansi.py
#   www/config/stringtable_de.txt        copied from src/webui/www/
#   www/webui/js/lang/<lang>/translate.lang*.js
#                                        copied from src/webui/www/
#
# The generator reads the descriptions in the order glob returns them, which is the file system's;
# it runs here with a glob that sorts, so DEVDB.tcl is the same from build to build. Its content is
# the classic build's either way. lite_series.py keeps the rootfs patches' sections for exactly
# these files, and the lite post-build guard allows exactly them under /www.
#
# Usage: stage_lite_www.sh OPENCCU_BASE_SOURCE ROOTFS TCLSH PYTHON
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $# == 4 ]] || die "usage: ${0##*/} OPENCCU_BASE_SOURCE ROOTFS TCLSH PYTHON"
source_dir=$(cd "$1" && pwd -P)
rootfs=$2
tclsh=$3
python=$4
webui_www=${source_dir}/src/webui/www
www_source=${source_dir}/src/webui/www_source

for required in \
  "${webui_www}/config/img/devices/250" \
  "${webui_www}/config/img/devices/50" \
  "${webui_www}/config/stringtable_de.txt" \
  "${www_source}/config/devdescr" \
  "${www_source}/create_devdb_tcl.tcl" \
  "${www_source}/utf82ansi.py"; do
  [[ -e $required ]] || die "openccu-base source lacks ${required#"${source_dir}"/}"
done

rm -rf "${rootfs}/www/config/img/devices" "${rootfs}/www/config/devdescr" \
  "${rootfs}/www/config/stringtable_de.txt" "${rootfs}/www/webui/js/lang"
mkdir -p "${rootfs}/www/config/img" "${rootfs}/www/config/devdescr" "${rootfs}/www/webui/js/lang"
cp -R "${webui_www}/config/img/devices" "${rootfs}/www/config/img/devices"
cp "${webui_www}/config/stringtable_de.txt" "${rootfs}/www/config/stringtable_de.txt"
found=0
for lang_dir in "${webui_www}/webui/js/lang"/*/; do
  lang=$(basename "$lang_dir")
  for file in "$lang_dir"translate.lang*.js; do
    [[ -f $file ]] || continue
    mkdir -p "${rootfs}/www/webui/js/lang/${lang}"
    cp "$file" "${rootfs}/www/webui/js/lang/${lang}/"
    found=$((found + 1))
  done
done
[[ $found -gt 0 ]] || die "no translate.lang*.js under src/webui/www/webui/js/lang/"

work=$(mktemp -d "${TMPDIR:-/tmp}/openccu-devdb.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "${work}/config"
cp -R "${www_source}/config/devdescr" "${work}/config/devdescr"
cp "${www_source}/create_devdb_tcl.tcl" "${www_source}/utf82ansi.py" "$work/"
cat >"${work}/sorted.tcl" <<'TCL'
rename glob openccu_lite_glob
proc glob {args} { lsort [openccu_lite_glob {*}$args] }
source create_devdb_tcl.tcl
TCL
(cd "$work" && "$tclsh" sorted.tcl && "$python" ./utf82ansi.py DEVDB.tcl)
[[ -s ${work}/DEVDB.tcl ]] || die "create_devdb_tcl.tcl wrote no DEVDB.tcl"
cp "${work}/DEVDB.tcl" "${rootfs}/www/config/devdescr/DEVDB.tcl"

find "${rootfs}/www/config/img/devices" "${rootfs}/www/config/devdescr" \
  "${rootfs}/www/config/stringtable_de.txt" "${rootfs}/www/webui/js/lang" -type d -exec chmod 0755 {} +
find "${rootfs}/www/config/img/devices" "${rootfs}/www/config/devdescr" \
  "${rootfs}/www/config/stringtable_de.txt" "${rootfs}/www/webui/js/lang" -type f -exec chmod 0644 {} +
printf 'stage_lite_www: %s pictures, DEVDB.tcl from %s descriptions, %s translation files\n' \
  "$(find "${rootfs}/www/config/img/devices" -type f -name '*.png' | wc -l)" \
  "$(find "${work}/config/devdescr" -type f -name '*.tcl' | wc -l)" "$found"
