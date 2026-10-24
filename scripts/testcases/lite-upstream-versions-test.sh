#!/bin/sh
# openccu-lite: scripts/lite-upstream-versions.py offline, against fixtures instead of upstream:
# the fork's own pins are found; the rule for "current" per component (buildroot point release and
# series, the Raspberry Pi kernel tag and rpi3 = rpi4, the VM kernel's series, newer and end of life,
# U-Boot and rpi3 = rpi4, the Raspberry Pi firmware built with our kernel tag and the newest one, the
# rpi-eeprom default channel; the end of support of buildroot's series and of the kernel series:
# iseol, gone from releases.json, the projected dates within six months, unreadable pages); findings exit 0 with ::warning:: lines and a yellow badge, errors exit
# 2 (pin) or 3 (upstream) with a grey badge - never green; the report pages and the job summary.
#
# Usage: sh scripts/testcases/lite-upstream-versions-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
PY="$HERE/scripts/lite-upstream-versions.py"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
C=buildroot-external/configs
FW_OURS=1111111111111111111111111111111111111111
K_OLD=aaaa000000000000000000000000000000000000
K_NEW=bbbb000000000000000000000000000000000000

# a tree: <buildroot> <ova kernel> <rpi tag> <u-boot> <firmware commit> <eeprom date>
tree() {
  rm -rf "$tmp/root"; mkdir -p "$tmp/root/$C" "$tmp/root/buildroot-external/package/rpi-eeprom"
  printf 'BUILDROOT_VERSION=%s\nBUILDROOT_SHA256=x\n' "$1" >"$tmp/root/Makefile"
  printf 'BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="%s"\n' "$2" >"$tmp/root/$C/x86_64-ova.config"
  for p in rpi3 rpi4; do
    { printf 'BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION="https://github.com/raspberrypi/linux/archive/%s.tar.gz"\n' "$3"
      printf 'BR2_PACKAGE_RPI_FIRMWARE_VERSION="%s"\nBR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE="%s"\n' "$5" "$4"
    } >"$tmp/root/$C/aarch64-$p.config"
  done
  echo 'BR2_PACKAGE_RPI_EEPROM=y' >>"$tmp/root/$C/aarch64-rpi4.config"
  printf 'ifeq ($(BR2_PACKAGE_RPI_EEPROM_RPI4),y)\n  RPI_EEPROM_FIRMWARE_PATH = firmware-2711/stable/pieeprom-%s.bin\n' "$6" \
    >"$tmp/root/buildroot-external/package/rpi-eeprom/rpi-eeprom.mk"
}
set_cfg() { # <product> <variable> <value>
  sed -i "s|^$2=.*|$2=\"$3\"|" "$tmp/root/$C/$1.config"
}
tags() { # <fixture> <tag>... (an annotated tag's ^{} line as well)
  f=$1; shift; for t in "$@"; do printf 'aaaa\trefs/tags/%s\nbbbb\trefs/tags/%s^{}\n' "$t" "$t" >>"$tmp/fx/$f"; done
}
rpi_tag() { # <tag> <commit> <kernel version>
  printf '%s\trefs/tags/%s\n' "$2" "$1" >>"$tmp/fx/rpi-tags.txt"
  printf '# SPDX\nVERSION = %s\nPATCHLEVEL = %s\nSUBLEVEL = %s\nEXTRAVERSION =\n' \
    "$(echo "$3" | cut -d. -f1)" "$(echo "$3" | cut -d. -f2)" "$(echo "$3" | cut -d. -f3)" >"$tmp/fx/rpi-Makefile-$1"
}
fw() { # <tag or commit> <linux commit> [tag]
  echo "$2" >"$tmp/fx/firmware-git_hash-$1"
  [ "${3:-}" = tag ] && printf 'cccc\trefs/tags/%s\n' "$1" >>"$tmp/fx/firmware-tags.txt"
  return 0
}
releases() { # moniker:version:eol ...
  { printf '{"releases": ['; sep=""
    for r in "$@"; do
      IFS=: read -r m v e <<EOF
$r
EOF
      printf '%s{"moniker": "%s", "version": "%s", "iseol": %s}' "$sep" "$m" "$v" "$e"; sep=", "
    done; printf ']}\n'; } >"$tmp/fx/releases.json"
}
base() { # a current world
  tree 2026.08.1 6.18.58 stable_20260911 2026.10 $FW_OURS 2026-09-23
  rm -rf "$tmp/fx"; mkdir -p "$tmp/fx"
  tags buildroot-tags.txt 2026.02 2026.02.6 2026.05 2026.05.2 2026.08-rc1 2026.08 2026.08.1 2026.11-rc1
  tags uboot-tags.txt v2026.04 v2026.07 v2026.10-rc5 v2026.10
  releases mainline:7.3:false stable:7.2.12:false longterm:6.18.58:false longterm:6.12.114:false
  rpi_tag stable_20260609 $K_OLD 6.18.34; rpi_tag stable_20260911 $K_NEW 6.18.50
  fw 1.20260610 $K_OLD tag; fw 1.20260915 $K_NEW tag; fw $FW_OURS $K_NEW
  printf '# firmware-2711\n2026-10-23  1  f56d  latest  2\n2026-09-23  1  4564  default  1\n2026-05-17  1  2248  default  1\n' \
    >"$tmp/fx/eeprom-versions.txt"
  kernel_eol "Dec, 2028"
  br_eol "June 2027"
  printf 'ref: refs/heads/rpi-6.18.y\tHEAD\naeadd6ed\tHEAD\n' >"$tmp/fx/rpi-head.txt"
}
kernel_eol() { # <projected EOL of 6.18> - kernel.org's longterm table
  printf '<table><caption>Longterm release kernels</caption>\n<thead><tr><th class="head">Version</th><th>Maintainer</th><th>Released</th><th>Projected EOL</th></tr></thead>\n<tbody valign="top">\n<tr><td>6.18</td>\n<td>Greg &amp; Sasha</td>\n<td>2025-11-30</td>\n<td>%s</td>\n</tr>\n<tr><td>6.12</td>\n<td>Greg</td>\n<td>2024-11-17</td>\n<td>Dec, 2028</td>\n</tr>\n</tbody></table>\n' "$1" >"$tmp/fx/releases.html"
}
br_eol() { # <end of support of 2026.08> [<of the LTS 2025.02>] - buildroot.org's download table, with a commented-out row
  printf '<tr>\n  <th>Stable</th>\n  <th>2026.08.1.x</th>\n  <td>%s</td>\n</tr>\n<!--\n<tr><th>Stable</th><th>2026.08.x</th><td>January 2020</td></tr>\n-->\n<tr><th>Old stable</th><th>2026.05.x</th><td>September 2026</td></tr>\n<tr><th>Long-term support</th><th>2025.02.x</th><td>%s</td></tr>\n' "$1" "${2:-March 2028}" >"$tmp/fx/buildroot-download.html"
}
run() { rm -rf "$tmp/sum" "$tmp/site"; python3 "$PY" --root "$tmp/root" --fixtures "$tmp/fx" --today 2026-10-24 --summary "$tmp/sum" --site "$tmp/site" >"$tmp/out" 2>&1; echo $?; }
expect() { # <what> <exit code> <badge message> [text in the output]
  rc=$(run)
  if [ "$rc" = "$2" ] && grep -qF "\"message\": \"$3\"" "$tmp/site/badge.json" 2>/dev/null \
     && { [ -z "${4:-}" ] || grep -qF -- "$4" "$tmp/out"; }; then ok "$1"
  else bad "$1: exit $rc (want $2), badge $(cat "$tmp/site/badge.json" 2>/dev/null) (want '$3')${4:+, want '$4'}"; sed 's/^/     /' "$tmp/out"; fi
}
UPD="updates available"

# the fork's own pins are found and understood
python3 - "$HERE" "$PY" >"$tmp/pins" 2>&1 <<'EOF'
import importlib.util, re, sys
s = importlib.util.spec_from_file_location("v", sys.argv[2]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
root = sys.argv[1]
print("buildroot", m.pin(root, "Makefile", r"^BUILDROOT_VERSION\s*:?=\s*(\S+)\s*$", "x"))
print("rpi", " ".join(m.rpi_pins(root).values()))
print("vm", m.pin(root, m.cfg(m.VM), r'^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="([^"]+)"', "x"))
for p in m.RPI:
    print("uboot", m.pin(root, m.cfg(p), r'^BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE="([^"]+)"', "x"))
    print("firmware", m.pin(root, m.cfg(p), r'^BR2_PACKAGE_RPI_FIRMWARE_VERSION="([0-9a-f]{40})"', "x"))
mk = open(root + "/buildroot-external/package/rpi-eeprom/rpi-eeprom.mk").read()
print("eeprom", re.search(r"^\s*RPI_EEPROM_FIRMWARE_PATH\s*=\s*firmware-2711/\S*pieeprom-(\d{4}-\d{2}-\d{2})\.bin", mk, re.M).group(1))
EOF
[ $? -eq 0 ] && [ "$(grep -c '^uboot 20' "$tmp/pins")" -eq 2 ] && [ "$(grep -c '^firmware [0-9a-f]' "$tmp/pins")" -eq 2 ] \
  && grep -q '^rpi stable_[0-9]* stable_' "$tmp/pins" && grep -q '^eeprom 20' "$tmp/pins" && grep -q '^vm [0-9]' "$tmp/pins" \
  && ok "the fork's pins: buildroot, kernels, U-Boot, firmware, rpi-eeprom" \
  || { bad "the fork's pins are not found"; sed 's/^/     /' "$tmp/pins"; }

base; expect "all current: exit 0, green" 0 "up to date" "all current"
grep -q '::warning::\|::error::' "$tmp/out" && bad "no annotations when current" || ok "no annotations when current"
grep -qF '| Raspberry Pi firmware (rpi3, rpi4) | 111111111111 (stable_20260911) | 1.20260915 (stable_20260911) | no published support period | up to date |' "$tmp/sum" \
  && grep -qF '| buildroot | 2026.08.1 | 2026.08.1 | 2027-06 | up to date |' "$tmp/sum" \
  && grep -qF '| VM kernel (ova) | 6.18.58 | 6.18.58 | 2028-12 | up to date |' "$tmp/sum" \
  && grep -qF '**All current.**' "$tmp/sum" && ok "the job summary" || { bad "the job summary"; cat "$tmp/sum"; }
grep -qF '"color": "brightgreen"' "$tmp/site/badge.json" && ok "badge green" || bad "badge green"
grep -q '<html lang="de">' "$tmp/site/index.html" && grep -qF 'aktuell' "$tmp/site/index.html" \
  && grep -q '<html lang="en">' "$tmp/site/en.html" && grep -qF 'up to date' "$tmp/site/en.html" \
  && grep -qF 'href="en.html"' "$tmp/site/index.html" && grep -qF 'prefers-color-scheme:dark' "$tmp/site/index.html" \
  && [ "$(grep -c '<tr><td>' "$tmp/site/en.html")" -eq 6 ] && grep -qF 'GRUB (VM) and Go come with buildroot' "$tmp/site/en.html" \
  && grep -qF '<th>Support bis</th>' "$tmp/site/index.html" && grep -qF 'kein veröffentlichter Supportzeitraum' "$tmp/site/index.html" \
  && ok "the report pages: German and English, six components, the support column, dark mode" || bad "the report pages"

base; tags buildroot-tags.txt 2026.08.2; expect "buildroot: a newer point release" 0 "$UPD" "::warning::update available - buildroot: buildroot 2026.08.2 is out"
grep -qF '"color": "yellow"' "$tmp/site/badge.json" && ok "badge yellow" || bad "badge yellow"
grep -qF 'Update verfügbar' "$tmp/site/index.html" && grep -qF 'buildroot 2026.08.2 ist erschienen' "$tmp/site/index.html" \
  && ok "the German page names the finding" || bad "the German page names the finding"
base; tags buildroot-tags.txt 2026.11; expect "buildroot: a newer series" 0 "$UPD" "buildroot series 2026.11 is out"
base; tree 2026.02.6 6.18.58 stable_20260911 2026.10 $FW_OURS 2026-09-23; expect "buildroot: a newer series for an LTS too" 0 "$UPD" "buildroot series 2026.05 is out"
base; tags buildroot-tags.txt 2026.11-rc2; expect "buildroot: release candidates do not count" 0 "up to date"

base; rpi_tag stable_20261020 cccc000000000000000000000000000000000000 6.18.60
expect "rpi kernel: a newer stable_ tag" 0 "$UPD" "raspberrypi/linux stable_20261020 (kernel 6.18.60) is out"
base; set_cfg aarch64-rpi3 BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION https://github.com/raspberrypi/linux/archive/stable_20260609.tar.gz
expect "rpi kernel: rpi3 and rpi4 on different tags" 0 "$UPD" "rpi3 and rpi4 pin different kernels"
grep -qF 'rpi3: firmware 111111111111 belongs to stable_20260911, the kernel is stable_20260609' "$tmp/out" \
  && ok "firmware: a firmware that does not belong to the kernel" || bad "firmware: a firmware that does not belong to the kernel"

base; releases mainline:7.3:false longterm:6.18.59:false; expect "VM kernel: a newer release of our series" 0 "$UPD" "kernel 6.18.59 is out (we pin 6.18.58)"
base; releases mainline:7.3:false longterm:7.2.1:false longterm:6.18.58:true
expect "VM kernel: our series marked iseol is end of life, not a failed check" 0 "$UPD" "kernel 6.18 is end of life (marked EOL on kernel.org), move to the next longterm (7.2.1)"
grep -qF '| VM kernel (ova) | 6.18.58 | 6.18.58 | end of life | update available |' "$tmp/sum" && ok "VM kernel: the support column says end of life" || bad "VM kernel: the support column says end of life"
base; releases mainline:7.3:false longterm:7.2.1:false longterm:6.12.114:false
expect "VM kernel: our series gone from releases.json is end of life, not a failed check" 0 "$UPD" "kernel 6.18 is end of life (no longer listed on kernel.org), move to the next longterm (7.2.1)"
base; releases mainline:7.3:false longterm:7.2.1:false longterm:6.18.58:false; kernel_eol "Apr, 2027"
expect "VM kernel: the projected EOL within six months" 0 "$UPD" "VM kernel (ova): kernel 6.18 reaches its end of support in 6 month(s) (2027-04), plan the move to 7.2.1"
grep -qF 'Raspberry Pi kernel (rpi3, rpi4): kernel 6.18 reaches its end of support in 6 month(s)' "$tmp/out" \
  && ok "Raspberry Pi kernel: its series' projected EOL within six months" || bad "Raspberry Pi kernel: its series' projected EOL within six months"
base; kernel_eol "May, 2027"; expect "VM kernel: the projected EOL seven months ahead is a date only" 0 "up to date"
base; kernel_eol "Jan, 2026"; expect "VM kernel: a projected EOL in the past" 0 "$UPD" "kernel 6.18 is past its end of support (2026-01)"
base; echo '<html>no table here</html>' >"$tmp/fx/releases.html"
expect "kernel.org's releases page unparsable: EOL unknown, not a failed check" 0 "up to date" "projected end of life unknown"
grep -qF '| VM kernel (ova) | 6.18.58 | 6.18.58 | unknown | up to date |' "$tmp/sum" && grep -qF '<td>unbekannt</td>' "$tmp/site/index.html" \
  && ok "the support column says unknown" || bad "the support column says unknown"
base; rm "$tmp/fx/releases.html"; expect "kernel.org's releases page unreachable: EOL unknown, not a failed check" 0 "up to date" "projected end of life unknown"
base; printf 'ref: refs/heads/rpi-7.1.y\tHEAD\n' >"$tmp/fx/rpi-head.txt"
expect "Raspberry Pi kernel: raspberrypi's default branch on a newer series is a note" 0 "up to date" "default branch moved to rpi-7.1.y (ours: 6.18)"
base; rm "$tmp/fx/rpi-head.txt"; expect "raspberrypi/linux's HEAD unreachable: exit 3" 3 "check failed"

# the days count from 2026-10-24 (run's --today) to the last day of the month named
base; br_eol "October 2026"; expect "buildroot: a quarterly series within two weeks of its end of support" 0 "$UPD" "buildroot 2026.08 reaches its end of support in 7 day(s) (2026-10)"
base; br_eol "November 2026"; expect "buildroot: a quarterly series 37 days ahead is a date only (the commented-out row is ignored)" 0 "up to date"
grep -qF '| buildroot | 2026.08.1 | 2026.08.1 | 2026-11 | up to date |' "$tmp/sum" && ok "buildroot: the support column" || bad "buildroot: the support column"
base; br_eol "September 2026"; expect "buildroot: a quarterly series past its end of support" 0 "$UPD" "buildroot 2026.08 is past its end of support (2026-09)"
base; tree 2025.02.19 6.18.58 stable_20260911 2026.10 $FW_OURS 2026-09-23; tags buildroot-tags.txt 2025.02.19; br_eol "June 2027" "April 2027"
expect "buildroot: an LTS within six months of its end of support" 0 "$UPD" "buildroot 2025.02 (LTS) reaches its end of support in 6 month(s) (2027-04)"
base; tree 2025.02.19 6.18.58 stable_20260911 2026.10 $FW_OURS 2026-09-23; tags buildroot-tags.txt 2025.02.19; br_eol "June 2027" "May 2027"
run >/dev/null; grep -qF 'end of support' "$tmp/out" && bad "buildroot: an LTS seven months ahead is a date only" || ok "buildroot: an LTS seven months ahead is a date only"
grep -qF '| buildroot | 2025.02.19 | 2026.08.1 | 2027-05 |' "$tmp/sum" && ok "buildroot: the LTS's support column" || bad "buildroot: the LTS's support column"
base; tree 2026.02.6 6.18.58 stable_20260911 2026.10 $FW_OURS 2026-09-23; tags buildroot-tags.txt 2026.02.6
expect "buildroot: a series no longer on the download page is past its support" 0 "$UPD" "buildroot 2026.02 is no longer listed on buildroot.org's download page"
base; echo '<html>changed</html>' >"$tmp/fx/buildroot-download.html"
expect "buildroot.org's download page unparsable: unknown, not a failed check" 0 "up to date" "end of support unknown"
base; rm "$tmp/fx/buildroot-download.html"; expect "buildroot.org's download page unreachable: unknown, not a failed check" 0 "up to date" "end of support unknown"
base; releases mainline:7.3:false longterm:7.2.1:false longterm:6.18.58:false; expect "VM kernel: a newer longterm is a note" 0 "up to date" "newer longterm: 7.2.1"

base; tags uboot-tags.txt v2027.01; expect "U-Boot: a newer release" 0 "$UPD" "U-Boot 2027.01 is out (rpi3, rpi4 pins 2026.10)"
base; set_cfg aarch64-rpi4 BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE 2023.01
expect "U-Boot: rpi3 and rpi4 differ" 0 "$UPD" "rpi3 and rpi4 pin different U-Boot versions: rpi3 2026.10, rpi4 2023.01"
grep -qF 'U-Boot 2026.10 is out (rpi4 pins 2023.01)' "$tmp/out" && ok "U-Boot: the old one is named" || bad "U-Boot: the old one is named"

base; fw 1.20261021 cccc000000000000000000000000000000000000 tag; rpi_tag stable_20261020 cccc000000000000000000000000000000000000 6.18.60
expect "firmware: a newer release built with a newer stable_ tag" 0 "$UPD" "firmware 1.20261021 (built with stable_20261020) is out; ours was built with stable_20260911"
base; fw 1.20261021 dddd000000000000000000000000000000000000 tag; expect "firmware: a release built with no stable_ tag does not count" 0 "up to date"
base; fw $FW_OURS dddd000000000000000000000000000000000000; expect "firmware: ours built with no stable_ tag" 0 "$UPD" "was not built with a raspberrypi/linux stable_ tag"
base; set_cfg aarch64-rpi3 BR2_PACKAGE_RPI_FIRMWARE_VERSION 2222222222222222222222222222222222222222; fw 2222222222222222222222222222222222222222 $K_NEW
expect "firmware: rpi3 and rpi4 differ" 0 "$UPD" "rpi3 and rpi4 pin different firmware commits"

base; printf '2026-10-30  1  x  default  1\n' >>"$tmp/fx/eeprom-versions.txt"; expect "rpi-eeprom: a newer default release" 0 "$UPD" "rpi-eeprom 2026-10-30 is the default release (we pin 2026-09-23)"
base; printf '2026-11-30  1  x  latest  1\n' >>"$tmp/fx/eeprom-versions.txt"; expect "rpi-eeprom: a newer latest release does not count" 0 "up to date"
base; tree 2026.08.1 6.18.58 stable_20260911 2026.10 $FW_OURS 2026-10-23; expect "rpi-eeprom: ours newer than default is a note" 0 "up to date" "ours is newer than default (channel latest)"

base; rm "$tmp/fx/releases.json"; expect "kernel.org unreachable: exit 3, grey" 3 "check failed" "::error::upstream unreachable"
grep -qF '"color": "lightgrey"' "$tmp/site/badge.json" && grep -qF 'Prüfung fehlgeschlagen' "$tmp/site/index.html" \
  && grep -qF 'Check failed' "$tmp/site/en.html" && ok "check failed: grey badge, the pages say why" || bad "check failed: grey badge, the pages say why"
base; : >"$tmp/fx/buildroot-tags.txt"; expect "an empty buildroot listing: exit 3" 3 "check failed" "no release tags"
base; echo '{"x": 1}' >"$tmp/fx/releases.json"; expect "a releases.json without releases: exit 3" 3 "check failed" "releases.json"
base; rm "$tmp/fx/rpi-Makefile-stable_20260911"; expect "a raspberrypi/linux Makefile unreachable: exit 3" 3 "check failed"
base; echo 'not a hash' >"$tmp/fx/firmware-git_hash-1.20260915"; expect "a firmware git_hash not a commit: exit 3" 3 "check failed" "extra/git_hash is not a commit"
base; echo '# empty' >"$tmp/fx/eeprom-versions.txt"; expect "no default eeprom release: exit 3" 3 "check failed" "no default release"
base; sed -i 's/^BUILDROOT_VERSION=.*/X=1/' "$tmp/root/Makefile"; expect "no BUILDROOT_VERSION: exit 2" 2 "check failed" "pin not found"
base; echo 'BR2_LINUX_KERNEL=y' >"$tmp/root/$C/aarch64-rpi3.config"; expect "a Pi product without its pins: exit 2" 2 "check failed" "aarch64-rpi3"

echo; [ "$fails" -eq 0 ] && { echo "lite-upstream-versions-test: all passed"; exit 0; }
echo "lite-upstream-versions-test: $fails check(s) failed"; exit 1
