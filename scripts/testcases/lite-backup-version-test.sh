#!/bin/sh
# openccu-lite (task 433): a backup's firmware_version names the openccu-lite release, against
# stand-ins (no root, no crypttool, no /usr/local):
#   - createBackup.sh writes VERSION=<base> as upstream does and, when /VERSION has a LITE= line,
#     LITE=<openccu-lite version> after it - occulited's backup inspection reads it (the kind and
#     the version of the file);
#   - without a LITE= line (upstream OpenCCU, RaspberryMatic) the file is upstream's single line;
#   - the readers still get VERSION from such a file: restoreBackup.sh sources it (and has no LITE
#     of its own to be overwritten), the recovery's restore_backup.cgi takes the VERSION= line with
#     sed, an OpenCCU/RaspberryMatic restore does the same as one of the two.
#
# Usage: sh scripts/testcases/lite-backup-version-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
CREATE="$HERE/buildroot-external/overlay/base-openccu/bin/createBackup.sh"
RESTORE="$HERE/buildroot-external/overlay/base-openccu/bin/restoreBackup.sh"
CGI="$HERE/buildroot-external/package/recovery-system/external/package/hm-platform/rootfs-overlay/www/cgi-bin/restore_backup.cgi"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# createBackup.sh is BusyBox ash with [[ ]]; bash runs the block the same way
SH="bash"
command -v bash >/dev/null 2>&1 || SH="sh"

$SH -n "$CREATE" && ok "createBackup.sh parses" || bad "createBackup.sh does not parse"

# the block that writes firmware_version, as the script has it
sed -n '/# store the firmware VERSION/,/^$/p' "$CREATE" > "$T/block"
grep -q 'firmware_version' "$T/block" && ok "the firmware_version block is found" || bad "no firmware_version block in createBackup.sh"

# run it the way createBackup.sh does: after '. /VERSION'
write() { # <VERSION file content>
  printf '%b' "$1" > "$T/VERSION"
  rm -f "$T/firmware_version"
  env -u VERSION -u LITE TMPDIR="$T" $SH -c '. "$TMPDIR/VERSION"; . "$TMPDIR/block"' > "$T/out" 2>&1
}

write 'VERSION=3.89.11\nPRODUCT=rpi4\nPLATFORM=rpi4\nVARIANT=lite\nLITE=1.3.0-beta.0\n'
if [ "$(cat "$T/firmware_version")" = "$(printf 'VERSION=3.89.11\nLITE=1.3.0-beta.0')" ]; then
  ok "openccu-lite: VERSION=3.89.11 and LITE=1.3.0-beta.0, nothing else of /VERSION"
else
  bad "openccu-lite: firmware_version is '$(cat "$T/firmware_version" 2>/dev/null)' ($(cat "$T/out"))"
fi
cp "$T/firmware_version" "$T/fv-lite"

write 'VERSION=3.89.11.20260919\nPRODUCT=rpi4\nPLATFORM=rpi4\n'
if [ "$(cat "$T/firmware_version")" = "VERSION=3.89.11.20260919" ]; then
  ok "upstream (no LITE= line): the single VERSION line as before"
else
  bad "upstream: firmware_version is '$(cat "$T/firmware_version" 2>/dev/null)' ($(cat "$T/out"))"
fi

write 'VERSION=3.89.11\nLITE=\n'
if [ "$(cat "$T/firmware_version")" = "VERSION=3.89.11" ]; then
  ok "an empty LITE= line writes no LITE line"
else
  bad "empty LITE=: firmware_version is '$(cat "$T/firmware_version" 2>/dev/null)'"
fi

# restoreBackup.sh: sources the file and takes VERSION
grep -q '^  \. "\${TMPDIR}/firmware_version"$' "$RESTORE" && grep -q '^  BACKUP_VERSION=\${VERSION}$' "$RESTORE" \
  && ok "restoreBackup.sh sources firmware_version and takes VERSION" || bad "restoreBackup.sh reads firmware_version differently now - recheck the extra line"
if grep -q 'LITE' "$RESTORE"; then
  bad "restoreBackup.sh uses a LITE variable, which the sourced line would overwrite"
else
  ok "restoreBackup.sh has no LITE of its own"
fi
got=$(VERSION=3.89.99 TMPDIR="$T"; cp "$T/fv-lite" "$T/firmware_version"; . "$T/firmware_version"; echo "$VERSION")
[ "$got" = 3.89.11 ] && ok "sourced: VERSION=3.89.11" || bad "sourced: VERSION=$got"

# the recovery: never sources it, takes the first VERSION= line with sed
line=$(grep '^BACKUP_VERSION=\$(sed' "$CGI")
[ -n "$line" ] && ok "restore_backup.cgi parses VERSION with sed" || bad "restore_backup.cgi reads firmware_version differently now - recheck the extra line"
got=$(TMPDIR="$T"; cp "$T/fv-lite" "$T/firmware_version"; eval "$line"; echo "$BACKUP_VERSION")
[ "$got" = 3.89.11 ] && ok "recovery: VERSION=3.89.11" || bad "recovery: VERSION=$got"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
