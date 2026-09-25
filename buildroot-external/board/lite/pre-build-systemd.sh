#!/bin/bash
# openccu-lite (task 20, D-30): merged-/usr copies of the overlays for the systemd products.
#
# systemd selects BR2_ROOTFS_MERGED_USR, and buildroot's target-finalize then refuses any overlay
# that carries a real /bin, /sbin or /lib ("should be missing, or be a relative symlink to
# usr/bin"). Upstream's overlays do (overlay/base/bin, overlay/base/lib, ...), and restructuring
# them is not ours to do (D-4: rebase discipline). So this runs at buildroot's `prepare` step,
# copies every source overlay named in BR2_ROOTFS_PRE_BUILD_SCRIPT_ARGS into
# $BASE_DIR/overlay-merged/<name>/ with bin, sbin and lib moved under usr/, and the product's
# BR2_ROOTFS_OVERLAY points at those copies. Same files, same order, no /bin at the top.
#
# Files that left an overlay (B-101). Buildroot copies the overlays into the target and never
# removes anything, so a unit or drop-in deleted from an overlay stayed in every incremental image.
# The previous copies are the list of what the last build put there: every file and symlink that is
# in them and in none of the new copies is removed from the target, before any package installs.
# A package may install the same path (the overlay replaced the package's file), and buildroot's
# per-package file lists that would say so are empty after <pkg>-reinstall or -rebuild. So the
# packages whose list names such a path, and every installed package without a list, lose their
# install stamps and install again - and the build stops once with "run make again", because this
# make has already read those stamps. A clean build has no previous copies and removes nothing.
# Directories stay: an empty one changes nothing on the box.
#
# Called as: pre-build-systemd.sh <target dir> <overlay dir>...
set -eu -o pipefail
shopt -s nullglob
TARGET=${1:?target dir}; shift
OUT="${BASE_DIR:?BASE_DIR from buildroot}/overlay-merged"
NEW="${OUT}.new"
PKGS="${BUILD_DIR:-${BASE_DIR}/build}"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

# every file and symlink under the given trees, as ./path, sorted, once
overlay_files() {
  local d
  for d in "$@"; do
    (cd "${d}" && find . \( -type f -o -type l \) -print)
  done | LC_ALL=C sort -u
}

rm -rf "${NEW}"
mkdir -p "${NEW}"
for src in "$@"; do
  name=$(basename "${src}")
  dst="${NEW}/${name}"
  mkdir -p "${dst}"
  [ -d "${src}" ] || continue
  # everything but the three merged directories, verbatim
  rsync -a --exclude=/bin --exclude=/sbin --exclude=/lib "${src}/" "${dst}/"
  for d in bin sbin lib; do
    if [ -d "${src}/${d}" ] && [ ! -L "${src}/${d}" ]; then
      mkdir -p "${dst}/usr/${d}"
      rsync -a "${src}/${d}/" "${dst}/usr/${d}/"
    fi
  done
done

removed=()
reinstall=()
if [ -d "${OUT}" ] && [ -d "${TARGET}" ]; then
  old=("${OUT}"/*/)
  new=("${NEW}"/*/)
  overlay_files ${old[@]+"${old[@]}"} >"${TMP}/old"
  overlay_files ${new[@]+"${new[@]}"} >"${TMP}/new"
  LC_ALL=C comm -23 "${TMP}/old" "${TMP}/new" >"${TMP}/gone"
  root=$(cd "${TARGET}" && pwd -P)
  : >"${TMP}/paths"
  while IFS= read -r p; do
    t="${TARGET}/${p#./}"
    # a file or symlink in the target; a directory there now is not the overlay's file any more
    if [ -L "${t}" ] || { [ -e "${t}" ] && [ ! -d "${t}" ]; }; then
      [ -d "$(dirname "${t}")" ] || continue
      dir=$(cd "$(dirname "${t}")" && pwd -P)
      case "${dir}/" in
        "${root}"/*) ;;
        *) printf 'overlay-merged: WARNING: %s resolves outside the target, left alone\n' "${p#.}" >&2
           continue ;;
      esac
      removed+=("${t}")
      # the path as buildroot's file lists spell it: through the target's real directories
      printf '.%s/%s\n' "${dir#"${root}"}" "$(basename "${t}")" >>"${TMP}/paths"
    fi
  done <"${TMP}/gone"

  if [ ${#removed[@]} -gt 0 ]; then
    lists=("${PKGS}"/*/.files-list.txt)
    owners=
    if [ ${#lists[@]} -gt 0 ]; then
      owners=$(awk 'NR == FNR { want[$0] = 1; next }
        { i = index($0, ","); if (i > 0 && (substr($0, i + 1) in want)) print FILENAME }' \
        "${TMP}/paths" "${lists[@]}" | LC_ALL=C sort -u)
    fi
    # a list that names a removed path: every install step of that package again, as
    # <pkg>-reinstall does (a host package can write into the target too, host-gcc-final does)
    while IFS= read -r l; do
      [ -n "${l}" ] || continue
      d=$(dirname "${l}")
      reinstall+=("${d}")
      rm -f "${d}/.stamp_installed" "${d}/.stamp_staging_installed" "${d}/.stamp_target_installed" \
        "${d}/.stamp_images_installed" "${d}/.stamp_host_installed"
    done <<<"${owners}"
    # no list: any installed target package may own a removed path; its target install again
    for s in "${PKGS}"/*/.stamp_target_installed; do
      d=$(dirname "${s}")
      [ -s "${d}/.files-list.txt" ] && continue
      reinstall+=("${d}")
      rm -f "${d}/.stamp_target_installed" "${d}/.stamp_installed"
    done
    # the stamps went first: if this stops half-way, the reinstall is still pending on the next run
    for t in "${removed[@]}"; do
      rm -f "${t}"
      printf 'overlay-merged: %s is in no overlay any more, removed from the target\n' "${t#"${TARGET}"}"
    done
  fi
fi

rm -rf "${OUT}"
mv "${NEW}" "${OUT}"
for src in "$@"; do
  printf 'overlay-merged: %s -> %s\n' "${src}" "${OUT}/$(basename "${src}")"
done

# A package installed again meets a target the finalize hooks have already shaped. The
# ca-certificates patch's hook replaces etc/ssl/certs with a link to /var/etc/ssl/certs, which
# dangles on the build host, and libopenssl's install_ssldirs then fails its "mkdir -p" on it with
# "File exists" - every incremental ARM build stopped there, where libopenssl has no file list. The
# hook makes the link again at the end of every build, after all installs, so it goes here.
if [ ${#reinstall[@]} -gt 0 ] && [ -L "${TARGET}/etc/ssl/certs" ]; then
  rm -f "${TARGET}/etc/ssl/certs"
  echo "overlay-merged: etc/ssl/certs (a link the ca-certificates hook makes again) removed for the reinstall"
fi

if [ ${#reinstall[@]} -gt 0 ]; then
  printf 'overlay-merged: install again (a list names a removed path, or no list): %s\n' \
    "$(for d in "${reinstall[@]}"; do basename "${d}"; done | tr '\n' ' ')"
  echo "overlay-merged: ERROR: files left the overlays and packages are marked for reinstall; run make again" >&2
  exit 1
fi
exit 0
