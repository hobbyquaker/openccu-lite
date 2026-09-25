#!/bin/sh
# openccu-lite: every unit the lite units name in an ordering or dependency exists in the image.
# (Also run by the lite post-build on the target, and by lite-unit-order-test.sh on the overlay.)
#
# An After=/Before= on a unit that does not exist orders nothing, silently, and a Wants= on one pulls
# nothing in. The hm_mode race of 2026-09-09 came from such an edge. This reads the lite units
# (the unit files and drop-ins in <root>/usr/lib/systemd/system that begin with "# openccu-lite")
# and looks up each name in After=, Before=, Wants=, Requires=, Requisite=, BindsTo=, PartOf=,
# Upholds=, OnFailure= and Conflicts= among the unit files of <root>.
#
# Names that exist only at run time are not missing:
#   addon-*.service   the addon generator writes them at boot
#   *.mount, *.swap, *.device, *.slice, *.scope   generated or made by systemd itself
# An instance (name@x.service) is found by its template (name@.service).
#
# Usage: lite-unit-refs.sh <root> [<name that may be missing on this product> ...]
#   prints each missing reference; exits 1 if there is one that is not listed as allowed.
set -u
ROOT=${1:?root directory (a target tree, or / on a box)}
shift
ALLOWED=" $* "
UNITDIRS="$ROOT/usr/lib/systemd/system $ROOT/lib/systemd/system $ROOT/etc/systemd/system"

exists() {
  n=$1
  case "$n" in
    addon-*.service|*.mount|*.swap|*.device|*.slice|*.scope) return 0 ;;
  esac
  t=$n
  case "$n" in
    *@?*.*) t="${n%%@*}@.${n##*.}" ;;
  esac
  for d in $UNITDIRS; do
    [ -e "$d/$n" ] || [ -L "$d/$n" ] || [ -e "$d/$t" ] && return 0
  done
  return 1
}

files=$(
  for f in "$ROOT"/usr/lib/systemd/system/* "$ROOT"/usr/lib/systemd/system/*.d/*.conf; do
    [ -f "$f" ] || continue
    head -n 1 "$f" | grep -q '^# openccu-lite' && echo "$f"
  done
)

missing=0
checked=0
for f in $files; do
  refs=$(sed -n 's/^\(After\|Before\|Wants\|Requires\|Requisite\|BindsTo\|PartOf\|Upholds\|OnFailure\|Conflicts\)=//p' "$f" | tr ' ' '\n' | grep -v '^$' | sort -u)
  for r in $refs; do
    checked=$((checked + 1))
    exists "$r" && continue
    rel=${f#"$ROOT"}
    case "$ALLOWED" in
      *" $r "*) echo "allowed missing: $r (in $rel)" ;;
      *) echo "MISSING: $r (in $rel)"; missing=$((missing + 1)) ;;
    esac
  done
done
if [ "$missing" -gt 0 ]; then
  echo "lite unit references: $missing name(s) that no unit file in $ROOT provides ($checked checked)"
  exit 1
fi
echo "lite unit references: all $checked found"
