#!/usr/bin/env bash
set -euo pipefail

BBB_HOST="${1:-debian@192.168.8.2}"
SYSROOT="/opt/bbb-sysroot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOARD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOLCHAIN_FILE="${BOARD_DIR}/toolchain/arm-bbb-toolchain.cmake"

echo "[BSP] Preparing clean Debian 13 (armhf) sysroot at ${SYSROOT}..."
sudo mkdir -p "${SYSROOT}/usr"
sudo chown -R "$USER:$USER" "${SYSROOT}"

# Remove stray non-sysroot folders (/etc, /opt) if left over from older rsyncs
rm -rf "${SYSROOT}/etc" "${SYSROOT}/opt"

# Preserve Debian 13 usr-merge symlink (/lib -> usr/lib)
if [[ ! -L "${SYSROOT}/lib" ]]; then
    rm -rf "${SYSROOT}/lib"
    ln -s usr/lib "${SYSROOT}/lib"
fi

EXCLUDES=(
    --exclude='*/perl*'
    --exclude='*/python*'
    --exclude='*/locale/*'
    --exclude='*/doc/*'
    --exclude='*/man/*'
)

echo "[BSP] Syncing /usr/include and /usr/lib from ${BBB_HOST}..."
rsync -avz --delete "${EXCLUDES[@]}" "${BBB_HOST}:/usr/include" "${SYSROOT}/usr/"
rsync -avz --delete "${EXCLUDES[@]}" "${BBB_HOST}:/usr/lib"     "${SYSROOT}/usr/"

echo "[BSP] Converting absolute symlinks in ${SYSROOT} to relative paths..."
symlinks -cr "${SYSROOT}" >/dev/null

if [[ -f "${TOOLCHAIN_FILE}" ]]; then
    echo "[BSP] Installing ${TOOLCHAIN_FILE} -> ${SYSROOT}/arm-bbb-toolchain.cmake"
    cp -f "${TOOLCHAIN_FILE}" "${SYSROOT}/arm-bbb-toolchain.cmake"
fi

echo "[BSP] Sysroot sync complete. Current top-level structure of ${SYSROOT}:"
ls -la "${SYSROOT}"
