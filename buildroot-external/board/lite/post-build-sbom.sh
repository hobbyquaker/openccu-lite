#!/bin/sh
# openccu-lite (task 179): the image's SBOM, /usr/share/openccu-lite/sbom.cdx.json.gz - CycloneDX 1.6
# with the licence texts, which occulited's /licenses page shows. The last post-build step, so it
# sees the target tree as the image gets it. scripts/lite-sbom.py --check fails the build on a gap
# (a component without a licence, a package without a component) that
# buildroot-external/sbom-exceptions.txt does not name with a reason.
set -e
top="$(cd "$(dirname "$0")/../../.." && pwd)"
if [ ! -f "${BASE_DIR}/show-info.json" ]; then
	echo "post-build (sbom): ERROR: ${BASE_DIR}/show-info.json is missing - build through the top Makefile, which writes it" >&2
	exit 1
fi
python3 "${top}/scripts/lite-sbom.py" --build-dir "${BASE_DIR}" --product "${PRODUCT}" --version "${LITE_VERSION:-0.0.0}" \
	--check --out "${TARGET_DIR}/usr/share/openccu-lite/sbom.cdx.json.gz"
