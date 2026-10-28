# BeagleBone Black (AM3358) Real-Time Linux Image Guide

> **Scope:** This Knowledge Base covers **BeagleBone Black Rev C (TI Sitara AM3358)** specific bootloader configurations, partition layouts, Device Tree overlays (`.dtbo`), I2C hardware buses, PRU-ICSS subsystems, network helper scripts, and cross-compilation toolchain settings.
>
> **Prerequisite General Concepts:** For kernel preemption theory, `sysctl`/`limits.d` parameters, `journald` RAM logging, and `udev` rules shared across all boards, see the [General Embedded Real-Time Linux Image Guide](../01-general-rt-linux-robotics.md).

---

## Quick Subject Search (Table of Contents)

1. [Hardware Architecture & Verified Baseline Image Specs](#1-hardware-architecture--verified-baseline-image-specs)
   * [1.1 TI Sitara AM3358 SoC Overview](#11-ti-sitara-am3358-soc-overview)
   * [1.2 Verified OS Image, Kernel, & Real-Time Latency Benchmark](#12-verified-os-image-kernel--real-time-latency-benchmark)
   * [1.3 Storage Devices (`mmcblk0` microSD vs. `mmcblk1` eMMC) & Partition Layouts](#13-storage-devices-mmcblk0-microsd-vs-mmcblk1-emmc--partition-layouts)
2. [Network Connectivity: USB Gadget (`192.168.8.2`) & On-Demand Wi-Fi (`wifi-net`)](#2-network-connectivity-usb-gadget-19216882--on-demand-wi-fi-wifi-net)
   * [2.1 USB Ethernet Gadget & Passwordless `sudo` (`zz-debian-nopasswd`)](#21-usb-ethernet-gadget--passwordless-sudo-zz-debian-nopasswd)
   * [2.2 On-Demand Wireless Control Script (`/usr/local/bin/wifi-net`)](#22-on-demand-wireless-control-script-usrlocalbinwifi-net)
3. [U-Boot Bootloader Configuration (`/boot/uEnv.txt`)](#3-u-boot-bootloader-configuration-bootuenvtxt)
   * [3.1 How U-Boot Evaluates `/boot/uEnv.txt` vs. `/boot/firmware/extlinux/extlinux.conf`](#31-how-u-boot-evaluates-bootuenvtxt-vs-bootfirmwareextlinuxextlinuxconf)
   * [3.2 Disabling HDMI Video/Audio (`lcdc@0`) to Eliminate L3 DMA Jitter](#32-disabling-hdmi-videoaudio-lcdc0-to-eliminate-l3-dma-jitter)
   * [3.3 Complete Production `/boot/uEnv.txt` Reference](#33-complete-production-bootuenvtxt-reference)
4. [AM3358 I2C Hardware Buses & 400 kHz Fast-Mode Overlays](#4-am3358-i2c-hardware-buses--400-khz-fast-mode-overlays)
   * [4.1 AM3358 Silicon I2C Indexing vs. Linux `/dev/i2c-X` Numbering](#41-am3358-silicon-i2c-indexing-vs-linux-devi2c-x-numbering)
   * [4.2 Enabling 400 kHz Fast Mode (`BB-I2C2-FAST-00A0.dtbo`) & Avoiding `BB-I2C2-MPU6050.dtbo`](#42-enabling-400-khz-fast-mode-bb-i2c2-fast-00a0dtbo--avoiding-bb-i2c2-mpu6050dtbo)
   * [4.3 Inspecting & Decompiling `.dtbo` Overlays on the BBB](#43-inspecting--decompiling-dtbo-overlays-on-the-bbb)
5. [AM3358 PRU-ICSS Real-Time Co-Processors (`uio_pruss`)](#5-am3358-pru-icss-real-time-co-processors-uio_pruss)
   * [5.1 Enabling `/dev/uio0..7` via `AM335X-PRU-UIO-00A0.dtbo`](#51-enabling-devuio07-via-am335x-pru-uio-00a0dtbo)
   * [5.2 Distinguishing `uio_pruss` from `remoteproc0` (`44d00000.cpu` Cortex-M3)](#52-distinguishing-uio_pruss-from-remoteproc0-44d00000cpu-cortex-m3)
6. [Target Packages, Cortex-A8 CMake Toolchain, & BSP Scripts](#6-target-packages-cortex-a8-cmake-toolchain--bsp-scripts)
   * [6.1 Required Target Packages on the BeagleBone Black](#61-required-target-packages-on-the-beaglebone-black)
   * [6.2 Cortex-A8 + NEON Cross-Compilation Flags (`arm-bbb-toolchain.cmake`)](#62-cortex-a8--neon-cross-compilation-flags-arm-bbb-toolchaincmake)
   * [6.3 Using the Automated BBB Provisioning & Sync Scripts](#63-using-the-automated-bbb-provisioning--sync-scripts)

---

## 1. Hardware Architecture & Verified Baseline Image Specs

### 1.1 TI Sitara AM3358 SoC Overview
* **Application Processor:** Single-core 32-bit **ARM Cortex-A8** running at **1000 MHz** (`armv7-a`, `armhf` hard-float ABI) with **NEON SIMD** vector coprocessor and VFPv3 floating-point unit.
* **Real-Time Co-Processors (PRU-ICSS):** Dual 32-bit **200 MHz Programmable Real-Time Units (PRU0 & PRU1)** with single-cycle (5 ns) instruction execution and zero-jitter direct register I/O.
* **Memory:** 512 MB DDR3 RAM.

### 1.2 Verified OS Image, Kernel, & Real-Time Latency Benchmark
| Parameter | Verified Production Value |
| :--- | :--- |
| **Distribution** | Debian GNU/Linux 13 (Trixie) `armhf` (Base Image `2025-12-08`, `GLIBC 2.41`) |
| **Kernel Release** | `6.12.111-bone-rt-r73` (`SMP PREEMPT_RT`) |
| **CPU Governor / Clock** | Locked to `performance` at **1000 MHz** (`cpuidle.off=1`) |
| **1 kHz `cyclictest` Latency** | **Min: 9 µs \| Avg: 13 µs \| Max: 89 µs** (60,000 cycles at `SCHED_FIFO` 95) |

### 1.3 Storage Devices (`mmcblk0` microSD vs. `mmcblk1` eMMC) & Partition Layouts
On the BeagleBone Black:
* **`/dev/mmcblk0`** is the removable **16 GB microSD card** (`14.8 GiB` raw capacity).
* **`/dev/mmcblk1`** is the soldered onboard **4 GB eMMC flash** (`3.6 GiB` raw capacity, plus hardware boot partitions `mmcblk1boot0` and `mmcblk1boot1`).

#### Understanding the 3-Partition Layout on Debian 13 (Trixie)
BeagleBoard.org images use one of three partition layouts depending on the release vintage. Our current Debian 13 (Trixie) image uses the **3-Partition Layout**:
~~~text
mmcblk0      179:768  0 14.8G  0 disk
├─mmcblk0p1  179:769  0   36M  0 part /boot/firmware   (FAT32 boot metadata)
├─mmcblk0p2  179:770  0  512M  0 part                  (Dormant swap partition - disabled in /etc/fstab)
└─mmcblk0p3  179:771  0 14.3G  0 part /                (ext4 root filesystem, 1% root reserve via tune2fs)
~~~
* **Why `mmcblk0p2` Is Left Dormant Instead of Deleted:** Deleting `mmcblk0p2` would renumber the root partition from `mmcblk0p3` to `mmcblk0p2`, breaking any bootloader configuration or script referencing partition numbers. Instead, `provision-bbb.sh` comments out `mmcblk0p2` in `/etc/fstab` (so it never mounts as swap) and zeros out its blocks so it consumes 0 bytes inside compressed `.img.zst` backups.

---

## 2. Network Connectivity: USB Gadget (`192.168.8.2`) & On-Demand Wi-Fi (`wifi-net`)

### 2.1 USB Ethernet Gadget & Passwordless `sudo` (`zz-debian-nopasswd`)
* **What It Is:** When connected to a host PC via mini-USB, the BeagleBone exposes a virtual USB Ethernet gadget interface (`192.168.8.2` on the BBB, `192.168.8.1` on the host).
* **Why `zz-debian-nopasswd` Must Load Last:** Debian's `/etc/sudoers` evaluates rules in lexicographical order, and the **last matching rule wins**. Because `/etc/sudoers.d/admin` or `%sudo` group rules can override earlier files, placing `debian ALL=(ALL:ALL) NOPASSWD: ALL` inside **`/etc/sudoers.d/zz-debian-nopasswd`** (mode `0440`, owned by `root:root`) ensures non-interactive SSH commands (`sudo -n`), automated provisioning scripts, and remote `gdbserver` sessions never block on a password prompt.

### 2.2 On-Demand Wireless Control Script (`/usr/local/bin/wifi-net`)
* **What It Is:** A custom management wrapper around `iwd.service` (`iwctl`) and `systemd-networkd` (`networkctl`) installed at `/usr/local/bin/wifi-net` (tracked in `boards/beaglebone-black/configs/wifi-net`).
* **Why We Need It on the BBB:** Keeping the USB/SDIO Wi-Fi adapter (`wlan0`) and `iwd.service` powered down during real-time robot execution prevents wireless interrupt bursts and 5V rail current spikes, while allowing one-command internet access when installing `apt` packages.
* **How to Use It on the BBB:**
~~~bash
# Bring up iwd, connect wlan0 to Wi-Fi, acquire DHCP via systemd-networkd, and test 8.8.8.8
sudo wifi-net on

# Check service state, IP address, and kernel routing table
sudo wifi-net status

# Disconnect wlan0, bring the interface down, and stop iwd.service for hard real-time runs
sudo wifi-net off
~~~

---

## 3. U-Boot Bootloader Configuration (`/boot/uEnv.txt`)

### 3.1 How U-Boot Evaluates `/boot/uEnv.txt` vs. `/boot/firmware/extlinux/extlinux.conf`
* **What It Is:** On Debian 13 (`6.12.111-bone-rt-r73`), the U-Boot bootloader compiled for BeagleBone Black checks for **`/boot/uEnv.txt` on the root `ext4` partition (`mmcblk0p3`)**. When `/boot/uEnv.txt` defines `uname_r=...` and `enable_uboot_overlays=1`, U-Boot enters its **U-Boot Overlays boot path**—loading the base `.dtb`, applying every `uboot_overlay_addrX` `.dtbo` overlay into RAM, and passing `cmdline=` to the kernel (ignoring `/boot/firmware/extlinux/extlinux.conf`).
* **Why It Matters for the BBB:** Putting `cpuidle.off=1` or overlay directives only in `/boot/firmware/extlinux/extlinux.conf` will have **zero effect** when `/boot/uEnv.txt` is active. All kernel arguments (`cmdline=`) and hardware overlays (`uboot_overlay_addrX=`) must reside in **`/boot/uEnv.txt`**.

### 3.2 Disabling HDMI Video/Audio (`lcdc@0`) to Eliminate L3 DMA Jitter
* **What It Is:** The BeagleBone Black routes 24 processor pins on headers `P8` and `P9` to an onboard TDA19988 HDMI framer driven by the AM3358's `tilcdc` LCD DMA controller.
* **Why We Disable It on a Headless Robot:** Even with no monitor plugged in, an enabled `tilcdc` controller continuously polls display memory over the AM3358 L3 interconnect and occupies 24 header pins needed for PRU/GPIO/PWM signals. Setting `disable_uboot_overlay_video=1` and `disable_uboot_overlay_audio=1` in `/boot/uEnv.txt` shuts down the `lcdc@0` silicon block completely.

### 3.3 Complete Production `/boot/uEnv.txt` Reference
Tracked in `boards/beaglebone-black/configs/uEnv.txt`:
~~~ini
#Docs: http://elinux.org/Beagleboard:U-boot_partitioning_layout_2.0

uname_r=6.12.111-bone-rt-r73
#uuid=
#dtb=

###U-Boot Overlays###
###Documentation: http://elinux.org/Beagleboard:BeagleBoneBlack_Debian#U-Boot_Overlays
###Master Enable
enable_uboot_overlays=1

###Additional custom overlays
uboot_overlay_addr0=BB-I2C2-FAST-00A0.dtbo
#uboot_overlay_addr4=/lib/firmware/<file4>.dtbo

###Custom Cape
#dtb_overlay=/lib/firmware/<file8>.dtbo

###Disable auto loading of virtual capes (emmc/video/wireless/adc)
#disable_uboot_overlay_emmc=1
disable_uboot_overlay_video=1
disable_uboot_overlay_audio=1
#disable_uboot_overlay_wireless=1
#disable_uboot_overlay_adc=1

###PRUSS OPTIONS
###pru_uio (4.14.x-ti, 4.19.x-ti, 5.4.x-ti, 5.10.x-ti & 6.12.x-bone-rt)
uboot_overlay_pru=AM335X-PRU-UIO-00A0.dtbo

###Cape Universal Enable
enable_uboot_cape_universal=1

# Prevent CPU from entering deep idle sleep states (eliminates 50-150us wakeup jitter)
cmdline=coherent_pool=1M net.ifnames=0 lpj=1990656 rng_core.default_quality=100 quiet cpuidle.off=1
~~~

#### Post-Boot Verification Commands on the BBB:
~~~bash
# 1. Verify cpuidle.off=1 is active in the running kernel command line
cat /proc/cmdline

# 2. Verify HDMI video controller (lcdc@0) is disabled
tr '\0' '\n' < /proc/device-tree/ocp/interconnect@48000000/segment@300000/target-module@e000/lcdc@0/status
# Expected: disabled
~~~

---

## 4. AM3358 I2C Hardware Buses & 400 kHz Fast-Mode Overlays

### 4.1 AM3358 Silicon I2C Indexing vs. Linux `/dev/i2c-X` Numbering
The TI AM3358 SoC contains three hardware I2C controllers, indexed `I2C0`, `I2C1`, and `I2C2` in the TI Technical Reference Manual (where `1 + N` matches the Device Tree alias, while Linux numbers character devices dynamically based on enabled controllers):

| TI Silicon Name | Base Address | P9 Header Pins | Linux Device Node (Default) | Role on BeagleBone Black |
| :--- | :--- | :--- | :--- | :--- |
| **`I2C0`** | `0x44E0B000` | Internal Only | `/dev/i2c-0` (`400 kHz`) | Internal TPS65217C PMIC & Board ID EEPROM (**Do not use for sensors**) |
| **`I2C1`** | `0x4802A000` | `P9_17` (SCL), `P9_18` (SDA) | Disabled by default (`BB-I2C1-00A0.dtbo`) | Optional secondary external sensor bus |
| **`I2C2`** | `0x4819C000` | **`P9_19` (SCL), `P9_20` (SDA)** | **`/dev/i2c-2`** | **Primary external robotics sensor bus (MPU6050 IMU, etc.)** |

### 4.2 Enabling 400 kHz Fast Mode (`BB-I2C2-FAST-00A0.dtbo`) & Avoiding `BB-I2C2-MPU6050.dtbo`
* **Why Default `I2C2` Is Too Slow:** Out of the box, the BeagleBone Black base Device Tree configures `I2C2` (`0x4819C000`, `/dev/i2c-2`) at **100,000 Hz (100 kHz Standard Mode)**.
* **Why You Must NOT Load `BB-I2C2-MPU6050.dtbo`:** Although `/boot/firmware/overlays/BB-I2C2-MPU6050.dtbo` exists on the image, decompiling it reveals that it leaves the bus at `100 kHz` (`clock-frequency = <0x186a0>`) AND spawns a kernel `inv_mpu6050` IIO driver on `0x68`, locking out userspace C++ programs with `EBUSY` (`UU` in `i2cdetect`).
* **The Solution (`BB-I2C2-FAST-00A0.dtbo`):** Loading `uboot_overlay_addr0=BB-I2C2-FAST-00A0.dtbo` in `/boot/uEnv.txt` reconfigures `I2C2` (`P9_19`/`P9_20`) to **400,000 Hz (400 kHz Fast Mode, `0x61a80`)** while leaving address `0x68` completely unclaimed for direct userspace `ioctl` transfers.

### 4.3 Inspecting & Decompiling `.dtbo` Overlays on the BBB
To inspect what any `.dtbo` file inside `/boot/firmware/overlays/` actually changes before adding it to `/boot/uEnv.txt`, decompile it to human-readable Device Tree Source (`.dts`) using `dtc`:
~~~bash
dtc -I dtb -O dts /boot/firmware/overlays/BB-I2C2-FAST-00A0.dtbo
~~~
Verify live 400 kHz operation on `/dev/i2c-2` after rebooting:
~~~bash
tr -d '\0' < /sys/bus/i2c/devices/i2c-2/of_node/clock-frequency | od -An -t u4 --endian=big
# Expected: 400000
~~~

---

## 5. AM3358 PRU-ICSS Real-Time Co-Processors (`uio_pruss`)

### 5.1 Enabling `/dev/uio0..7` via `AM335X-PRU-UIO-00A0.dtbo`
* **What It Is:** Setting `uboot_overlay_pru=AM335X-PRU-UIO-00A0.dtbo` in `/boot/uEnv.txt` binds the AM3358's PRU-ICSS subsystem (`pruss@4a300000`) to the Userspace I/O driver (`uio_pruss`), exposing 8 interrupt/memory-mapping device nodes at **`/dev/uio0` through `/dev/uio7`**.
* **Permissions:** The stock rule `/etc/udev/rules.d/uio-pruss.rules` grants `0660` access to group **`users`**, which `provision-bbb.sh` assigns to the `debian` user.
* **How to Verify on the BBB:**
~~~bash
ls -l /dev/uio*
lsmod | grep uio_pruss
~~~

### 5.2 Distinguishing `uio_pruss` from `remoteproc0` (`44d00000.cpu` Cortex-M3)
When checking `/sys/class/remoteproc/` on the BeagleBone Black, you will always see `remoteproc0`:
~~~bash
cat /sys/class/remoteproc/remoteproc0/name
# Outputs: 44d00000.cpu (state: running, firmware: am335x-pm-firmware.elf)
~~~
* **What `44d00000.cpu` Is:** That is **not** a PRU—it is the AM3358's internal **Cortex-M3 Wakeup Microcontroller (`wkup_m3`)**, which manages SoC voltage domains and PMIC communication. Never stop or unbind `remoteproc0`. When `AM335X-PRU-UIO-00A0.dtbo` is active, both PRU0 and PRU1 are owned by `uio_pruss` (`/dev/uio0..7`).

---

## 6. Target Packages, Cortex-A8 CMake Toolchain, & BSP Scripts

### 6.1 Required Target Packages on the BeagleBone Black
When starting from a fresh BeagleBoard.org Debian 13 (Trixie) image, connect to the internet (`sudo wifi-net on`) and install these target packages on the BBB prior to syncing the sysroot:
~~~bash
sudo apt-get update
sudo apt-get install -y \
    rt-tests \
    libgpiod-dev gpiod \
    libi2c-dev i2c-tools \
    device-tree-compiler \
    gdbserver \
    zstd
sudo wifi-net off
~~~

### 6.2 Cortex-A8 + NEON Cross-Compilation Flags (`arm-bbb-toolchain.cmake`)
Tracked in `boards/beaglebone-black/toolchain/arm-bbb-toolchain.cmake` (and automatically copied to `/opt/bbb-sysroot/arm-bbb-toolchain.cmake` by `sync-sysroot.sh`):
* **Compiler Triplet:** `arm-linux-gnueabihf-gcc` / `arm-linux-gnueabihf-g++`
* **Sysroot Path:** `/opt/bbb-sysroot`
* **Architecture & SIMD Flags:** `-mcpu=cortex-a8 -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard`
* **Transitive Shared Library Resolution:** `-Wl,-rpath-link,/opt/bbb-sysroot/usr/lib/arm-linux-gnueabihf -Wl,-rpath-link,/opt/bbb-sysroot/lib/arm-linux-gnueabihf`
* **Isolated `pkg-config`:** Locks `PKG_CONFIG_LIBDIR` and `PKG_CONFIG_SYSROOT_DIR` to `/opt/bbb-sysroot` so host x86_64 `.pc` files are never read.

### 6.3 Using the Automated BBB Provisioning & Sync Scripts
All scripts live in `boards/beaglebone-black/scripts/` and run from your **WSL 2 host terminal**:

1. **Pull Live Configs from BBB into Git (`pull-configs-from-bbb.sh`):**
   Pulls all 4 common RT configs (`common/configs/`) and all 5 BBB-specific configs (`boards/beaglebone-black/configs/`, including `/usr/local/bin/wifi-net` and root-owned `/etc/sudoers.d/zz-debian-nopasswd` via `sudo -n cat` fallback):
~~~bash
./boards/beaglebone-black/scripts/pull-configs-from-bbb.sh
~~~
2. **Provision a BeagleBone Black Image (`provision-bbb.sh`):**
   Pushes `common/configs/` and `boards/beaglebone-black/configs/` to the BBB over SSH, disables SD swap (`mmcblk0p2`) and `zramswap.service`, configures hardware groups and `zz-debian-nopasswd`, enables `cpu-performance.service`, and reloads `udev`/`journald`/`sysctl`:
~~~bash
./boards/beaglebone-black/scripts/provision-bbb.sh
~~~
3. **Synchronize the Host Cross-Compilation Sysroot (`sync-sysroot.sh`):**
   Mirrors `/usr/include` and `/usr/lib` from the BBB into `/opt/bbb-sysroot`, preserves the Debian 13 `lib -> usr/lib` symlink, converts absolute symlinks to relative paths with `symlinks -cr`, and copies `arm-bbb-toolchain.cmake` into `/opt/bbb-sysroot/`:
~~~bash
./boards/beaglebone-black/scripts/sync-sysroot.sh
~~~
