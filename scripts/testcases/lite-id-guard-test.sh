#!/bin/sh
# openccu-lite: scripts/lite-id-guard.sh against fake repository roots - it must fail on a task,
# decision or bug id where a user reads it (a unit, a configuration file, a script's output, a
# here-document, a lite edit in a shared overlay) and pass on developer comments, upstream's own
# files and the look-alike numbers (addresses, versions). Then the fork itself must pass.
#
# Usage: sh scripts/testcases/lite-id-guard-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
GUARD="$HERE/scripts/lite-id-guard.sh"
[ -f "$GUARD" ] || { echo "lite-id-guard.sh not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

O="$T/root/buildroot-external/overlay"
# a root that passes: ids only in developer comments of scripts and in upstream's untouched files
clean() {
  rm -rf "$T/root"
  mkdir -p "$O/lite/usr/lib/systemd/system" "$O/lite/usr/libexec/occu" "$O/lite/etc/lighttpd/conf.d" \
    "$O/base/etc/init.d" "$O/base/etc/lighttpd/conf.d"
  printf '%s\n' '# openccu-lite: the daemon in the foreground, so systemd supervises it' '[Service]' \
    'ExecStart=/usr/sbin/foo -h 127.0.0.1 -v 3.89.8' > "$O/lite/usr/lib/systemd/system/foo.service"
  printf '%s\n' '#!/bin/sh' '# the marker (task 36, D-48, B-3) is read here' 'echo "starting foo"' \
    > "$O/lite/usr/libexec/occu/lite-foo"
  printf '%s\n' '#!/bin/sh' '# openccu-lite (task 35): lite edit, a developer comment' 'echo "starting"' \
    > "$O/base/etc/init.d/S50foo"
  printf '%s\n' '# upstream text that happens to say B-2 and task 7' > "$O/base/etc/lighttpd/conf.d/upstream.conf"
}
run() { sh "$GUARD" "$T/root" > "$T/out" 2>&1; }

clean
if run; then ok "a clean root passes ($(tail -1 "$T/out"))"; else fail "a clean root fails:"; cat "$T/out"; fi

clean; printf '%s\n' '# the board LEDs (task 158)' >> "$O/lite/usr/lib/systemd/system/foo.service"
if run; then fail "a unit comment with a task id passes"
else grep -q 'foo.service:4:' "$T/out" && ok "a unit comment with a task id fails, with file and line" || { fail "no file:line in the output"; cat "$T/out"; }; fi

for id in 'B-163' 'D-80' 'OQ-1' 'Q-5' 'tasks 12' 'Aufgabe 3' 'step 28.8'; do
  clean; printf '# %s\n' "$id" > "$O/lite/etc/lighttpd/conf.d/x.conf"
  if run; then fail "\"$id\" in a configuration file passes"; else ok "\"$id\" in a configuration file fails"; fi
done

clean; printf '%s\n' 'echo "done (B-3)"' >> "$O/lite/usr/libexec/occu/lite-foo"
if run; then fail "a script's output with an id passes"; else ok "a script's output with an id fails"; fi

clean; printf '%s\n' 'cat > /run/x.service <<EOF' '# written unit (task 20)' 'EOF' >> "$O/lite/usr/libexec/occu/lite-foo"
if run; then fail "a here-document comment with an id passes"; else ok "a here-document comment with an id fails"; fi

clean; printf '%s\n' 'cat <<-EOF' '	fine' '	EOF' '# after the here-document (task 20)' >> "$O/lite/usr/libexec/occu/lite-foo"
if run; then ok "a <<- here-document ends at its tab-indented token"; else fail "a <<- here-document swallows the comments after it"; cat "$T/out"; fi

clean; printf '%s\n' '#!/bin/sh' '# copied onto the userfs (task 28.8)' > "$O/lite/usr/libexec/occu/addon-rc-wrapper"
if run; then fail "a comment in a whole-checked script passes"; else ok "a comment in a whole-checked script fails"; fi

clean; printf '%s\n' '# openccu-lite (task 165, D-108): the UPnP description stays on http' > "$O/base/etc/lighttpd/conf.d/httpsredirect.conf"
if run; then fail "a lite edit in a shared overlay's configuration passes"
else grep -q 'overlay/base/etc/lighttpd/conf.d/httpsredirect.conf:1:' "$T/out" && ok "a lite edit in a shared overlay's configuration fails" || { fail "wrong finding"; cat "$T/out"; }; fi

clean; printf '%s\n' 'echo "openccu-lite: done (B-27)"' >> "$O/base/etc/init.d/S50foo"
if run; then fail "a lite edit's output in a shared overlay's script passes"; else ok "a lite edit's output in a shared overlay's script fails"; fi

clean; rm -rf "$T/root/buildroot-external/overlay/lite"
if run; then fail "a root without overlay/lite* passes"; else ok "a root without overlay/lite* is refused"; fi

if sh "$GUARD" "$HERE" > "$T/out" 2>&1; then ok "the fork passes ($(tail -1 "$T/out"))"; else fail "the fork fails:"; cat "$T/out"; fi

[ "$fails" -eq 0 ] && echo "lite-id-guard-test: all passed" || echo "lite-id-guard-test: $fails failed"
[ "$fails" -eq 0 ]
