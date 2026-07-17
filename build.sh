#!/bin/bash

# Ensure the script exits on error
set -e

TOOLCHAIN_PATH=$HOME/zyc-clang/bin
GIT_COMMIT_ID=$(git rev-parse --short=8 HEAD)
TARGET_DEVICE=$1

if [ -z "$1" ]; then
    echo "Error: No argument provided, please specify a target device." 
    echo "If you need KernelSU, please add [ksu] as the second arg."
    echo "Examples:"
    echo "Build for kebab (OnePlus 8T) without KernelSU:"
    echo "    bash build.sh kebab"
    echo "Build for kebab (OnePlus 8T) with KernelSU:"
    echo "    bash build.sh kebab ksu"
    exit 1
fi

if [ ! -d "$TOOLCHAIN_PATH" ]; then
    echo "TOOLCHAIN_PATH [$TOOLCHAIN_PATH] does not exist."
    echo "Please ensure the toolchain is there, or change TOOLCHAIN_PATH in the script to your toolchain path."
    exit 1
fi

echo "TOOLCHAIN_PATH: [$TOOLCHAIN_PATH]"
export PATH="$TOOLCHAIN_PATH:$PATH"

if ! command -v aarch64-linux-gnu-ld >/dev/null 2>&1; then
    echo "[aarch64-linux-gnu-ld] does not exist, please check your environment."
    exit 1
fi

if ! command -v arm-linux-gnueabi-ld >/dev/null 2>&1; then
    echo "[arm-linux-gnueabi-ld] does not exist, please check your environment."
    exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
    echo "[clang] does not exist, please check your environment."
    exit 1
fi

# Enable ccache for speed up compiling 
export CCACHE_DIR="$HOME/.cache/ccache_mikernel" 
export CC="clang"
export CXX="clang++"
export PATH="/usr/lib/ccache:$PATH"
export CCACHE_COMPILERCHECK=content
export CCACHE_SLOPPINESS=time_macros,include_file_mtime,include_file_ctime
echo "CCACHE_DIR: [$CCACHE_DIR]"

MAKE_ARGS="ARCH=arm64 \
           SUBARCH=arm64 \
           O=out \
           CC=clang \
           HOSTCC=gcc \
           HOSTCXX=g++ \
           CLANG_TRIPLE=aarch64-linux-gnu- \
           CROSS_COMPILE=aarch64-linux-gnu- \
           CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
           CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
           LD=ld.lld \
           AR=llvm-ar \
           NM=llvm-nm \
           OBJCOPY=llvm-objcopy \
           OBJDUMP=llvm-objdump \
           STRIP=llvm-strip"

if [ "$1" == "j1" ]; then
    make $MAKE_ARGS -j1
    exit
fi

if [ "$1" == "continue" ]; then
    make $MAKE_ARGS -j$(nproc)
    exit
fi

# 自动适配 kebab_defconfig 或 vendor/kebab_defconfig
if [ -f "arch/arm64/configs/${TARGET_DEVICE}_defconfig" ]; then
    DEFCONFIG="${TARGET_DEVICE}_defconfig"
elif [ -f "arch/arm64/configs/vendor/${TARGET_DEVICE}_defconfig" ]; then
    DEFCONFIG="vendor/${TARGET_DEVICE}_defconfig"
else
    echo "No target device [${TARGET_DEVICE}] defconfig found."
    echo "Available defconfigs:"
    find arch/arm64/configs -name "*defconfig"
    exit 1
fi

# Check clang is existing.
echo "[clang --version]:"
clang --version

KSU_ZIP_STR=NoKernelSU
if [ "$2" == "ksu" ]; then
    KSU_ENABLE=1
    KSU_ZIP_STR=ReSukiSU-Manual
else
    KSU_ENABLE=0
fi

echo "TARGET_DEVICE: $TARGET_DEVICE using config: $DEFCONFIG"

if [ $KSU_ENABLE -eq 1 ]; then
    echo "KSU is enabled"
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash
else
    echo "KSU is disabled"
fi

echo "Integrating Baseband-guard..."
curl -LSs "https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh" | bash
sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' security/Kconfig

echo "Cleaning..."
rm -rf out/
rm -rf anykernel/

echo "Clone AnyKernel3 for packing kernel"
git clone https://github.com/AstideLabs/AnyKernel3 -b master --single-branch --depth=1 anykernel

# ------------- Building for OxygenOS/ColorOS (OOS/COS) -------------

echo "Building for OxygenOS/ColorOS (OOS/COS)....."
make $MAKE_ARGS $DEFCONFIG

if [ $KSU_ENABLE -eq 1 ]; then
    scripts/config --file out/.config \
    -e KSU \
    -e THREAD_INFO_IN_TASK \
    -e KSU_MANUAL_HOOK \
    -e KSU_MANUAL_HOOK_AUTO_SETUID_HOOK \
    -e KSU_MANUAL_HOOK_AUTO_INITRC_HOOK \
    -e KSU_MANUAL_HOOK_AUTO_INPUT_HOOK \
    -d KSU_SUSFS \
    -e KSU_MULTI_MANAGER_SUPPORT
else
    scripts/config --file out/.config -d KSU
fi

scripts/config --file out/.config \
    -e BBG

# 适用于一加 OOS/COS 的性能与底层配置调整
scripts/config --file out/.config \
    -e PERF_CRITICAL_RT_TASK \
    -e OVERLAY_FS \
    -d LTO_CLANG \
    -e LTO_NONE \
    -e TASK_DELAY_ACCT \
    -d REKERNEL \
    -d REKERNEL_NETWORK

make $MAKE_ARGS -j$(nproc)

if [ -f "out/arch/arm64/boot/Image" ]; then
    echo "The file [out/arch/arm64/boot/Image] exists. OOS/COS Build successfully."
else
    echo "The file [out/arch/arm64/boot/Image] does not exist. Seems OOS/COS build failed."
    exit 1
fi

echo "Generating [out/arch/arm64/boot/dtb]......"
find out/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + >out/arch/arm64/boot/dtb

rm -rf anykernel/kernels/
mkdir -p anykernel/kernels/oos/

cp out/arch/arm64/boot/Image anykernel/kernels/oos/
cp out/arch/arm64/boot/dtb anykernel/kernels/oos/
cp out/arch/arm64/boot/dtbo.img anykernel/kernels/oos/

echo "Build for OOS/COS finished."

# ------------- End of Building for OOS/COS -------------

cd anykernel 
ZIP_FILENAME=APTKernel_OOS_${TARGET_DEVICE}_${KSU_ZIP_STR}_$(date +'%Y%m%d_%H%M%S')_anykernel3_${GIT_COMMIT_ID}.zip
zip -r9 $ZIP_FILENAME ./* -x .git .gitignore out/ ./*.zip
mv $ZIP_FILENAME ../
cd ..

echo "Done. The flashable zip is: [./$ZIP_FILENAME]"
