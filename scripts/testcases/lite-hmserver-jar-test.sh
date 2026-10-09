#!/bin/sh
# openccu-lite: HMServer.jar is in the image (B-313). On a system without an HmIP module occulited
# runs hmipserver as HMServer.jar for its VirtualDevices half (as OpenCCU's S62HMServer); without
# the jar it loops (dev.44). package/openccu-base takes it with the rest of opt/ from OpenCCU-Base's
# release archive, pruned to openccu-base-paths.txt (task 335).
#
# 1. openccu-base-paths.txt lists opt/HMServer/HMServer.jar, and neither HMServer's pages nor the
#    measurement templates.
# 2. The install copies the staged opt/ and insists on the jar, and the JAR licence step runs for it.
# 3. board/lite/post-build.sh's HMServer block on fake targets: with the jar and the four pages it
#    passes; without the jar, with an empty jar, with measurement/ or with a fifth page it stops.
# 4. scripts/lite-sbom.py groups the jar as HMServer.jar.
#
# Usage: sh scripts/testcases/lite-hmserver-jar-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
PKG="$HERE/buildroot-external/package/openccu-base"
MK="$PKG/openccu-base.mk"
LIST="$PKG/openccu-base-paths.txt"
PRUNE="$PKG/scripts/prune_source.py"
PB="$HERE/buildroot-external/board/lite/post-build.sh"
SBOM="$HERE/scripts/lite-sbom.py"
for f in "$MK" "$LIST" "$PRUNE" "$PB" "$SBOM"; do [ -f "$f" ] || { echo "$f not found"; exit 2; }; done

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# --- 1. the list
m=$(python3 "$PRUNE" --match "$LIST" opt/HMServer/HMServer.jar opt/HMServer/HMIPServer.jar opt/HMServer/pages/AvailableFirmware.ftl opt/HMServer/measurement/x.ftl opt/HMServer/templates.dit 2>&1 | cut -f2 | tr '\n' ' ')
[ "$m" = "opt/HMServer/HMServer.jar opt/HMServer/HMIPServer.jar - - - " ] && ok "the list has HMServer.jar and HMIPServer.jar, not the pages, measurement/ or templates.dit" || fail "the list: $m"

# --- 2. install and licence step
grep -q 'cp -av "$(@D)/build/rootfs/opt/." "$(TARGET_DIR)/opt/"' "$MK" && ok "the staged opt/ is installed as a whole" || fail "the opt/ install line"
grep -q 'test -s "$(TARGET_DIR)/opt/HMServer/HMServer.jar"' "$MK" && ok "the install insists on /opt/HMServer/HMServer.jar" || fail "no test on the installed jar"
if grep -v '^[[:space:]]*#' "$MK" | grep -q 'EXTRA_DOWNLOADS\|HMSERVER_ARCHIVE'; then fail "the extra download of the jar is still there"; else ok "no extra download: the jar comes with the archive"; fi
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
