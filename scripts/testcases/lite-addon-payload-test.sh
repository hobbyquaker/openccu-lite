#!/bin/sh
# openccu-lite B-267: lite-addon-payload, the ExecCondition= of every addon unit, says whether a
# backup restore left an addon without its program (the addons keep it in .nobackup directories,
# whose contents a backup leaves out, as on a CCU). Exit 1 skips the unit (inactive, not failed);
# exit 0 starts it. Fake trees shaped like Mosquitto, Homematic Manager and RedMatic after a restore
# and before one; nothing needs root.
#
# Usage: sh scripts/testcases/lite-addon-payload-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
CHK="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-addon-payload"
GEN="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system-generators/occu-addons"
[ -f "$CHK" ] || { echo "lite-addon-payload not found at $CHK"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
RCD="$T/rc.d"; AD="$T/addons"
mkdir -p "$RCD" "$AD"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

wrapper() { printf '#!/bin/sh\n# openccu-lite addon-rc wrapper (stand-in)\n' > "$RCD/$1"; chmod 755 "$RCD/$1"; }
tag() { mkdir -p "$AD/$1/$2" && : > "$AD/$1/$2/.nobackup"; }
file() { mkdir -p "$(dirname "$AD/$1")" && echo x > "$AD/$1"; }

run() { # name -> rc in $rc, stderr in $T/err
  OCCU_ADDON_RCD="$RCD" OCCU_ADDONS_DIR="$AD" sh "$CHK" "$1" > "$T/out" 2> "$T/err"
  rc=$?
  [ -s "$T/out" ] && bad "$1: output on stdout: $(cat "$T/out")"
}
expect() { # name rc what
  run "$1"
  if [ "$rc" = "$2" ]; then ok "$3"; else bad "$3 (exit $rc: $(cat "$T/err"))"; fi
}

# Mosquitto after a restore: bin, lib, www hold only the tag; the script link points into bin
wrapper mosq; ln -s "$AD/mosq/bin/mosquitto-service" "$RCD/mosq.script"
tag mosq bin; tag mosq lib; tag mosq www; file mosq/etc/mosquitto.conf; file mosq/var/db
expect mosq 1 "mosquitto restored: the dangling script link skips the unit"
grep -q "addon mosq: its program files are missing (rc.d/mosq.script points to $AD/mosq/bin/mosquitto-service)" "$T/err" \
  && grep -q 'reinstall it' "$T/err" && ok "mosquitto restored: one journal line naming the link" || bad "mosquitto journal line: $(cat "$T/err")"
[ "$(wc -l < "$T/err")" = 1 ] && ok "one line only" || bad "lines: $(cat "$T/err")"

# Homematic Manager after a restore: its script is in rc.d/ (untagged), app, bin, www hold only the tag
wrapper hmm; file hmm/rc.d/hmm; ln -s "$AD/hmm/rc.d/hmm" "$RCD/hmm.script"
tag hmm app; tag hmm bin; tag hmm www; file hmm/etc/hmm.env; mkdir -p "$AD/hmm/var/cache"
expect hmm 1 "hmm restored: every tagged program directory holds only the tag"
grep -q 'app, bin, www hold only .nobackup' "$T/err" && ok "hmm: the directories named" || bad "hmm line: $(cat "$T/err")"

# ... and installed: the same tree with its program
file hmm/app/index.js; file hmm/bin/node; file hmm/www/index.html
expect hmm 0 "hmm installed: starts"
[ -s "$T/err" ] && bad "hmm installed: a journal line: $(cat "$T/err")" || ok "hmm installed: nothing said"

# one program directory emptied by hand (a cleared www) is not a missing program
rm "$AD/hmm/www/index.html"
expect hmm 0 "one emptied program directory: starts"

# RedMatic default after a restore, the caches tagged too (tmp, var/npm-cache)
wrapper rm1; ln -s "$AD/rm1/bin/redmatic" "$RCD/rm1.script"
for d in bin include lib share tmp www var/npm-cache; do tag rm1 "$d"; done
file rm1/etc/settings.json; file rm1/var/node_modules/x
expect rm1 1 "redmatic restored: skipped"
# the same with the link replaced by a real script beside it (so the tags decide)
rm "$RCD/rm1.script"; echo '#!/bin/sh' > "$RCD/rm1.script"
expect rm1 1 "redmatic restored, script present: the tags decide"
grep -q 'bin, include, lib, share, www hold only .nobackup' "$T/err" && ok "redmatic: caches not named" || bad "redmatic line: $(cat "$T/err")"

# RedMatic "full" backup: its program untagged and there, only the caches tagged and empty
wrapper rm2; ln -s "$AD/rm2/bin/redmatic" "$RCD/rm2.script"
file rm2/bin/redmatic; file rm2/lib/node_modules/x; tag rm2 tmp; tag rm2 var/npm-cache
expect rm2 0 "redmatic full: empty caches alone are no missing program"

# a wrapper without its script at all
wrapper gone
expect gone 1 "a wrapper without its script: skipped"
grep -q 'program files are missing (rc.d/gone.script)' "$T/err" && ok "gone: named" || bad "gone line: $(cat "$T/err")"

# no wrapper (an addon that was never adopted), no addon directory: nothing to decide
printf '#!/bin/sh\n' > "$RCD/plain"; chmod 755 "$RCD/plain"
expect plain 0 "an unwrapped addon without a directory: starts"
expect nothere 0 "an unknown name: starts"
expect '../x' 0 "a name with a slash: starts, nothing looked up"
expect '' 0 "no name: starts"

# the whole addon directory tagged and emptied
wrapper whole; echo '#!/bin/sh' > "$RCD/whole.script"; mkdir -p "$AD/whole"; : > "$AD/whole/.nobackup"
expect whole 1 "a tagged addon directory holding only the tag: skipped"

# a tag at depth 2 below an untagged program directory, and a tagged directory below a tagged one
wrapper deep; echo '#!/bin/sh' > "$RCD/deep.script"
tag deep share/node; file deep/share/other/x
expect deep 1 "deep: its only tagged program directory emptied"
file deep/share/node/x; tag deep share/node/inner
expect deep 0 "deep: content in the tagged directory (a tag below it does not count)"

# a symlinked directory is not followed
wrapper linked; echo '#!/bin/sh' > "$RCD/linked.script"; mkdir -p "$AD/linked" "$T/elsewhere"
: > "$T/elsewhere/.nobackup"; ln -s "$T/elsewhere" "$AD/linked/bin"
expect linked 0 "a linked directory is not followed"

# the generator puts the check first, as root, in every addon unit
R="$T/root"; E="$T/early"
mkdir -p "$R/usr/local/etc/config/rc.d" "$E"
printf '#!/bin/sh\n' > "$R/usr/local/etc/config/rc.d/any"; chmod 755 "$R/usr/local/etc/config/rc.d/any"
OCCU_ADDONS_KMSG="$T/kmsg" OCCU_ADDONS_ROOT="$R" sh "$GEN" "$T/n" "$E" "$T/l" > "$T/gout" 2>&1 || bad "generator: $(cat "$T/gout")"
grep -qx 'ExecCondition=+/usr/libexec/occu/lite-addon-payload any' "$E/addon-any.service" \
  && ok "generator: ExecCondition= with the check, as root" || bad "generator: $(grep -i condition "$E/addon-any.service")"
[ "$(grep -c '^ExecCondition=' "$E/addon-any.service")" = 1 ] && ok "generator: one condition" || bad "generator: conditions $(grep -c '^ExecCondition=' "$E/addon-any.service")"

[ "$fails" = 0 ] && echo "lite-addon-payload: all cases passed" || { echo "lite-addon-payload: $fails case(s) failed"; exit 1; }
