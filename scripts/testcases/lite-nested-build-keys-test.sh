#!/bin/sh
# openccu-lite: the nested builds (multilib32, recovery-system) are keyed on their own inputs (task 353).
#
# - Their version, i.e. their build directory, holds only what needs a fresh nested tree (Buildroot,
#   the nested configuration), never OpenCCU-Base's version: a pin change used to rename both
#   directories and cost a full rebuild of the 32-bit userland and the recovery (~70-115 min a product).
# - Every variable their build passes to the nested make on the command line is one of their
#   LITE_INPUTS (packages.mk's LITE_INPUTS_STAMP): a change reruns the package from its configure step
#   in the same directory, where the nested build rebuilds only what changed.
# - LITE_INPUTS_STAMP itself, run by make against a stand-in for buildroot's stamp rule: a first run
#   builds, an unchanged input does not rebuild, a changed one does, once.
#
# Usage: sh scripts/testcases/lite-nested-build-keys-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
PKG="$HERE/buildroot-external/package"
ML="$PKG/multilib32/multilib32.mk"
RS="$PKG/recovery-system/recovery-system.mk"
PM="$PKG/packages.mk"
for f in "$ML" "$RS" "$PM"; do [ -f "$f" ] || { echo "$f not found"; exit 2; }; done
command -v make >/dev/null 2>&1 || { echo "make not found"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# a make variable's definition, continuation lines joined
mkvar() { awk -v v="$2" '
  $0 ~ "^"v" *[:?]?= " { p=1 }
  p { line=line $0; if ($0 !~ /\\$/) { print line; exit } }' "$1"; }

# 1. the versions
for pair in "MULTILIB32:$ML" "RECOVERY_SYSTEM:$RS"; do
  P=${pair%%:*}; F=${pair#*:}
  v=$(mkvar "$F" "${P}_VERSION")
  [ -n "$v" ] || { bad "$P: no ${P}_VERSION in $F"; continue; }
  case "$v" in
    *OPENCCU_BASE*) bad "$P: its version names OpenCCU-Base ($v): a pin change renames its build directory" ;;
    *) ok "$P: its version does not name OpenCCU-Base" ;;
  esac
  case "$v" in *BR2_VERSION*|*MULTILIB32_VERSION*) ok "$P: its version names Buildroot's" ;;
    *) bad "$P: its version does not name Buildroot's ($v)" ;; esac
  case "$v" in *CONFIG_HASH*|*MULTILIB32_VERSION*) ok "$P: its version names its configuration's hash" ;;
    *) bad "$P: its version has no configuration hash ($v)" ;; esac
done
v=$(mkvar "$RS" RECOVERY_SYSTEM_VERSION)
case "$v" in *MULTILIB32_VERSION*RECOVERY_SYSTEM_CONFIG_HASH*) ok "RECOVERY_SYSTEM: its version takes multilib32's and its own configuration hash" ;;
  *) bad "RECOVERY_SYSTEM: its version lacks multilib32's or its own configuration hash ($v)" ;; esac

# 2. every variable passed to the nested make on its command line is an input
for pair in "MULTILIB32:$ML" "RECOVERY_SYSTEM:$RS"; do
  P=${pair%%:*}; F=${pair#*:}
  inputs=$(mkvar "$F" "${P}_INPUTS")
  [ -n "$inputs" ] || { bad "$P: no ${P}_INPUTS"; continue; }
  grep -q "^\$(eval \$(call LITE_INPUTS_STAMP,[a-z0-9-]*,$P))" "$F" && ok "$P: LITE_INPUTS_STAMP is called" \
    || bad "$P: LITE_INPUTS_STAMP is not called for it"
  # NAME=$(VAR) or NAME="$(VAR)" in the build commands, except the paths and tools of the build itself
  # and the multilib fragment (the recovery's grep for it; it is hashed into MULTILIB32_VERSION)
  build=$(awk -v v="${P}_BUILD_CMDS" '$0 == "define "v { p=1; next } p && /^endef/ { exit } p' "$F")
  [ -n "$build" ] || { bad "$P: no ${P}_BUILD_CMDS"; continue; }
  passed=$(printf '%s\n' "$build" | grep -oE '[A-Z0-9_]+="?\$\([A-Za-z0-9_]+\)' | sed 's/^[A-Z0-9_]*="*\$(\([A-Za-z0-9_]*\))/\1/' \
    | grep -vxE 'HOSTCXX_NOCCACHE|HOSTCC_NOCCACHE|TOPDIR|[A-Z0-9_]+_PKGDIR|BR2_PACKAGE_MULTILIB32_CONFIG_FRAGMENT_FILE' | sort -u)
  n=0
  for x in $passed; do
    n=$((n+1))
    case "$inputs" in
      *"\$($x)"*|*",\$($x))"*) ok "$P: $x, passed to the nested build, is an input" ;;
      *) bad "$P: $x is passed to the nested build but is not in ${P}_INPUTS: a change would not rebuild it" ;;
    esac
  done
  [ "$n" -gt 0 ] && ok "$P: $n variables passed to the nested build found" || bad "$P: no variable passed to the nested build found - the pattern no longer matches"
done
grep -q '^\$(RECOVERY_SYSTEM_DIR)/.stamp_configured: \$(MULTILIB32_DIR)/.stamp_target_installed' "$RS" \
  && ok "RECOVERY_SYSTEM: a rebuilt multilib32 reruns the recovery's nested build" \
  || bad "RECOVERY_SYSTEM: its configure stamp does not depend on multilib32's install"
grep -q 'MULTILIB32_STALE_BASE_CMD' "$ML" && grep -q 'MULTILIB32_STALE_BASE_CMD' "$RS" \
  && ok "the nested openccu-base directories of other versions are removed (multilib32 and the recovery's copy)" \
  || bad "MULTILIB32_STALE_BASE_CMD is not used by both"

# 3. LITE_INPUTS_STAMP in make, against a stand-in for buildroot's pattern rule
sed -n '/^define LITE_INPUTS_STAMP$/,/^endef$/p' "$PM" > "$T/stamp.mk"
[ -s "$T/stamp.mk" ] || { bad "no LITE_INPUTS_STAMP in packages.mk"; }
cat > "$T/Makefile" <<'EOF'
include stamp.mk
BUILD_DIR = build
FOO_VERSION = 1
FOO_DIR = $(BUILD_DIR)/foo-$(FOO_VERSION)
FOO_INPUTS = base=$(BASE) kernel=$(KERNEL)
$(BUILD_DIR)/%/.stamp_configured:
	@mkdir -p $(@D); echo configured >> $(@D)/clog; touch $@
$(BUILD_DIR)/%/.stamp_built: $(BUILD_DIR)/%/.stamp_configured
	@mkdir -p $(@D); echo built >> $(@D)/log; touch $@
$(eval $(call LITE_INPUTS_STAMP,foo,FOO))
all: $(FOO_DIR)/.stamp_built
EOF
run() { (cd "$T" && make -s all "$@" > "$T/out" 2>&1) || { cat "$T/out"; bad "make failed ($*)"; }; }
built() { if [ -f "$T/build/foo-1/log" ]; then wc -l < "$T/build/foo-1/log" | tr -d ' '; else echo 0; fi; }
run BASE=v1.0.0-beta.3 KERNEL=6.18.56
[ "$(built)" = 1 ] && ok "a first build builds" || bad "a first build: built $(built) times"
sleep 1; run BASE=v1.0.0-beta.3 KERNEL=6.18.56
[ "$(built)" = 1 ] && ok "unchanged inputs: no rebuild" || bad "unchanged inputs rebuilt (built $(built) times)"
sleep 1; run BASE=v1.0.0-beta.4 KERNEL=6.18.56
[ "$(built)" = 2 ] && ok "a changed input rebuilds in the same directory" || bad "a changed input: built $(built) times, want 2"
grep -q 'foo: inputs changed: base=v1.0.0-beta.3 kernel=6.18.56 -> base=v1.0.0-beta.4 kernel=6.18.56' "$T/out" \
  && ok "the change is named in the log" || { bad "the change is not named in the log"; cat "$T/out"; }
sleep 1; run BASE=v1.0.0-beta.4 KERNEL=6.18.56
[ "$(built)" = 2 ] && ok "the changed input rebuilds once" || bad "the changed input rebuilt again (built $(built) times)"
sleep 1; run BASE=v1.0.0-beta.4 KERNEL=6.18.57
[ "$(built)" = 3 ] && ok "any input counts (the kernel)" || bad "a kernel change: built $(built) times, want 3"
[ "$(wc -l < "$T/build/foo-1/clog" | tr -d ' ')" = 3 ] && ok "a change reruns from the configure step (buildroot's file-list snapshot)" \
  || bad "the configure step ran $(wc -l < "$T/build/foo-1/clog" | tr -d ' ') times, want 3"
[ "$(cat "$T/build/foo-1/.lite_inputs")" = "base=v1.0.0-beta.4 kernel=6.18.57" ] && ok "the inputs file holds the current inputs" \
  || bad "the inputs file holds '$(cat "$T/build/foo-1/.lite_inputs")'"

echo; [ "$fails" -eq 0 ] && { echo "lite-nested-build-keys-test: all passed"; exit 0; }
echo "lite-nested-build-keys-test: $fails check(s) failed"; exit 1
