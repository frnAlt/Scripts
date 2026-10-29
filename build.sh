#!/bin/bash

# ============================================================
# Crave Custom ROM Build Pipeline - Lunaris OS (Android 16.2)
# Target: Xiaomi Poco X5 5G / Redmi Note 12 5G (stone)
# Maintainer: @Parvez52
# ============================================================

# Ensure working directory is android root if executed inside Crave
if [ -d "/tmp/src/android" ] && [ "$PWD" != "/tmp/src/android" ]; then
    cd /tmp/src/android
fi

DEVICE=${1:-"stone"}
START_TIME=$(date +%s)
LOG_FILE="build_${DEVICE}_$(date +%Y%m%d_%H%M).log"

rm -f "/tmp/build_failed.lock"
rm -f "./out/siso_failed_commands.sh" "out/siso_failed_commands.sh" 2>/dev/null || true

export BUILD_USERNAME="${BUILD_USERNAME:-frnAlt}"
if [ -d "/opt/crave" ]; then
    export BUILD_HOSTNAME="crave"
else
    export BUILD_HOSTNAME="$(hostname)"
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

# Ensure basic utilities are installed early
install_prerequisites() {
    if command -v apt-get &>/dev/null; then
        local NEEDED_PKGS=""
        for pkg in jq unzip curl wget ccache; do
            if ! command -v "$pkg" &>/dev/null; then
                NEEDED_PKGS="$NEEDED_PKGS $pkg"
            fi
        done
        if [ -n "$NEEDED_PKGS" ]; then
            echo "[INFO] Installing prerequisite packages: $NEEDED_PKGS"
            if [ "$(id -u)" -eq 0 ]; then
                apt-get update -qq >/dev/null 2>&1 && apt-get install -y $NEEDED_PKGS >/dev/null 2>&1 || true
            elif command -v sudo &>/dev/null; then
                sudo apt-get update -qq >/dev/null 2>&1 && sudo apt-get install -y $NEEDED_PKGS >/dev/null 2>&1 || true
            fi
        fi
    fi
}

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
BUILD_TARGET="lineage_${DEVICE}-bp4a-userdebug"
BUILD_COMMAND="m bacon"

echo "[INFO] Selected Device:  ${DEVICE_NAME}"
echo "[INFO] Selected ROM:     ${ROM_NAME}"
echo "[INFO] Android Version:  ${ANDROID_VERSION}"
echo "[INFO] Manifest URL:     ${REPO_INIT_URL} (-b ${REPO_INIT_BRANCH})"
echo "[INFO] Local Manifests:  ${LOCAL_MANIFEST_URL} (-b ${LOCAL_MANIFEST_BRANCH})"
echo "[INFO] Build Target:     ${BUILD_TARGET}"
echo "[INFO] Build Command:    ${BUILD_COMMAND}"
echo "[INFO] Build Hostname:   ${BUILD_HOSTNAME}"

# ============================================================
# Automated In-Flight Patching & Workspace Sanitization
# ============================================================
auto_patch_manifests() {
    echo "[INFO] Checking and auto-patching local manifests..."
    if [ -d ".repo/local_manifests" ]; then
        for xml_file in .repo/local_manifests/*.xml; do
            [ -f "$xml_file" ] || continue

            # Fix 1: Auto-remove duplicate vendor/lunaris-priv/keys if present
            # Prevents duplicate Soong module collision (com.android.*.certificate.override)
            if grep -q "vendor/lunaris-priv/keys" "$xml_file"; then
                echo "[AUTO-FIX] Removing conflicting 'vendor/lunaris-priv/keys' entry from $xml_file"
                sed -i '/vendor\/lunaris-priv\/keys/d' "$xml_file"
            fi

            # Fix 2: Auto-update renamed ViPER4AndroidFX repo to eliminate HTTP 301
            if grep -q "packages_apps_ViPER4AndroidFX" "$xml_file"; then
                echo "[AUTO-FIX] Updating ViPER4AndroidFX repo target in $xml_file"
                sed -i 's/name="packages_apps_ViPER4AndroidFX"/name="vendor_viper4"/g' "$xml_file"
            fi
        done
    fi
}

auto_clean_workspace() {
    echo "[INFO] Sanitizing Crave workspace for clean compilation..."

    # Fix 3: Prune stale vendor/lunaris-priv directory from persistent Crave cache
    if [ -d "vendor/lunaris-priv" ]; then
        echo "[AUTO-FIX] Removing stale conflicting directory: vendor/lunaris-priv"
        rm -rf "vendor/lunaris-priv"
    fi
    rm -rf .repo/projects/vendor/lunaris-priv* 2>/dev/null || true

    # Fix 4: Clear stale git lock files from aborted runs
    find .repo/ -name "*.lock" -type f -delete 2>/dev/null || true

    # Fix 5: Invalidate previous corrupted Soong ninja files
    rm -f out/soong/build.*.ninja out/.module_paths/Android.bp.list 2>/dev/null || true

    # Fix 6: Remove stale ViPER4AndroidFX project git dir to avoid hook discrepancy
    if [ -d ".repo/projects/packages/apps/ViPER4AndroidFX.git" ]; then
        rm -rf ".repo/projects/packages/apps/ViPER4AndroidFX.git"
    fi

    # Fix 7: Auto-sanitize device.mk to remove non-existent DolbyAtmos
    if [ -f "device/xiaomi/stone/device.mk" ]; then
        if grep -q "DolbyAtmos" "device/xiaomi/stone/device.mk"; then
            echo "[AUTO-FIX] Sanitizing device/xiaomi/stone/device.mk (removing non-existent DolbyAtmos)..."
            sed -i "/# Dolby/,/DolbyAtmos/c\# Dolby\n\$(call inherit-product-if-exists, hardware/dolby/dolby.mk)" "device/xiaomi/stone/device.mk"
        fi
    fi
}

# ============================================================
# Repository Synchronization
# ============================================================
sync_repositories() {
    install_prerequisites

    echo "============================================================"
    echo "[INFO] Initializing Lunaris AOSP repository: ${REPO_INIT_URL} (${REPO_INIT_BRANCH})"
    echo "============================================================"

    # Reset any unstaged working tree changes to prevent rebase errors
    git reset --hard HEAD 2>/dev/null || true
    git clean -fd 2>/dev/null || true
    if [ -d ".repo/manifests" ]; then
        git -C .repo/manifests reset --hard HEAD 2>/dev/null || true
        git -C .repo/manifests clean -fd 2>/dev/null || true
    fi

    # Prune stale ViPER repo project git before sync to avoid hook conflict
    if [ -d ".repo/projects/packages/apps/ViPER4AndroidFX.git" ]; then
        rm -rf ".repo/projects/packages/apps/ViPER4AndroidFX.git"
    fi

    repo init -u "$REPO_INIT_URL" -b "$REPO_INIT_BRANCH" --git-lfs --depth=1

    rm -rf .repo/local_manifests/
    echo "[INFO] Fetching local manifests from branch: ${LOCAL_MANIFEST_BRANCH}"
    git clone --depth=1 -b "$LOCAL_MANIFEST_BRANCH" "$LOCAL_MANIFEST_URL" .repo/local_manifests

    # Apply in-flight manifest patches BEFORE sync
    auto_patch_manifests

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

    # Clean up workspace after sync to remove leftover directories
    auto_clean_workspace

    # Setup Clang r614150 Toolchain for stone
    CLANG_TARGET_DIR="prebuilts/clang/host/linux-x86/clang-r614150"
    if [ ! -d "$CLANG_TARGET_DIR" ] || [ ! -x "$CLANG_TARGET_DIR/bin/clang" ]; then
        echo "[INFO] Setting up Clang r614150 toolchain..."
        rm -rf "$CLANG_TARGET_DIR"
        mkdir -p "$CLANG_TARGET_DIR"

        CLANG_URL="https://github.com/bachnxuan/aosp_clang_mirror/releases/download/clang-r614150-16165221/clang-r614150.tar.gz"
        echo "[INFO] Downloading Clang r614150..."
        if ! curl -fSL "$CLANG_URL" -o /tmp/clang-download.tar.gz; then
            echo "[WARN] Curl download failed, falling back to wget..."
            wget -c "$CLANG_URL" -O /tmp/clang-download.tar.gz
        fi

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
            CLANG_VER=$("$CLANG_TARGET_DIR/bin/clang" --version 2>/dev/null | head -n 1 || echo "r614150")
            echo "[INFO] Clang configured: ${CLANG_VER}"
        else
            echo "[ERROR] Clang binary missing at ${CLANG_TARGET_DIR}/bin/clang after extraction."
            handle_error $LINENO
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

    # Maintain consistent build user and hostname across subshells
    export BUILD_USERNAME="${BUILD_USERNAME:-frnAlt}"
    if [ -d "/opt/crave" ]; then
        export BUILD_HOSTNAME="crave"
    else
        export BUILD_HOSTNAME="$(hostname)"
    fi

    # Configure Ccache if installed
    if command -v ccache &>/dev/null; then
        export USE_CCACHE=1
        export CCACHE_EXEC="$(command -v ccache)"
        export CCACHE_DIR="${CCACHE_DIR:-/tmp/src/android/.ccache}"
        ccache -M 50G >/dev/null 2>&1 || true
        echo "[INFO] Ccache enabled (${CCACHE_DIR})"
    fi

    set +eE
    source build/envsetup.sh

    export BUILD_USERNAME="${BUILD_USERNAME:-frnAlt}"
    export BUILD_HOSTNAME="${BUILD_HOSTNAME}"

    echo "[INFO] Selecting lunch target..."
    lunch "$BUILD_TARGET" || lunch "lineage_${DEVICE}-userdebug" || {
        echo "[ERROR] Lunch target selection failed."
        handle_error $LINENO
    }
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

    TARGET_DIR="out/target/product/${DEVICE}"
    ROM_ZIP=$(ls -t ${TARGET_DIR}/Lunaris*${DEVICE}*.zip ${TARGET_DIR}/lineage*${DEVICE}*.zip ${TARGET_DIR}/*${DEVICE}*.zip 2>/dev/null | grep -v "target_files" | grep -v "ota" | head -n 1 || true)

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
    if command -v unzip &>/dev/null; then
        unzip -p "$ROM_ZIP" META-INF/com/android/metadata > "$EXTRACT_DIR/metadata.txt" 2>/dev/null || true
    fi
    
    if [ -s "$EXTRACT_DIR/metadata.txt" ] && grep -q "post-timestamp=" "$EXTRACT_DIR/metadata.txt" 2>/dev/null; then
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

    if command -v jq &>/dev/null; then
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
    else
        cat <<JSON_EOF > "$JSON_FILE"
{
  "response": [
    {
      "maintainer": "@Parvez52",
      "currently_maintained": true,
      "oem": "Xiaomi",
      "device": "${DEVICE}",
      "filename": "${FILE_NAME}",
      "download": "${GH_DOWNLOAD_URL}",
      "timestamp": ${BUILD_DATETIME},
      "md5": "${FILE_MD5}",
      "sha256": "${FILE_HASH}",
      "size": ${FILE_SIZE},
      "version": "${ROM_VERSION}",
      "buildtype": "UNOFFICIAL"
    }
  ]
}
JSON_EOF
    fi

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
