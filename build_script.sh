#!/bin/bash
#
# Copyright (C) 2020 azrim.
# All rights reserved.

# Init
KERNEL_DIR="${PWD}"
cd "$KERNEL_DIR" || exit
DTB_TYPE="" # define as "single" if want use single file
KERN_IMG="${KERNEL_DIR}"/out/arch/arm64/boot/Image.gz   # if use single file define as Image.gz-dtb instead
KERN_DTBO="${KERNEL_DIR}"/out/arch/arm64/boot/dtbo.img       # and comment this variable
KERN_DTB="${KERNEL_DIR}"/out/arch/arm64/boot/dtb.img
ANYKERNEL="${HOME}"/anykernel
LOGS="${HOME}"/${CHEAD}.log

# Repo URL
ANYKERNEL_REPO="https://github.com/azrim/anykernel3.git"
ANYKERNEL_BRANCH="master"

# Repo info
PARSE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
PARSE_ORIGIN="$(git config --get remote.origin.url)"
COMMIT_POINT="$(git log --pretty=format:'%h : %s' -1)"
CHEAD="$(git rev-parse --short HEAD)"
LATEST_COMMIT="[$COMMIT_POINT](https://github.com/silont-project/kernel_xiaomi_surya/commit/$CHEAD)"
LOGS_URL="[See Drone CI Build Logs Here](https://cloud.drone.io/silont-project/kernel_xiaomi_surya/$DRONE_BUILD_NUMBER)"

# Compiler
mkdir -p "/mnt/workdir/silont-clang"
COMP_TYPE="clang" # unset if want to use gcc as compiler
CLANG_DIR="/mnt/workdir/silont-clang"
CLANG_URL="https://github.com/silont-project/silont-clang/archive/20210117.tar.gz"
GCC_DIR="" # Doesn't needed if use proton-clang
GCC32_DIR="" # Doesn't needed if use proton-clang
CLANG_FILE="/mnt/workdir/clang.tar.gz"

git clone https://gitlab.com/AnggaR96s/clang-gengkapak.git --depth=1 --single-branch $CLANG_DIR

if [[ "${COMP_TYPE}" =~ "clang" ]]; then
    CSTRING=$("$CLANG_DIR"/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
    COMP_PATH="$CLANG_DIR/bin:${PATH}"
else
    COMP_PATH="${GCC_DIR}/bin:${GCC32_DIR}/bin:${PATH}"
fi

# Defconfig
DEFCONFIG="surya_defconfig"
REGENERATE_DEFCONFIG="" # unset if don't want to regenerate defconfig

# Telegram
CHATID="-1001156668998" # Group/channel chatid (use rose/userbot to get it)
TELEGRAM_TOKEN="${TG_TOKEN}"

# Export Telegram.sh
TELEGRAM_FOLDER="${HOME}"/telegram
if ! [ -d "${TELEGRAM_FOLDER}" ]; then
    git clone https://github.com/fabianonline/telegram.sh/ "${TELEGRAM_FOLDER}"
fi

TELEGRAM="${TELEGRAM_FOLDER}"/telegram
tg_cast() {
	curl -s -X POST https://api.telegram.org/bot"$TELEGRAM_TOKEN"/sendMessage -d disable_web_page_preview="true" -d chat_id="$CHATID" -d "parse_mode=MARKDOWN" -d text="$(
		for POST in "${@}"; do
			echo "${POST}"
		done
	)" &> /dev/null
}
tg_ship() {
    "${TELEGRAM}" -f "${ZIPNAME}" -t "${TELEGRAM_TOKEN}" -c "${CHATID}" -H \
    "$(
                for POST in "${@}"; do
                        echo "${POST}"
                done
    )"
}
tg_fail() {
    "${TELEGRAM}" -f "${LOGS}" -t "${TELEGRAM_TOKEN}" -c "${CHATID}" -H \
    "$(
                for POST in "${@}"; do
                        echo "${POST}"
                done
    )"
}

# Versioning
versioning() {
    DEF=$(cat arch/arm64/configs/${DEFCONFIG} | grep CONFIG_LOCALVERSION= | sed "s/-SiLonT-//g" | sed 's/"//g' | sed "s/CONFIG_LOCALVERSION/KERNELTYPE/g")
    export $DEF
}

# Patch Defconfig
patch_config() {
    sed -i "s/${KERNELTYPE}/${KERNELTYPE}-TEST/g" "${KERNEL_DIR}/arch/arm64/configs/${DEFCONFIG}"
    sed -i 's/CONFIG_THINLTO=y/CONFIG_THINLTO=n/g' arch/arm64/configs/"${DEFCONFIG}"
    sed -i 's~SiLonT/~SiLonT-~g' arch/arm64/configs/"${DEFCONFIG}"
    sed -i 's/# CONFIG_LOCALVERSION_AUTO is not set/CONFIG_LOCALVERSION_AUTO=y/g' arch/arm64/configs/"${DEFCONFIG}"
    sed -i 's/# CONFIG_LOCALVERSION_BRANCH_SHA is not set/CONFIG_LOCALVERSION_AUTO=y/g' arch/arm64/configs/"${DEFCONFIG}"
}

# Costumize
patch_config
versioning
KERNEL="[TEST]-SiLonT"
DEVICE="Surya"
KERNELNAME="${KERNEL}-${DEVICE}-${KERNELTYPE}-$(date +%y%m%d-%H%M)"
TEMPZIPNAME="${KERNELNAME}-unsigned.zip"
ZIPNAME="${KERNELNAME}.zip"

# Regenerating Defconfig
regenerate() {
    cp out/.config arch/arm64/configs/"${DEFCONFIG}"
    git add arch/arm64/configs/"${DEFCONFIG}"
    git commit -m "defconfig: Regenerate"
}

# Build Failed
build_failed() {
	    END=$(date +"%s")
	    DIFF=$(( END - START ))
	    echo -e "Kernel compilation failed, See buildlog to fix errors"
	    tg_fail "Build for ${DEVICE} <b>failed</b> in $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)!"
	    exit 1
}

# Building
makekernel() {
    echo "azrim@Hearthaka" > "$KERNEL_DIR"/.builderdata
    export PATH="${COMP_PATH}"
    make O=out ARCH=arm64 ${DEFCONFIG}
    if [[ "${REGENERATE_DEFCONFIG}" =~ "true" ]]; then
        regenerate
    fi
    if [[ "${COMP_TYPE}" =~ "clang" ]]; then
        make -j$(nproc --all) CC=clang CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- O=out ARCH=arm64 LLVM=1 2>&1 | tee "$LOGS"
    else
      	make -j$(nproc --all) O=out ARCH=arm64 CROSS_COMPILE="${GCC_DIR}/bin/aarch64-elf-" CROSS_COMPILE_ARM32="${GCC32_DIR}/bin/arm-eabi-"
    fi
    # Check If compilation is success
    packingkernel
}

# Packing kranul
packingkernel() {
    # Copy compiled kernel
    if [ -d "${ANYKERNEL}" ]; then
        rm -rf "${ANYKERNEL}"
    fi
    git clone "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" "${ANYKERNEL}"
    if ! [ -f "${KERN_IMG}" ]; then
        build_failed
    fi
    if ! [ -f "${KERN_DTBO}" ]; then
        build_failed
    fi
    if [[ "${DTB_TYPE}" =~ "single" ]]; then
        cp "${KERN_IMG}" "${ANYKERNEL}"/Image.gz-dtb
    else
        cp "${KERN_IMG}" "${ANYKERNEL}"/Image.gz
        cp "${KERN_DTBO}" "${ANYKERNEL}"/dtbo.img
        cp "${KERN_DTB}" "${ANYKERNEL}"/dtb.img
    fi

    # Zip the kernel, or fail
    cd "${ANYKERNEL}" || exit
    zip -r9 "${TEMPZIPNAME}" ./*

    # Sign the zip before sending it to Telegram
    curl -sLo zipsigner-4.0.jar https://raw.githubusercontent.com/baalajimaestro/AnyKernel3/master/zipsigner-4.0.jar
    java -jar zipsigner-4.0.jar "${TEMPZIPNAME}" "${ZIPNAME}"

    END=$(date +"%s")
    DIFF=$(( END - START ))

    # Ship it to the CI channel
    tg_ship "<b>-------- $DRONE_BUILD_NUMBER Build Succeed --------</b>" \
            "" \
            "<b>Device:</b> ${DEVICE}" \
            "<b>Version:</b> ${KERNELTYPE}" \
            "<b>Commit Head:</b> ${CHEAD}" \
            "<b>Time elapsed:</b> $((DIFF / 60)):$((DIFF % 60))" \
            "" \
            "Leave a comment below if encountered any bugs!"
}

# Starting
NOW=$(date +%d/%m/%Y-%H:%M)
START=$(date +"%s")
tg_cast "*$DRONE_BUILD_NUMBER CI Build Triggered*" \
	"Compiling with *$(nproc --all)* CPUs" \
	"-----------------------------------------" \
	"*Compiler:* ${CSTRING}" \
	"*Device:* ${DEVICE}" \
	"*Kernel:* ${KERNEL}" \
	"*Version:* ${KERNELTYPE}" \
	"*Linux Version:* $(make kernelversion)" \
	"*Branch:* ${DRONE_BRANCH}" \
	"*Clocked at:* ${NOW}" \
	"*Latest commit:* ${LATEST_COMMIT}" \
 	"------------------------------------------" \
	"${LOGS_URL}"

makekernel
