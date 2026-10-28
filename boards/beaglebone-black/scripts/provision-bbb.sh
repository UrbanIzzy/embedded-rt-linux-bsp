#!/usr/bin/env bash
set -euo pipefail

BBB_HOST="${1:-debian@192.168.8.2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOARD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${BOARD_DIR}/../.." && pwd)"

COMMON_CFG_DIR="${REPO_ROOT}/common/configs"
BBB_CFG_DIR="${BOARD_DIR}/configs"

echo "[BSP] Uploading common & BBB-specific RT configurations to ${BBB_HOST}..."
ssh "${BBB_HOST}" "rm -rf /tmp/bbb_bsp_stage && mkdir -p /tmp/bbb_bsp_stage/common /tmp/bbb_bsp_stage/bbb"
scp -q "${COMMON_CFG_DIR}/"* "${BBB_HOST}:/tmp/bbb_bsp_stage/common/"
scp -q "${BBB_CFG_DIR}/"*    "${BBB_HOST}:/tmp/bbb_bsp_stage/bbb/"

ssh "${BBB_HOST}" '
set -euo pipefail

echo "[BBB] 1. Installing bootloader (/boot/uEnv.txt) & helper scripts (/usr/local/bin/wifi-net)..."
sudo -n cp /boot/uEnv.txt /boot/uEnv.txt.bak 2>/dev/null || true
sudo -n cp /tmp/bbb_bsp_stage/bbb/uEnv.txt /boot/uEnv.txt
if [[ -f /tmp/bbb_bsp_stage/bbb/wifi-net ]]; then
    sudo -n cp /tmp/bbb_bsp_stage/bbb/wifi-net /usr/local/bin/wifi-net
    sudo -n chmod 0755 /usr/local/bin/wifi-net
fi

echo "[BBB] 2. Installing common RT sysctl, PAM limits, RAM journald, and udev rules..."
sudo -n rm -f /etc/sysctl.d/90-bbb-preempt-rt-tuning.conf
sudo -n cp /tmp/bbb_bsp_stage/common/99-realtime-sysctl.conf /etc/sysctl.d/99-realtime.conf
sudo -n cp /tmp/bbb_bsp_stage/common/99-realtime-limits.conf /etc/security/limits.d/99-realtime.conf

sudo -n mkdir -p /etc/systemd/journald.conf.d
sudo -n cp /tmp/bbb_bsp_stage/common/99-ram-logging.conf /etc/systemd/journald.conf.d/99-ram-logging.conf
sudo -n rm -rf /var/log/journal

sudo -n cp /tmp/bbb_bsp_stage/common/99-cpu-dma-latency.rules /etc/udev/rules.d/99-cpu-dma-latency.rules
sudo -n cp /tmp/bbb_bsp_stage/bbb/cpu-performance.service /etc/systemd/system/cpu-performance.service

echo "[BBB] 3. Disabling SD swap (mmcblk0p2) and compressed RAM swap (zramswap)..."
sudo -n swapoff -a
sudo -n cp /etc/fstab /etc/fstab.bak
sudo -n sed -i "/mmcblk0p2/s/^#*//; /mmcblk0p2/s/^/#/" /etc/fstab
sudo -n systemctl disable --now zramswap.service 2>/dev/null || true

echo "[BBB] 4. Applying permissions, sudoers, systemd units, and sysctl parameters..."
sudo -n usermod -aG users,i2c,gpio,dialout,kmem debian
sudo -n rm -f /etc/sudoers.d/90-debian-nopasswd
sudo -n cp /tmp/bbb_bsp_stage/bbb/zz-debian-nopasswd /etc/sudoers.d/zz-debian-nopasswd
sudo -n chown root:root /etc/sudoers.d/zz-debian-nopasswd
sudo -n chmod 0440 /etc/sudoers.d/zz-debian-nopasswd

sudo -n systemctl daemon-reload
sudo -n systemctl enable --now cpu-performance.service
sudo -n systemctl restart systemd-journald
sudo -n udevadm control --reload-rules && sudo -n udevadm trigger
sudo -n /usr/sbin/sysctl --system >/dev/null

rm -rf /tmp/bbb_bsp_stage
echo "[BBB] Provisioning complete and verified!"
'
