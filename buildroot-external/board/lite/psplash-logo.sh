#!/bin/sh
# openccu-lite: the boot splash shows the openccu-lite logo - OpenCCU's logo with "lite" beside it,
# made like the web UI's wordmark - and not upstream's patches/psplash/logo.png, which stays for the
# upstream products. psplash builds the image that BR2_PACKAGE_PSPLASH_IMAGE names into its binary,
# and package/recovery-system passes the same variable to the recovery system's build, so the
# product configuration decides both. This stops the build when a product with psplash names any
# other image. A product without psplash (the containers) is not checked.
#
# Usage: psplash-logo.sh <BR2_CONFIG>
set -u
CONFIG=${1:?usage: psplash-logo.sh <BR2_CONFIG>}
# shellcheck disable=SC2016 # the configuration keeps the make variable unexpanded
LOGO='$(BR2_EXTERNAL_EQ3_PATH)/board/lite/psplash/logo.png'

grep -qx 'BR2_PACKAGE_PSPLASH=y' "${CONFIG}" || exit 0
grep -qxF "BR2_PACKAGE_PSPLASH_IMAGE=\"${LOGO}\"" "${CONFIG}" && exit 0
echo "post-build (lite): psplash must use ${LOGO}; the configuration has: $(grep '^BR2_PACKAGE_PSPLASH_IMAGE=' "${CONFIG}" || echo 'no image')" >&2
exit 1
