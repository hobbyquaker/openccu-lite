#!/bin/sh
# openccu-lite: the WebUI's files addons read on a CCU (task 331) - the device pictures, DEVDB.tcl,
# stringtable_de.txt and translate.lang*.js at the CCU's paths under /www.
#
# 1. board/lite/webui-files-guard.sh on fake targets: the files as package/openccu-base installs
#    them pass; another file, a directory of the WebUI, a link, a picture outside 50/ and 250/, a
#    file not 0644, a directory not 0755, a missing DEVDB.tcl or too few pictures stop the build.
# 2. rootfs-patches/lite_series.py keeps a patch's sections on exactly those files (and everything
#    outside www/ and opt/HMServer/pages/), and drops the rest of www/.
# 3. rootfs-patches/stage_lite_www.sh on a made-up source tree: the files staged with their modes,
#    DEVDB.tcl generated in sorted order whatever order the file system lists the descriptions in,
#    and a source without the pictures refused. Needs tclsh (skipped without it, said so).
# 4. post-build.sh runs the guard, the lite webui.conf serves the paths, and the series of the
#    real stack still keeps the sections that are not www/.
#
# Usage: sh scripts/testcases/lite-webui-files-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$HERE/buildroot-external"
GUARD="$EXT/board/lite/webui-files-guard.sh"
RP="$EXT/package/openccu-base/rootfs-patches"
[ -f "$GUARD" ] || { echo "webui-files-guard.sh not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# --- 1. the guard
good_target() {
  rm -rf "$T/t"
  mkdir -p "$T/t/www/config/img/devices/250/coupling" "$T/t/www/config/img/devices/50/coupling" \
    "$T/t/www/config/devdescr" "$T/t/www/webui/js/lang/de" "$T/t/www/webui/js/lang/en"
  ln -s /etc/config/addons/www "$T/t/www/addons"
  i=0
  while [ $i -lt 100 ]; do
    echo png >"$T/t/www/config/img/devices/250/${i}_dev.png"
    echo png >"$T/t/www/config/img/devices/50/${i}_dev_thumb.png"
    i=$((i+1))
  done
  echo png >"$T/t/www/config/img/devices/250/coupling/c.png"
  echo png >"$T/t/www/config/img/devices/50/coupling/c.png"
  echo 'set DEV_LIST {}' >"$T/t/www/config/devdescr/DEVDB.tcl"
  echo 'x' >"$T/t/www/config/stringtable_de.txt"
  for l in de en; do
    echo 'x' >"$T/t/www/webui/js/lang/$l/translate.lang.js"
    echo 'x' >"$T/t/www/webui/js/lang/$l/translate.lang.extension.js"
  done
  find "$T/t/www/config" "$T/t/www/webui" -type d -exec chmod 0755 {} +
  find "$T/t/www/config" "$T/t/www/webui" -type f -exec chmod 0644 {} +
}
passes() { if sh "$GUARD" "$T/t" >"$T/out" 2>&1; then ok "$1"; else fail "$1: $(cat "$T/out")"; fi; }
stops()  { if sh "$GUARD" "$T/t" >"$T/out" 2>&1; then fail "$1: the guard let it through"; else ok "$1: $(head -n 1 "$T/out" | cut -c 1-160)"; fi; }

good_target; passes "the files as package/openccu-base installs them"
good_target; passes "the same target twice"
good_target; echo x >"$T/t/www/config/cp_security.cgi"; chmod 0644 "$T/t/www/config/cp_security.cgi"; stops "a WebUI CGI next to them"
good_target; mkdir -m 0755 "$T/t/www/config/easymodes"; stops "the easymodes directory"
good_target; echo x >"$T/t/www/webui/webui.js"; chmod 0644 "$T/t/www/webui/webui.js"; stops "webui.js"
good_target; echo x >"$T/t/www/webui/js/lang/translate.js"; chmod 0644 "$T/t/www/webui/js/lang/translate.js"; stops "the translations' loader"
good_target; echo x >"$T/t/www/config/devdescr/100_hm-rc-8.tcl"; chmod 0644 "$T/t/www/config/devdescr/100_hm-rc-8.tcl"; stops "a device description next to DEVDB.tcl"
good_target; mkdir -m 0755 "$T/t/www/config/img/devices/100"; echo png >"$T/t/www/config/img/devices/100/a.png"; chmod 0644 "$T/t/www/config/img/devices/100/a.png"; stops "a picture outside 50/ and 250/"
good_target; echo x >"$T/t/www/config/img/devices/250/a.png.orig"; chmod 0644 "$T/t/www/config/img/devices/250/a.png.orig"; stops "a patch's .orig among the pictures"
good_target; ln -s /etc/shadow "$T/t/www/config/img/devices/250/x.png"; stops "a link among the pictures"
good_target; chmod 0664 "$T/t/www/config/devdescr/DEVDB.tcl"; stops "DEVDB.tcl group-writable"
good_target; chmod 0700 "$T/t/www/config/img/devices/50"; stops "a directory 0700"
good_target; rm "$T/t/www/config/devdescr/DEVDB.tcl"; stops "DEVDB.tcl missing"
good_target; rm "$T/t/www/webui/js/lang/en/translate.lang.js"; stops "the English translate.lang.js missing"
good_target; rm "$T/t/www/config/img/devices/50/1"*_thumb.png; stops "fewer than 100 small pictures"

# --- 2. lite_series.py
mkdir -p "$T/rp"
cat >"$T/rp/0001-a.patch" <<'EOF'
--- a/www/config/devdescr/DEVDB.tcl
+++ b/www/config/devdescr/DEVDB.tcl
@@ -1 +1 @@
-a
+b
--- a/www/webui/webui.js
+++ b/www/webui/webui.js
@@ -1 +1 @@
-a
+b
--- a/www/webui/js/lang/de/translate.lang.extension.js
+++ b/www/webui/js/lang/de/translate.lang.extension.js
@@ -1 +1 @@
-a
+b
--- a/www/webui/js/lang/translate.js
+++ b/www/webui/js/lang/translate.js
@@ -1 +1 @@
-a
+b
--- a/www/config/stringtable_de.txt
+++ b/www/config/stringtable_de.txt
@@ -1 +1 @@
-a
+b
--- a/www/config/img/devices/250/coupling/c.png
+++ b/www/config/img/devices/250/coupling/c.png
@@ -1 +1 @@
-a
+b
--- a/www/config/easymodes/x.tcl
+++ b/www/config/easymodes/x.tcl
@@ -1 +1 @@
-a
+b
--- a/opt/HMServer/pages/x.ftl
+++ b/opt/HMServer/pages/x.ftl
@@ -1 +1 @@
-a
+b
--- a/bin/hm_startup
+++ b/bin/hm_startup
@@ -1 +1 @@
-a
+b
EOF
cat >"$T/rp/0002-b.patch" <<'EOF'
--- a/www/webui/webui.js
+++ b/www/webui/webui.js
@@ -1 +1 @@
-b
+c
EOF
printf '0001-a.patch\n0002-b.patch\n' >"$T/rp/series"
if python3 "$RP/lite_series.py" "$T/rp" "$T/lite" >"$T/out" 2>&1; then
  got=$(grep '^+++ ' "$T/lite/0001-a.patch" | sed 's/^+++ b\///' | tr '\n' ' ')
  want="www/config/devdescr/DEVDB.tcl www/webui/js/lang/de/translate.lang.extension.js www/config/stringtable_de.txt www/config/img/devices/250/coupling/c.png bin/hm_startup "
  if [ "$got" = "$want" ]; then ok "lite_series keeps the WebUI files' sections and drops the rest of www/"; else fail "lite_series kept: $got"; fi
  if [ "$(cat "$T/lite/series")" = "0001-a.patch" ] && [ ! -e "$T/lite/0002-b.patch" ]; then ok "a patch left empty leaves the series"; else fail "the series: $(cat "$T/lite/series")"; fi
else
  fail "lite_series.py: $(cat "$T/out")"
fi
rm -rf "$T/lite2"
if python3 "$RP/lite_series.py" "$RP" "$T/lite2" >"$T/out" 2>&1; then
  for p in 0003-rftypes-Fix.patch 0034-WebUI-Addon-Config.patch 0072-WebUI-Fix-hm_autoconf.patch 0109-WebUI-Fix-SystemLanguageDefaultNames.patch; do
    if grep -qx "$p" "$T/lite2/series"; then ok "the real series keeps $p"; else fail "the real series lost $p"; fi
  done
  if grep -h '^+++ ' "$T/lite2"/*.patch | sed 's/^+++ b\///' | grep '^www/' | grep -Ev '^www/(config/devdescr/DEVDB\.tcl|config/stringtable_de\.txt|webui/js/lang/[^/]+/translate\.lang[^/]*\.js|config/img/devices/(50|250)/.*)$'; then
    fail "the real series keeps other www/ sections (above)"
  else
    ok "the real series keeps no other www/ section"
  fi
else
  fail "lite_series.py on the real series: $(cat "$T/out")"
fi

# --- 3. stage_lite_www.sh
TCLSH=$(command -v tclsh8.6 || command -v tclsh || true)
if [ -n "$TCLSH" ]; then
  S="$T/src"
  mkdir -p "$S/src/webui/www/config/img/devices/250/coupling" "$S/src/webui/www/config/img/devices/50" \
    "$S/src/webui/www/webui/js/lang/de" "$S/src/webui/www/webui/js/lang/en" "$S/src/webui/www_source/config/devdescr"
  echo png >"$S/src/webui/www/config/img/devices/250/1_a.png"
  echo png >"$S/src/webui/www/config/img/devices/250/coupling/c.png"
  echo png >"$S/src/webui/www/config/img/devices/50/1_a_thumb.png"
  echo st >"$S/src/webui/www/config/stringtable_de.txt"
  echo de >"$S/src/webui/www/webui/js/lang/de/translate.lang.js"
  echo en >"$S/src/webui/www/webui/js/lang/en/translate.lang.js"
  echo loader >"$S/src/webui/www/webui/js/lang/translate.js"
  # upstream's generator, cut down to what decides the output: the glob over the descriptions
  cat >"$S/src/webui/www_source/create_devdb_tcl.tcl" <<'EOF'
set DEV_LIST ""
foreach file [glob -nocomplain [file join "config/devdescr/*.tcl"]] {
  set TYPE ""
  source $file
  lappend DEV_LIST $TYPE
}
set fd [open DEVDB.tcl w]
puts $fd "set DEV_LIST [list $DEV_LIST]"
close $fd
EOF
  printf 'import sys\n' >"$S/src/webui/www_source/utf82ansi.py"
  # created out of order, so a directory listing in creation order is not sorted
  for t in zz mm aa kk; do echo "set TYPE $t" >"$S/src/webui/www_source/config/devdescr/$t.tcl"; done
  chmod 0600 "$S/src/webui/www/config/stringtable_de.txt"
  if bash "$RP/stage_lite_www.sh" "$S" "$T/r" "$TCLSH" python3 >"$T/out" 2>&1; then
    if [ "$(cat "$T/r/www/config/devdescr/DEVDB.tcl")" = "set DEV_LIST {aa kk mm zz}" ]; then ok "DEVDB.tcl generated in sorted order"; else fail "DEVDB.tcl: $(cat "$T/r/www/config/devdescr/DEVDB.tcl")"; fi
    got=$(cd "$T/r/www" && find . -type f | sort | tr '\n' ' ')
    want="./config/devdescr/DEVDB.tcl ./config/img/devices/250/1_a.png ./config/img/devices/250/coupling/c.png ./config/img/devices/50/1_a_thumb.png ./config/stringtable_de.txt ./webui/js/lang/de/translate.lang.js ./webui/js/lang/en/translate.lang.js "
    if [ "$got" = "$want" ]; then ok "the staged files, and not the loader"; else fail "staged: $got"; fi
    if [ -z "$(cd "$T/r/www" && { find . -type f ! -perm 0644; find . -type d ! -perm 0755; })" ]; then ok "files 0644, directories 0755"; else fail "modes: $(cd "$T/r/www" && find . ! -perm 0644 ! -perm 0755)"; fi
  else
    fail "stage_lite_www.sh: $(cat "$T/out")"
  fi
  rm -rf "$S/src/webui/www/config/img/devices/50"
  if bash "$RP/stage_lite_www.sh" "$S" "$T/r2" "$TCLSH" python3 >"$T/out" 2>&1; then fail "a source without the small pictures was staged"; else ok "a source without the small pictures is refused: $(cat "$T/out")"; fi
else
  echo "skip stage_lite_www.sh: no tclsh here"
fi

# --- 4. the wiring
if grep -v '^[[:space:]]*#' "$EXT/board/lite/post-build.sh" | grep -q 'webui-files-guard\.sh" "\${TARGET_DIR}"'; then ok "post-build.sh runs the guard"; else fail "post-build.sh does not run webui-files-guard.sh"; fi
if grep -v '^[[:space:]]*#' "$EXT/package/openccu-base/openccu-base.mk" | grep -q 'stage_lite_www\.sh'; then ok "openccu-base.mk stages the files"; else fail "openccu-base.mk does not run stage_lite_www.sh"; fi
# the source they are staged from survives the prune to openccu-base-paths.txt (task 335)
unlisted=$(python3 "$EXT/package/openccu-base/scripts/prune_source.py" --match "$EXT/package/openccu-base/openccu-base-paths.txt" \
  src/webui/www/config/img/devices/250/x.png src/webui/www/config/img/devices/50/x.png src/webui/www/config/stringtable_de.txt \
  src/webui/www_source/config/devdescr/x.tcl src/webui/www_source/create_devdb_tcl.tcl src/webui/www_source/utf82ansi.py \
  src/webui/www/webui/js/lang/de/translate.lang.js src/webui/www/webui/js/lang/en/translate.lang.extension.js 2>&1 | awk -F'\t' '$2=="-"{print $1}' | tr '\n' ' ')
if [ -z "$unlisted" ]; then ok "openccu-base-paths.txt keeps what stage_lite_www.sh reads"; else fail "openccu-base-paths.txt drops: $unlisted"; fi
if grep -v '^[[:space:]]*#' "$EXT/overlay/lite/etc/lighttpd/conf.d/webui.conf" | grep -qF 'config/(img/devices/|devdescr/DEVDB\.tcl$|stringtable_de\.txt$)|webui/js/lang/'; then ok "the lite webui.conf serves the paths"; else fail "the lite webui.conf has no block for the paths"; fi

[ "$fails" -eq 0 ] && echo "lite-webui-files-test: all passed" || echo "lite-webui-files-test: $fails failed"
[ "$fails" -eq 0 ]
