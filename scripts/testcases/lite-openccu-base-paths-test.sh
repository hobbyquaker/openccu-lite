#!/bin/sh
# openccu-lite: openccu-base builds only the paths openccu-base-paths.txt lists (task 335).
# package/openccu-base fetches OpenCCU-Base's release archive and prunes it right after the extract
# to that list (scripts/prune_source.py, a post-extract hook; package/eq3_char_loop the same), so a
# file the list does not name cannot reach the build, and the extract fails when an entry names
# nothing in the archive.
#
# 1. prune_source.py on a made-up tree: a listed file, a listed directory (with and without the
#    trailing slash), a regex entry with a lookahead stay; everything else goes, empty directories
#    with it, a symlink is handled by its own path; an entry that names nothing fails and deletes
#    nothing; --match says which entry takes a path; a glob: entry and an absolute path are refused.
# 2. The real list: it parses, and it matches what openccu-base.mk, stage_lite_www.sh and the CMake
#    build read (the licences, the startup scripts, etc/, firmware/, the jars, src/ components, the
#    WebUI files for addons) and not what openccu-lite must not take (the WebUI itself, hss_led,
#    eq3configd, ssdpd, HMServer's pages and measurement templates, the prebuilt www/, bin/<arch>/
#    and lib/<arch>/, usr/, tests/, the repository's own files).
# 3. The wiring: openccu-base.mk fetches OpenCCU/OpenCCU-Base's archive at OPENCCU_BASE_VERSION,
#    the compat version is that release, the hook runs the prune with the list, no extra download
#    and no openccu-lite-base are left; eq3_char_loop.mk prunes too; openccu-base.hash names the
#    archive and nothing of openccu-lite-base.
#
# Usage: sh scripts/testcases/lite-openccu-base-paths-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
PKG="$HERE/buildroot-external/package/openccu-base"
PRUNE="$PKG/scripts/prune_source.py"
LIST="$PKG/openccu-base-paths.txt"
MK="$PKG/openccu-base.mk"
HASH="$PKG/openccu-base.hash"
EQ3="$HERE/buildroot-external/package/eq3_char_loop/eq3_char_loop.mk"
for f in "$PRUNE" "$LIST" "$MK" "$HASH" "$EQ3"; do [ -f "$f" ] || { echo "$f not found"; exit 2; }; done

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# --- 1. the prune on a made-up tree
mktree() { # mktree <dir>
	rm -rf "$1"
	mkdir -p "$1/keep/sub" "$1/dir/deep/er" "$1/src/rfd" "$1/src/webui/www" "$1/src/hss_led" "$1/gone/empty/also" "$1/top"
	echo a >"$1/file.txt"; echo b >"$1/keep/sub/x"; echo c >"$1/dir/deep/er/y"; echo d >"$1/src/rfd/rfd.cpp"
	echo e >"$1/src/webui/www/webui.js"; echo f >"$1/src/hss_led/led.c"; echo g >"$1/top/other.txt"; echo h >"$1/README"
	ln -s ../file.txt "$1/keep/link"; ln -s nowhere "$1/top/dangling"; ln -s . "$1/gone/loop"
}
cat >"$T/list" <<'LST'
# a comment, then a blank line

file.txt
keep
dir/
regex:^src/(?!(webui|hss_led)/)
LST
mktree "$T/a"
if python3 "$PRUNE" "$T/list" "$T/a" >"$T/out" 2>&1; then ok "the prune runs: $(cat "$T/out")"; else fail "the prune failed: $(cat "$T/out")"; fi
left=$(cd "$T/a" && find . -mindepth 1 \( -type f -o -type l \) | LC_ALL=C sort | tr '\n' ' ')
[ "$left" = "./dir/deep/er/y ./file.txt ./keep/link ./keep/sub/x ./src/rfd/rfd.cpp " ] && ok "exactly the listed files and links stay" || fail "left: $left"
dirs=$(cd "$T/a" && find . -mindepth 1 -type d | LC_ALL=C sort | tr '\n' ' ')
[ "$dirs" = "./dir ./dir/deep ./dir/deep/er ./keep ./keep/sub ./src ./src/rfd " ] && ok "the emptied directories are gone" || fail "dirs: $dirs"
[ -L "$T/a/keep/link" ] && [ "$(readlink "$T/a/keep/link")" = "../file.txt" ] && ok "a kept symlink stays a symlink" || fail "the kept link"
[ ! -e "$T/a/src/webui" ] && [ ! -e "$T/a/src/hss_led" ] && ok "the lookahead regex drops src/webui and src/hss_led" || fail "the regex kept what it excludes"

mktree "$T/b"
printf 'file.txt\nmissing/\nregex:^nothing-here\n' >"$T/list-missing"
if python3 "$PRUNE" "$T/list-missing" "$T/b" >"$T/out" 2>&1; then fail "an entry that names nothing passes"; else ok "an entry that names nothing fails"; fi
grep -q 'list-missing:2 names nothing' "$T/out" && grep -q 'list-missing:3 names nothing' "$T/out" && ok "it names both entries with their line numbers" || fail "the message: $(cat "$T/out")"
n=$(cd "$T/b" && find . -mindepth 1 \( -type f -o -type l \) | wc -l)
[ "$n" = 11 ] && ok "and deleted nothing ($n files and links as made)" || fail "the failed prune deleted something: $n left"

printf 'glob:*.txt\n' >"$T/list-glob"
python3 "$PRUNE" "$T/list-glob" "$T/b" >"$T/out" 2>&1 && fail "a glob: entry passes" || ok "a glob: entry is refused: $(head -1 "$T/out")"
printf '/etc/\n' >"$T/list-abs"
python3 "$PRUNE" "$T/list-abs" "$T/b" >"$T/out" 2>&1 && fail "an absolute path passes" || ok "an absolute path is refused"
printf '# nothing\n\n' >"$T/list-empty"
python3 "$PRUNE" "$T/list-empty" "$T/b" >"$T/out" 2>&1 && fail "an empty list passes" || ok "an empty list is refused"
m=$(python3 "$PRUNE" --match "$T/list" keep/sub/x dir src/rfd/x.c src/webui/x top/other.txt keeper 2>&1 | tr '\t' '=' | tr '\n' ' ')
[ "$m" = "keep/sub/x=keep dir=dir/ src/rfd/x.c=regex:^src/(?!(webui|hss_led)/) src/webui/x=- top/other.txt=- keeper=- " ] && ok "--match names the entry per path (a prefix matches whole components only)" || fail "--match: $m"

# --- 2. the real list
n=$(python3 "$PRUNE" --list "$LIST" 2>"$T/err" | wc -l)
[ "$n" -ge 15 ] && [ ! -s "$T/err" ] && ok "openccu-base-paths.txt parses: $n entries" || fail "openccu-base-paths.txt: $n entries, $(cat "$T/err")"
must='CMakeLists.txt cmake/WriteVersionHeader.cmake build-tools/bidcos-devicetype-strip licenses/licenses.md licenses/HMSL2.txt licenses/gpl-2.0.txt licenses/lgpl-2.1.txt bin/hm_autoconf bin/hm_deldev bin/hm_startup etc/config_templates/crRFD.conf firmware/rftypes/rf_cfm_tw.xml opt/HMServer/HMIPServer.jar opt/HMServer/HMServer.jar opt/HMServer/coupling/ESHBridge.jar opt/HMServer/groups/groupdefinitions.xml opt/HmIP/hmip-copro-update.jar src/rfd/rfd.cpp src/eq3_char_loop/eq3_char_loop.c src/tcl_homematic/CMakeLists.txt src/devicetypes/CMakeLists.txt src/libxmlparser/x.cpp src/libXmlRpc/x.cpp src/tclrpc/x.cpp src/webui/www/config/img/devices/250/x.png src/webui/www/config/img/devices/50/x.png src/webui/www_source/config/devdescr/x.tcl src/webui/www_source/create_devdb_tcl.tcl src/webui/www_source/utf82ansi.py src/webui/www/webui/js/lang/de/translate.lang.js src/webui/www/webui/js/lang/en/translate.lang.extension.js src/webui/www/config/stringtable_de.txt'
mustnot='src/webui/CMakeLists.txt src/webui/www/webui/webui.js src/webui/www/config/st_values.cgi src/webui/www/config/img/x.png src/webui/www_source/config/x.tcl src/hss_led/x.c src/eq3configd/x.c src/ssdpd/x.c opt/HMServer/pages/GroupListPage.ftl opt/HMServer/measurement/x.ftl opt/HMServer/templates.dit www/config/devdescr/DEVDB.tcl bin/x86_64-linux-gnu/ReGaHss bin/aarch64-linux-gnu/ssdpd lib/x86_64-linux-gnu/libeq3config.so usr/lib/tcl8.2/homematic/homematic.tcl tests/x Makefile CMakePresets.json README.md .gitignore .github/workflows/x.yml'
# shellcheck disable=SC2086
python3 "$PRUNE" --match "$LIST" $must >"$T/must" 2>&1
# shellcheck disable=SC2086
python3 "$PRUNE" --match "$LIST" $mustnot >"$T/mustnot" 2>&1
unmatched=$(awk -F'\t' '$2=="-"{print $1}' "$T/must" | tr '\n' ' ')
[ -z "$unmatched" ] && ok "every path the build reads is listed ($(wc -l <"$T/must") checked)" || fail "not listed: $unmatched"
matched=$(awk -F'\t' '$2!="-"{print $1"="$2}' "$T/mustnot" | tr '\n' ' ')
[ -z "$matched" ] && ok "nothing openccu-lite must not take is listed ($(wc -l <"$T/mustnot") checked)" || fail "listed but must not be: $matched"
grep -q '^opt/HMServer/HMServer\.jar$' "$LIST" && ok "HMServer.jar is an entry of its own (B-313)" || fail "HMServer.jar is not listed by name"
grep -Eq '^regex:\^src/' "$LIST" && grep -q 'hss_led|eq3configd|ssdpd' "$LIST" && ok "src/ is one regex that excludes the daemons occulited replaces" || fail "the src/ entry"

# --- 3. the wiring
ver=$(sed -n 's/^OPENCCU_BASE_VERSION = //p' "$MK"); compat=$(sed -n 's/^OPENCCU_BASE_COMPAT_VERSION = //p' "$MK")
[ -n "$ver" ] && [ "$ver" = "$compat" ] && echo "$ver" | grep -Eq '^[0-9]+(\.[0-9]+)+$' && ok "OPENCCU_BASE_VERSION $ver is OpenCCU-Base's release and the compat version" || fail "version '$ver', compat '$compat'"
grep -q '^OPENCCU_BASE_SITE = $(call github,OpenCCU,OpenCCU-Base,$(OPENCCU_BASE_VERSION))$' "$MK" && ok "the site is OpenCCU/OpenCCU-Base's archive of that release" || fail "OPENCCU_BASE_SITE"
grep -q '^OPENCCU_BASE_PATHS_FILE = $(OPENCCU_BASE_PKGDIR)/openccu-base-paths.txt$' "$MK" && ok "the list is openccu-base-paths.txt" || fail "OPENCCU_BASE_PATHS_FILE"
grep -q 'python3 $(OPENCCU_BASE_PKGDIR)/scripts/prune_source.py $(OPENCCU_BASE_PATHS_FILE)' "$MK" && grep -q '^OPENCCU_BASE_POST_EXTRACT_HOOKS += OPENCCU_BASE_PRUNE_SOURCE$' "$MK" \
	&& awk '/^define OPENCCU_BASE_PRUNE_SOURCE$/,/^endef$/' "$MK" | grep -q '$(OPENCCU_BASE_PRUNE_SOURCE_CMD) $(@D)' \
	&& ok "openccu-base.mk prunes the extracted source with the list" || fail "the prune hook in openccu-base.mk"
if grep -v '^[[:space:]]*#' "$MK" | grep -q 'EXTRA_DOWNLOADS\|HMSERVER_ARCHIVE\|openccu-lite-base\|DL_SUBDIR'; then fail "openccu-base.mk still has the extra download or openccu-lite-base"; else ok "no extra download, no openccu-lite-base in openccu-base.mk"; fi
grep -q 'cp -av "$(@D)/build/rootfs/opt/." "$(TARGET_DIR)/opt/"' "$MK" && grep -q 'test -s "$(TARGET_DIR)/opt/HMServer/HMServer.jar"' "$MK" && ok "the install takes HMServer.jar with the staged opt/ and insists on it" || fail "the opt/ install"
grep -q '^EQ3_CHAR_LOOP_POST_EXTRACT_HOOKS += EQ3_CHAR_LOOP_PRUNE_SOURCE$' "$EQ3" && awk '/^define EQ3_CHAR_LOOP_PRUNE_SOURCE$/,/^endef$/' "$EQ3" | grep -q '$(OPENCCU_BASE_PRUNE_SOURCE_CMD) $(@D)' \
	&& grep -q '^EQ3_CHAR_LOOP_DL_SUBDIR = openccu-base$' "$EQ3" && ok "eq3_char_loop.mk prunes the same archive from the same download directory" || fail "eq3_char_loop.mk"
grep -Eq "^sha256  [0-9a-f]{64}  openccu-base-$ver\.tar\.gz$" "$HASH" && ok "openccu-base.hash has openccu-base-$ver.tar.gz" || fail "no hash for openccu-base-$ver.tar.gz"
if grep -q 'lite\.[0-9]\|OpenCCU-Base-' "$HASH"; then fail "openccu-base.hash still names openccu-lite-base's tarball or the extra archive"; else ok "openccu-base.hash names nothing of openccu-lite-base"; fi
if grep -rq 'openccu-lite-base' "$HERE/buildroot-external/package" --include='*.mk' --include='*.hash' --include='Config.in' --exclude-dir=rootfs-patches 2>/dev/null; then
	grep -rl 'openccu-lite-base' "$HERE/buildroot-external/package" --include='*.mk' --include='*.hash' --include='Config.in' | grep -v '^[[:space:]]*#' >/dev/null
	if grep -rh 'openccu-lite-base' "$HERE/buildroot-external/package" --include='*.mk' --include='*.hash' --include='Config.in' | grep -vq '^[[:space:]]*#'; then fail "a package still builds from openccu-lite-base"; else ok "openccu-lite-base is history in the packages (comments only)"; fi
else ok "no package names openccu-lite-base"; fi

echo "--- $fails failure(s)"
[ "$fails" = 0 ]
