#!/bin/bash

set -o nounset -o errexit -o pipefail
[ "${XTRACE:-0}" = "1" ] && set -o xtrace

trap 'trap - INT; kill -s INT "$$"' INT

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <arch> <dest_dir>"
    echo "  arch: aarch64 or x86_64"
    exit 1
fi

ARCH="$1"
DL_DIR="$2"

[ "${ARCH}" = "aarch64" ] || [ "${ARCH}" = "x86_64" ] || { echo "ARCH must be aarch64 or x86_64"; exit 1; }

VER="3.21.3"
URL="https://dl-cdn.alpinelinux.org/alpine/v${VER%.*}/releases/${ARCH}"

rm -f "${DL_DIR}"/{arch.txt,vmlinuz-virt,modloop-virt,initramfs-virt,alpine-minirootfs.tar.gz}

cd "${DL_DIR}"
echo "${ARCH}" > arch.txt

set -o xtrace

curl -o vmlinuz-virt "${URL}/netboot/vmlinuz-virt"
curl -o modloop-virt "${URL}/netboot/modloop-virt"
curl -o alpine-minirootfs.tar.gz "${URL}/alpine-minirootfs-${VER}-${ARCH}.tar.gz"
curl -o initramfs-virt "${URL}/netboot/initramfs-virt"
