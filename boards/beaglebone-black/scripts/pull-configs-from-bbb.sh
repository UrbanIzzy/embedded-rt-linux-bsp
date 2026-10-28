#!/usr/bin/env bash
set -uo pipefail

BBB_HOST="${1:-debian@192.168.8.2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOARD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${BOARD_DIR}/../.." && pwd)"

COMMON_CFG_DIR="${REPO_ROOT}/common/configs"
BBB_CFG_DIR="${BOARD_DIR}/configs"

mkdir -p "${COMMON_CFG_DIR}" "${BBB_CFG_DIR}"

echo "[BSP] Pulling live RT configurations from ${BBB_HOST}..."
echo "--------------------------------------------------------------------------------"

PULLED_COUNT=0
MISSING_COUNT=0
MISSING_FILES=()

pull_file() {
    local remote_path="$1"
    local dest_path="$2"
    local display_dest="${dest_path#${REPO_ROOT}/}"

    printf "  %-48s -> %-35s " "${remote_path}" "${display_dest}"
    # Try standard scp first; fallback to sudo cat over ssh for root-only (0440) files
    if scp -q "${BBB_HOST}:${remote_path}" "${dest_path}" 2>/dev/null; then
        echo "[OK]"
        ((PULLED_COUNT++))
    elif ssh "${BBB_HOST}" "sudo -n test -f '${remote_path}'" 2>/dev/null && \
         ssh "${BBB_HOST}" "sudo -n cat '${remote_path}'" > "${dest_path}" 2>/dev/null; then
        echo "[OK (sudo)]"
        ((PULLED_COUNT++))
    else
        rm -f "${dest_path}"
        echo "[MISSING]"
        ((MISSING_COUNT++))
        MISSING_FILES+=("${remote_path}")
    fi
}

# 1. Pull Hardware-Agnostic Real-Time Linux Configs into common/configs/
pull_file "/etc/sysctl.d/99-realtime.conf"                   "${COMMON_CFG_DIR}/99-realtime-sysctl.conf"
pull_file "/etc/security/limits.d/99-realtime.conf"          "${COMMON_CFG_DIR}/99-realtime-limits.conf"
pull_file "/etc/systemd/journald.conf.d/99-ram-logging.conf" "${COMMON_CFG_DIR}/99-ram-logging.conf"
pull_file "/etc/udev/rules.d/99-cpu-dma-latency.rules"       "${COMMON_CFG_DIR}/99-cpu-dma-latency.rules"

# 2. Pull BeagleBone Black Specific Configs & Scripts into boards/beaglebone-black/configs/
pull_file "/boot/uEnv.txt"                                   "${BBB_CFG_DIR}/uEnv.txt"
pull_file "/etc/fstab"                                       "${BBB_CFG_DIR}/fstab"
pull_file "/etc/systemd/system/cpu-performance.service"      "${BBB_CFG_DIR}/cpu-performance.service"
pull_file "/etc/sudoers.d/zz-debian-nopasswd"                "${BBB_CFG_DIR}/zz-debian-nopasswd"
pull_file "/usr/local/bin/wifi-net"                          "${BBB_CFG_DIR}/wifi-net"

chmod +x "${BBB_CFG_DIR}/wifi-net" 2>/dev/null || true

echo "--------------------------------------------------------------------------------"
echo "[BSP] Summary: ${PULLED_COUNT} pulled, ${MISSING_COUNT} missing."

if (( MISSING_COUNT > 0 )); then
    echo "[BSP-WARN] Missing files on ${BBB_HOST}:"
    for item in "${MISSING_FILES[@]}"; do
        echo "  * ${item}"
    done
    exit 1
fi
echo "[BSP] All 9 configuration files pulled successfully."
