#!/bin/bash
# shellcheck source=/dev/null
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/utils.sh"

PACKAGE_NAME="openccu-base"
PACKAGE_DIR="buildroot-external/package/${PACKAGE_NAME}"
PACKAGE_HASH="${PACKAGE_DIR}/${PACKAGE_NAME}.hash"
DOWNLOAD_DIR="download/${PACKAGE_NAME}"
CURRENT_ID=$(sed -nE 's/^OPENCCU_BASE_VERSION = (.*)$/\1/p' "buildroot-external/package/${PACKAGE_NAME}/${PACKAGE_NAME}.mk" | head -n1)
PACKAGE_SITE=$(sed -nE 's/^OPENCCU_BASE_SITE = (.*)$/\1/p' "buildroot-external/package/${PACKAGE_NAME}/${PACKAGE_NAME}.mk" | head -n1)

function pin_type() {
  local id="${1}"
  if [[ "${id}" =~ ^[0-9a-f]{40}$ ]]; then
    echo "commit"
    return
  fi
  if [[ "${id}" =~ ^[vV]?[0-9]+(\.[0-9]+)*$ ]]; then
    echo "release"
    return
  fi
  echo "unknown"
}

CURRENT_PIN_TYPE=$(pin_type "${CURRENT_ID}")
if [[ "${CURRENT_PIN_TYPE}" == "unknown" ]]; then
  echo "Unsupported ${PACKAGE_NAME} pin format '${CURRENT_ID}'. Expected release version or 40-char commit SHA." >&2
  exit 1
fi

if [[ -n "${1}" ]]; then
  ID=${1}
else
  if [[ "${CURRENT_PIN_TYPE}" == "commit" ]]; then
    ID=$(resolve_latest_github_head_commit "OpenCCU" "OpenCCU-Base")
  else
    ID=$(strip_v_prefix "$(resolve_latest_github_stable_release_tag "OpenCCU" "OpenCCU-Base")")
  fi
fi

if [[ -z "${1}" ]]; then
  RESOLVED_PIN_TYPE=$(pin_type "${ID}")
  if [[ "${RESOLVED_PIN_TYPE}" != "${CURRENT_PIN_TYPE}" ]]; then
    echo "Refusing to switch ${PACKAGE_NAME} pin type automatically (${CURRENT_PIN_TYPE} -> ${RESOLVED_PIN_TYPE}). Use an explicit script argument to override." >&2
    exit 1
  fi

  exit_if_version_unchanged "${CURRENT_ID}" "${ID}" "${PACKAGE_NAME}"
fi

sed -i "s/^OPENCCU_BASE_VERSION = .*/OPENCCU_BASE_VERSION = ${ID}/g" "buildroot-external/package/${PACKAGE_NAME}/${PACKAGE_NAME}.mk"

# openccu-lite (task 335): the package fetches OpenCCU-Base's release archive from GitHub
# (OPENCCU_BASE_SITE is the github macro, the file openccu-base-<version>.tar.gz) and prunes it to
# openccu-base-paths.txt at the extract; upstream's git-tree download is not what the build reads.
# Download that archive, hash it, and hash the licence files out of it.
if [[ "${PACKAGE_SITE}" != *'$(call github,OpenCCU,OpenCCU-Base,'* ]]; then
  echo "OPENCCU_BASE_SITE is not the github archive macro: ${PACKAGE_SITE}" >&2
  exit 1
fi
ARCHIVE_FILE="${PACKAGE_NAME}-${ID}.tar.gz"
ARCHIVE_PATH="${DOWNLOAD_DIR}/${ARCHIVE_FILE}"
ARCHIVE_URL="https://github.com/OpenCCU/OpenCCU-Base/archive/${ID}/${ARCHIVE_FILE}"

mkdir -p "${DOWNLOAD_DIR}"
curl -fsSL --retry 3 -o "${ARCHIVE_PATH}.tmp" "${ARCHIVE_URL}"
mv -f "${ARCHIVE_PATH}.tmp" "${ARCHIVE_PATH}"

WORK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/openccu-base-update.XXXXXX")
trap 'rm -rf -- "${WORK_TMP}"' EXIT
mkdir -p "${WORK_TMP}/source"
tar -xzf "${ARCHIVE_PATH}" -C "${WORK_TMP}/source" --strip-components=1

ARCHIVE_HASH=$(sha256sum "${ARCHIVE_PATH}" | awk '{ print $1 }')
LICENSES_MD_HASH=$(sha256sum "${WORK_TMP}/source/licenses/licenses.md" | awk '{ print $1 }')
HMSL2_HASH=$(sha256sum "${WORK_TMP}/source/licenses/HMSL2.txt" | awk '{ print $1 }')
GPL2_HASH=$(sha256sum "${WORK_TMP}/source/licenses/gpl-2.0.txt" | awk '{ print $1 }')
LGPL21_HASH=$(sha256sum "${WORK_TMP}/source/licenses/lgpl-2.1.txt" | awk '{ print $1 }')

if [[ -z "${ARCHIVE_HASH}" || -z "${LICENSES_MD_HASH}" || -z "${HMSL2_HASH}" || -z "${GPL2_HASH}" || -z "${LGPL21_HASH}" ]]; then
  echo "Failed to retrieve one or more hashes for ${PACKAGE_NAME}" >&2
  exit 1
fi

cat >"${PACKAGE_HASH}" <<EOF
# Locally computed
sha256  ${LICENSES_MD_HASH}  licenses/licenses.md
sha256  ${HMSL2_HASH}  licenses/HMSL2.txt
sha256  ${GPL2_HASH}  licenses/gpl-2.0.txt
sha256  ${LGPL21_HASH}  licenses/lgpl-2.1.txt
# OpenCCU-Base's release archive from GitHub (the file the recovery's hm-platform downloads too)
sha256  ${ARCHIVE_HASH}  ${ARCHIVE_FILE}
EOF

# every listed path must exist in the new release: the prune names the ones that do not, and
# deletes nothing then
python3 "${PACKAGE_DIR}/scripts/prune_source.py" "${PACKAGE_DIR}/openccu-base-paths.txt" "${WORK_TMP}/source"
