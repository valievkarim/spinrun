#!/bin/bash

set -o nounset -o errexit -o pipefail
[ "${XTRACE:-0}" = "1" ] && set -o xtrace

trap 'trap - INT; kill -s INT "$$"' INT


DL_DIR="$1"
INITRAMFS_DST="$2"

ORIG_DIR="$(pwd)"
ARCH="$(cat "${DL_DIR}/arch.txt")"
TMP_DIR="${ORIG_DIR}/tmp/${ARCH}"
INITRD_ROOT="${TMP_DIR}/initrd"

rm -rf "${INITRD_ROOT}"
mkdir -p "${INITRD_ROOT}"

gzip -dc "${DL_DIR}/initramfs-virt" | (cd "${INITRD_ROOT}" && cpio -idm)
tar -xpzf "${DL_DIR}/alpine-minirootfs.tar.gz" -C "${INITRD_ROOT}"


# this unpacks all kernel modules
unsquashfs -i -f -d "${INITRD_ROOT}/lib" "${DL_DIR}/modloop-virt" '*'

# That gives +56 MB of initramfs size after decompression
# It can be optimized by including only the modules you need.
# to view list of files in modloop, run: 
# unsquashfs -l dl/arm/modloop-virt
# 
# then comment unsquashfs line above and edit and uncomment the following lines:
#
# modloop_include=(
#   'modules/*/modules.*' # modules metadata, needed for module loading
#   'modules/*/kernel/drivers/firmware/qemu_fw_cfg.ko' # needed for spinrun
#   'modules/*/kernel/drivers/scsi/virtio_scsi.ko' # needed for i don't remember for what
#   'modules/*/kernel/fs/ext4/ext4.ko' # add which modules are needed (can be removed)
#   'modules/*/kernel/fs/exfat' # ... (can be removed)
# )
#
# unsquashfs -i -f -d "${INITRD_ROOT}/lib/" "${DL_DIR}/modloop-virt" "${modloop_include[@]}"


rmdir "${INITRD_ROOT}/.modloop" "${INITRD_ROOT}/newroot"

# Copy overlay files
cp -a "${ORIG_DIR}/overlay/"* "${INITRD_ROOT}/"

# Repack initrd

(cd "${INITRD_ROOT}" && find . | cpio -H newc -o --owner 0:0) | zstd -1 -T0 > "${INITRAMFS_DST}"

echo "Built initramfs image: ${INITRAMFS_DST}"
echo


