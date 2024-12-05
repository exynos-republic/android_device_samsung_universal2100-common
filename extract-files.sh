#!/bin/bash
#
# SPDX-FileCopyrightText: 2016 The CyanogenMod Project
# SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

set -e

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

export TARGET_ENABLE_CHECKELF=true

# If XML files don't have comments before the XML header, use this flag
# Can still be used with broken XML files by using blob_fixup
export TARGET_DISABLE_XML_FIXING=true

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_COMMON=
ONLY_FIRMWARE=
ONLY_TARGET=
KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-common)
            ONLY_COMMON=true
            ;;
        --only-firmware)
            ONLY_FIRMWARE=true
            ;;
        --only-target)
            ONLY_TARGET=true
            ;;
        -n | --no-cleanup)
            CLEAN_VENDOR=false
            ;;
        -k | --kang)
            KANG="--kang"
            ;;
        -s | --section)
            SECTION="${2}"
            shift
            CLEAN_VENDOR=false
            ;;
        *)
            SRC="${1}"
            ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        vendor/lib*/libsensorlistener.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --add-needed libshim_sensorndkbridge.so "${2}"
            ;;
        vendor/lib*/libskeymaster4device.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --replace-needed libcrypto.so libcrypto-tm.so "${2}"
            "${PATCHELF}" --add-needed libssl-tm.so "${2}"
            "${PATCHELF}" --add-needed libshim_crypto.so "${2}"
            ;;
	vendor/lib*/libwvhidl.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --replace-needed libprotobuf-cpp-lite-3.9.1.so libprotobuf-cpp-full-3.9.1.so "${2}"
            ;;
        vendor/lib*/sensors.*.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --replace-needed libutils.so libutils-v32.so "${2}"
            sed -i 's/_ZN7android6Thread3runEPKcim/_ZN7utils326Thread3runEPKcim/g' "${2}"
            ;;
        vendor/bin/hw/rild)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --replace-needed libril.so libril-samsung.so "${2}"
            ;;
        vendor/lib64/libsec-ril.so)
            xxd -p -c0 "${2}" | sed "s/600e40f9e10315aa820c8052e30314aa/600e40f9e10315aa820c8052030080d2/g" | xxd -r -p > "${2}".patched
            mv "${2}".patched "${2}"
            ;;
        vendor/lib/soundfx/libaudioeffectoffload.so | vendor/lib64/soundfx/libaudioeffectoffload.so)
            [ "$2" = "" ] && return 0
	        "$PATCHELF" --replace-needed libtinyalsa.so libtinyalsa.exynos2100.so "$2"
            ;;
        vendor/lib/hw/audio.primary.exynos2100.so)
            [ "$2" = "" ] && return 0
	        "$PATCHELF" --replace-needed libaudioroute.so libaudioroute.exynos2100.so "$2"
            "$PATCHELF" --replace-needed libtinyalsa.so libtinyalsa.exynos2100.so "$2"
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

function blob_fixup_dry() {
    blob_fixup "$1" ""
}

if [ -z "${ONLY_FIRMWARE}" ] && [ -z "${ONLY_TARGET}" ]; then
    # Initialize the helper for common device
    setup_vendor "${DEVICE_COMMON}" "${VENDOR_COMMON:-$VENDOR}" "${ANDROID_ROOT}" true "${CLEAN_VENDOR}"

    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

if [ -z "${ONLY_COMMON}" ] && [ -s "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-files.txt" ]; then
    # Reinitialize the helper for device
    source "${MY_DIR}/../../${VENDOR}/${DEVICE}/extract-files.sh"
    setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

    if [ -z "${ONLY_FIRMWARE}" ]; then
        extract "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
    fi

    if [ -z "${SECTION}" ] && [ -f "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-firmware.txt" ]; then
        extract_firmware "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-firmware.txt" "${SRC}"
    fi
fi

"${MY_DIR}/setup-makefiles.sh"
