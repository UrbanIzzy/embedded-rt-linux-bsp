# General Embedded Real-Time Linux Image Guide for Robotics

> **Scope:** This Knowledge Base covers **hardware-agnostic** Linux OS image architecture, kernel tuning, memory determinism, peripheral subsystems, cross-compilation sysroots, and image backup strategies applicable to any Single-Board Computer (SBC) running hard real-time robotics workloads.
>
> **Board-Specific Guides:**
> * [BeagleBone Black (TI Sitara AM3358) Image Guide](boards/beaglebone-black.md)

---

## Quick Subject Search (Table of Contents)

1. [Real-Time Linux Kernel Architecture (`PREEMPT_RT`)](#1-real-time-linux-kernel-architecture-preempt_rt)
   * [1.1 Standard Linux vs. `PREEMPT_RT` Preemption Models](#11-standard-linux-vs-preempt_rt-preemption-models)
   * [1.2 RT-Mutexes & Priority Inheritance](#12-rt-mutexes--priority-inheritance)
   * [1.3 Threaded Interrupt Handlers (`irq/*`)](#13-threaded-interrupt-handlers-irq)
2. [CPU Power Management, C-States, DVFS, & Interconnect QoS](#2-cpu-power-management-c-states-dvfs--interconnect-qos)
   * [2.1 Deep Idle Sleep States (`cpuidle` / C-States)](#21-deep-idle-sleep-states-cpuidle--c-states)
   * [2.2 Dynamic Voltage and Frequency Scaling (DVFS Governors)](#22-dynamic-voltage-and-frequency-scaling-dvfs-governors)
   * [2.3 Runtime DMA Latency QoS (`/dev/cpu_dma_latency`)](#23-runtime-dma-latency-qos-devcpu_dma_latency)
3. [Virtual Memory Determinism, Swap, ZRAM, & Page Writeback](#3-virtual-memory-determinism-swap-zram--page-writeback)
   * [3.1 Disabling Disk Swap & Compressed RAM Swap (`ZRAM`)](#31-disabling-disk-swap--compressed-ram-swap-zram)
   * [3.2 Virtual Memory (`vm.swappiness`) & Dirty Page Writeback Tuning](#32-virtual-memory-vmswappiness--dirty-page-writeback-tuning)
4. [Real-Time Scheduler Bandwidth & PAM Security Limits](#4-real-time-scheduler-bandwidth--pam-security-limits)
   * [4.1 Disabling the 95% RT Scheduler Throttle (`sched_rt_runtime_us`)](#41-disabling-the-95-rt-scheduler-throttle-sched_rt_runtime_us)
   * [4.2 Non-Root Real-Time Privileges (`/etc/security/limits.d/`)](#42-non-root-real-time-privileges-etcuritylimitsd)
5. [Flash Storage Longevity & Volatile System Logging (`journald`)](#5-flash-storage-longevity--volatile-system-logging-journald)
   * [5.1 Locking `systemd-journald` to Volatile RAM (`/run/log/journal`)](#51-locking-systemd-journald-to-volatile-ram-runlogjournal)
   * [5.2 Reclaiming `ext4` Reserved Root Blocks (`tune2fs`)](#52-reclaiming-ext4-reserved-root-blocks-tune2fs)
6. [Userspace Hardware Subsystems (`udev`, I2C, GPIO, & Wireless Radios)](#6-userspace-hardware-subsystems-udev-i2c-gpio--wireless-radios)
   * [6.1 Linux Hardware Permission Groups & `udev` Rules](#61-linux-hardware-permission-groups--udev-rules)
   * [6.2 Linux I2C Bus Speeds (Device Tree vs. Userspace) & Kernel Driver Conflicts (`UU` / `EBUSY`)](#62-linux-i2c-bus-speeds-device-tree-vs-userspace--kernel-driver-conflicts-uu--ebusy)
   * [6.3 On-Demand Wireless Radio Power Control (`iwd` / `wlan0`)](#63-on-demand-wireless-radio-power-control-iwd--wlan0)
7. [Cross-Compilation Sysroot Architecture & ELF Verification](#7-cross-compilation-sysroot-architecture--elf-verification)
   * [7.1 Why Target Sysroot Synchronization Is Required (`GLIBC` ABI Matching)](#71-why-target-sysroot-synchronization-is-required-glibc-abi-matching)
   * [7.2 Mirroring a Minimal Target Sysroot & Fixing Absolute Symlinks](#72-mirroring-a-minimal-target-sysroot--fixing-absolute-symlinks)
   * [7.3 Inspecting Cross-Compiled Binaries (`file`, `readelf`, `objdump`)](#73-inspecting-cross-compiled-binaries-file-readelf-objdump)
8. [Real-Time Latency Benchmarking (`cyclictest`) & Gold Image Backups](#8-real-time-latency-benchmarking-cyclictest--gold-image-backups)
   * [8.1 Measuring Deterministic Wakeup Latency with `cyclictest`](#81-measuring-deterministic-wakeup-latency-with-cyclictest)
   * [8.2 Two-Tier Backup Strategy & The SD Card Capacity Trap](#82-two-tier-backup-strategy--the-sd-card-capacity-trap)

---

## 1. Real-Time Linux Kernel Architecture (`PREEMPT_RT`)

### 1.1 Standard Linux vs. `PREEMPT_RT` Preemption Models
* **What It Is:** A mainline Linux kernel configured with `PREEMPT_NONE` or `PREEMPT_VOLUNTARY` optimizes for aggregate server/desktop throughput. When the kernel executes a system call or enters a `spinlock_t` critical section, it cannot be preempted by a userspace thread—even one running at maximum real-time priority (`SCHED_FIFO` 99)—until the kernel path voluntarily yields or completes.
* **Why It Matters for RT Robotics:** In closed-loop motor control and state estimation (e.g., 500 Hz – 1 kHz IMU + actuator loops), non-preemptible kernel sections cause unbounded scheduling latency spikes (often 2,000 µs to 20,000+ µs) whenever background filesystem, network, or display drivers hold kernel locks. Applying the **`PREEMPT_RT` (`CONFIG_PREEMPT_RT=y`)** patchset converts almost the entire Linux kernel into a fully preemptible state machine.

### 1.2 RT-Mutexes & Priority Inheritance
* **What It Is:** `PREEMPT_RT` replaces standard kernel spinlocks (`spinlock_t`, which disable hardware interrupts and busy-wait on the CPU) with sleeping **RT-mutexes (`rt_mutex`)** that support **Priority Inheritance (PI)**.
* **Why It Matters for RT Robotics:** If a low-priority background task holds a kernel lock required by your high-priority `SCHED_FIFO` control thread, Priority Inheritance temporarily boosts the low-priority task to the high-priority thread's priority until it releases the lock, preventing **unbounded priority inversion**.

### 1.3 Threaded Interrupt Handlers (`irq/*`)
* **What It Is:** In standard Linux, hardware Interrupt Service Routines (ISRs) execute in hard-IRQ context with all other interrupts disabled. Under `PREEMPT_RT`, peripheral interrupt handlers are forced into scheduled kernel threads (`irq/<N>-<device>`), leaving only a minimal top-half wake-up stub in hard-IRQ context.
* **Why It Matters for RT Robotics:** Because peripheral ISRs run as standard kernel threads, you can lower the priority of noisy non-critical interrupts (e.g., Ethernet, USB, MMC storage) below your `SCHED_FIFO` robotics control loop so SD card or network activity never delays a control tick.
* **How to Verify on Any Board:**
~~~bash
# 1. Verify kernel release and SMP PREEMPT_RT build flag
uname -a

# 2. Verify active kernel preemption model (if debugfs is enabled)
sudo cat /sys/kernel/debug/sched/preempt 2>/dev/null || zcat /proc/config.gz 2>/dev/null | grep CONFIG_PREEMPT_RT

# 3. Inspect threaded interrupt handlers and their RT priorities
ps -eo pid,cls,rtprio,comm | grep -E "irq/|ktimers" | head -n 20
~~~

---

## 2. CPU Power Management, C-States, DVFS, & Interconnect QoS

### 2.1 Deep Idle Sleep States (`cpuidle` / C-States)
* **What It Is:** When the Linux scheduler has no runnable threads between timer ticks, the `cpuidle` subsystem executes architecture sleep instructions (`WFI` on ARM) and transitions the CPU core and internal bus phase-locked loops (PLLs) into progressively deeper low-power C-states (`C1`, `C2`, etc.).
* **Why It Matters for RT Robotics:** A 1 kHz robotics loop sleeps for ~800 µs out of every 1,000 µs period. If the CPU enters a deep C-state during that 800 µs sleep window, waking the core, relocking PLLs, and repopulating L1/L2 caches adds **50 µs to 250 µs of unpredictable wakeup jitter** to every control cycle.
* **How to Configure & Verify:**
  1. Append `cpuidle.off=1` (or `nohlt`) to the kernel command line in your board's bootloader configuration.
  2. Verify at runtime:
~~~bash
cat /proc/cmdline | grep cpuidle.off
~~~

### 2.2 Dynamic Voltage and Frequency Scaling (DVFS Governors)
* **What It Is:** The Linux `cpufreq` subsystem dynamically scales CPU core clock frequency and PMIC supply voltage based on load using governors like `ondemand`, `schedutil`, or `powersave`.
* **Why It Matters for RT Robotics:** Switching CPU clock multipliers requires communicating with an external Power Management IC (PMIC) over I2C to ramp core voltage, stalling instruction execution for hundreds of microseconds and changing instruction execution time mid-cycle. Robotics boards must lock the governor to **`performance`** (100% maximum clock frequency at all times).
* **How to Configure & Verify:**
~~~bash
# Inspect current governor and clock frequency (in kHz)
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
~~~

### 2.3 Runtime DMA Latency QoS (`/dev/cpu_dma_latency`)
* **What It Is:** Linux exposes a Power Management Quality of Service (PM QoS) character device at `/dev/cpu_dma_latency`. When a process opens this file and writes a 32-bit binary integer $N$ (in microseconds), the kernel prevents the CPU and SoC DMA/interconnect buses from entering any power-saving state whose exit latency exceeds $N\text{ }\mu\text{s}$ for as long as the file descriptor remains open.
* **Why It Matters for RT Robotics:** Writing `int32_t zero = 0` (`0x00000000`) to `/dev/cpu_dma_latency` acts as a runtime hardware lock ensuring zero-latency interconnect and CPU transitions even if a kernel driver attempts to engage runtime PM.
* **How to Configure (`common/configs/99-cpu-dma-latency.rules`):**
  By default, `/dev/cpu_dma_latency` is owned by `root:root` (`0600`). Grant group `users` read/write access via `udev` so non-root robotics processes and `cyclictest` can lock DMA latency:
~~~udev
KERNEL=="cpu_dma_latency", GROUP="users", MODE="0660"
~~~
  Reload `udev` rules and verify permissions:
~~~bash
sudo udevadm control --reload-rules && sudo udevadm trigger
ls -l /dev/cpu_dma_latency
# Expected: crw-rw---- 1 root users 10, 62 ... /dev/cpu_dma_latency
~~~

---

## 3. Virtual Memory Determinism, Swap, ZRAM, & Page Writeback

### 3.1 Disabling Disk Swap & Compressed RAM Swap (`ZRAM`)
* **What It Is:** Linux uses swap space (either a flash partition on SD/eMMC or a compressed RAM block device via `zramswap.service`) to evict anonymous memory pages when physical RAM pressure increases or when pages appear cold.
* **Why It Matters for RT Robotics:**
  1. **Flash Swap:** Taking a major page fault that reads from an SD card blocks the faulting thread for **5 ms to 50+ ms**, causing catastrophic real-time deadline misses and wearing out flash cells.
  2. **Compressed RAM Swap (`ZRAM`):** Even without touching the SD card, `ZRAM` intercepts page allocations and runs synchronous LZ4/LZO compression and decompression on the CPU core, injecting hundreds of microseconds of latency jitter.
* **How to Configure & Verify:**
  1. Comment out any `swap` partition entry in `/etc/fstab`.
  2. Disable `zramswap.service` and turn off all active swap devices:
~~~bash
sudo swapoff -a
sudo systemctl disable --now zramswap.service 2>/dev/null || true
free -h
swapon --show
~~~

### 3.2 Virtual Memory (`vm.swappiness`) & Dirty Page Writeback Tuning
* **What It Is:** When processes write data to filesystems, Linux buffers those writes as "dirty pages" in RAM (`vm.dirty_background_ratio` / `vm.dirty_ratio`) before flushing them asynchronously to block storage via `kworker` flush threads.
* **Why It Matters for RT Robotics:** Default Linux settings (`dirty_ratio = 20%`, `dirty_background_ratio = 10%`) allow large bursts of dirty pages to accumulate in RAM before suddenly unleashing a massive SD/eMMC DMA write storm that saturates the SoC memory interconnect. Lowering these ratios forces tiny, smooth background flushes.
* **How to Configure (`common/configs/99-realtime-sysctl.conf`):**
~~~ini
# Disable RT scheduler throttling (allow 100% RT CPU bandwidth if needed)
kernel.sched_rt_runtime_us = -1

# Minimize page swapping aggressiveness and shrink dirty page writeback bursts
vm.swappiness = 10
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
~~~

---

## 4. Real-Time Scheduler Bandwidth & PAM Security Limits

### 4.1 Disabling the 95% RT Scheduler Throttle (`sched_rt_runtime_us`)
* **What It Is:** By default, the Linux kernel sets `kernel.sched_rt_runtime_us = 950000` inside a `kernel.sched_rt_period_us = 1000000` (1 second) window. This throttles all `SCHED_FIFO` and `SCHED_RR` real-time threads after 950 ms of cumulative CPU usage, forcibly pausing them for **50 ms** (`50,000 µs`) to let `SCHED_OTHER` tasks run.
* **Why It Matters for RT Robotics:** A 50 ms forced pause in the middle of a balancing or trajectory maneuver will crash a dynamic robot. Setting `kernel.sched_rt_runtime_us = -1` in `/etc/sysctl.d/99-realtime.conf` disables the throttle completely.

### 4.2 Non-Root Real-Time Privileges (`/etc/security/limits.d/`)
* **What It Is:** Standard non-root Linux users are forbidden from calling `sched_setscheduler(..., SCHED_FIFO, ...)` or locking virtual memory pages into physical RAM via `mlockall(MCL_CURRENT | MCL_FUTURE)`.
* **Why It Matters for RT Robotics:** Running robotics binaries as `root` is hazardous and complicates IDE remote debugging. Configuring Pluggable Authentication Modules (PAM) limits allows your standard user account (or members of group `@users`) to spawn `SCHED_FIFO` threads up to priority 99 and lock unlimited RAM against page faults.
* **How to Configure (`common/configs/99-realtime-limits.conf`):**
~~~text
debian           -       rtprio          99
debian           -       memlock         unlimited
debian           -       nice            -20
@users           -       rtprio          99
@users           -       memlock         unlimited
~~~
* **How to Verify (Log out and back in over SSH first):**
~~~bash
ulimit -r -l
# Expected:
# real-time priority              (-r) 99
# max locked memory       (kbytes, -l) unlimited
~~~

---

## 5. Flash Storage Longevity & Volatile System Logging (`journald`)

### 5.1 Locking `systemd-journald` to Volatile RAM (`/run/log/journal`)
* **What It Is:** By default, `systemd-journald` writes structured binary system logs to `/var/log/journal` on the root `ext4` filesystem and periodically calls `fsync()`, triggering `ext4` journal commits (`jbd2` kernel thread).
* **Why It Matters for RT Robotics:** Every `jbd2` flash commit generates MMC/SD DMA interrupts and wears out NAND flash blocks. Setting `Storage=volatile` redirects all system logs exclusively into the `tmpfs` RAM disk at `/run/log/journal` (capped at 16 MB).
* **How to Configure (`common/configs/99-ram-logging.conf`):**
  Place in `/etc/systemd/journald.conf.d/99-ram-logging.conf`:
~~~ini
[Journal]
Storage=volatile
RuntimeMaxUse=16M
~~~
  Apply and remove old persistent flash logs:
~~~bash
sudo rm -rf /var/log/journal
sudo systemctl restart systemd-journald
journalctl --disk-usage
~~~

### 5.2 Reclaiming `ext4` Reserved Root Blocks (`tune2fs`)
* **What It Is:** When an `ext4` filesystem is formatted, it reserves **5%** of total blocks exclusively for user `root`. On a 16 GB SD card (`14.3 GiB` root partition), 5% locks away **~715 MB** of usable space.
* **Why It Matters for RT Robotics:** Because `journald` is locked to 16 MB of RAM, background logs cannot accidentally fill the root disk. Reducing the reserved block ratio from 5% to **1%** (~140 MB) immediately reclaims **~575 MB** of usable storage online:
~~~bash
sudo tune2fs -m 1 /dev/mmcblk0p3
df -h /
~~~

---

## 6. Userspace Hardware Subsystems (`udev`, I2C, GPIO, & Wireless Radios)

### 6.1 Linux Hardware Permission Groups & `udev` Rules
* **What It Is:** Linux character devices for hardware buses (`/dev/i2c-*`, `/dev/gpiochip*`, `/dev/ttyS*`, `/dev/uio*`, `/dev/mem`) are assigned group ownership by `udev` at boot.
* **Why It Matters for RT Robotics:** Adding the robotics user account to the hardware groups once during image provisioning allows direct, zero-overhead file descriptor access from non-root processes:
~~~bash
sudo usermod -aG users,i2c,gpio,dialout,kmem debian
~~~

### 6.2 Linux I2C Bus Speeds (Device Tree vs. Userspace) & Kernel Driver Conflicts (`UU` / `EBUSY`)
* **What It Is:**
  1. **Bus Clock Frequency (`clock-frequency`):** Unlike microcontroller bare-metal registers, the Linux kernel's `/dev/i2c-X` userspace interface (`linux/i2c-dev.h`) **does not provide an `ioctl()` to change the I2C SCL clock rate at runtime**. The I2C peripheral clock divider is programmed once by the kernel I2C bus driver at boot based on the `clock-frequency` property in the compiled **Device Tree (`.dtb` / `.dtbo`)**.
  2. **Kernel IIO Driver Conflicts (`UU` / `EBUSY`):** If a Device Tree overlay declares a specific sensor node inside an I2C bus (e.g., `mpu6050@68`), the Linux kernel automatically probes its internal Industrial I/O (`iio`) driver and claims address `0x68`.
* **Why It Matters for RT Robotics:**
  * **100 kHz vs. 400 kHz I2C:** Reading a 14-byte IMU burst over 100 kHz Standard-Mode I2C takes **~1.45 ms**—making a 1 kHz (1.0 ms period) control loop physically impossible. Switching the Device Tree to **400 kHz Fast-Mode** drops that same 14-byte transfer to **~360 µs**.
  * **Avoiding `EBUSY` (`Device or resource busy`):** When a kernel `iio` driver claims an I2C address, `i2cdetect` displays **`UU`** instead of the hex address (`68`), and any userspace `ioctl(fd, I2C_SLAVE, 0x68)` call fails with `EBUSY`. For hard real-time userspace polling, load **only the raw bus speed overlay** (not the sensor driver overlay) so `i2cdetect` displays the raw hex address (`68`).
* **How to Inspect Live I2C Bus Speeds & Device Claims:**
~~~bash
# 1. Read the active I2C bus clock-frequency (in Hz) from the live kernel Device Tree
for bus in /sys/bus/i2c/devices/i2c-*; do
    if [ -f "$bus/of_node/clock-frequency" ]; then
        freq=$(tr -d '\0' < "$bus/of_node/clock-frequency" | od -An -t u4 --endian=big | tr -d ' ')
        echo "$(basename $bus) ($(cat $bus/name)): ${freq} Hz"
    fi
done

# 2. Scan an I2C bus (e.g. bus 2) - ensure sensor addresses show hex (e.g. '68'), NOT 'UU'
i2cdetect -y -r 2
~~~

### 6.3 On-Demand Wireless Radio Power Control (`iwd` / `wlan0`)
* **What It Is:** Wi-Fi interfaces (`wlan0`) managed by background daemons (`iwd` or `wpa_supplicant`) periodically scan channels, handle beacon interrupts over SDIO/USB buses, and draw burst current from the board's 5V/3.3V rails.
* **Why It Matters for RT Robotics:** Keeping `wlan0` and `iwd.service` powered down by default eliminates wireless bus DMA interrupts and voltage rail droop during real-time experiments, while an on-demand helper script (`sudo wifi-net on` / `sudo wifi-net off`) allows instant connectivity when installing packages or pulling logs.

---

## 7. Cross-Compilation Sysroot Architecture & ELF Verification

### 7.1 Why Target Sysroot Synchronization Is Required (`GLIBC` ABI Matching)
* **What It Is:** A cross-compiler running on an x86_64 host (such as `arm-linux-gnueabihf-g++` on Ubuntu 22.04 WSL 2) ships with a generic version of the GNU C Library (`GLIBC`, e.g., `2.35`). Meanwhile, your target SBC OS image (e.g., Debian 13 Trixie) runs a newer `GLIBC` (`2.41`) and has target-specific hardware libraries (`libgpiod`, `libi2c`) installed via `apt`.
* **Why It Matters for RT Robotics:** If you compile against the host's built-in headers/libraries, you either cannot `#include` target libraries installed on the board or encounter dynamic linker (`ld-linux-armhf.so.3`) symbol version errors. Mirroring the target's `/usr/include` and `/usr/lib` into a dedicated host directory (e.g., `/opt/<board>-sysroot`) and passing `--sysroot=/opt/<board>-sysroot` guarantees 100% ABI compatibility.

### 7.2 Mirroring a Minimal Target Sysroot & Fixing Absolute Symlinks
* **What It Is:** Many shared library `.so` development symlinks on a live Linux filesystem use **absolute paths** (e.g., `/usr/lib/arm-linux-gnueabihf/libpthread.so -> /lib/arm-linux-gnueabihf/libpthread.so.0`).
* **Why It Matters for RT Robotics:** When copied into `/opt/<board>-sysroot` on your x86_64 PC, an absolute symlink pointing to `/lib/...` escapes the sysroot and points to your host PC's root directory (where ARM libraries do not exist!), causing cross-compilation linker failures.
* **How to Sync & Fix Symlinks (`sync-sysroot.sh` pattern):**
  1. Preserve Debian's `usr-merge` top-level symlink (`/opt/<board>-sysroot/lib -> usr/lib`).
  2. Use `rsync` over SSH to mirror only `/usr/include` and `/usr/lib` while excluding `python*`, `perl*`, `locale`, `doc`, and `man` bloat.
  3. Run `symlinks -cr /opt/<board>-sysroot` on the host to convert all absolute symlinks into relative symlinks (`../../lib/...`).

### 7.3 Inspecting Cross-Compiled Binaries (`file`, `readelf`, `objdump`)
Before deploying a binary to the target board, verify its architecture, ABI, and dynamic library dependencies on the host using these three commands:
~~~bash
# 1. Verify ELF architecture (32-bit ARM EABI5 hard-float vs 64-bit aarch64)
file ./build/my_robot_binary

# 2. Verify required shared libraries (NEEDED) and CPU architecture attributes
arm-linux-gnueabihf-readelf -d -A ./build/my_robot_binary

# 3. Disassemble and verify hardware FPU/NEON vector instructions were emitted
arm-linux-gnueabihf-objdump -d -C ./build/my_robot_binary | head -n 40
~~~

---

## 8. Real-Time Latency Benchmarking (`cyclictest`) & Gold Image Backups

### 8.1 Measuring Deterministic Wakeup Latency with `cyclictest`
* **What It Is:** `cyclictest` (from the `rt-tests` package) spawns a `SCHED_FIFO` real-time thread that sleeps on a high-resolution POSIX timer (`clock_nanosleep` with `TIMER_ABSTIME`) at a fixed period (e.g., `-i 1000` for 1,000 µs = 1 kHz) and measures the exact delta between the theoretical wakeup timestamp and the actual instant the CPU executes the thread.
* **Why It Matters for RT Robotics:** The **Max** latency column reported by `cyclictest` under load defines the worst-case timing jitter of your OS image. For a 1 kHz control loop (`1,000 µs` period), maximum wakeup latency should remain reliably **under 100 µs**.
* **Standard 1 kHz Benchmark Command:**
~~~bash
sudo cyclictest --mlockall --smp --priority=95 --interval=1000 --distance=0 --duration=60s
~~~
  * `--mlockall` (`-m`): Locks virtual memory pages into RAM (`MCL_CURRENT | MCL_FUTURE`).
  * `--smp` (`-a` + `-t`): Starts one measurement thread per CPU core.
  * `--priority=95` (`-p 95`): Runs at `SCHED_FIFO` priority 95.
  * `--interval=1000` (`-i 1000`): 1,000 µs (1 kHz) control loop period.
  * Automatic PM QoS lock: `cyclictest` automatically opens `/dev/cpu_dma_latency` and writes `0` (`0x00000000`) for the duration of the test.

### 8.2 Two-Tier Backup Strategy & The SD Card Capacity Trap

#### Why Raw 16 GB SD Card Images Fail on Slightly Smaller "16 GB" Cards
Not all "16 GB" microSD cards have the exact same raw sector count—a SanDisk 16 GB card may expose `14.83 GiB` (`15,931,539,456` bytes), whereas a Kingston or Samsung 16 GB card may expose `14.45 GiB`. Because a full block copy (`dd if=/dev/mmcblk0`) copies the partition table extending to the very last sector of the source card, flashing a `14.83 GiB` raw `.img` onto a `14.45 GiB` card will fail with an **"Image is too large for target drive"** error.

To eliminate this hardware risk while still maintaining bare-metal disaster recovery, always maintain a **Two-Tier Backup Strategy**:

| Backup Tier | What Is Stored | Size | Hardware Portability & Purpose |
| :--- | :--- | :--- | :--- |
| **Tier 1 (Universal BSP + Sysroot)** | 1. Git-tracked `common/` + `boards/<board>/` scripts & configs<br>2. Compressed host `/opt/<board>-sysroot` archive (`.tar.zst`) | ~1 KB in Git<br>~110 MB `.tar.zst` | **Works on ANY storage size (4 GB eMMC, 8 GB, 16 GB, 32 GB, 64 GB).** Reconstructs the exact real-time setup on any stock OS image in 15 seconds via `provision-<board>.sh`, and restores host cross-compilation offline. |
| **Tier 2 (Bare-Metal Gold Clone)** | Full block-level SD card image (`dd if=/dev/mmcblk0`) compressed with `zstd` (`.img.zst`) | ~450–750 MB `.img.zst` | **Zero-configuration disaster recovery.** Flash directly with BalenaEtcher onto the original SD card (or any card $\ge$ source capacity) to boot immediately without running a single command. |

#### Pre-Backup Zero-Fill Procedure (Run on Target Board Before Tier 2 `dd`)
When files are deleted on `ext4`, only their inode pointers are cleared—old non-zero data blocks remain on the flash sectors. Writing `0x00` bytes to all unallocated space on the root and dormant swap partitions allows `zstd` to compress 13+ GB of empty space down to nearly zero bytes:
~~~bash
# 1. Zero-fill free space on the mounted root filesystem, then delete the temporary file
dd if=/dev/zero of=/tmp/zero.fill bs=4M status=progress || true
sync && rm -f /tmp/zero.fill && sync

# 2. Zero-fill the dormant swap partition (if present, e.g., /dev/mmcblk0p2) and restore swap header
sudo dd if=/dev/zero of=/dev/mmcblk0p2 bs=4M status=progress || true
sudo mkswap /dev/mmcblk0p2
sync
~~~

#### Fast Remote Streaming Backup Command (Run on Host PC / WSL 2)
Always run `zstd -1 -c` **on the target board side** of the SSH pipe so the 13+ GB of zero-filled blocks collapse to ~0 bytes in RAM *before* traversing the CPU's SSH encryption and USB/Ethernet link:
~~~bash
mkdir -p ~/bbb-gold-images
ssh debian@<BOARD_IP> \
    "sudo -n sync && sudo -n dd if=/dev/mmcblk0 bs=4M status=progress | zstd -1 -c" \
    > ~/bbb-gold-images/<board>-rt-gold-$(date +%Y-%m).img.zst
~~~
