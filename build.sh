#!/bin/bash

# ============================================================
# Crave Custom ROM Build Pipeline - Lunaris OS (Android 16.2)
# Target: Xiaomi Poco X5 5G / Redmi Note 12 5G (stone)
# Maintainer: @Parvez52
# ============================================================

DEVICE=${1:-"stone"}
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
    echo "[ERROR] ROM:     ${ROM_NAME:-Lunaris OS}"
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
echo "[INFO] Configuring build environment for Lunaris OS..."
echo "============================================================"

DEVICE_NAME="Redmi Note 12 5G / Poco X5 5G (stone)"
ROM_NAME="Lunaris OS"
ANDROID_VERSION="16.2"
ROM_VERSION="3.12"
GH_REPO="frnAlt/Lunaris_stone"

REPO_INIT_URL="https://github.com/Lunaris-AOSP/android"
REPO_INIT_BRANCH="16.2"
LOCAL_MANIFEST_URL="${LOCAL_MANIFEST_URL:-https://github.com/frnAlt/local_manifests-1.git}"
LOCAL_MANIFEST_BRANCH="lunaris"
BUILD_TARGET="lineage_stone-bp2a-userdebug"
BUILD_COMMAND="m lunaris"

echo "[INFO] Selected Device:  ${DEVICE_NAME}"
echo "[INFO] Selected ROM:     ${ROM_NAME}"
echo "[INFO] Android Version:  ${ANDROID_VERSION}"
echo "[INFO] Manifest URL:     ${REPO_INIT_URL} (-b ${REPO_INIT_BRANCH})"
echo "[INFO] Local Manifests:  ${LOCAL_MANIFEST_URL} (-b ${LOCAL_MANIFEST_BRANCH})"
echo "[INFO] Build Target:     ${BUILD_TARGET}"
echo "[INFO] Build Command:    ${BUILD_COMMAND}"
echo "[INFO] Build Hostname:   ${BUILD_HOSTNAME}"

# ============================================================
# Repository Synchronization
# ============================================================
sync_repositories() {
    echo "============================================================"
    echo "[INFO] Initializing Lunaris AOSP repository: ${REPO_INIT_URL} (${REPO_INIT_BRANCH})"
    echo "============================================================"

    repo init -u "$REPO_INIT_URL" -b "$REPO_INIT_BRANCH" --git-lfs --depth=1

    rm -rf .repo/local_manifests/
    echo "[INFO] Fetching local manifests from branch: ${LOCAL_MANIFEST_BRANCH}"
    git clone --depth=1 -b "$LOCAL_MANIFEST_BRANCH" "$LOCAL_MANIFEST_URL" .repo/local_manifests

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

    # Setup Clang r614150 Toolchain for stone
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
}

# ============================================================
# ROM Compilation
# ============================================================
compile_rom() {
    export TZ="Asia/Kolkata"

    set +eE
    source build/envsetup.sh
    lunch "$BUILD_TARGET" || lunch "${BUILD_TARGET/-bp2a/}" || lunch "lineage_${DEVICE}-userdebug"
    set -eE

    echo "[INFO] Cleaning target build environment..."
    m installclean

    echo "============================================================"
    echo "[INFO] Starting compilation: ${ROM_NAME} (${BUILD_TARGET})"
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

# ============================================================
# Post-Build Artifact Processing
# ============================================================
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
