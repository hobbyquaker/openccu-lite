#!/bin/sh
# openccu-lite: HMServer.jar is in the image (B-313). On a system without an HmIP module occulited
# runs hmipserver as HMServer.jar for its VirtualDevices half (as OpenCCU's S62HMServer); without
# the jar it loops (dev.44). openccu-lite-base does not carry it, so package/openccu-base takes it
# alone from OpenCCU-Base's release archive at the compat version.
#
# 1. openccu-base.mk downloads that archive (EXTRA_DOWNLOADS at OPENCCU_BASE_COMPAT_VERSION), and
#    openccu-base.hash has its hash under the same name.
# 2. The install extracts exactly opt/HMServer/HMServer.jar and installs it 0644, and the JAR
#    licence step runs for it.
# 3. board/lite/post-build.sh's HMServer block on fake targets: with the jar and the four pages it
#    passes; without the jar, with an empty jar, with measurement/ or with a fifth page it stops.
# 4. scripts/lite-sbom.py groups the jar as HMServer.jar.
#
# Usage: sh scripts/testcases/lite-hmserver-jar-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
MK="$HERE/buildroot-external/package/openccu-base/openccu-base.mk"
HASH="$HERE/buildroot-external/package/openccu-base/openccu-base.hash"
PB="$HERE/buildroot-external/board/lite/post-build.sh"
SBOM="$HERE/scripts/lite-sbom.py"
for f in "$MK" "$HASH" "$PB" "$SBOM"; do [ -f "$f" ] || { echo "$f not found"; exit 2; }; done

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# --- 1. download and hash
compat=$(sed -n 's/^OPENCCU_BASE_COMPAT_VERSION = //p' "$MK")
[ -n "$compat" ] && ok "compat version $compat" || fail "no OPENCCU_BASE_COMPAT_VERSION"
grep -q '^OPENCCU_BASE_HMSERVER_ARCHIVE = OpenCCU-Base-$(OPENCCU_BASE_COMPAT_VERSION).tar.gz$' "$MK" \
	&& ok "the archive is named by the compat version" || fail "OPENCCU_BASE_HMSERVER_ARCHIVE"
grep -q 'https://github.com/OpenCCU/OpenCCU-Base/archive/$(OPENCCU_BASE_COMPAT_VERSION)/$(OPENCCU_BASE_HMSERVER_ARCHIVE)' "$MK" \
	&& grep -q '^OPENCCU_BASE_EXTRA_DOWNLOADS = ' "$MK" \
	&& ok "EXTRA_DOWNLOADS fetches OpenCCU-Base's release archive" || fail "EXTRA_DOWNLOADS"
grep -Eq "^sha256  [0-9a-f]{64}  OpenCCU-Base-$compat\.tar\.gz$" "$HASH" \
	&& ok "openccu-base.hash has OpenCCU-Base-$compat.tar.gz" || fail "no hash for OpenCCU-Base-$compat.tar.gz"

# --- 2. install and licence step
grep -q '"OpenCCU-Base-$(OPENCCU_BASE_COMPAT_VERSION)/opt/HMServer/HMServer.jar"' "$MK" \
	&& ok "only opt/HMServer/HMServer.jar is extracted" || fail "the extract names another member"
grep -q 'INSTALL) -D -m 0644 "$(@D)/HMServer.jar" "$(TARGET_DIR)/opt/HMServer/HMServer.jar"' "$MK" \
	&& ok "installed 0644 at /opt/HMServer/HMServer.jar" || fail "the install line"
[ "$(grep -c -- '--jarfile=HMServer.jar' "$MK")" = 1 ] && grep -q 'HMServer.jar-JARLICENSEINFO.txt \\$' "$MK" \
	&& ok "the JAR licence step for HMServer.jar" || fail "the JAR licence step"

# --- 3. the post-build block, cut out of post-build.sh and run on fake targets
awk '/^# hmipserver runs HMIPServer.jar/{on=1} on{print} on&&/only the overlay.s four group pages belong there/{getline; print; getline; print; exit}' "$PB" > "$T/block.sh"
grep -q 'HMServer.jar is missing' "$T/block.sh" && grep -q 'opt/HMServer/pages' "$T/block.sh" \
	&& ok "the HMServer block found in post-build.sh" || fail "the HMServer block not found"
mk() { # mk <dir> : a target with the jar and the four pages
	mkdir -p "$1/opt/HMServer/pages"
	printf 'PK' > "$1/opt/HMServer/HMServer.jar"
	for p in GroupChooseDialog GroupConfigureDialog GroupEditPage GroupListPage; do : > "$1/opt/HMServer/pages/$p.ftl"; done
}
run() { TARGET_DIR="$1" sh "$T/block.sh" > "$T/out" 2>&1; }
mk "$T/good"; run "$T/good" && ok "jar + four pages pass" || { fail "jar + four pages refused"; cat "$T/out"; }
mk "$T/nojar"; rm "$T/nojar/opt/HMServer/HMServer.jar"; run "$T/nojar" && fail "a missing jar passes" || ok "a missing jar stops the build"
mk "$T/empty"; : > "$T/empty/opt/HMServer/HMServer.jar"; run "$T/empty" && fail "an empty jar passes" || ok "an empty jar stops the build"
mk "$T/meas"; mkdir "$T/meas/opt/HMServer/measurement"; run "$T/meas" && fail "measurement/ passes" || ok "measurement/ stops the build"
mk "$T/page"; : > "$T/page/opt/HMServer/pages/AvailableFirmware.ftl"; run "$T/page" && fail "a fifth page passes" || ok "a fifth page stops the build"

# --- 4. the SBOM's group
g=$(cd "$HERE/scripts" && python3 -c 'import importlib.util,sys
s=importlib.util.spec_from_file_location("s","lite-sbom.py"); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.base_group("opt/HMServer/HMServer.jar"), m.base_group("opt/HMServer/groups/groupdefinitions.xml"), m.base_group("opt/HMServer/HMIPServer.jar"))' 2>&1)
[ "$g" = "HMServer.jar HMIPServer.jar HMIPServer.jar" ] && ok "lite-sbom groups: $g" || fail "lite-sbom groups: $g"

echo "--- $fails failure(s)"
[ "$fails" = 0 ]
