#!/bin/bash
# Build the Droidian kernel packages + boot.img for Samsung Galaxy J5 (2017).
#
# Usage: scripts/build-kernel.sh [workdir]
#   workdir defaults to ./build
#
# Result: <workdir>/packages/*.deb and <workdir>/boot.img
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(realpath -m "${1:-$REPO_DIR/build}")"
KERNEL_URL="https://github.com/samsungexynos7870/android_kernel_samsung_exynos7870.git"
KERNEL_BRANCH="simple_q_permissive"
KERNEL_BASE="29223d295a58ebe82e95347c8eb8468ea2b1c336"
IMAGE="quay.io/droidian/build-essential:current-amd64"

mkdir -p "$WORK/packages"

if [ ! -d "$WORK/kernel/.git" ]; then
    git clone --branch "$KERNEL_BRANCH" --single-branch "$KERNEL_URL" "$WORK/kernel"
    git -C "$WORK/kernel" checkout -b droidian "$KERNEL_BASE"
    git -C "$WORK/kernel" -c user.name=build -c user.email=build@localhost \
        am "$REPO_DIR"/kernel/patches/*.patch
fi

docker run --rm \
    -v "$WORK/packages:/buildd" \
    -v "$WORK/kernel:/buildd/sources" \
    "$IMAGE" bash -c '
    set -e
    cd /buildd/sources
    apt-get update -qq
    apt-get install -y -qq linux-packaging-snippets
    rm -f debian/control
    debian/rules debian/control
    export DEB_BUILD_OPTIONS="parallel=$(nproc) nocheck"
    RELENG_HOST_ARCH=arm64 releng-build-package
    chown -R '"$(id -u):$(id -g)"' /buildd'

cp "$WORK/kernel/out/KERNEL_OBJ/boot.img" "$WORK/boot.img"
size=$(stat -c %s "$WORK/boot.img")
echo "boot.img: $WORK/boot.img ($size bytes, BOOT partition is 33554432)"
[ "$size" -le 33554432 ] || { echo "ERROR: boot.img does not fit the BOOT partition" >&2; exit 1; }
