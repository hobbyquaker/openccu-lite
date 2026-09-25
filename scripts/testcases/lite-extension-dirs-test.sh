#!/bin/sh
# openccu-lite: lite-extension-dirs against a fake root - the layers it prepares on the userfs, the
# mount it asks for (overlay where the kernel has it, a bound copy otherwise), what a start keeps
# and repairs in the writable layer, the status it reports and what a reset removes. mount, umount
# and modprobe are stand-ins on PATH that record their arguments; /proc/self/mountinfo and
# /proc/filesystems are files of the test. Nothing needs root or a kernel with overlayfs; the real
# mounts are the lab's.
#
# Usage: sh scripts/testcases/lite-extension-dirs-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-extension-dirs"
[ -f "$TOOL" ] || { echo "lite-extension-dirs not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# the stand-ins: every call appended to $T/calls; "mount -t overlay" fails when $T/overlay-fails exists
mkdir -p "$T/bin"
cat > "$T/bin/mount" <<'EOF'
#!/bin/sh
echo "mount $*" >> "${CALLS}"
case " $* " in *" -t overlay "*) [ -e "${CALLS%/*}/overlay-fails" ] && exit 32 ;; esac
exit 0
EOF
# umount empties the test's mountinfo, as the real one drops the line
printf '#!/bin/sh\necho "umount $*" >> "${CALLS}"\n: > "${MOUNTINFO_FILE}"\nexit 0\n' > "$T/bin/umount"
printf '#!/bin/sh\necho "modprobe $*" >> "${CALLS}"\nexit 1\n' > "$T/bin/modprobe"
chmod 755 "$T/bin/mount" "$T/bin/umount" "$T/bin/modprobe"
export CALLS="$T/calls" MOUNTINFO_FILE="$T/mountinfo"

R="$T/root"
IMG="$R/firmware/rftypes"
ST="$R/usr/local/etc/config/extensions/rftypes"
fresh_root() {
  rm -rf "$R"; : > "$CALLS"
  mkdir -p "$IMG/replaceMap" "$R/usr/local/addons/hb/firmware/rftypes"
  for n in rf_4dis.xml rf_cfm_tw.xml rf_sec_sc.xml; do echo "<device name=\"$n\"/>" > "$IMG/$n"; done
  echo "<map/>" > "$IMG/replaceMap/rfReplaceMap.xml"
  echo "<device name=\"hb-uni\"/>" > "$R/usr/local/addons/hb/firmware/rftypes/hb-uni.xml"
}
with_overlay() { printf 'nodev\tsysfs\nnodev\toverlay\n\text4\n' > "$T/filesystems"; }
without_overlay() { printf 'nodev\tsysfs\n\text4\n' > "$T/filesystems"; }
not_mounted() { : > "$T/mountinfo"; }
mounted_overlay() { printf '30 20 0:40 / /firmware/rftypes rw,relatime shared:5 - overlay overlay rw,lowerdir=/firmware/rftypes,upperdir=%s/upper,workdir=%s/work\n' "$ST" "$ST" > "$T/mountinfo"; }
mounted_copy() { printf '31 20 8:3 /etc/config/extensions/rftypes/copy /firmware/rftypes rw,noatime shared:6 - ext4 /dev/sda3 rw\n' > "$T/mountinfo"; }

run() { OCCU_EXT_ROOT="$R" OCCU_EXT_MOUNTINFO="$T/mountinfo" OCCU_EXT_FILESYSTEMS="$T/filesystems" PATH="$T/bin:$PATH" sh "$TOOL" "$@"; }
status_val() { run status /firmware/rftypes | sed -n "s/^$1=//p"; }

# --- overlay: the first boot ----------------------------------------------------------------------
fresh_root; with_overlay; not_mounted
out=$(run start 2>&1); rc=$?
[ "$rc" = 0 ] && ok "overlay start exits 0" || bad "overlay start exits $rc: $out"
[ -d "$ST/upper" ] && [ -d "$ST/work" ] && ok "upper and work created on the userfs" || bad "layers missing under $ST"
[ -f "$ST/work/.nobackup" ] && ok "the work directory is out of the backup" || bad "no .nobackup in work"
if [ "$(cat "$ST/image-names")" = "$(printf 'replaceMap\nrf_4dis.xml\nrf_cfm_tw.xml\nrf_sec_sc.xml')" ]; then ok "image-names lists the image's entries"; else bad "image-names: $(tr '\n' ' ' < "$ST/image-names")"; fi
want="mount -t overlay overlay -o lowerdir=$IMG,upperdir=$ST/upper,workdir=$ST/work $IMG"
if grep -qxF "$want" "$CALLS"; then ok "the overlay mount over the image's directory"; else bad "mount calls: $(cat "$CALLS")"; fi
grep -q modprobe "$CALLS" && bad "modprobe called although overlay is in /proc/filesystems" || ok "no modprobe when the kernel has overlayfs"
case "$out" in *"overlay, additions in /usr/local/etc/config/extensions/rftypes/upper"*) ok "says where the additions go" ;; *) bad "output: $out" ;; esac

# --- overlay: what a start keeps, what status counts -----------------------------------------------
mounted_overlay
ln -s /usr/local/addons/hb/firmware/rftypes/hb-uni.xml "$ST/upper/hb-uni.xml"   # an addon's addition
echo "patched" > "$ST/upper/rf_4dis.xml"                                       # an image file copied up and changed
: > "$CALLS"
out=$(run start 2>&1)
grep -q '^mount' "$CALLS" && bad "a start while mounted mounted again: $(cat "$CALLS")" || ok "a start while mounted mounts nothing"
case "$out" in *"already writable (overlay)"*) ok "and says so" ;; *) bad "output: $out" ;; esac
[ -L "$ST/upper/hb-uni.xml" ] && [ -f "$ST/upper/rf_4dis.xml" ] && ok "a start keeps additions and replacements" || bad "the upper layer was changed by a start"
[ "$(status_val mode)" = overlay ] && ok "status: mode=overlay" || bad "status mode: $(status_val mode)"
[ "$(status_val image)" = 4 ] && ok "status: image=4" || bad "status image: $(status_val image)"
[ "$(status_val added)" = 1 ] && ok "status: added=1 (the addon's link)" || bad "status added: $(status_val added)"
[ "$(status_val replaced)" = 1 ] && ok "status: replaced=1 (the changed image file)" || bad "status replaced: $(status_val replaced)"
[ "$(status_val removed)" = 0 ] && ok "status: removed=0" || bad "status removed: $(status_val removed)"
[ "$(status_val state)" = /usr/local/etc/config/extensions/rftypes ] && ok "status: the state directory" || bad "status state: $(status_val state)"

# --- overlay: reset ------------------------------------------------------------------------------
: > "$CALLS"
out=$(run reset /firmware/rftypes 2>&1); rc=$?
[ "$rc" = 0 ] && ok "reset exits 0" || bad "reset exits $rc: $out"
[ "$(sed -n 1p "$CALLS")" = "umount $IMG" ] && ok "reset unmounts first" || bad "reset's first call: $(sed -n 1p "$CALLS")"
[ ! -e "$ST/upper/rf_4dis.xml" ] && ok "reset removes the replaced image file from the upper layer" || bad "rf_4dis.xml still in upper"
[ -L "$ST/upper/hb-uni.xml" ] && ok "reset keeps the addon's addition" || bad "the addition is gone"
grep -qxF "$want" "$CALLS" && ok "reset mounts the overlay again" || bad "calls after reset: $(cat "$CALLS")"
case "$out" in *"1 image file(s) restored"*) ok "reset says what it restored" ;; *) bad "reset output: $out" ;; esac

# --- overlay mount refused: the copy as the fallback ---------------------------------------------
fresh_root; with_overlay; not_mounted; touch "$T/overlay-fails"
out=$(run start 2>&1); rc=$?
rm -f "$T/overlay-fails"
[ "$rc" = 0 ] && ok "a refused overlay mount falls back, exit 0" || bad "fallback exit $rc: $out"
grep -qxF "mount -o bind $ST/copy $IMG" "$CALLS" && ok "the copy is bound over the directory" || bad "calls: $(cat "$CALLS")"
[ -f "$ST/copy/rf_4dis.xml" ] && [ -f "$ST/copy/replaceMap/rfReplaceMap.xml" ] && ok "the copy holds the image's files and replaceMap" || bad "copy incomplete: $(ls -R "$ST/copy")"

# --- no overlayfs in the kernel: the copy --------------------------------------------------------
fresh_root; without_overlay; not_mounted
out=$(run start 2>&1); rc=$?
[ "$rc" = 0 ] && ok "copy start exits 0" || bad "copy start exits $rc: $out"
grep -qx "modprobe overlay" "$CALLS" && ok "the module is tried first" || bad "no modprobe: $(cat "$CALLS")"
grep -qxF "mount -o bind $ST/copy $IMG" "$CALLS" && ok "the copy is bound over the directory" || bad "calls: $(cat "$CALLS")"
[ ! -d "$ST/upper" ] && ok "no upper layer in copy mode" || bad "an upper layer was made without overlayfs"
[ "$(cat "$ST/copy/rf_sec_sc.xml")" = '<device name="rf_sec_sc.xml"/>' ] && ok "the copy is the image's content" || bad "copy content differs"
case "$out" in *"a copy on the userfs"*) ok "says it is a copy" ;; *) bad "output: $out" ;; esac

# --- copy: repair at the next boot, replacements kept, status --------------------------------------
mounted_copy
ln -s /usr/local/addons/hb/firmware/rftypes/hb-uni.xml "$ST/copy/hb-uni.xml"          # an addition
rm -f "$ST/copy/rf_cfm_tw.xml"                                                        # a stray delete
rm -f "$ST/copy/rf_sec_sc.xml"; ln -s /usr/local/addons/hb/x.xml "$ST/copy/rf_sec_sc.xml"  # an addon's replacement
[ "$(status_val removed)" = 1 ] && ok "status before the repair: removed=1" || bad "status removed: $(status_val removed)"
[ "$(status_val replaced)" = 1 ] && ok "status: replaced=1 (a link with an image name)" || bad "status replaced: $(status_val replaced)"
[ "$(status_val added)" = 1 ] && ok "status: added=1" || bad "status added: $(status_val added)"
[ "$(status_val mode)" = copy ] && ok "status: mode=copy" || bad "status mode: $(status_val mode)"
# the next boot: the directory is not mounted yet, the copy is synced from the image again
not_mounted; : > "$CALLS"
run start > /dev/null 2>&1
[ -f "$ST/copy/rf_cfm_tw.xml" ] && ok "a start copies a deleted image file again" || bad "rf_cfm_tw.xml not restored"
[ -L "$ST/copy/rf_sec_sc.xml" ] && ok "a start keeps an addon's replacement" || bad "the replacement was overwritten"
[ -L "$ST/copy/hb-uni.xml" ] && ok "a start keeps the addition" || bad "the addition is gone"
echo "<device name=\"rf_4dis.xml\" v=\"2\"/>" > "$IMG/rf_4dis.xml"   # a firmware update's new version
run start > /dev/null 2>&1
grep -q 'v="2"' "$ST/copy/rf_4dis.xml" && ok "a start refreshes an image file from the new image" || bad "the copy kept the old version"

# --- copy: reset ---------------------------------------------------------------------------------
mounted_copy; : > "$CALLS"
out=$(run reset /firmware/rftypes 2>&1); rc=$?
[ "$rc" = 0 ] && ok "copy reset exits 0" || bad "copy reset exits $rc: $out"
[ "$(sed -n 1p "$CALLS")" = "umount $IMG" ] && ok "copy reset unmounts first" || bad "first call: $(sed -n 1p "$CALLS")"
[ -f "$ST/copy/rf_sec_sc.xml" ] && [ ! -L "$ST/copy/rf_sec_sc.xml" ] && ok "reset puts the image file back over the replacement" || bad "rf_sec_sc.xml: $(ls -l "$ST/copy/rf_sec_sc.xml")"
[ -L "$ST/copy/hb-uni.xml" ] && ok "reset keeps the addition" || bad "the addition is gone after reset"
grep -qxF "mount -o bind $ST/copy $IMG" "$CALLS" && ok "reset binds the copy again" || bad "calls: $(cat "$CALLS")"

# --- the forced mode, the refusals, an absent directory ------------------------------------------
fresh_root; with_overlay; not_mounted
OCCU_EXT_MODE=copy run start > /dev/null 2>&1
grep -q "^mount -t overlay" "$CALLS" && bad "OCCU_EXT_MODE=copy still mounted an overlay" || ok "OCCU_EXT_MODE=copy forces the copy"
run reset /etc > /dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "reset of a directory that is not an extension directory is refused" || bad "reset /etc exits $rc"
fresh_root; not_mounted
[ "$(status_val mode)" = none ] && ok "status: mode=none before the mount" || bad "status mode: $(status_val mode)"
rm -rf "$IMG"; : > "$CALLS"
out=$(run start 2>&1); rc=$?
[ "$rc" = 0 ] && ! grep -q '^mount' "$CALLS" && ok "an absent directory is skipped, exit 0" || bad "absent directory: rc=$rc calls=$(cat "$CALLS")"
run > /dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "no action: usage, exit 2" || bad "no action exits $rc"

[ "$fails" = 0 ] && echo "lite-extension-dirs: all checks passed" || echo "lite-extension-dirs: $fails check(s) failed"
[ "$fails" = 0 ]
