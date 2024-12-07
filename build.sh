#!/bin/bash
# =========================================
#         _____            _
#        |  ___|__ _ __ __| |___
#        | |_ / _ \ '__/ _` / __|
#        |  _|  __/ | | (_| \__ \
#        |_|  \___|_|  \__,_|___/
#
# =========================================

# Gki - Kernel build script for Mint
# The Fresh Project
# Copyright (C) 2019-2023 TenSeventy7

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# =========================

# Utility directories
ORIGIN_DIR=$(pwd)
CURRENT_BUILD_USER=$(whoami)

# Toolchain options
BUILD_PREF_COMPILER='clang'
BUILD_PREF_COMPILER_VERSION='proton'

# Local toolchain directory
TOOLCHAIN=$HOME/toolchains/exynos9610_toolchains_fresh

# External toolchain directory
TOOLCHAIN_EXT=$(pwd)/toolchain

DEVICE_DB_DIR="${ORIGIN_DIR}/Documentation/device-db"

export ARCH=arm64
export SUBARCH=arm64
export ANDROID_MAJOR_VERSION=r
export PLATFORM_VERSION=11.0.0
export $ARCH

script_echo() {
  echo "  $1"
}

exit_script() {
  kill -INT $$
}

download_toolchain() {
  git clone https://gitlab.com/TenSeventy7/exynos9610_toolchains_fresh.git ${TOOLCHAIN_EXT} --single-branch -b ${BUILD_PREF_COMPILER_VERSION} --depth 1 2>&1 | sed 's/^/     /'
  verify_toolchain
}

verify_toolchain() {
  sleep 2
  script_echo " "

  if [[ -d "${TOOLCHAIN}" ]]; then
    script_echo "I: Toolchain found at default location"
    export PATH="${TOOLCHAIN}/bin:$PATH"
    export LD_LIBRARY_PATH="${TOOLCHAIN}/lib:$LD_LIBRARY_PATH"
  elif [[ -d "${TOOLCHAIN_EXT}" ]]; then

    script_echo "I: Toolchain found at repository root"

    cd ${TOOLCHAIN_EXT}
    git pull
    cd ${ORIGIN_DIR}

    export PATH="${TOOLCHAIN_EXT}/bin:$PATH"
    export LD_LIBRARY_PATH="${TOOLCHAIN_EXT}/lib:$LD_LIBRARY_PATH"

    if [[ ${BUILD_KERNEL_CI} == 'true' ]]; then
      if [[ ${BUILD_PREF_COMPILER_VERSION} == 'proton' ]]; then
        sudo mkdir -p /root/build/install/aarch64-linux-gnu
        sudo cp -r "${TOOLCHAIN_EXT}/lib" /root/build/install/aarch64-linux-gnu/

        sudo chown ${CURRENT_BUILD_USER} /root
        sudo chown ${CURRENT_BUILD_USER} /root/build
        sudo chown ${CURRENT_BUILD_USER} /root/build/install
        sudo chown ${CURRENT_BUILD_USER} /root/build/install/aarch64-linux-gnu
        sudo chown ${CURRENT_BUILD_USER} /root/build/install/aarch64-linux-gnu/lib
      fi
    fi
  else
    script_echo "I: Toolchain not found at default location or repository root"
    script_echo "   Downloading recommended toolchain at ${TOOLCHAIN_EXT}..."
    download_toolchain
  fi

  export CROSS_COMPILE=aarch64-linux-gnu-
  export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  export CC=${BUILD_PREF_COMPILER}
}

update_magisk() {
  script_echo " "
  script_echo "I: Updating Magisk..."

  if [[ "x${BUILD_KERNEL_MAGISK_BRANCH}" == "xcanary" ]]; then
    MAGISK_BRANCH="canary"
  elif [[ "x${BUILD_KERNEL_MAGISK_BRANCH}" == "xlocal" ]]; then
    MAGISK_BRANCH="local"
  else
    MAGISK_BRANCH=""
  fi

  ${ORIGIN_DIR}/usr/magisk/update_magisk.sh ${MAGISK_BRANCH} 2>&1 | sed 's/^/     /'
}

fill_magisk_config() {
  MAGISK_USR_DIR="${ORIGIN_DIR}/usr/magisk/"

  script_echo " "
  script_echo "I: Configuring Magisk..."

  if [[ -f "$MAGISK_USR_DIR/backup_magisk" ]]; then
    rm "$MAGISK_USR_DIR/backup_magisk"
  fi

  echo "KEEPVERITY=true" >> "$MAGISK_USR_DIR/backup_magisk"
  echo "KEEPFORCEENCRYPT=true" >> "$MAGISK_USR_DIR/backup_magisk"
  echo "RECOVERYMODE=false" >> "$MAGISK_USR_DIR/backup_magisk"
  echo "PREINITDEVICE=userdata" >> "$MAGISK_USR_DIR/backup_magisk"

  # Create a unique random seed per-build
  script_echo "   - Generating a unique random seed for this build..."
  RANDOMSEED=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)
  echo "RANDOMSEED=0x$RANDOMSEED" >> "$MAGISK_USR_DIR/backup_magisk"
}

show_usage() {
  script_echo "Usage: ./build.sh -d|--device <device> -v|--variant <variant> [main options]"
  script_echo " "
  script_echo "Main options:"
  script_echo "-d, --device <device>     Set build device to build the kernel for. Required."
  script_echo "-a, --android <version>   Set Android version to build the kernel for. (Default: 11)"
  script_echo "-v, --variant <variant>   Set build variant to build the kernel for. Required."
  script_echo " "
  script_echo "-n, --no-clean            Do not clean and update Magisk before build."
  script_echo "-m, --magisk [canary]     Pre-root the kernel with Magisk. Optional flag to use canary builds."
  script_echo "                          Not available for 'recovery' variant."
  script_echo "-p, --permissive          Build kernel with SELinux fully permissive. NOT RECOMMENDED!"
  script_echo "-g, --gki                 Build kernel with GKI compatibility."
  script_echo " "
  script_echo "-h, --help                Show this message."
  script_echo " "
  script_echo "Variant options:"
  script_echo "    oneui: Build Mint for use with stock and One UI-based ROMs."
  script_echo "     aosp: Build Mint for use with AOSP and AOSP-based Generic System Images (GSIs)."
  script_echo " recovery: Build Mint for use with recovery device trees. Doesn't build a ZIP."
  script_echo " "
  script_echo "Supported devices:"
  script_echo "  a50 (Samsung Galaxy A50)"
  script_echo " a50s (Samsung Galaxy A50s)"
  exit_script
}

merge_config() {
  if [[ ! -e "${SUB_CONFIGS_DIR}/mint_${1}.config" ]]; then
    script_echo "E: Subconfig not found on config DB!"
    script_echo "   ${SUB_CONFIGS_DIR}/mint_${1}.config"
    script_echo "   Make sure it is in the proper directory."
    script_echo " "
    exit_script
  else
    echo "$(cat "${SUB_CONFIGS_DIR}/mint_${1}.config")" >> "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_TMP_CONFIG}"
  fi
}

set_android_version() {
  echo "CONFIG_MINT_PLATFORM_VERSION=${BUILD_ANDROID_PLATFORM}" >> "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_TMP_CONFIG}"
}

get_devicedb_info() {
  if [[ ! -e "${DEVICE_DB_DIR}/${BUILD_DEVICE_NAME}.sh" ]]; then
    script_echo "E: Device info not found from device DB!"
    script_echo "   ${DEVICE_DB_DIR}/${BUILD_DEVICE_NAME}.sh"
    script_echo "   Make sure it is in the proper directory."
    script_echo " "
    exit_script
  else
    source "${DEVICE_DB_DIR}/${BUILD_DEVICE_NAME}.sh"
  fi
}

check_defconfig() {
  if [[ ! -e "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_CONFIG}" ]]; then
    script_echo "E: Defconfig not found!"
    script_echo "   ${BUILD_CONFIG_DIR}/${BUILD_DEVICE_CONFIG}"
    script_echo "   Make sure it is in the proper directory."
    script_echo ""
    exit_script
  else
    echo "$(cat "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_CONFIG}")" > "${BUILD_CONFIG_DIR}/${BUILD_DEVICE_TMP_CONFIG}"
  fi
}

build_kernel() {
  sleep 3
  script_echo " "

  make -C $(pwd) CC=${BUILD_PREF_COMPILER} HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip ${BUILD_DEVICE_TMP_CONFIG} LOCALVERSION="${LOCALVERSION}" 2>&1 | sed 's/^/     /'
  make -C $(pwd) CC=${BUILD_PREF_COMPILER} HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip -j$(nproc --all) LOCALVERSION="${LOCALVERSION}" 2>&1 | sed 's/^/     /'
}

build_image() {
  if [[ -e "$(pwd)/arch/arm64/boot/Image" ]]; then
    script_echo " "
    script_echo "I: Building kernel image..."
    script_echo "    Header/Page size: ${DEVICE_KERNEL_HEADER}/${DEVICE_KERNEL_PAGESIZE}"
    script_echo "      Board and base: ${DEVICE_KERNEL_BOARD}/${DEVICE_KERNEL_BASE}"
    script_echo " "
    script_echo "     Android Version: ${PLATFORM_VERSION}"
    script_echo "Security patch level: ${PLATFORM_PATCH_LEVEL}"

    ${ORIGIN_DIR}/tools/make/bin/mkbootimg \
              --kernel $(pwd)/arch/arm64/boot/Image \
              --cmdline "androidboot.selinux=permissive androidboot.selinux=permissive loop.max_part=7" --board "$DEVICE_KERNEL_BOARD" \
              --base $DEVICE_KERNEL_BASE --pagesize $DEVICE_KERNEL_PAGESIZE \
              --kernel_offset $DEVICE_KERNEL_OFFSET --ramdisk_offset $DEVICE_RAMDISK_OFFSET \
              --second_offset $DEVICE_SECOND_OFFSET --tags_offset $DEVICE_TAGS_OFFSET \
              --os_version "$PLATFORM_VERSION" --os_patch_level "$PLATFORM_PATCH_LEVEL" \
              --header_version $DEVICE_KERNEL_HEADER --hashtype $DEVICE_DTB_HASHTYPE \
              -o ${ORIGIN_DIR}/tools/make/boot.img

    if [[ ! -f ${ORIGIN_DIR}/tools/make/boot.img ]]; then
      script_echo " "
      script_echo "E: Kernel image not built successfully!"
      script_echo "   Errors can be fround from above."
      sleep 3
      exit_script
    fi

  else
    script_echo "E: Image not built!"
    script_echo "   Errors can be fround from above."
    sleep 3
    exit_script
  fi
}

export_image() {
  if [[ -e "$(pwd)/arch/arm64/boot/Image" ]]; then
    script_echo " "
    script_echo "I: Exporting kernel image..."
    mv -f $(pwd)/arch/arm64/boot/Image ${BUILD_KERNEL_OUTPUT}
  else
    script_echo "E: Image not built!"
    script_echo "   Errors can be fround from above."
    sleep 3
    exit_script
  fi
}

build_dtb() {
  $(pwd)/tools/dtb/mkdtboimg cfg_create \
      --dtb-dir=$(pwd) \
      $(pwd)/tools/dtb/dtb.img \
      "$(pwd)/arch/arm64/boot/config/exynos9610-${BUILD_DEVICE_NAME}.dtb.config"
}

build_dtbo() {
  $(pwd)/tools/dtb/mkdtboimg cfg_create \
      --dtb-dir=$(pwd) \
      $(pwd)/tools/dtb/dtbo.img \
      "$(pwd)/arch/arm64/boot/config/exynos9610-${BUILD_DEVICE_NAME}.dtbo.config"
}

set_file_name() {
ZIP_ONEUI_VERSION=""

if [[ ${BUILD_KERNEL_CODE} == "oneui" ]]; then
  ZIP_ONEUI_VERSION="$((${BUILD_ANDROID_PLATFORM} - 8))"
fi

if [[ ! -z ${BUILD_KERNEL_BRANCH} ]]; then

  if [[ ${BUILD_KERNEL_BRANCH} == *"android-"* ]]; then
    BUILD_KERNEL_BRANCH='mainline'
  fi

  if [[ ${BUILD_KERNEL_PERMISSIVE} == 'true' ]]; then
    FILE_NAME_SELINUX="Permissive"
  else
    FILE_NAME_SELINUX="Enforcing"
  fi

  if [[ ${BUILD_KERNEL_BRANCH} == "mainline" ]]; then
    LOCALVERSION=" - Mint ${KERNEL_BUILD_VERSION}"
    export LOCALVERSION=" - Mint ${KERNEL_BUILD_VERSION}"

    if [[ ${BUILD_KERNEL_MAGISK} == 'true' ]]; then
      FILE_OUTPUT=Mint-${KERNEL_BUILD_VERSION}.A${BUILD_ANDROID_PLATFORM}_${FILE_KERNEL_CODE}${ZIP_ONEUI_VERSION}_${BUILD_DEVICE_NAME^}.zip
    else
      FILE_OUTPUT=Mint-${KERNEL_BUILD_VERSION}.A${BUILD_ANDROID_PLATFORM}_${FILE_KERNEL_CODE}${ZIP_ONEUI_VERSION}-NoRoot_${BUILD_DEVICE_NAME^}.zip
    fi
  else
    LOCALVERSION=" - Mint Beta ${GITHUB_RUN_NUMBER}"
    export LOCALVERSION=" - Mint Beta ${GITHUB_RUN_NUMBER}"

    if [[ ${BUILD_KERNEL_MAGISK} == 'true' ]]; then
      FILE_OUTPUT=MintBeta-${GITHUB_RUN_NUMBER}.A${BUILD_ANDROID_PLATFORM}.${FILE_KERNEL_CODE}${ZIP_ONEUI_VERSION}-${FILE_NAME_SELINUX}_${BUILD_DEVICE_NAME^}.CI.zip
    else
      FILE_OUTPUT=MintBeta-${GITHUB_RUN_NUMBER}.A${BUILD_ANDROID_PLATFORM}.${FILE_KERNEL_CODE}${ZIP_ONEUI_VERSION}-${FILE_NAME_SELINUX}-NoRoot_${BUILD_DEVICE_NAME^}.CI.zip
    fi
  fi
else
  if [[ ${BUILD_KERNEL_MAGISK} == 'true' ]]; then
    FILE_OUTPUT=Mint-${BUILD_DATE}.A${BUILD_ANDROID_PLATFORM}_${FILE_KERNEL_CODE}${ZIP_ONEUI_VERSION}_${BUILD_DEVICE_NAME^}_UB.zip
  else
    FILE_OUTPUT=Mint-${BUILD_DATE}.A${BUILD_ANDROID_PLATFORM}_${FILE_KERNEL_CODE}${ZIP_ONEUI_VERSION}_${BUILD_DEVICE_NAME^}_UB.zip
  fi

  BUILD_KERNEL_BRANCH='user'
  LOCALVERSION=" - Mint-user"
  export LOCALVERSION=" - Mint-user"
fi
}

build_package() {
  script_echo " "
  script_echo "I: Building kernel ZIP..."

  # Copy kernel image to package directory
  mv $(pwd)/arch/arm64/boot/Image $(pwd)/tools/make/package/Image -f

  # Copy DTB image to package directory
  mv $(pwd)/arch/arm64/boot/dtb_exynos.img $(pwd)/tools/make/package/dtb.img -f

  # Make the manifest
  touch $(pwd)/tools/make/package/mint.prop

  echo "ro.mint.build.date=${BUILD_DATE}" > $(pwd)/tools/make/package/mint.prop
  echo "ro.mint.build.branch=${BUILD_KERNEL_BRANCH}" >> $(pwd)/tools/make/package/mint.prop
  echo "ro.mint.droid.device=${BUILD_DEVICE_NAME^}" >> $(pwd)/tools/make/package/mint.prop
  echo "ro.mint.droid.variant=${FILE_KERNEL_CODE^}" >> $(pwd)/tools/make/package/mint.prop

  if [[ ${BUILD_KERNEL_BRANCH} == "mainline" ]]; then
    echo "ro.mint.droid.beta=false" >> $(pwd)/tools/make/package/mint.prop
    echo "ro.mint.build.version=${KERNEL_BUILD_VERSION}" >> $(pwd)/tools/make/package/mint.prop
  else
    echo "ro.mint.droid.beta=true" >> $(pwd)/tools/make/package/mint.prop
    echo "ro.mint.build.version=${GITHUB_RUN_NUMBER}" >> $(pwd)/```bash
mint.prop
  fi

  echo "ro.mint.droid.android=${BUILD_ANDROID_PLATFORM}" >> $(pwd)/tools/make/package/mint.prop

  if [[ ${BUILD_KERNEL_MAGISK} == 'true' ]]; then
    echo "ro.mint.droid.root=true" >> $(pwd)/tools/make/package/mint.prop
  else
    echo "ro.mint.droid.root=false" >> $(pwd)/tools/make/package/mint.prop
  fi

  if [[ ${BUILD_KERNEL_PERMISSIVE} == 'true' ]]; then
    echo "ro.mint.droid.selinux=permissive" >> $(pwd)/tools/make/package/mint.prop
  else
    echo "ro.mint.droid.selinux=enforcing" >> $(pwd)/tools/make/package/mint.prop
  fi

  # Make the ZIP
  cd $(pwd)/tools/make/package
  zip -r9 ${FILE_OUTPUT} * -x .git README.md *placeholder

  # Move the ZIP to the output directory
  mv ${FILE_OUTPUT} ${BUILD_KERNEL_OUTPUT}/${FILE_OUTPUT}

  cd ${ORIGIN_DIR}
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--device)
      BUILD_DEVICE_NAME="$2"
      shift 2
      ;;
    -a|--android)
      BUILD_ANDROID_PLATFORM="$2"
      shift 2
      ;;
    -v|--variant)
      BUILD_KERNEL_CODE="$2"
      shift 2
      ;;
    -n|--no-clean)
      BUILD_KERNEL_NOCLEAN='true'
      shift
      ;;
    -m|--magisk)
      BUILD_KERNEL_MAGISK='true'
      if [[ "$2" == "canary" ]]; then
        BUILD_KERNEL_MAGISK_BRANCH='canary'
        shift
      elif [[ "$2" == "local" ]]; then
        BUILD_KERNEL_MAGISK_BRANCH='local'
        shift
      fi
      shift
      ;;
    -p|--permissive)
      BUILD_KERNEL_PERMISSIVE='true'
      shift
      ;;
    -g|--gki)
      BUILD_KERNEL_GKI='true'
      shift
      ;;
    -h|--help)
      show_usage
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      ;;
  esac
done

# Check if required arguments are provided
if [[ -z "$BUILD_DEVICE_NAME" || -z "$BUILD_KERNEL_CODE" ]]; then
  show_usage
fi

# Set default Android version if not provided
if [[ -z "$BUILD_ANDROID_PLATFORM" ]]; then
  BUILD_ANDROID_PLATFORM="11"
fi

# Set variables based on arguments
BUILD_DATE=$(date +%Y%m%d)
BUILD_TIME=$(date +%H%M)
BUILD_ANDROID_PATCH="2023-05"
PLATFORM_VERSION="${BUILD_ANDROID_PLATFORM}.0.0"
PLATFORM_PATCH_LEVEL="${BUILD_ANDROID_PATCH}"

# Set build directories
BUILD_CONFIG_DIR="$(pwd)/arch/${ARCH}/configs"
SUB_CONFIGS_DIR="${BUILD_CONFIG_DIR}/fragments"
BUILD_KERNEL_OUTPUT="$(pwd)/out"

# Set device-specific variables
get_devicedb_info

# Set build configuration
BUILD_DEVICE_CONFIG="${DEVICE_DEFCONFIG}"
BUILD_DEVICE_TMP_CONFIG="${DEVICE_DEFCONFIG}_tmp"

# Set file name variables
FILE_KERNEL_CODE="${BUILD_KERNEL_CODE}"
if [[ ${BUILD_KERNEL_CODE} == "oneui" ]]; then
  FILE_KERNEL_CODE="stock"
fi

# Verify and download toolchain if needed
verify_toolchain

# Clean build if not specified otherwise
if [[ ${BUILD_KERNEL_NOCLEAN} != 'true' ]]; then
  script_echo "I: Cleaning build..."
  make -C $(pwd) clean && make -C $(pwd) mrproper
  rm -rf ${BUILD_KERNEL_OUTPUT}
fi

# Create output directory
mkdir -p ${BUILD_KERNEL_OUTPUT}

# Check and prepare defconfig
check_defconfig

# Merge configurations
merge_config "${BUILD_KERNEL_CODE}"

if [[ ${BUILD_KERNEL_GKI} == 'true' ]]; then
  merge_config "gki"
fi

if [[ ${BUILD_KERNEL_PERMISSIVE} == 'true' ]]; then
  merge_config "permissive"
fi

# Set Android version in config
set_android_version

# Update Magisk if needed
if [[ ${BUILD_KERNEL_MAGISK} == 'true' && ${BUILD_KERNEL_CODE} != 'recovery' ]]; then
  update_magisk
  fill_magisk_config
fi

# Set file name
set_file_name

# Build kernel
build_kernel

# Build kernel image
build_image

# Build DTB
build_dtb

# Build DTBO
build_dtbo

# Export kernel image
export_image

# Build package
if [[ ${BUILD_KERNEL_CODE} != 'recovery' ]]; then
  build_package
fi

script_echo " "
script_echo "I: Build completed successfully!"
script_echo "   Output: ${BUILD_KERNEL_OUTPUT}/${FILE_OUTPUT}"
script_echo " "

exit 0
