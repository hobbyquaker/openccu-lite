#!/bin/bash
# openccu-lite (D-44): the release artefacts are named openccu-lite-<product>-<version>.<ext>,
# with the image inside the zip named the same way; derived from upstream's board script, only
# the names differ. The recovery takes the first *.img in the zip, whatever its name.

# Stop on error
set -e

#BOARD_DIR=${1}
PRODUCT=${2}
PRODUCT_VERSION=${3}
BOARD=${2}

# change into release dir
cd ./release

# copy the *.img and create checksum
cp -a "../build-${PRODUCT}/images/sdcard.img" "./openccu-lite-${BOARD}-${PRODUCT_VERSION}.img"
sha256sum "openccu-lite-${BOARD}-${PRODUCT_VERSION}.img" >"openccu-lite-${BOARD}-${PRODUCT_VERSION}.img.sha256"

# prepare the release *.zip
rm -f "./openccu-lite-${BOARD}-${PRODUCT_VERSION}.zip"
zip --junk-paths "./openccu-lite-${BOARD}-${PRODUCT_VERSION}.zip" "./openccu-lite-${BOARD}-${PRODUCT_VERSION}.img" "./openccu-lite-${BOARD}-${PRODUCT_VERSION}.img.sha256" ../LICENSE "./updatepkg/${PRODUCT}/EULA.de" "./updatepkg/${PRODUCT}/EULA.en"
sha256sum "openccu-lite-${BOARD}-${PRODUCT_VERSION}.zip" >"openccu-lite-${BOARD}-${PRODUCT_VERSION}.zip.sha256"

# prepare the CCU3 release tgz archive
rm -rf "/tmp/${PRODUCT}-${PRODUCT_VERSION}" 2>/dev/null
mkdir -p "/tmp/${PRODUCT}-${PRODUCT_VERSION}"

while IFS= read -r f; do
  ln -s "$(pwd)/updatepkg/${PRODUCT}/${f}" "/tmp/${PRODUCT}-${PRODUCT_VERSION}/"
done < "updatepkg/${PRODUCT}/files-package.txt"

while IFS= read -r f; do
  gzip -c "$(pwd)/../build-${PRODUCT}/images/${f}" >"/tmp/${PRODUCT}-${PRODUCT_VERSION}/${f}.gz"
done < "updatepkg/${PRODUCT}/files-images.txt"

(cd "/tmp/${PRODUCT}-${PRODUCT_VERSION}" && sha256sum ./* >"${PRODUCT}-${PRODUCT_VERSION}.sha256")
# shellcheck disable=SC2046
tar -C "/tmp/${PRODUCT}-${PRODUCT_VERSION}" --owner=root --group=root -cvzhf "./openccu-lite-${BOARD}-${PRODUCT_VERSION}-ccu3.tgz" $(ls "/tmp/${PRODUCT}-${PRODUCT_VERSION}")
sha256sum "openccu-lite-${BOARD}-${PRODUCT_VERSION}-ccu3.tgz" >"openccu-lite-${BOARD}-${PRODUCT_VERSION}-ccu3.tgz.sha256"
rm -rf "/tmp/${PRODUCT}-${PRODUCT_VERSION}" 2>/dev/null

# create manifest file with checksum+sizes
rm -f "openccu-lite-${BOARD}-${PRODUCT_VERSION}.mf"

# shellcheck disable=SC2129
echo "$(stat -c %s "./openccu-lite-${BOARD}-${PRODUCT_VERSION}.img") $(cat "openccu-lite-${BOARD}-${PRODUCT_VERSION}.img.sha256")" >>"openccu-lite-${BOARD}-${PRODUCT_VERSION}.mf"
echo "$(stat -c %s "./openccu-lite-${BOARD}-${PRODUCT_VERSION}.zip") $(cat "openccu-lite-${BOARD}-${PRODUCT_VERSION}.zip.sha256")" >>"openccu-lite-${BOARD}-${PRODUCT_VERSION}.mf"
echo "$(stat -c %s "./openccu-lite-${BOARD}-${PRODUCT_VERSION}-ccu3.tgz") $(cat "openccu-lite-${BOARD}-${PRODUCT_VERSION}-ccu3.tgz.sha256")" >>"openccu-lite-${BOARD}-${PRODUCT_VERSION}.mf"
