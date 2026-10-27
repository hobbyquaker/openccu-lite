#!/bin/sh
# openccu-lite: board/lite/version-file.sh writes the lite lines of /VERSION. Run in a sandbox on
# what board/post-build.sh writes before it (VERSION=<product version>, PRODUCT, PLATFORM):
# - every lite product of lite-version.mk gets upstream's PRODUCT/PLATFORM (D-31, B-27), VARIANT=lite
#   and LITE=<lite version>;
# - VERSION= is the base's three-part firmware version, 3.89.11 from BASE=3.89.11.20260919, as a
#   CCU3 writes it (task 396), and LITE-VERSION's own BASE gives three parts;
# - a BASE that is not <major>.<minor>.<patch>[.<date>] stops the build;
# - a second run changes nothing, and without LITE_BASE (an upstream product) VERSION= stays.
#
# Usage: sh scripts/testcases/lite-version-file-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$HERE/buildroot-external/board/lite/version-file.sh"
[ -f "$SCRIPT" ] || { echo "no $SCRIPT"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# run <product> <base>: the script on a fresh target; the file is $T/<product>/VERSION
run() {
  mkdir -p "$T/$1"
  printf 'VERSION=1.0.0-rc.9\nPRODUCT=%s\nPLATFORM=%s\n' "$1" "$1" > "$T/$1/VERSION"
  PRODUCT=$1 LITE_BASE=$2 LITE_VERSION=1.0.0-rc.9 sh "$SCRIPT" "$T/$1" > "$T/$1.log" 2>&1
}
expect() { # <product> <expected file content>
  if [ "$(cat "$T/$1/VERSION")" = "$2" ]; then ok "$1: $(tr '\n' ' ' < "$T/$1/VERSION")"; else fail "$1: got $(tr '\n' ' ' < "$T/$1/VERSION")"; fi
}

# every lite product, with OpenCCU's four-part tag as BASE
products=$(sed -n 's/^LITE_PRODUCTS:=//p' "$HERE/lite-version.mk")
[ -n "$products" ] || fail "no LITE_PRODUCTS in lite-version.mk"
for p in $products; do
  case "$p" in
    aarch64-rpi3) up=rpi3 pl=rpi3 ;;
    aarch64-rpi4) up=rpi4 pl=rpi4 ;;
    aarch64-rpi5) up=rpi5 pl=rpi5 ;;
    x86_64-ova)   up=ova pl=ova ;;
    lxc-lite_amd64) up=lxc_amd64 pl=lxc ;;
    lxc-lite_arm64) up=lxc_arm64 pl=lxc ;;
    *) fail "$p: a lite product this test does not know - add it here and to version-file.sh"; continue ;;
  esac
  if run "$p" 3.89.11.20260919; then
    expect "$p" "$(printf 'VERSION=3.89.11\nPRODUCT=%s\nPLATFORM=%s\nVARIANT=lite\nLITE=1.0.0-rc.9' "$up" "$pl")"
  else
    fail "$p: $(cat "$T/$p.log")"
  fi
done

# idempotent: a second run (an incremental build) changes nothing
before=$(cat "$T/aarch64-rpi4/VERSION")
PRODUCT=aarch64-rpi4 LITE_BASE=3.89.11.20260919 LITE_VERSION=1.0.0-rc.9 sh "$SCRIPT" "$T/aarch64-rpi4" >/dev/null 2>&1
[ "$(cat "$T/aarch64-rpi4/VERSION")" = "$before" ] && ok "a second run changes nothing" || fail "a second run changed /VERSION"

# a three-part BASE stays as it is
run x86_64-ova 3.90.1 && grep -qx 'VERSION=3.90.1' "$T/x86_64-ova/VERSION" && ok "BASE=3.90.1 -> VERSION=3.90.1" || fail "BASE=3.90.1: $(cat "$T/x86_64-ova/VERSION")"

# a malformed BASE stops the build
for bad in 3.89 v3.89.11 3.89.x.2026 ''; do
  [ -z "$bad" ] && continue
  if run aarch64-rpi3 "$bad"; then fail "BASE=$bad was accepted: $(cat "$T/aarch64-rpi3/VERSION")"; else ok "BASE=$bad stops the build"; fi
done

# without LITE_BASE (upstream's products): VERSION= and no LITE= line
mkdir -p "$T/up"
printf 'VERSION=3.89.11.20260919\nPRODUCT=rpi4\nPLATFORM=rpi4\n' > "$T/up/VERSION"
PRODUCT=rpi4 LITE_BASE='' sh "$SCRIPT" "$T/up" >/dev/null 2>&1
if grep -qx 'VERSION=3.89.11.20260919' "$T/up/VERSION" && ! grep -q '^LITE=' "$T/up/VERSION"; then ok "no LITE_BASE: VERSION= as it was"; else fail "no LITE_BASE: $(tr '\n' ' ' < "$T/up/VERSION")"; fi

# LITE-VERSION's own BASE gives three parts
base=$(sed -n 's/^BASE=//p' "$HERE/LITE-VERSION")
run aarch64-rpi5 "$base" && grep -Eq '^VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$T/aarch64-rpi5/VERSION" \
  && ok "LITE-VERSION's BASE=$base -> $(grep '^VERSION=' "$T/aarch64-rpi5/VERSION")" || fail "LITE-VERSION's BASE=$base: $(cat "$T/aarch64-rpi5.log")"

# the lite post-build runs it
grep -v '^[[:space:]]*#' "$HERE/buildroot-external/board/lite/post-build.sh" | grep -q 'version-file\.sh" "\${TARGET_DIR}"' \
  && ok "board/lite/post-build.sh runs version-file.sh" || fail "board/lite/post-build.sh does not run version-file.sh"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
