# ==============================================================================
# File: arm-bbb-toolchain.cmake
# Target: BeagleBone Black Rev C (TI Sitara AM3358 - 1GHz ARM Cortex-A8)
# OS / Sysroot: Debian 13 (Trixie) armhf (GLIBC 2.41) at /opt/bbb-sysroot
# Kernel: 6.12.111-bone-rt-r73 (PREEMPT_RT)
# ==============================================================================

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(CROSS_COMPILE_PREFIX "arm-linux-gnueabihf-")
set(CROSS_COMPILE_ROOT   "/usr")
set(TARGET_SYSROOT       "/opt/bbb-sysroot")

# ------------------------------------------------------------------------------
# 1. Sysroot & CMake Search Path Isolation
# ------------------------------------------------------------------------------
set(CMAKE_SYSROOT "${TARGET_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH "${TARGET_SYSROOT}")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Lock pkg-config to /opt/bbb-sysroot so it never leaks host x86_64 paths
set(ENV{PKG_CONFIG_DIR}         "")
set(ENV{PKG_CONFIG_LIBDIR}      "${TARGET_SYSROOT}/usr/lib/arm-linux-gnueabihf/pkgconfig:${TARGET_SYSROOT}/usr/share/pkgconfig")
set(ENV{PKG_CONFIG_SYSROOT_DIR} "${TARGET_SYSROOT}")

# ------------------------------------------------------------------------------
# 2. Cross-Compiler & Binutils Binaries
# ------------------------------------------------------------------------------
set(CMAKE_C_COMPILER   "${CROSS_COMPILE_ROOT}/bin/${CROSS_COMPILE_PREFIX}gcc")
set(CMAKE_CXX_COMPILER "${CROSS_COMPILE_ROOT}/bin/${CROSS_COMPILE_PREFIX}g++")
set(CMAKE_ASM_COMPILER "${CROSS_COMPILE_ROOT}/bin/${CROSS_COMPILE_PREFIX}gcc")

set(CMAKE_AR      "${CROSS_COMPILE_ROOT}/bin/${CROSS_COMPILE_PREFIX}ar"      CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB  "${CROSS_COMPILE_ROOT}/bin/${CROSS_COMPILE_PREFIX}ranlib"  CACHE FILEPATH "Ranlib")
set(CMAKE_STRIP   "${CROSS_COMPILE_ROOT}/bin/${CROSS_COMPILE_PREFIX}strip"   CACHE FILEPATH "Strip")
set(CMAKE_OBJCOPY "${CROSS_COMPILE_ROOT}/bin/${CROSS_COMPILE_PREFIX}objcopy" CACHE FILEPATH "Objcopy")
set(CMAKE_OBJDUMP "${CROSS_COMPILE_ROOT}/bin/${CROSS_COMPILE_PREFIX}objdump" CACHE FILEPATH "Objdump")

# ------------------------------------------------------------------------------
# 3. Cortex-A8 (AM3358) Architecture & Linker RPATH-Link Flags
# ------------------------------------------------------------------------------
set(BB_ARCH_FLAGS "-mcpu=cortex-a8 -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard")

set(CMAKE_C_FLAGS_INIT   "${BB_ARCH_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${BB_ARCH_FLAGS}")
set(CMAKE_ASM_FLAGS_INIT "${BB_ARCH_FLAGS}")

set(BB_RPATH_LINK "-Wl,-rpath-link,${TARGET_SYSROOT}/usr/lib/arm-linux-gnueabihf -Wl,-rpath-link,${TARGET_SYSROOT}/lib/arm-linux-gnueabihf")

set(CMAKE_EXE_LINKER_FLAGS_INIT    "${BB_RPATH_LINK}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${BB_RPATH_LINK}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${BB_RPATH_LINK}")

# ------------------------------------------------------------------------------
# 4. Feature Detection & Single-Print Configuration Summary Banner
# ------------------------------------------------------------------------------
if(EXISTS "${TARGET_SYSROOT}/usr/include/linux/rpmsg.h")
    set(BEAGLEBONE_HAS_PRU TRUE)
    set(BEAGLEBONE_PRU_MODE "UIO (/dev/uio0..7) & Mainline RemoteProc headers")
elseif(EXISTS "${TARGET_SYSROOT}/usr/include/prussdrv.h")
    set(BEAGLEBONE_HAS_PRU TRUE)
    set(BEAGLEBONE_PRU_MODE "Legacy UIO (prussdrv)")
else()
    set(BEAGLEBONE_HAS_PRU FALSE)
endif()

if(NOT _BBB_TOOLCHAIN_BANNER_PRINTED)
    set(_BBB_TOOLCHAIN_BANNER_PRINTED TRUE CACHE INTERNAL "Banner guard")
    message(STATUS "=================================================")
    message(STATUS "BeagleBone Black Cross-Compilation Configuration")
    message(STATUS "=================================================")
    message(STATUS "Target Processor:     ${CMAKE_SYSTEM_PROCESSOR} (Cortex-A8 / AM3358)")
    message(STATUS "Toolchain Prefix:     ${CROSS_COMPILE_PREFIX}")
    message(STATUS "Target Sysroot:       ${TARGET_SYSROOT}")
    message(STATUS "C++ Compiler:         ${CMAKE_CXX_COMPILER}")
    message(STATUS "Architecture Flags:   ${BB_ARCH_FLAGS}")
    if(BEAGLEBONE_HAS_PRU)
        message(STATUS "PRU Support:          Available (${BEAGLEBONE_PRU_MODE})")
    else()
        message(STATUS "PRU Support:          Not detected")
    endif()
    message(STATUS "=================================================")
endif()
