#!/bin/sh

# Stop on error
set -e

BOARD_DIR="$(dirname "$0")"
#BOARD_NAME="$(basename "${BOARD_DIR}")"

# Use our own cmdline.txt+config.txt
cp "${BOARD_DIR}/cmdline.txt" "${BINARIES_DIR}/"
cp "${BOARD_DIR}/config.txt" "${BINARIES_DIR}/"

#
# Create user filesystem
#
echo "Create user filesystem"
mkdir -p "${BUILD_DIR}/userfs"
touch "${BUILD_DIR}/userfs/.doFactoryReset"
rm -f "${BINARIES_DIR}/userfs.ext4"
"${HOST_DIR}/sbin/mkfs.ext4" -d "${BUILD_DIR}/userfs" -F -L userfs -I 256 -E lazy_itable_init=0,lazy_journal_init=0 "${BINARIES_DIR}/userfs.ext4" 3000

# README needs to be present, otherwise os_prefix is not
# prepended implicitly to the overlays' path, see:
# https://www.raspberrypi.com/documentation/computers/config_txt.html#overlay_prefix
touch "${BINARIES_DIR}/overlays/README" 2>/dev/null || true

#
# VERSION File
#
cp "${TARGET_DIR}/boot/VERSION" "${BINARIES_DIR}"

# create *.img file using genimage
GENIMAGE_CFG="${BOARD_DIR}/genimage.cfg"
# openccu-lite (task 366): with BR2_PACKAGE_RPI_EEPROM_OFFER the bootloader EEPROM update stays
# out of the boot partition - the boot ROM would flash it at the first start - and the image keeps
# it under /usr/share/rpi-eeprom/ for occulited's Hardware page to offer
if grep -q '^BR2_PACKAGE_RPI_EEPROM_OFFER=y' "${BR2_CONFIG}"; then
  GENIMAGE_CFG="${BUILD_DIR}/genimage-offer.cfg"
  grep -v '"rpi-eeprom/' "${BOARD_DIR}/genimage.cfg" >"${GENIMAGE_CFG}"
  if grep -q 'rpi-eeprom' "${GENIMAGE_CFG}"; then
    echo "post-image: rpi-eeprom files left in ${GENIMAGE_CFG}" >&2
    exit 1
  fi
fi
support/scripts/genimage.sh -c "${GENIMAGE_CFG}"
