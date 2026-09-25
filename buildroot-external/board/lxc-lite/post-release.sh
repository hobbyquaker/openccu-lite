#!/bin/bash
# openccu-lite (D-44, task 34): the release artefacts are named openccu-lite-<product>-<version>.<ext>;
# derived from upstream's board/lxc/post-release.sh, only the names differ. The product is
# lxc-lite_amd64 / lxc-lite_arm64 in configs/, the artefact is openccu-lite-lxc-amd64-<v>.tar.xz /
# openccu-lite-lxc-arm64-<v>.tar.xz: a Proxmox CT template (pct create ... local:vztmpl/<file>),
# not a bootable image and not an update package - there is no recovery system in a container.

# Stop on error
set -e

#BOARD_DIR=${1}
PRODUCT=${2}
PRODUCT_VERSION=${3}
# lxc-lite_amd64 -> lxc-amd64
BOARD=$(echo "${PRODUCT}" | sed -e 's/^lxc-lite_/lxc-/')
NAME="openccu-lite-${BOARD}-${PRODUCT_VERSION}"

# copy the template to the release path and compress it
rm -f "./release/${NAME}.tar" "./release/${NAME}.tar.xz"
cp -a "build-${PRODUCT}/images/rootfs.tar" "./release/${NAME}.tar"
xz -z -T 0 "./release/${NAME}.tar"
(cd ./release && sha256sum "${NAME}.tar.xz" >"${NAME}.tar.xz.sha256")

# create manifest file with checksum+sizes
rm -f "./release/${NAME}.mf"

# shellcheck disable=SC2129
echo "$(stat -c %s "./release/${NAME}.tar.xz") $(cat "./release/${NAME}.tar.xz.sha256")" >>"./release/${NAME}.mf"
