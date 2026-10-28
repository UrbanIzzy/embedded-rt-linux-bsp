# Embedded Real-Time Linux BSP & Knowledge Base

Standalone Board Support Package (BSP), OS provisioning scripts, cross-compilation toolchain templates, and engineering knowledge base for hard real-time (`PREEMPT_RT`) robotics Single-Board Computers (SBCs).

---

## Knowledge Base Documentation

* **[General Embedded Real-Time Linux Guide (`docs/01-general-rt-linux-robotics.md`)](docs/01-general-rt-linux-robotics.md)**  
  Hardware-agnostic `PREEMPT_RT` architecture, CPU C-states & DVFS governors, `/dev/cpu_dma_latency` PM QoS, swap/ZRAM removal, `SCHED_FIFO` & PAM limits, volatile RAM `journald`, Device Tree I2C clocking, cross-compilation sysroot ABI rules, `cyclictest` benchmarking, and the 2-Tier Gold Image backup strategy.
* **[BeagleBone Black (AM3358) Image Guide (`docs/boards/beaglebone-black.md`)](docs/boards/beaglebone-black.md)**  
  TI Sitara AM3358 specifics: Debian 13 (Trixie) 3-partition layout, USB Ethernet gadget (`192.168.8.2`), `/usr/local/bin/wifi-net` radio control, U-Boot `/boot/uEnv.txt` overlays, 400 kHz Fast-Mode `I2C2` (`BB-I2C2-FAST-00A0.dtbo`), PRU-ICSS UIO (`AM335X-PRU-UIO-00A0.dtbo`), and Cortex-A8 NEON CMake toolchain configuration.

---

## Repository Structure

~~~text
.
├── common/
│   └── configs/                        # Hardware-agnostic RT Linux configs (sysctl, limits, journald, udev)
├── boards/
│   └── beaglebone-black/
│       ├── configs/                    # BBB-specific configs (uEnv.txt, fstab, cpu-performance, wifi-net, sudoers)
│       ├── scripts/                    # Automated SSH config pull, target provisioning, and sysroot sync
│       └── toolchain/                  # CMake cross-compilation toolchain (arm-bbb-toolchain.cmake)
└── docs/
    ├── 01-general-rt-linux-robotics.md # General RT Linux Knowledge Base
    └── boards/
        └── beaglebone-black.md         # BeagleBone Black Specific Knowledge Base
~~~

---

## Quick-Start Commands (BeagleBone Black)

~~~bash
# 1. Pull live RT configuration files from a running BBB into this repo
./boards/beaglebone-black/scripts/pull-configs-from-bbb.sh debian@192.168.8.2

# 2. Provision a fresh or existing BBB image with all RT configs & permissions
./boards/beaglebone-black/scripts/provision-bbb.sh debian@192.168.8.2

# 3. Synchronize target headers/libs and toolchain to /opt/bbb-sysroot on WSL 2
./boards/beaglebone-black/scripts/sync-sysroot.sh debian@192.168.8.2
~~~
