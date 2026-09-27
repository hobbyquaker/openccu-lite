#!/bin/sh
# openccu-lite: scripts/lite-hardening-guard.sh against fake image roots - it must fail on a binary
# that lost a flag (RELRO, PIE, the stack protector, a non-executable stack, a Go program that became
# dynamic, a named program missing) and pass on the image as it is meant to be, a product without
# chronyd, a merged /usr, and the files that are not ELF at all.
#
# The ELF headers come from a fake readelf: every fixture file starts with the ELF magic and then
# names its properties (type=DYN interp=yes needed=yes relro=full nx=yes canary=yes fortify=yes
# pieflag=no), and the fake prints what readelf would.
#
# Usage: sh scripts/testcases/lite-hardening-guard-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
GUARD="$HERE/scripts/lite-hardening-guard.sh"
[ -f "$GUARD" ] || { echo "lite-hardening-guard.sh not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

mkdir -p "$T/bin"
cat > "$T/bin/readelf" <<'FAKE'
#!/bin/sh
# a readelf that reads the fixture's own description
for a; do f=$a; done
head -c 4 "$f" | grep -q 'ELF' || { echo "readelf: Error: Not an ELF file" >&2; exit 1; }
type=EXEC interp=no needed=no relro=none nx=yes canary=no fortify=no pieflag=no
for kv in $(sed -n 2p "$f"); do eval "$kv"; done
case " $* " in
  *" --dyn-syms "*)
    echo "Symbol table '.dynsym' contains 3 entries:"
    [ "$canary" = yes ] && echo "     1: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND __stack_chk_fail@GLIBC_2.4 (2)"
    [ "$fortify" = yes ] && echo "     2: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND __memcpy_chk@GLIBC_2.3.4 (2)"
    exit 0 ;;
esac
echo "ELF Header:"
echo "  Type:                              $type (Executable file)"
echo "Program Headers:"
[ "$interp" = yes ] && echo "  INTERP         0x000318 0x0000000000000318 0x0000000000000318 0x00001c 0x00001c R   0x1"
echo "  LOAD           0x000000 0x0000000000000000 0x0000000000000000 0x001000 0x001000 R E 0x1000"
if [ "$nx" = yes ]; then stack="RW "; else stack="RWE"; fi
echo "  GNU_STACK      0x000000 0x0000000000000000 0x0000000000000000 0x000000 0x000000 $stack 0x10"
[ "$relro" != none ] && echo "  GNU_RELRO      0x002000 0x0000000000003000 0x0000000000003000 0x001000 0x001000 R   0x1"
echo "Dynamic section at offset 0x2000 contains 4 entries:"
[ "$needed" = yes ] && echo " 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]"
flags=""
[ "$relro" = full ] && flags="NOW"
[ "$pieflag" = yes ] && flags="$flags PIE"
[ -n "$flags" ] && echo " 0x000000006ffffffb (FLAGS_1)            Flags:$flags"
echo " 0x0000000000000000 (NULL)               0x0"
exit 0
FAKE
chmod +x "$T/bin/readelf"
export READELF="$T/bin/readelf"

# elf <path> <properties...>
elf() {
  p=$1; shift
  mkdir -p "$T/root/$(dirname "$p")"
  { printf '\177ELF\n'; echo "$*"; } > "$T/root/$p"
}
C_PIE="type=DYN interp=yes needed=yes nx=yes canary=yes fortify=yes"
clean() {
  rm -rf "$T/root"; mkdir -p "$T/root/usr/bin"
  elf usr/bin/occulited type=EXEC
  elf usr/bin/xenstore type=EXEC
  elf usr/sbin/lighttpd "$C_PIE" relro=full
  elf bin/busybox "$C_PIE" relro=full
  elf usr/sbin/chronyd "$C_PIE" relro=full
  elf usr/sbin/sshd "$C_PIE" relro=full
  elf lib/systemd/systemd "$C_PIE" relro=full
  elf lib/tclrega.so type=DYN needed=yes relro=full
  elf usr/lib/lighttpd/mod_magnet.so type=DYN needed=yes relro=full
  elf usr/lib/lighttpd/mod_proxy.so type=DYN needed=yes relro=full
  elf bin/rfd "$C_PIE" relro=partial
  elf bin/multimacd "$C_PIE" relro=partial
  elf usr/bin/rsync "$C_PIE" relro=partial
  elf usr/libexec/sftp-server "$C_PIE" relro=full
  printf '#!/bin/sh\necho a script, not ELF\n' > "$T/root/usr/bin/eQ3StartNetwork"
  printf 'plain text\n' > "$T/root/usr/sbin/notes.txt"
}
run() { sh "$GUARD" "$T/root" > "$T/out" 2>&1; }

clean
if run; then ok "the image as meant passes ($(tail -1 "$T/out"))"; else fail "the image as meant fails:"; cat "$T/out"; fi

clean
if sh "$GUARD" -v "$T/root" > "$T/out" 2>&1 && grep -q '^pie  *full  *yes  *yes  *yes  *usr/sbin/lighttpd' "$T/out" && grep -q '^static  *none .*usr/bin/occulited' "$T/out"; then
  ok "-v prints the table"; else fail "-v does not print the table:"; cat "$T/out"; fi

clean; elf usr/sbin/lighttpd "$C_PIE" relro=partial
if run; then fail "lighttpd with partial RELRO passes"; else grep -q '^usr/sbin/lighttpd: RELRO partial, expected full' "$T/out" && ok "lighttpd with partial RELRO fails, naming it" || { fail "wrong finding for lighttpd:"; cat "$T/out"; }; fi

clean; elf usr/lib/lighttpd/mod_magnet.so type=DYN needed=yes relro=partial
if run; then fail "a lighttpd module with partial RELRO passes"; else grep -q '^usr/lib/lighttpd/mod_magnet.so: RELRO partial, expected full' "$T/out" && ok "a lighttpd module with partial RELRO fails" || { fail "wrong finding for the module:"; cat "$T/out"; }; fi

clean; elf bin/busybox type=EXEC needed=yes interp=yes relro=full nx=yes canary=yes fortify=yes
if run; then fail "a non-PIE busybox passes"; else grep -q '^bin/busybox: is a exec, expected pie' "$T/out" && ok "a non-PIE busybox fails" || { fail "wrong finding for busybox:"; cat "$T/out"; }; fi

clean; elf usr/sbin/chronyd type=DYN interp=yes needed=yes relro=full nx=yes canary=no fortify=yes
if run; then fail "chronyd without the stack protector passes"; else grep -q '^usr/sbin/chronyd: no stack protector' "$T/out" && ok "chronyd without the stack protector fails" || { fail "wrong finding for chronyd:"; cat "$T/out"; }; fi

clean; elf usr/sbin/lighttpd "$C_PIE" relro=full fortify=no
if run; then fail "lighttpd without FORTIFY passes"; else grep -q '^usr/sbin/lighttpd: no FORTIFY' "$T/out" && ok "lighttpd without FORTIFY fails" || { fail "wrong finding:"; cat "$T/out"; }; fi

clean; elf usr/bin/rsync "$C_PIE" relro=partial nx=no
if run; then fail "an executable stack passes"; else grep -q '^usr/bin/rsync: executable stack' "$T/out" && ok "an executable stack fails" || { fail "wrong finding for rsync:"; cat "$T/out"; }; fi

clean; elf usr/sbin/newd type=EXEC interp=yes needed=yes relro=partial nx=yes canary=yes fortify=yes
if run; then fail "a new non-PIE daemon passes the sweep"; else grep -q '^usr/sbin/newd: is a exec, not a PIE' "$T/out" && ok "a new non-PIE daemon fails the sweep" || { fail "wrong finding for newd:"; cat "$T/out"; }; fi

clean; elf usr/bin/newtool "$C_PIE" relro=none
if run; then fail "a new PIE without RELRO passes the sweep"; else grep -q '^usr/bin/newtool: no RELRO' "$T/out" && ok "a new PIE without RELRO fails the sweep" || { fail "wrong finding for newtool:"; cat "$T/out"; }; fi

clean; elf usr/bin/occulited type=DYN interp=yes needed=yes relro=partial nx=yes
if run; then fail "a dynamic occulited passes"; else grep -q '^usr/bin/occulited: is a pie, expected static' "$T/out" && ok "a dynamic occulited fails (D-15)" || { fail "wrong finding for occulited:"; cat "$T/out"; }; fi

clean; rm "$T/root/usr/sbin/lighttpd"
if run; then fail "a missing lighttpd passes"; else grep -q '^usr/sbin/lighttpd: missing from the image' "$T/out" && ok "a missing lighttpd fails" || { fail "wrong finding for the missing lighttpd:"; cat "$T/out"; }; fi

clean; rm "$T/root/usr/sbin/chronyd" "$T/root/usr/sbin/sshd" "$T/root/bin/rfd" "$T/root/bin/multimacd"
if run; then ok "a product without chronyd, sshd and the interface daemons passes"; else fail "a product without the optional programs fails:"; cat "$T/out"; fi

clean; elf bin/rfd "$C_PIE" relro=none
if run; then fail "rfd without RELRO passes"; else grep -q '^bin/rfd: RELRO none, expected partial' "$T/out" && ok "rfd without RELRO fails" || { fail "wrong finding for rfd:"; cat "$T/out"; }; fi

# a merged /usr: lib -> usr/lib, the named paths resolve through the link, the sweep counts each file once
clean; mkdir -p "$T/root/usr/lib"; mv "$T/root/lib/systemd" "$T/root/usr/lib/systemd"; mv "$T/root/lib/tclrega.so" "$T/root/usr/lib/"; rmdir "$T/root/lib"; ln -s usr/lib "$T/root/lib"
if run; then ok "a merged /usr passes"; else fail "a merged /usr fails:"; cat "$T/out"; fi
elf usr/lib/systemd/systemd-bad type=EXEC interp=yes needed=yes relro=partial nx=yes
if run; then fail "a bad binary under the merged lib passes"; else [ "$(grep -c '^usr/lib/systemd/systemd-bad:' "$T/out")" = 1 ] && ok "a bad binary under the merged lib is reported once" || { fail "reported $(grep -c 'systemd-bad' "$T/out") times:"; cat "$T/out"; }; fi

clean; rm -rf "$T/root/usr/bin"
if run; then fail "a root without usr/bin passes"; else ok "a root without usr/bin is refused"; fi

[ "$fails" -eq 0 ] && { echo "lite-hardening-guard-test: all passed"; exit 0; }
echo "lite-hardening-guard-test: $fails failed"; exit 1
