#!/bin/bash

# ============================================================
# Crave Custom ROM Build Pipeline
# ============================================================

DEVICE=${1:-"stone"}
ROM_CHOICE=${2:-1}
START_TIME=$(date +%s)
LOG_FILE="build_${DEVICE}_$(date +%Y%m%d_%H%M).log"

rm -f "/tmp/build_failed.lock"
rm -f "./out/siso_failed_commands.sh" "out/siso_failed_commands.sh" 2>/dev/null || true

export BUILD_USERNAME="${BUILD_USERNAME:-frnAlt}"
if [ -d "/opt/crave" ]; then
    export BUILD_HOSTNAME="crave"
else
    export BUILD_HOSTNAME=$(hostname)
fi

# ============================================================
# Logging Setup
# ============================================================
exec 3>&1 4>&2
exec 1> >(tee -a "$LOG_FILE") 2>&1

set -eE
set -o pipefail

# ============================================================
# Signal & Error Handling
# ============================================================
handle_error() {
    trap - ERR
    set +eE
    set +o pipefail
    local FAILED_LINE="$1"

    exec 1>&3 2>&4
    sleep 1

    if [ -f "/tmp/build_failed.lock" ]; then
        exit 1
    fi
    touch "/tmp/build_failed.lock"

    local END_TIME=$(date +%s)
    local ELAPSED_SECONDS=$((END_TIME - START_TIME))
    local ELAPSED_MINUTES=$((ELAPSED_SECONDS / 60))
    local REM_SECONDS=$((ELAPSED_SECONDS % 60))

    echo "============================================================"
    echo "[ERROR] Build failed on line ${FAILED_LINE}"
    echo "[ERROR] Device:  ${DEVICE_NAME:-${DEVICE}}"
    echo "[ERROR] ROM:     ${ROM_NAME:-Unknown}"
    echo "[ERROR] Elapsed: ${ELAPSED_MINUTES}m ${REM_SECONDS}s"
    if [ -f "$LOG_FILE" ]; then
        echo "[ERROR] Log:     ${LOG_FILE}"
    fi

    local SISO_FAILED_FILE="./out/siso_failed_commands.sh"
    if [ ! -f "$SISO_FAILED_FILE" ] && [ -f "out/siso_failed_commands.sh" ]; then
        SISO_FAILED_FILE="out/siso_failed_commands.sh"
    fi
    if [ -f "$SISO_FAILED_FILE" ]; then
        echo "[ERROR] Failed commands: ${SISO_FAILED_FILE}"
    fi
    echo "============================================================"

    exit 1
}

trap 'handle_error $LINENO' ERR

# ============================================================
# Target Configuration
# ============================================================
echo "============================================================"
echo "[INFO] Analyzing build target configuration..."
echo "============================================================"

MANUAL_REMOVALS=()
MANUAL_GIT_CLONES=()
CUSTOM_REPOS=()
BUILD_TARGET=""

case "$DEVICE" in
    "stone")
        DEVICE_NAME="Redmi Note 12 5G / Poco X5 5G (stone)"
        case "$ROM_CHOICE" in
            1|6|"lunaris")
                ROM_NAME="Lunaris OS"
                ANDROID_VERSION="16.2"
                ROM_VERSION="3.12"
                GH_REPO="frnAlt/Lunaris_stone"

                REPO_INIT_URL="https://github.com/Lunaris-AOSP/android"
                REPO_INIT_BRANCH="16.2"
                USE_LOCAL_MANIFEST="true"
                LOCAL_MANIFEST_BRANCH="lunaris"
                BUILD_TARGET="lineage_stone-bp2a-userdebug"
                BUILD_COMMAND="m lunaris"
                ;;

            "lineage-23.2")
                ROM_NAME="LineageOS 23.2"
                ANDROID_VERSION="16-QPR2"
                ROM_VERSION="23.2"
                GH_REPO="frnAlt/LineageOS_stone"

                REPO_INIT_URL="https://github.com/LineageOS/android.git"
                REPO_INIT_BRANCH="lineage-23.2"
                USE_LOCAL_MANIFEST="true"
                LOCAL_MANIFEST_BRANCH="lineage-16"
                BUILD_TARGET="lineage_stone-bp4a-userdebug"
                BUILD_COMMAND="m bacon"

                BASE_URL="https://github.com/lineage-23-2-stone"
                CUSTOM_REPOS=(
                    "packages/apps/Settings|lineage_qpr2_packages_apps_Settings"
                    "packages/apps/Launcher3|lineage_qpr2_packages_apps_Launcher3"
                    "frameworks/native|lineage_qpr2_frameworks_native"
                    "art|lineage_qpr2_android_art"
                    "frameworks/base|lineage_qpr2_frameworks_base"
                    "bionic|lineage_qpr2_bionic"
                    "frameworks/libs/systemui|lineage_qpr2_frameworks_libs_systemui"
                    "hardware/lineage/interfaces|lineage_qpr2_hardware_lineage_interfaces"
                    "vendor/lineage|lineage_qpr2_vendor_lineage"
                    "system/sepolicy|lineage_qpr2_system_sepolicy"
                )
                ;;

            2)
                ROM_NAME="LineageOS 22.2"
                ANDROID_VERSION="15"
                ROM_VERSION="22.2"
                GH_REPO="frnAlt/LineageOS_stone"

                REPO_INIT_URL="https://github.com/LineageOS/android.git"
                REPO_INIT_BRANCH="lineage-22.2"
                USE_LOCAL_MANIFEST="true"
                LOCAL_MANIFEST_BRANCH="lineage-15"
                BUILD_TARGET="lineage_stone-bp1a-userdebug"
                BUILD_COMMAND="m bacon"

                MANUAL_GIT_CLONES=(
                    "https://github.com/LineageOS/android_external_google-fonts_google-sans-flex.git -b lineage-23.2 external/google-fonts/google-sans-flex"
                )

                BASE_URL="https://github.com/lineage-22-2-stone"
                CUSTOM_REPOS=(
                    "packages/apps/Updater|lineage_a15_packages_apps_Updater"
                    "packages/apps/Settings|lineage_a15_packages_apps_Settings"
                    "packages/apps/Trebuchet|lineage_a15_packages_apps_Trebuchet"
                    "frameworks/native|lineage_a15_frameworks_native"
                    "frameworks/base|lineage_a15_frameworks_base"
                    "bionic|lineage_a15_bionic"
                    "art|lineage_a15_art"
                    "build/soong|lineage_a15_build_soong"
                    "frameworks/libs/systemui|lineage_a15_frameworks_libs_systemui"
                    "hardware/lineage/interfaces|lineage_a15_hardware_lineage_interfaces"
                    "vendor/lineage|lineage_a15_vendor_lineage"
                    "packages/overlays/Lineage|lineage_a15_packages_overlays_Lineage"
                )
                ;;

            3)
                ROM_NAME="YAAP 17"
                ANDROID_VERSION="17"
                GH_REPO="frnAlt/YAAP_stone"

                REPO_INIT_URL="https://github.com/yaap/manifest.git"
                REPO_INIT_BRANCH="seventeen"
                USE_LOCAL_MANIFEST="true"
                LOCAL_MANIFEST_BRANCH="yaap-17"
                BUILD_TARGET="yaap_stone-userdebug"
                BUILD_COMMAND="m yaap"

                BASE_URL="https://github.com/yaap-17-stone"
                CUSTOM_REPOS=(
                    "build/soong|build_soong"
                    "frameworks/native|frameworks_native"
                    "packages/apps/Launcher3|packages_apps_Launcher3"
                )
                ;;

            4)
                ROM_NAME="Infinity-X"
                ANDROID_VERSION="17"
                GH_REPO="frnAlt/Infinity-X_stone"

                REPO_INIT_URL="https://github.com/projectinfinity-X/manifest"
                REPO_INIT_BRANCH="17"
                USE_LOCAL_MANIFEST="false"
                LOCAL_MANIFEST_BRANCH=""
                BUILD_TARGET="infinity_stone-userdebug"
                BUILD_COMMAND="m bacon"

                MANUAL_GIT_CLONES=(
                    "https://github.com/frnAlt/device_xiaomi_stone_new.git -b infinity-17 device/xiaomi/stone"
                    "https://github.com/frnAlt/vendor_xiaomi_stone.git vendor/xiaomi/stone"
                    "https://github.com/frnAlt/kernel_xiaomi_stone_rebase.git kernel/xiaomi/stone"
                    "https://github.com/frnAlt/infinity_build_soong.git build/soong"
                    "https://github.com/LineageOS/android_hardware_xiaomi.git -b lineage-23.2 hardware/xiaomi"
                    "https://github.com/frnAlt/packages_apps_ViPER4AndroidFX.git packages/apps/ViPER4AndroidFX"
                    "https://github.com/frnAlt/hardware_dolby.git hardware/dolby"
                )
                ;;

            5)
                ROM_NAME="LineageOS 24.0"
                ANDROID_VERSION="17"
                ROM_VERSION="24.0"
                GH_REPO="frnAlt/LineageOS_stone"

                REPO_INIT_URL="https://github.com/lineage-24-stone/android.git"
                REPO_INIT_BRANCH="lineage-24.0"
                USE_LOCAL_MANIFEST="true"
                LOCAL_MANIFEST_BRANCH="lineage-17"
                BUILD_TARGET="lineage_stone-cp2a-userdebug"
                BUILD_COMMAND="m bacon"
                ;;

            *)
                echo "[ERROR] Invalid ROM choice for stone: $ROM_CHOICE"
                handle_error $LINENO
                ;;
        esac
        ;;

    "spes")
        DEVICE_NAME="Redmi Note 11 (spes)"
        case "$ROM_CHOICE" in
            1)
                ROM_NAME="LineageOS 20"
                ANDROID_VERSION="13"
                ROM_VERSION="20.0"
                GH_REPO="frnAlt/LineageOS_spes"

                REPO_INIT_URL="https://github.com/LineageOS/android.git"
                REPO_INIT_BRANCH="lineage-20.0"
                USE_LOCAL_MANIFEST="true"
                LOCAL_MANIFEST_BRANCH="spes-13"
                BUILD_TARGET="lineage_spes-userdebug"
                BUILD_COMMAND="m bacon"
                ;;

            *)
                echo "[ERROR] Invalid ROM choice for spes: $ROM_CHOICE"
                handle_error $LINENO
                ;;
        esac
        ;;

    *)
        echo "[ERROR] Unsupported device: $DEVICE"
        handle_error $LINENO
        ;;
esac

echo "[INFO] Selected Device:  ${DEVICE_NAME}"
echo "[INFO] Selected ROM:     ${ROM_NAME}"
echo "[INFO] Android Version:  ${ANDROID_VERSION}"
echo "[INFO] Build Hostname:   ${BUILD_HOSTNAME}"

# ============================================================
# Modular Execution Functions
# ============================================================

sync_repositories() {
    echo "============================================================"
    echo "[INFO] Initializing repository: ${REPO_INIT_URL} (${REPO_INIT_BRANCH})"
    echo "============================================================"

    repo init -u "$REPO_INIT_URL" -b "$REPO_INIT_BRANCH" --git-lfs --depth=1

    rm -rf .repo/local_manifests/
    if [ "$USE_LOCAL_MANIFEST" == "true" ]; then
        echo "[INFO] Fetching local manifests from branch: ${LOCAL_MANIFEST_BRANCH}"
        LOCAL_MANIFEST_URL="${LOCAL_MANIFEST_URL:-https://github.com/frnAlt/local_manifests-1.git}"
        git clone --depth=1 -b "$LOCAL_MANIFEST_BRANCH" "$LOCAL_MANIFEST_URL" .repo/local_manifests
    else
        echo "[INFO] Local manifests disabled for ${ROM_NAME}."
    fi

    if [ "$ANDROID_VERSION" == "17" ]; then
        rm -rf prebuilts/gcc 2>/dev/null || true
    fi

    if [ -f /opt/crave/resync.sh ]; then
        echo "[INFO] Executing Crave resync routine..."
        /opt/crave/resync.sh
    else
        echo "[INFO] Executing repo sync..."
        for i in {1..3}; do
            repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc --all) && break || {
                if [ $i -eq 3 ]; then
                    echo "[ERROR] Repo sync failed after 3 attempts."
                    handle_error $LINENO
                fi
                echo "[WARN] Repo sync attempt $i failed. Retrying in 30 seconds..."
                sleep 30
            }
        done
    fi

    if [ ${#MANUAL_REMOVALS[@]} -gt 0 ]; then
        echo "[INFO] Removing conflicting paths..."
        for rm_target in "${MANUAL_REMOVALS[@]}"; do
            echo "[INFO] Removing ${rm_target}..."
            rm -rf "$rm_target"
        done
    fi

    if [ ${#MANUAL_GIT_CLONES[@]} -gt 0 ]; then
        echo "[INFO] Executing manual git clones..."
        for clone_args in "${MANUAL_GIT_CLONES[@]}"; do
            TARGET_DIR=$(echo "$clone_args" | awk '{print $NF}')
            rm -rf "$TARGET_DIR"
            git clone --depth=1 $clone_args &
        done
        wait
    fi

    if [ ${#CUSTOM_REPOS[@]} -gt 0 ]; then
        echo "[INFO] Syncing custom repositories for ${ROM_NAME}..."
        for repo_info in "${CUSTOM_REPOS[@]}"; do
            DIR="${repo_info%%|*}"
            REPO_NAME="${repo_info##*|}"
            rm -rf "$DIR"
            git clone "$BASE_URL/$REPO_NAME.git" --depth=1 "$DIR" &
        done
        wait
        echo "[INFO] Custom sources synchronized."
    fi

    if [ "$DEVICE" == "stone" ]; then
        CLANG_TARGET_DIR="prebuilts/clang/host/linux-x86/clang-r614150"
        if [ ! -d "$CLANG_TARGET_DIR" ] || [ ! -x "$CLANG_TARGET_DIR/bin/clang" ]; then
            echo "[INFO] Setting up Clang r614150 toolchain..."
            rm -rf "$CLANG_TARGET_DIR"
            mkdir -p "$CLANG_TARGET_DIR"

            CLANG_URL="https://github.com/bachnxuan/aosp_clang_mirror/releases/download/clang-r614150-16165221/clang-r614150.tar.gz"
            wget -q "$CLANG_URL" -O /tmp/clang-download.tar.gz
            tar -xf /tmp/clang-download.tar.gz -C "$CLANG_TARGET_DIR"
            rm -f /tmp/clang-download.tar.gz

            if [ ! -f "$CLANG_TARGET_DIR/bin/clang" ]; then
                NESTED_DIR=$(find "$CLANG_TARGET_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
                if [ -n "$NESTED_DIR" ] && [ -f "$NESTED_DIR/bin/clang" ]; then
                    shopt -s dotglob 2>/dev/null || true
                    mv "$NESTED_DIR"/* "$CLANG_TARGET_DIR"/ 2>/dev/null || true
                    shopt -u dotglob 2>/dev/null || true
                    rm -rf "$NESTED_DIR"
                fi
            fi

            chmod -R +x "$CLANG_TARGET_DIR/bin" 2>/dev/null || true

            if [ -x "$CLANG_TARGET_DIR/bin/clang" ]; then
                set +eE
                CLANG_VER=$("$CLANG_TARGET_DIR/bin/clang" --version 2>/dev/null | head -n 1 || echo "r614150")
                set -eE
                echo "[INFO] Clang configured: ${CLANG_VER}"
            else
                echo "[WARN] Clang binary missing at ${CLANG_TARGET_DIR}/bin/clang after extraction."
            fi
        else
            echo "[INFO] Clang r614150 toolchain verified."
        fi
    fi

    if [[ "$ROM_NAME" == *"YAAP"* ]]; then
        echo "[INFO] Applying genfscon fix for YAAP..."
        find device/qcom/sepolicy_vndr -name "genfs_contexts" -exec sed -i '/genfscon sysfs \/class\/typec/d' {} + 2>/dev/null || true
    fi

    if [ "$DEVICE" == "spes" ]; then
        echo "[INFO] Applying Android 13 compatibility fixes for spes..."
        find packages/apps/ViPER4AndroidFX vendor/bcr -name "Android.bp" -exec sed -i '/preprocessed:/d' {} + 2>/dev/null || true
    fi
}

compile_rom() {
    export TZ="Asia/Kolkata"

    if [ "$DEVICE" == "spes" ]; then
        if ! dpkg -s libncurses5 &> /dev/null; then
            echo "[INFO] Installing libncurses5 compatibility packages..."
            sudo apt-get update -y
            sudo apt-get install -y libncurses5 libtinfo5 || true
        fi
        
        if ! dpkg -s libncurses5 &> /dev/null; then
            echo "[INFO] Linking ncurses6 system fallback libraries..."
            NCURSES_LIB=$(find /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib /lib -maxdepth 2 -name "libncurses.so.6*" -print -quit 2>/dev/null)
            TINFO_LIB=$(find /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib /lib -maxdepth 2 -name "libtinfo.so.6*" -print -quit 2>/dev/null)
            
            if [ -n "$NCURSES_LIB" ]; then
                NCURSES_DIR=$(dirname "$NCURSES_LIB")
                sudo ln -sf "$NCURSES_LIB" "$NCURSES_DIR/libncurses.so.5"
            fi
            if [ -n "$TINFO_LIB" ]; then
                TINFO_DIR=$(dirname "$TINFO_LIB")
                sudo ln -sf "$TINFO_LIB" "$TINFO_DIR/libtinfo.so.5"
            fi
            sudo ldconfig || true
        fi
    fi

    set +eE
    source build/envsetup.sh
    if [ -n "$BUILD_TARGET" ]; then
        if [[ "$BUILD_TARGET" == *" "* ]]; then
            $BUILD_TARGET
        else
            lunch "$BUILD_TARGET" || lunch "${BUILD_TARGET/-bp2a/}" || lunch "lineage_${DEVICE}-userdebug"
        fi
        set -eE

        echo "[INFO] Cleaning target build environment..."
        m installclean
    else
        set -eE
        echo "[INFO] Using custom build command directly without lunch."
    fi

    echo "============================================================"
    echo "[INFO] Starting build for: ${ROM_NAME} (${BUILD_TARGET})"
    echo "============================================================"

    rm -f "./out/siso_failed_commands.sh" "out/siso_failed_commands.sh" 2>/dev/null || true
    $BUILD_COMMAND

    local END_TIME=$(date +%s)
    local BUILD_MINUTES=$(((END_TIME - START_TIME) / 60))
    local BUILD_HOURS=$((BUILD_MINUTES / 60))
    local REMAINING_MINUTES=$((BUILD_MINUTES % 60))

    DISPLAY_TIME="${BUILD_MINUTES}m"
    if [ "$BUILD_HOURS" -gt 0 ]; then
        DISPLAY_TIME="${BUILD_HOURS}h ${REMAINING_MINUTES}m"
    fi

    echo "[INFO] Build completed in: ${DISPLAY_TIME}"
}

process_artifacts() {
    echo "============================================================"
    echo "[INFO] Inspecting build artifacts..."
    echo "============================================================"

    if ! command -v jq &> /dev/null; then
        sudo apt-get install -y jq > /dev/null 2>&1 || true
    fi

    TARGET_DIR="out/target/product/${DEVICE}"
    ROM_ZIP=$(ls -t ${TARGET_DIR}/*${DEVICE}*.zip 2>/dev/null | head -n 1 || true)

    if [ -z "$ROM_ZIP" ] || [ ! -f "$ROM_ZIP" ]; then
        echo "[ERROR] ROM package not found in ${TARGET_DIR}."
        handle_error $LINENO
    fi

    echo "[INFO] Found target ROM: $(basename "$ROM_ZIP")"

    ROM_SIZE_HUMAN=$(du -h "$ROM_ZIP" 2>/dev/null | awk '{print $1}' || echo "Unknown")
    ROM_SHA256=$(sha256sum "$ROM_ZIP" 2>/dev/null | awk '{print $1}' || echo "Unknown")
    ROM_MD5=$(md5sum "$ROM_ZIP" 2>/dev/null | awk '{print $1}' || echo "Unknown")

    FILE_NAME=$(basename "$ROM_ZIP")
    REL_TAG=$(date +%y%m%d)

    EXTRACT_DIR=$(mktemp -d)
    unzip -p "$ROM_ZIP" META-INF/com/android/metadata > "$EXTRACT_DIR/metadata.txt" 2>/dev/null || true
    
    if grep -q "post-timestamp=" "$EXTRACT_DIR/metadata.txt" 2>/dev/null; then
        BUILD_DATETIME=$(grep "post-timestamp=" "$EXTRACT_DIR/metadata.txt" | cut -d= -f2 | tr -d '\r')
        echo "[INFO] Extracted build timestamp: ${BUILD_DATETIME}"
    else
        BUILD_DATETIME=$(date +%s)
        echo "[WARN] Unable to extract metadata timestamp. Using current timestamp: ${BUILD_DATETIME}"
    fi
    rm -rf "$EXTRACT_DIR"

    case $ROM_CHOICE in
        1|6|"lunaris")
            echo "[INFO] Generating OTA metadata for Lunaris OS..."
            FILE_SIZE=$(stat -c %s "$ROM_ZIP")
            FILE_HASH=$(sha256sum "$ROM_ZIP" | awk '{print $1}')
            FILE_MD5=$(md5sum "$ROM_ZIP" | awk '{print $1}')
            GH_DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/${REL_TAG}/${FILE_NAME}"
            JSON_FILE="${TARGET_DIR}/${DEVICE}.json"

            jq -n \
              --arg dt "$BUILD_DATETIME" \
              --arg fn "$FILE_NAME" \
              --arg id "$FILE_HASH" \
              --arg md5 "$FILE_MD5" \
              --arg sz "$FILE_SIZE" \
              --arg url "$GH_DOWNLOAD_URL" \
              --arg ver "$ROM_VERSION" \
              --arg dev "$DEVICE" \
              '{
                response: [
                  {
                    maintainer: "@Parvez52",
                    currently_maintained: true,
                    oem: "Xiaomi",
                    device: $dev,
                    filename: $fn,
                    download: $url,
                    timestamp: ($dt | tonumber),
                    md5: $md5,
                    sha256: $id,
                    size: ($sz | tonumber),
                    version: $ver,
                    buildtype: "UNOFFICIAL"
                  }
                ]
              }' > "$JSON_FILE"

            echo "[INFO] Generated ${JSON_FILE}"
            ;;

        5|"lineage-23.2")
            echo "[INFO] Generating OTA metadata for LineageOS..."
            FILE_SIZE=$(stat -c %s "$ROM_ZIP")
            FILE_HASH=$(sha256sum "$ROM_ZIP" | awk '{print $1}')
            GH_DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/${REL_TAG}/${FILE_NAME}"
            JSON_FILE="${TARGET_DIR}/${DEVICE}.json"

            jq -n \
              --arg dt "$BUILD_DATETIME" \
              --arg fn "$FILE_NAME" \
              --arg id "$FILE_HASH" \
              --arg rt "UNOFFICIAL" \
              --arg sz "$FILE_SIZE" \
              --arg url "$GH_DOWNLOAD_URL" \
              --arg ver "$ROM_VERSION" \
              '[
                {
                  datetime: ($dt | tonumber),
                  type: $rt,
                  version: $ver,
                  files: [
                    {
                      filename: $fn,
                      sha256: $id,
                      size: ($sz | tonumber),
                      url: $url
                    }
                  ]
                }
              ]' > "$JSON_FILE"

            echo "[INFO] Generated ${JSON_FILE}"
            ;;

        2)
            echo "[INFO] Generating response metadata for LineageOS 22.2..."
            FILE_SIZE=$(stat -c %s "$ROM_ZIP")
            FILE_HASH=$(sha256sum "$ROM_ZIP" | awk '{print $1}')
            GH_DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/${REL_TAG}/${FILE_NAME}"
            JSON_FILE="${TARGET_DIR}/${DEVICE}.json"

            jq -n \
              --arg dt "$BUILD_DATETIME" \
              --arg fn "$FILE_NAME" \
              --arg id "$FILE_HASH" \
              --arg rt "nightly" \
              --arg sz "$FILE_SIZE" \
              --arg url "$GH_DOWNLOAD_URL" \
              --arg ver "$ROM_VERSION" \
              '{
                response: [
                  {
                    datetime: ($dt | tonumber),
                    filename: $fn,
                    id: $id,
                    romtype: $rt,
                    size: ($sz | tonumber),
                    url: $url,
                    version: $ver
                  }
                ]
              }' > "$JSON_FILE"

            echo "[INFO] Generated ${JSON_FILE}"
            ;;

        3)
            echo "[INFO] Generating YAAP payload metadata..."
            JSON_FILE="${TARGET_DIR}/${DEVICE}.json"

            python3 - <<EOF > "$JSON_FILE"
import zipfile, json

zip_path = "$ROM_ZIP"
filename = "$FILE_NAME"
datetime_val = int("$BUILD_DATETIME")

offset = 0
file_hash = ""
file_size = "0"
metadata_hash = ""
metadata_size = "0"

with zipfile.ZipFile(zip_path, 'r') as z:
    try:
        info = z.getinfo('payload.bin')
        offset = info.header_offset + 30 + len(info.filename) + len(info.extra)
    except KeyError:
        offset = 0

    try:
        with z.open('payload_properties.txt') as f:
            for line in f.read().decode('utf-8').splitlines():
                if '=' in line:
                    k, v = line.split('=', 1)
                    k = k.strip()
                    v = v.strip()
                    if k == 'FILE_HASH':
                        file_hash = v
                    elif k == 'FILE_SIZE':
                        file_size = v
                    elif k == 'METADATA_HASH':
                        metadata_hash = v
                    elif k == 'METADATA_SIZE':
                        metadata_size = v
    except KeyError:
        pass

data = {
    "response": [
        {
            "datetime": datetime_val,
            "filename": filename,
            "payload": [
                {
                    "offset": offset,
                    "FILE_HASH": file_hash,
                    "FILE_SIZE": file_size,
                    "METADATA_HASH": metadata_hash,
                    "METADATA_SIZE": metadata_size
                }
            ]
        }
    ]
}

print(json.dumps(data, indent=2))
EOF
            echo "[INFO] Generated ${JSON_FILE}"
            ;;

        4)
            AUTO_JSON="${ROM_ZIP}.json"
            if [ -n "$AUTO_JSON" ] && [ -f "$AUTO_JSON" ]; then
                echo "[INFO] Autogenerated Infinity-X JSON: $(basename "$AUTO_JSON")"
            else
                echo "[WARN] Expected Infinity-X metadata not found at $(basename "$AUTO_JSON")"
            fi
            ;;
    esac

    for IMG in boot.img dtb.img dtbo.img vendor_boot.img; do
        if [ -f "${TARGET_DIR}/$IMG" ]; then
            echo "[INFO] Found kernel partition image: ${IMG}"
        fi
    done
}

# ============================================================
# Main Execution Pipeline
# ============================================================
sync_repositories
compile_rom
process_artifacts

exec 1>&3 2>&4
sleep 1

echo "============================================================"
echo "[SUCCESS] Build pipeline completed successfully"
echo "============================================================"
echo "Device:       ${DEVICE_NAME}"
echo "ROM:          ${ROM_NAME} (${ANDROID_VERSION})"
echo "Duration:     ${DISPLAY_TIME}"
echo "Package:      ${ROM_ZIP}"
echo "Size:         ${ROM_SIZE_HUMAN}"
echo "SHA256:       ${ROM_SHA256}"
echo "MD5:          ${ROM_MD5}"
echo "Log:          ${LOG_FILE}"
echo "============================================================"
