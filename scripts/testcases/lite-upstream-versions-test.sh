#!/bin/sh
# openccu-lite: scripts/lite-upstream-versions.py offline, against fixtures instead of upstream:
# the fork's own pins are found; the rule for "current" per component (buildroot point release and
# series, the Raspberry Pi kernel tag and rpi3 = rpi4, the VM kernel's series and end of life (a newer
# point release of the VM kernel is a note only, the badge stays green),
# the Raspberry Pi firmware built with our kernel tag and the newest one, the
# rpi-eeprom default channel; the end of support of buildroot's series and of the kernel series:
# iseol, gone from releases.json, the projected dates within six months, unreadable pages; the JVM against
# Azul's newest Zulu build of our Java major per architecture; HMIPServer against eQ-3's
# homematicip/OpenCCU-Base (shown, never a finding) and the newest version tag of OpenCCU/OpenCCU-Base
# (chosen by version order among other tags; a finding when ours is older), ours with the OpenCCU-Base
# tag its jar comes from - the jar by its git blob sha and its version read by
# range from small test jars, a snapshot named as such; the OpenCCU-Base commits above our line from
# its report.json, each linked); findings exit 0 with ::warning:: lines and a yellow badge, errors exit
# 2 (pin) or 3 (upstream) with a grey badge - never green; the report pages (with the link to the
# OpenCCU-Base report) and the job summary. U-Boot is not checked (it follows buildroot's version from the
# LTS 2027.02 on, bumped deliberately until then) and the pages carry no "GRUB (VM) and Go" note: both
# fail the test when they come back.
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
JAR_OURS=f22c000000000000000000000000000000000000
JAR_THEIRS=e5ea000000000000000000000000000000000000
JAR_EQ3=e3e3000000000000000000000000000000000000

# a tree: <buildroot> <ova kernel> <rpi tag> <u-boot> <firmware commit> <eeprom date> (the U-Boot pin stays in
# the configs, as in the fork, and must not be read)
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
  printf 'ifeq ($(BR2_PACKAGE_RPI_EEPROM_RPI4),y)\n  RPI_EEPROM_FIRMWARE_PATH = firmware-2711/default/pieeprom-%s.bin\n' "$6" \
    >"$tmp/root/buildroot-external/package/rpi-eeprom/rpi-eeprom.mk"
  java_mk "$tmp/root/buildroot-external/package/java-azul/java-azul.mk" 21.52.203-ca-jre21.0.12.1
  base_mk "$tmp/root/buildroot-external/package/openccu-base/openccu-base.mk" v1.0.0-rc.3 '$(call github,hobbyquaker,OpenCCU-Base,$(OPENCCU_BASE_VERSION))'
}
java_mk() { # <file> <JAVA_AZUL_VERSION>
  mkdir -p "$(dirname "$1")"
  printf '# Azul\nJAVA_AZUL_VERSION = %s\nJAVA_AZUL_SITE = https://cdn.azul.com/zulu/bin\n' "$2" >"$1"
}
base_mk() { # <file> <OPENCCU_BASE_VERSION> <OPENCCU_BASE_SITE>
  mkdir -p "$(dirname "$1")"
  printf '# OpenCCU-Base\nOPENCCU_BASE_VERSION = %s\nOPENCCU_BASE_COMPAT_VERSION = 3.89.11\nOPENCCU_BASE_SITE = %s\n' "$2" "$3" >"$1"
}
jar() { # <blob sha> <server-core version, or "" for none> [stored] - a small jar: the version entry between others
  python3 - "$tmp/fx/jar-$1" "$2" "${3:-}" <<'PY'
import sys, zipfile
out, ver, stored = sys.argv[1], sys.argv[2], sys.argv[3] == "stored"
with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED) as z:
    z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\nBuild-Version: 1.5.1-SNAPSHOT\n")
    z.writestr("META-INF/maven/de.eq3.cbcs/devicemanagement/pom.properties", "version=9.9.9\n")
    if ver:
        z.writestr("META-INF/maven/de.eq3.cbcs.server/server-core/pom.properties",
                   "artifactId=server-core\ngroupId=de.eq3.cbcs.server\nversion=%s\n" % ver)
    z.writestr("de/eq3/x.class", b"\xca\xfe" * 5000)
PY
}
contents() { # <owner_repo-ref fixture name> <blob sha of HMIPServer.jar>
  printf '[{"name": "HMIPServer.jar", "sha": "%s", "size": 39996391}, {"name": "HMServer.jar", "sha": "484534cedc7e2a4b711600c09b7a908e83593c04"}]\n' "$2" \
    >"$tmp/fx/contents-$1.json"
}
azul() { # <arch> <zulu-ca-jre-java>... - Azul's metadata API answer (a musl and a JDK build mixed in)
  a=$1; shift
  { printf '['; sep=""
    for z in "$@"; do printf '%s{"name": "zulu%s-linux_%s.tar.gz"}, {"name": "zulu%s-linux_musl_%s.tar.gz"}' "$sep" "$z" "$a" "$(echo "$z" | sed 's/jre21/jre21.9/')" "$a"; sep=", "; done
    printf '%s{"name": "zulu99.1.1-ca-jdk21.9.9-linux_%s.tar.gz"}]\n' "$sep" "$a"; } >"$tmp/fx/azul-$a.json"
}
zulu_eol() { # <eolFrom of 21> [isEol]
  printf '{"result": {"releases": [{"name": "25", "eolFrom": "2033-09-30", "isEol": false}, {"name": "21", "eolFrom": "%s", "isEol": %s}]}}\n' "$1" "${2:-false}" >"$tmp/fx/zulu-eol.json"
}
base_report() { # <generated date> <subject>... of the commits above the line
  g=$1; shift
  { printf '{"generated": "%s 10:52 UTC", "boundary": {"sha": "423cde2b", "subject": "libXmlRpc: regenerate (#190)", "date": "2026-10-13T23:34:42+02:00"}, "above": [' "$g"
    sep=""; n=0
    for subj in "$@"; do n=$((n+1)); printf '%s{"subject": "%s", "date": "2026-10-1%sT10:00:00Z", "url": "https://github.com/OpenCCU/OpenCCU-Base/commit/%040d"}' "$sep" "$subj" "$n" "$n"; sep=", "; done
    printf ']}\n'; } >"$tmp/fx/base-report.json"
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
  releases mainline:7.3:false stable:7.2.12:false longterm:6.18.58:false longterm:6.12.114:false
  rpi_tag stable_20260609 $K_OLD 6.18.34; rpi_tag stable_20260911 $K_NEW 6.18.50
  fw 1.20260610 $K_OLD tag; fw 1.20260915 $K_NEW tag; fw $FW_OURS $K_NEW
  printf '# firmware-2711\n2026-10-23  1  f56d  latest  2\n2026-09-23  1  4564  default  1\n2026-05-17  1  2248  default  1\n' \
    >"$tmp/fx/eeprom-versions.txt"
  kernel_eol "Dec, 2028"
  br_eol "June 2027"
  printf 'ref: refs/heads/rpi-6.18.y\tHEAD\naeadd6ed\tHEAD\n' >"$tmp/fx/rpi-head.txt"
  tags openccu-base-tags.txt 3.89.9 3.89.11 v1.0.0-rc.3 3.89.11.20260919 lts-1 4.0.0-rc1
  azul aarch64 21.52.203-ca-jre21.0.12.1 21.50.19-ca-jre21.0.11; azul x64 21.52.203-ca-jre21.0.12.1
  contents hobbyquaker_OpenCCU-Base-v1.0.0-rc.3 $JAR_OURS; contents OpenCCU_OpenCCU-Base-3.89.11 $JAR_OURS
  echo '{"full_name": "homematicip/OpenCCU-Base", "default_branch": "main"}' >"$tmp/fx/eq3-repo.json"
  contents homematicip_OpenCCU-Base-main $JAR_OURS
  jar $JAR_OURS 1.60.1
  zulu_eol 2031-09-30
  base_report 2026-10-24
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
    print("firmware", m.pin(root, m.cfg(p), r'^BR2_PACKAGE_RPI_FIRMWARE_VERSION="([0-9a-f]{40})"', "x"))
print("java", "".join(m.zulu(m.pin(root, m.JAVA_MK, m.JAVA_VAR, "x")) or ("none",)))
print("openccu-base", " ".join(m.base_source(m.read(root, m.BASE_MK)) or ("none",)))
mk = open(root + "/buildroot-external/package/rpi-eeprom/rpi-eeprom.mk").read()
print("eeprom", re.search(r"^\s*RPI_EEPROM_FIRMWARE_PATH\s*=\s*firmware-2711/\S*pieeprom-(\d{4}-\d{2}-\d{2})\.bin", mk, re.M).group(1))
EOF
[ $? -eq 0 ] && [ "$(grep -c '^firmware [0-9a-f]' "$tmp/pins")" -eq 2 ] \
  && grep -q '^rpi stable_[0-9]* stable_' "$tmp/pins" && grep -q '^eeprom 20' "$tmp/pins" && grep -q '^vm [0-9]' "$tmp/pins" \
  && grep -q '^java [0-9.]*[0-9][0-9.]*jre$' "$tmp/pins" && grep -q '^openccu-base hobbyquaker/OpenCCU-Base v1\.[0-9]' "$tmp/pins" \
  && ok "the fork's pins: buildroot, kernels, firmware, rpi-eeprom, JVM, OpenCCU-Base" \
  || { bad "the fork's pins are not found"; sed 's/^/     /' "$tmp/pins"; }

base; expect "all current: exit 0, green" 0 "up to date" "all current"
grep -q '::warning::\|::error::' "$tmp/out" && bad "no annotations when current" || ok "no annotations when current"
grep -qF '| Raspberry Pi firmware (rpi3, rpi4) | 111111111111 (stable_20260911) | 1.20260915 (stable_20260911) |  | up to date |' "$tmp/sum" \
  && grep -qF '| buildroot | 2026.08.1 | 2026.08.1 | 2027-06 | up to date |' "$tmp/sum" \
  && grep -qF '| VM kernel (ova) | 6.18.58 | 6.18.58 | 2028-12 | up to date |' "$tmp/sum" \
  && grep -qF '**All current.**' "$tmp/sum" && ok "the job summary" || { bad "the job summary"; cat "$tmp/sum"; }
grep -qF '"color": "brightgreen"' "$tmp/site/badge.json" && ok "badge green" || bad "badge green"
grep -q '<html lang="de">' "$tmp/site/index.html" && grep -qF 'aktuell' "$tmp/site/index.html" \
  && grep -q '<html lang="en">' "$tmp/site/en.html" && grep -qF 'up to date' "$tmp/site/en.html" \
  && grep -qF 'href="en.html"' "$tmp/site/index.html" && grep -qF 'prefers-color-scheme:dark' "$tmp/site/index.html" \
  && [ "$(grep -c '<tr><td>' "$tmp/site/en.html")" -eq 8 ] \
  && grep -qF '<th>Support bis</th>' "$tmp/site/index.html" \
  && ok "the report pages: German and English, eight components, the support column, dark mode" || bad "the report pages"
! grep -qiF 'Supportzeitraum' "$tmp/site/index.html" && ! grep -qiF 'support period' "$tmp/site/en.html" \
  && grep -qF '</td><td></td><td><span class="ok">aktuell</span>' "$tmp/site/index.html" \
  && grep -qF '</td><td></td><td><span class="ok">up to date</span>' "$tmp/site/en.html" \
  && ok "no published support period: the cell stays empty" || bad "no published support period: the cell stays empty"
grep -qF '<td><a href="https://hobbyquaker.github.io/OpenCCU-Base/">0 Commit(s) über der Linie</a></td>' "$tmp/site/index.html" \
  && grep -qF '<td><a href="https://hobbyquaker.github.io/OpenCCU-Base/">0 commit(s) above the line</a></td>' "$tmp/site/en.html" \
  && ok "OpenCCU-Base: the count links the commit report" || bad "OpenCCU-Base: the count links the commit report"
grep -qF '<a href="https://hobbyquaker.github.io/OpenCCU-Base/">der OpenCCU-Base-Commit-Bericht</a>' "$tmp/site/index.html" \
  && grep -qF '<a href="https://hobbyquaker.github.io/OpenCCU-Base/">the OpenCCU-Base commit report</a>' "$tmp/site/en.html" \
  && ok "both pages link the OpenCCU-Base commit report" || bad "both pages link the OpenCCU-Base commit report"
grep -qF '| JVM (Azul Zulu) | 21.0.12.1 (Zulu 21.52.203, JRE) | 21.0.12.1 (Zulu 21.52.203, JRE) | 2031-09 | up to date |' "$tmp/sum" \
  && grep -qF '| HMIPServer | 1.60.1 (OpenCCU-Base 3.89.11) | homematicip/OpenCCU-Base main: 1.60.1 (the same jar) · OpenCCU/OpenCCU-Base 3.89.11: 1.60.1 (the same jar) |  | up to date |' "$tmp/sum" \
  && grep -qF '| OpenCCU-Base commits above our line | lite at: libXmlRpc: regenerate (#190) (2026-10-13) | 0 commit(s) above the line |  | up to date |' "$tmp/sum" \
  && grep -qF '<td>homematicip/OpenCCU-Base main: 1.60.1 (dasselbe Jar) · OpenCCU/OpenCCU-Base 3.89.11: 1.60.1 (dasselbe Jar)</td>' "$tmp/site/index.html" \
  && grep -qF '<td>1.60.1 (OpenCCU-Base 3.89.11)</td>' "$tmp/site/index.html" && grep -qF '<td>1.60.1 (OpenCCU-Base 3.89.11)</td>' "$tmp/site/en.html" \
  && ! grep -qF 'v1.0.0-rc.3' "$tmp/site/index.html" "$tmp/site/en.html" \
  && ok "the JVM, HMIPServer and OpenCCU-Base rows" || { bad "the JVM, HMIPServer and OpenCCU-Base rows"; cat "$tmp/sum"; }

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

base; releases mainline:7.3:false longterm:6.18.59:false
expect "VM kernel: a newer release of our series is a note, the badge stays green" 0 "up to date" "kernel 6.18.59 is out (we pin 6.18.58) - update available, information only"
grep -q '::warning::' "$tmp/out" && bad "VM kernel: a newer release is no ::warning::" || ok "VM kernel: a newer release is no ::warning::"
grep -qF '| VM kernel (ova) | 6.18.58 | 6.18.59 | 2028-12 | up to date |' "$tmp/sum" && grep -qF '"color": "brightgreen"' "$tmp/site/badge.json" \
  && grep -qF 'Update verfügbar, nur zur Information' "$tmp/site/index.html" \
  && ok "VM kernel: a newer release shown in the row, green" || { bad "VM kernel: a newer release shown in the row, green"; cat "$tmp/sum"; }
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

# U-Boot is not checked: no row, no upstream lookup (no uboot-tags.txt fixture), rpi3 != rpi4 is no finding;
# and no "GRUB (VM) and Go" note - neither may come back
base; set_cfg aarch64-rpi4 BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE 2023.01
expect "U-Boot: not checked, rpi3 and rpi4 may differ" 0 "up to date" "all current"
! grep -qi 'u-boot\|uboot' "$tmp/out" "$tmp/sum" "$tmp/site/index.html" "$tmp/site/en.html" \
  && ! grep -qi 'grub\|kommen mit buildroot\|come with buildroot' "$tmp/out" "$tmp/sum" "$tmp/site/index.html" "$tmp/site/en.html" \
  && ! grep -qi 'u-boot\|uboot\|grub' "$PY" \
  && ok "no U-Boot and no GRUB/Go note: output, summary, both pages, the script" \
  || bad "no U-Boot and no GRUB/Go note: output, summary, both pages, the script"

base; fw 1.20261021 cccc000000000000000000000000000000000000 tag; rpi_tag stable_20261020 cccc000000000000000000000000000000000000 6.18.60
expect "firmware: a newer release built with a newer stable_ tag" 0 "$UPD" "firmware 1.20261021 (built with stable_20261020) is out; ours was built with stable_20260911"
base; fw 1.20261021 dddd000000000000000000000000000000000000 tag; expect "firmware: a release built with no stable_ tag does not count" 0 "up to date"
base; fw $FW_OURS dddd000000000000000000000000000000000000; expect "firmware: ours built with no stable_ tag" 0 "$UPD" "was not built with a raspberrypi/linux stable_ tag"
base; set_cfg aarch64-rpi3 BR2_PACKAGE_RPI_FIRMWARE_VERSION 2222222222222222222222222222222222222222; fw 2222222222222222222222222222222222222222 $K_NEW
expect "firmware: rpi3 and rpi4 differ" 0 "$UPD" "rpi3 and rpi4 pin different firmware commits"

base; printf '2026-10-30  1  x  default  1\n' >>"$tmp/fx/eeprom-versions.txt"; expect "rpi-eeprom: a newer default release" 0 "$UPD" "rpi-eeprom 2026-10-30 is the default release (we pin 2026-09-23)"
base; printf '2026-11-30  1  x  latest  1\n' >>"$tmp/fx/eeprom-versions.txt"; expect "rpi-eeprom: a newer latest release does not count" 0 "up to date"
base; tree 2026.08.1 6.18.58 stable_20260911 2026.10 $FW_OURS 2026-10-23; expect "rpi-eeprom: ours newer than default is a note" 0 "up to date" "ours is newer than default (channel latest)"

# the JVM against Azul's newest Zulu 21 build per architecture
base; azul x64 21.52.203-ca-jre21.0.12.1 21.54.107-ca-jre21.0.13; azul aarch64 21.54.107-ca-jre21.0.13
expect "JVM: a newer Java 21 build for both architectures" 0 "$UPD" "Zulu 21.54.107 (Java 21.0.13) is out for aarch64, x64; we pin 21.52.203 (Java 21.0.12.1)"
base; azul x64 21.53.1-ca-jre21.0.12.1
expect "JVM: the same Java in a newer Zulu build, one architecture" 0 "$UPD" "Zulu 21.53.1 (Java 21.0.12.1) is out for x64"
grep -qF '| JVM (Azul Zulu) | 21.0.12.1 (Zulu 21.52.203, JRE) | 21.0.12.1 (Zulu 21.52.203, JRE) aarch64 / 21.0.12.1 (Zulu 21.53.1, JRE) x64 |' "$tmp/sum" \
  && ok "JVM: architectures that differ are named" || { bad "JVM: architectures that differ are named"; grep JVM "$tmp/sum"; }
base; azul x64 21.50.19-ca-jre21.0.11; azul aarch64 21.50.19-ca-jre21.0.11
expect "JVM: ours newer than Azul's newest is a note" 0 "up to date" "ours is newer than Azul's newest GA build"
base; azul x64 21.52.203-ca-jre21.0.12.1 22.1.1-ca-jre22.0.1
expect "JVM: another Java major does not count" 0 "up to date"
base; zulu_eol 2027-04-30; expect "JVM: Zulu 21's end of support within six months" 0 "$UPD" "Azul Zulu 21 reaches its end of support in 6 month(s) (2027-04)"
base; zulu_eol 2027-05-31; expect "JVM: seven months ahead is a date only" 0 "up to date"
base; zulu_eol 2031-09-30 true; expect "JVM: Zulu marked end of life" 0 "$UPD" "Azul Zulu 21 is end of life"
base; echo 'nope' >"$tmp/fx/zulu-eol.json"; expect "JVM: endoflife.date unreadable is a note, not a failed check" 0 "up to date" "end of support of Zulu 21 unknown"
base; rm "$tmp/fx/zulu-eol.json"; expect "JVM: endoflife.date unreachable is a note, not a failed check" 0 "up to date" "end of support of Zulu 21 unknown"
base; rm "$tmp/fx/openccu-base-tags.txt"; expect "OpenCCU-Base's tags unreachable: exit 3" 3 "check failed" "::error::upstream unreachable"
base; : >"$tmp/fx/openccu-base-tags.txt"; tags openccu-base-tags.txt v1.0.0-rc.3 lts-1 4.0.0-rc1
expect "OpenCCU-Base without a version tag: exit 3" 3 "check failed" "OpenCCU/OpenCCU-Base: no version tag"
base; rm "$tmp/fx/azul-x64.json"; expect "Azul's metadata API unreachable: exit 3" 3 "check failed" "azul-x64.json"
base; echo '[{"name": "zulu21.54.107-ca-jre21.0.13-linux_musl_x64.tar.gz"}]' >"$tmp/fx/azul-x64.json"; expect "Azul's metadata API without a glibc JRE for x64: exit 3" 3 "check failed" "no Zulu 21 JRE for linux_x64"
base; rm "$tmp/root/buildroot-external/package/java-azul/java-azul.mk"; expect "our java-azul.mk missing: exit 2" 2 "check failed" "java-azul.mk"

# HMIPServer: the jar by its blob sha, the version by range
base; tags openccu-base-tags.txt 3.89.12; contents OpenCCU_OpenCCU-Base-3.89.12 $JAR_THEIRS; jar $JAR_THEIRS 1.61.11-SNAPSHOT
expect "HMIPServer: the newest OpenCCU-Base tag has a newer snapshot" 0 "$UPD" "OpenCCU-Base 3.89.12 has a newer HMIPServer, a snapshot: 1.61.11-SNAPSHOT (ours: 1.60.1) - see the OpenCCU-Base report https://hobbyquaker.github.io/OpenCCU-Base/"
grep -qF '<li><a href="https://hobbyquaker.github.io/OpenCCU-Base/">OpenCCU-Base 3.89.12 hat einen neueren HMIPServer, einen Snapshot' "$tmp/site/index.html" \
  && grep -qF '| HMIPServer | 1.60.1 (OpenCCU-Base 3.89.11) | homematicip/OpenCCU-Base main: 1.60.1 (the same jar) · OpenCCU/OpenCCU-Base 3.89.12: 1.61.11-SNAPSHOT (snapshot) |' "$tmp/sum" \
  && ok "HMIPServer: the snapshot finding links the OpenCCU-Base report, both versions shown" || bad "HMIPServer: the snapshot finding links the OpenCCU-Base report, both versions shown"
base; contents homematicip_OpenCCU-Base-main $JAR_EQ3; jar $JAR_EQ3 1.61.11-SNAPSHOT
expect "HMIPServer: a newer snapshot at homematicip is shown, not a finding" 0 "up to date" "homematicip/OpenCCU-Base main has a newer one: 1.61.11-SNAPSHOT (snapshot) - information, not a finding"
grep -qF '| HMIPServer | 1.60.1 (OpenCCU-Base 3.89.11) | homematicip/OpenCCU-Base main: 1.61.11-SNAPSHOT (snapshot) · OpenCCU/OpenCCU-Base 3.89.11: 1.60.1 (the same jar) |  | up to date |' "$tmp/sum" \
  && grep -qF '<td>homematicip/OpenCCU-Base main: 1.61.11-SNAPSHOT (Snapshot) · OpenCCU/OpenCCU-Base 3.89.11: 1.60.1 (dasselbe Jar)</td>' "$tmp/site/index.html" \
  && ok "HMIPServer: both comparisons in the row" || { bad "HMIPServer: both comparisons in the row"; grep HMIP "$tmp/sum"; }
base; contents homematicip_OpenCCU-Base-main $JAR_EQ3; jar $JAR_EQ3 1.62.0
expect "HMIPServer: a newer release at homematicip is not a finding either" 0 "up to date" "has a newer one: 1.62.0 - information"
base; contents homematicip_OpenCCU-Base-main $JAR_EQ3; jar $JAR_EQ3 1.62.0; tags openccu-base-tags.txt 3.89.12; contents OpenCCU_OpenCCU-Base-3.89.12 $JAR_THEIRS; jar $JAR_THEIRS 1.61.2
expect "HMIPServer: the newest OpenCCU-Base tag newer is a finding, homematicip shown beside it" 0 "$UPD" "OpenCCU-Base 3.89.12 has a newer HMIPServer: 1.61.2 (ours: 1.60.1)"
grep -qF 'homematicip/OpenCCU-Base main: 1.62.0 · OpenCCU/OpenCCU-Base 3.89.12: 1.61.2 |' "$tmp/sum" && [ "$(grep -c '::warning::update available - HMIPServer' "$tmp/out")" -eq 1 ] \
  && ok "HMIPServer: one finding, both versions" || bad "HMIPServer: one finding, both versions"
base; contents homematicip_OpenCCU-Base-main $JAR_EQ3
expect "HMIPServer: homematicip's different jar unreachable: exit 3" 3 "check failed" "jar-$JAR_EQ3"
base; echo '{"message": "Not Found"}' >"$tmp/fx/eq3-repo.json"
expect "HMIPServer: homematicip/OpenCCU-Base without a default branch: exit 3" 3 "check failed" "no default branch"
base; tags openccu-base-tags.txt 3.89.12; contents OpenCCU_OpenCCU-Base-3.89.12 $JAR_THEIRS; jar $JAR_THEIRS 1.62.0 stored
expect "HMIPServer: a newer release (a stored entry)" 0 "$UPD" "OpenCCU-Base 3.89.12 has a newer HMIPServer: 1.62.0 (ours: 1.60.1)"
base; tags openccu-base-tags.txt 3.89.12; contents OpenCCU_OpenCCU-Base-3.89.12 $JAR_THEIRS; jar $JAR_THEIRS 1.58.4
expect "HMIPServer: an older one is a note" 0 "up to date" "OpenCCU-Base 3.89.12 has an older one"
base; tags openccu-base-tags.txt 3.89.12; contents OpenCCU_OpenCCU-Base-3.89.12 $JAR_THEIRS; jar $JAR_THEIRS 1.60.1
expect "HMIPServer: another build of the same version is a note" 0 "up to date" "a different build of the same version"
base; tags openccu-base-tags.txt 3.89.12; contents OpenCCU_OpenCCU-Base-3.89.12 $JAR_THEIRS; jar $JAR_THEIRS ""
expect "HMIPServer: a different jar without a readable version is a finding" 0 "$UPD" "OpenCCU-Base 3.89.12 has a different HMIPServer.jar (its version is not readable)"
base; tags openccu-base-tags.txt 3.89.12; contents OpenCCU_OpenCCU-Base-3.89.12 $JAR_THEIRS
expect "HMIPServer: OpenCCU-Base's different jar unreachable: exit 3" 3 "check failed" "jar-$JAR_THEIRS"
base; echo '[{"name": "HMServer.jar", "sha": "484534cedc7e2a4b711600c09b7a908e83593c04"}]' >"$tmp/fx/contents-OpenCCU_OpenCCU-Base-3.89.11.json"
expect "HMIPServer: no jar at the newest OpenCCU-Base tag: exit 3" 3 "check failed" "no opt/HMServer/HMIPServer.jar"
# the newest version tag by version order, our jar's own tag, a newer jar there is a finding
base; tags openccu-base-tags.txt 3.89.10 3.100.1 v9.9.9 9.9.9.1; contents OpenCCU_OpenCCU-Base-3.100.1 $JAR_OURS
expect "HMIPServer: the newest of several OpenCCU-Base tags by version order (3.100.1, not 3.89.11 or v9.9.9)" 0 "up to date"
grep -qF '| HMIPServer | 1.60.1 (OpenCCU-Base 3.100.1) | homematicip/OpenCCU-Base main: 1.60.1 (the same jar) · OpenCCU/OpenCCU-Base 3.100.1: 1.60.1 (the same jar) |' "$tmp/sum" \
  && ok "HMIPServer: 3.100.1 shown as the newest tag and as ours" || { bad "HMIPServer: 3.100.1 shown as the newest tag and as ours"; grep HMIP "$tmp/sum"; }
base; tags openccu-base-tags.txt 3.89.12; contents OpenCCU_OpenCCU-Base-3.89.12 $JAR_THEIRS; jar $JAR_THEIRS 1.61.2
expect "HMIPServer: a newer jar at the newest OpenCCU-Base tag is a finding" 0 "$UPD" "OpenCCU-Base 3.89.12 has a newer HMIPServer: 1.61.2 (ours: 1.60.1)"
grep -qF '| HMIPServer | 1.60.1 (OpenCCU-Base 3.89.11) | homematicip/OpenCCU-Base main: 1.60.1 (the same jar) · OpenCCU/OpenCCU-Base 3.89.12: 1.61.2 |' "$tmp/sum" \
  && grep -qF '<li>OpenCCU-Base 3.89.12 hat einen neueren HMIPServer: 1.61.2 (unserer: 1.60.1)</li>' "$tmp/site/index.html" \
  && ok "HMIPServer: ours from the older tag 3.89.11, the newest tag 3.89.12 beside it" || { bad "HMIPServer: ours from the older tag 3.89.11, the newest tag 3.89.12 beside it"; grep HMIP "$tmp/sum"; }
base; tags openccu-base-tags.txt 3.89.12; contents OpenCCU_OpenCCU-Base-3.89.12 $JAR_THEIRS; jar $JAR_THEIRS 1.60.1
contents OpenCCU_OpenCCU-Base-3.89.11 $JAR_EQ3; echo '[]' >"$tmp/fx/contents-OpenCCU_OpenCCU-Base-3.89.9.json"
expect "HMIPServer: our jar in no OpenCCU-Base tag is a note" 0 "up to date" "our jar is in none of the 10 newest version tags of OpenCCU/OpenCCU-Base"
grep -qF '<td>1.60.1 (in keinem OpenCCU-Base-Tag)</td>' "$tmp/site/index.html" && grep -qF '<td>1.60.1 (in no OpenCCU-Base tag)</td>' "$tmp/site/en.html" \
  && ok "HMIPServer: no tag of ours is said so" || bad "HMIPServer: no tag of ours is said so"
base; base_mk "$tmp/root/buildroot-external/package/openccu-base/openccu-base.mk" v1.0.0-rc.3 'https://example.org/x.tar.gz'
expect "HMIPServer: our openccu-base.mk not on GitHub: exit 2" 2 "check failed" "openccu-base.mk"

# OpenCCU-Base: the commits above our line
base; base_report 2026-10-24 'webui: default objects (#222)' 'rfd: a fix (#230)'
expect "OpenCCU-Base: commits above the line, one finding each" 0 "$UPD" "not taken yet: 2026-10-12 rfd: a fix (#230) https://github.com/OpenCCU/OpenCCU-Base/commit/0000000000000000000000000000000000000002"
[ "$(grep -c '::warning::update available - OpenCCU-Base commits above our line' "$tmp/out")" -eq 2 ] \
  && grep -qF '<li><a href="https://github.com/OpenCCU/OpenCCU-Base/commit/0000000000000000000000000000000000000001">noch nicht übernommen: 2026-10-11 webui: default objects (#222)</a></li>' "$tmp/site/index.html" \
  && grep -qF '<td><a href="https://hobbyquaker.github.io/OpenCCU-Base/">2 commit(s) above the line</a></td>' "$tmp/site/en.html" \
  && grep -qF '<td><a href="https://hobbyquaker.github.io/OpenCCU-Base/">2 Commit(s) über der Linie</a></td>' "$tmp/site/index.html" \
  && ok "OpenCCU-Base: two warnings, the subjects linked, the count linked" || bad "OpenCCU-Base: two warnings, the subjects linked, the count linked"
base; base_report 2026-10-21; expect "OpenCCU-Base: a stale report is a note" 0 "up to date" "the OpenCCU-Base report is from 2026-10-21"
base; base_report 2026-10-22; run >/dev/null; grep -qF 'report is from' "$tmp/out" && bad "OpenCCU-Base: two days old is not stale" || ok "OpenCCU-Base: two days old is not stale"
base; rm "$tmp/fx/base-report.json"; expect "OpenCCU-Base report unreachable: exit 3" 3 "check failed" "base-report.json"
base; echo '{"boundary": null}' >"$tmp/fx/base-report.json"; expect "OpenCCU-Base report without its commits: exit 3" 3 "check failed" "report.json"

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
