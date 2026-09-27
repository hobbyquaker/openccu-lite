#!/bin/sh
# openccu-lite: the image's binaries carry the hardening the build promises.
#
# Buildroot's flags (PIE, the stack protector, FORTIFY, RELRO) live in the toolchain wrapper and in a
# few per-package link flags (buildroot-external/lite-hardening.mk), and nothing else ever checks the
# result: a package rebuilt from a copied recipe, a bump that drops a flag, or a warm build tree that
# was never reconfigured ships with less than the flags say. This runs at the end of the lite
# post-build against the image's root, reads the ELF headers with readelf, and fails the build on a
# regression. `-v` prints the checksec-style table (one line per named file) as well.
#
# Checked:
#   - the named programs (NAMED below): the shape (a PIE, a static executable, a shared object), the
#     RELRO level (full: every symbol bound at start and the GOT read-only; partial: the GOT's
#     non-PLT part), a non-executable stack, and for the C programs the stack protector and FORTIFY
#     (both visible as imports, `__stack_chk_fail` and `__*_chk`). `full` is required where the
#     program parses what the network sends or runs as root at boot: lighttpd, busybox, chronyd,
#     sshd, systemd, the lighttpd modules and the tclrega shim. eQ-3's prebuilt interface daemons
#     (rfd, hs485d, multimacd, hmlangw) are checked as delivered: PIE, partial RELRO, NX.
#   - the Go programs (occulited, and the xe guest utilities on the ova) are static executables
#     without a libc: no interpreter, no shared library, a non-executable stack; they are not PIE,
#     because Go without cgo cannot produce a static PIE (a PIE with an interpreter is what it makes,
#     and the `-d` static PIE segfaults) - see package/occulited/occulited.mk.
#   - every other ELF file under the binary directories: a non-executable stack, and a PIE with at
#     least partial RELRO unless it is one of the Go programs above.
#
# Usage: scripts/lite-hardening-guard.sh [-v] <image root>     exit 1 with path: finding per regression
#   READELF=<path> names the readelf to use; else the toolchain's under $HOST_DIR/bin, else the host's.
set -u

VERBOSE=0
[ "${1:-}" = "-v" ] && { VERBOSE=1; shift; }
ROOT=${1:?usage: lite-hardening-guard.sh [-v] <image root>}
[ -d "$ROOT/usr/bin" ] || { echo "lite-hardening-guard: $ROOT has no usr/bin/" >&2; exit 2; }
cd "$ROOT" || exit 2

READELF=${READELF:-}
if [ -z "$READELF" ] && [ -n "${HOST_DIR:-}" ]; then
  for r in "$HOST_DIR"/bin/*-buildroot-linux-*-readelf; do
    [ -x "$r" ] && { READELF=$r; break; }
  done
fi
[ -n "$READELF" ] || READELF=$(command -v readelf) || { echo "lite-hardening-guard: no readelf found" >&2; exit 2; }

# path  shape  relro(min)  canary  fortify  presence
#   shape:  pie | static | dso        relro: full | partial | none
#   canary/fortify: yes | -           presence: must | may (checked when the product ships it)
#   (systemd's executable is a stub over libsystemd-core/-shared, so no fortified call of its own)
NAMED="
usr/bin/occulited          static none    - - must
usr/sbin/lighttpd          pie    full    yes yes must
bin/busybox                pie    full    yes yes must
usr/sbin/chronyd           pie    full    yes yes may
usr/sbin/sshd              pie    full    yes yes may
lib/systemd/systemd        pie    full    yes - must
lib/tclrega.so             dso    full    - - must
bin/rfd                    pie    partial yes yes may
bin/hs485d                 pie    partial yes yes may
bin/multimacd              pie    partial yes yes may
bin/hmlangw                pie    partial yes yes may
"
# Go programs: static, not PIE, no libc (see above)
GO_PROGRAMS="usr/bin/occulited usr/bin/xenstore usr/bin/xe-daemon"
# every ELF file under these is swept; a directory reached through a symlink (a merged /usr) is skipped
SWEEP_DIRS="bin sbin usr/bin usr/sbin usr/libexec lib/systemd usr/lib/systemd usr/lib/lighttpd"

FOUND=$(mktemp)
trap 'rm -f "$FOUND"' EXIT
ELF=$(printf '\177ELF')

# inspect <file>: sets SHAPE, RELRO, NX, CANARY, FORTIFY (readelf -h -l -d, and the dynamic symbols)
inspect() {
  hdr=$("$READELF" -h -l -d -W "$1" 2>/dev/null) || { SHAPE=not-elf; return 1; }
  type=$(printf '%s\n' "$hdr" | sed -n 's/^ *Type: *\([A-Z]*\).*/\1/p' | head -n 1)
  interp=no; printf '%s\n' "$hdr" | grep -q 'INTERP' && interp=yes
  needed=no; printf '%s\n' "$hdr" | grep -q '(NEEDED)' && needed=yes
  pieflag=no; printf '%s\n' "$hdr" | grep -q '(FLAGS_1).*PIE' && pieflag=yes
  case "$type" in
    DYN)
      if [ "$interp" = yes ]; then SHAPE=pie
      elif [ "$pieflag" = yes ]; then SHAPE=static-pie
      else SHAPE=dso; fi ;;
    EXEC)
      if [ "$interp" = no ] && [ "$needed" = no ]; then SHAPE=static; else SHAPE="exec"; fi ;;
    *) SHAPE=$type ;;
  esac
  RELRO=none
  if printf '%s\n' "$hdr" | grep -q 'GNU_RELRO'; then
    RELRO=partial
    printf '%s\n' "$hdr" | grep -Eq '\(BIND_NOW\)|\(FLAGS\).*BIND_NOW|\(FLAGS_1\).*NOW' && RELRO=full
  fi
  NX=yes
  printf '%s\n' "$hdr" | grep 'GNU_STACK' | grep -q 'RWE' && NX=no
  printf '%s\n' "$hdr" | grep -q 'GNU_STACK' || NX=none
  CANARY=-; FORTIFY=-
  if [ "$needed" = yes ]; then
    syms=$("$READELF" --dyn-syms -W "$1" 2>/dev/null)
    printf '%s\n' "$syms" | grep -q '__stack_chk_fail' && CANARY=yes
    # the fortified variants end in _chk (__memcpy_chk, __printf_chk); __stack_chk_fail is the canary's
    printf '%s\n' "$syms" | grep -Eq '__[a-z0-9_]+_chk(@|[[:space:]]|$)' && FORTIFY=yes
  fi
  return 0
}

finding() { echo "$1: $2" | tee -a "$FOUND" >&2; }

# relro_ok <have> <min>
relro_ok() {
  case "$2" in
    none) return 0 ;;
    partial) [ "$1" = partial ] || [ "$1" = full ] ;;
    full) [ "$1" = full ] ;;
  esac
}

[ "$VERBOSE" = 1 ] && printf '%-10s %-8s %-4s %-6s %-7s %s\n' SHAPE RELRO NX CANARY FORTIFY FILE

# the named programs
printf '%s\n' "$NAMED" | while read -r path shape relro canary fortify presence; do
  [ -n "$path" ] || continue
  if [ ! -f "$path" ]; then
    [ "$presence" = must ] && finding "$path" "missing from the image"
    continue
  fi
  if ! inspect "$path"; then finding "$path" "not an ELF file"; continue; fi
  [ "$VERBOSE" = 1 ] && printf '%-10s %-8s %-4s %-6s %-7s %s\n' "$SHAPE" "$RELRO" "$NX" "$CANARY" "$FORTIFY" "$path"
  [ "$SHAPE" = "$shape" ] || finding "$path" "is a $SHAPE, expected $shape"
  relro_ok "$RELRO" "$relro" || finding "$path" "RELRO $RELRO, expected $relro"
  [ "$NX" = yes ] || finding "$path" "executable stack (GNU_STACK $NX)"
  [ "$canary" = yes ] && [ "$CANARY" != yes ] && finding "$path" "no stack protector (__stack_chk_fail is not imported)"
  [ "$fortify" = yes ] && [ "$FORTIFY" != yes ] && finding "$path" "no FORTIFY (no __*_chk import)"
done

# lighttpd's modules: shared objects loaded into the one LAN-facing daemon, full RELRO like it
for m in usr/lib/lighttpd/mod_*.so; do
  [ -f "$m" ] || continue
  inspect "$m" || { finding "$m" "not an ELF file"; continue; }
  [ "$VERBOSE" = 1 ] && printf '%-10s %-8s %-4s %-6s %-7s %s\n' "$SHAPE" "$RELRO" "$NX" "$CANARY" "$FORTIFY" "$m"
  [ "$SHAPE" = dso ] || finding "$m" "is a $SHAPE, expected a shared object"
  relro_ok "$RELRO" full || finding "$m" "RELRO $RELRO, expected full"
done

# the sweep
for d in $SWEEP_DIRS; do
  [ -d "$d" ] || continue
  skip=0; p=""
  for c in $(printf '%s\n' "$d" | tr / ' '); do
    p=${p:+$p/}$c
    [ -L "$p" ] && { skip=1; break; }
  done
  [ "$skip" = 1 ] && continue
  find "$d" -type f | LC_ALL=C sort
done | while read -r f; do
  [ "$(head -c 4 "$f" 2>/dev/null)" = "$ELF" ] || continue
  inspect "$f" || continue
  [ "$NX" = yes ] || finding "$f" "executable stack (GNU_STACK $NX)"
  case " $GO_PROGRAMS " in
    *" $f "*)
      [ "$SHAPE" = static ] || finding "$f" "is a $SHAPE, expected a static executable (a Go program)"
      continue ;;
  esac
  case "$SHAPE" in
    pie|static-pie|dso) ;;
    *) finding "$f" "is a $SHAPE, not a PIE" ;;
  esac
  [ "$SHAPE" = static-pie ] || relro_ok "$RELRO" partial || finding "$f" "no RELRO"
done

if [ -s "$FOUND" ]; then
  echo "lite-hardening-guard: $(wc -l <"$FOUND" | tr -d ' ') finding(s) above - the image's binaries lost a hardening flag" >&2
  exit 1
fi
echo "lite-hardening-guard: the named programs and every ELF file under $(echo "$SWEEP_DIRS" | wc -w | tr -d ' ') binary directories carry their flags"
exit 0
