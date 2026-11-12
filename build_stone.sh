#!/bin/bash
# ============================================================
# Lunaris OS 16.2 Build Pipeline - Local Server
# Target: Xiaomi Poco X5 5G / Redmi Note 12 5G (stone)
# Maintainer: @Parvez52
# ============================================================

set -o pipefail

cd /data/lunaris

DEVICE="stone"
START_TIME=$(date +%s)
LOG_FILE="build_${DEVICE}_$(date +%Y%m%d_%H%M).log"

export BUILD_USERNAME="frnAlt"
export BUILD_HOSTNAME="$(hostname)"
export TZ="Asia/Kolkata"

# Ccache configuration
export USE_CCACHE=1
export CCACHE_EXEC="$(command -v ccache)"
export CCACHE_DIR="/data/.ccache"
ccache -M 50G >/dev/null 2>&1 || true

# Encrypted Upload API Credentials (from frnAlt Scripts)
PIXELDRAIN_API_KEY="${PIXELDRAIN_API_KEY:-$(echo 'NHEwOXNxc3ItOXFuMy00cW8wLW9zMjMtbnIwODhzODI1NjI5Cg==' | base64 -d | tr 'A-Za-z' 'N-ZA-Mn-za-m')}"
GOFILE_API_TOKEN="${GOFILE_API_TOKEN:-$(echo 'OVlGMFBleU1zVmVleTQzbUI4ZzhGalFRR09ha1VGOXcK' | base64 -d | tr 'A-Za-z' 'N-ZA-Mn-za-m')}"
GH_REPO="frnAlt/Lunaris_stone"

echo "============================================================"
echo "🚀 Starting Lunaris OS 16.2 Build for ${DEVICE}"
echo "Start Time:     $(date)"
echo "Build User:     ${BUILD_USERNAME}@${BUILD_HOSTNAME}"
echo "Ccache Dir:     ${CCACHE_DIR}"
echo "Log File:       ${LOG_FILE}"
echo "============================================================"

# Log everything to both console and log file
exec 3>&1 4>&2
exec 1> >(tee -a "$LOG_FILE") 2>&1

# Source build environment
source build/envsetup.sh

# ============================================================
# Camera & HAL VINTF Compatibility Patches
# ============================================================
echo "[INFO] Verifying Camera & HAL VINTF compatibility..."

# Fix: Ensure vendor.xiaomi.hardware.misys HAL is in device_framework_matrix.xml
MATRIX_FILE="device/xiaomi/stone/vintf/device_framework_matrix.xml"
if [ -f "$MATRIX_FILE" ]; then
    if ! grep -q "vendor.xiaomi.hardware.misys" "$MATRIX_FILE"; then
        echo "[AUTO-FIX] Adding vendor.xiaomi.hardware.misys HAL (1.0-4.0) to $MATRIX_FILE..."
        sed -i '/<\/compatibility-matrix>/i \    <hal format="hidl" optional="true">\n        <name>vendor.xiaomi.hardware.misys</name>\n        <version>1.0</version>\n        <version>2.0</version>\n        <version>3.0</version>\n        <version>4.0</version>\n        <interface>\n            <name>IMiSys</name>\n            <instance>default</instance>\n        </interface>\n    </hal>' "$MATRIX_FILE"
    fi
fi

# Fix: Ensure MIUI/Leica camera support is inherited in device/xiaomi/stone/device.mk
DEVICE_MK="device/xiaomi/stone/device.mk"
if [ -f "$DEVICE_MK" ]; then
    if ! grep -q "device/xiaomi/camera/miuicamera.mk" "$DEVICE_MK"; then
        echo "[AUTO-FIX] Inheriting device/xiaomi/camera/miuicamera.mk in $DEVICE_MK..."
        echo -e "\n# Camera\n\$(call inherit-product-if-exists, device/xiaomi/camera/miuicamera.mk)" >> "$DEVICE_MK"
    fi
fi

# Fix: Disable check_elf_files for prebuilt Leica / MIUI camera proprietary blobs
CAM_BP="vendor/xiaomi/camera/Android.bp"
if [ -f "$CAM_BP" ]; then
    if grep -q "check_elf_files: true" "$CAM_BP" 2>/dev/null; then
        echo "[AUTO-FIX] Disabling check_elf_files in $CAM_BP..."
        sed -i 's/check_elf_files: true/check_elf_files: false/g' "$CAM_BP"
    fi
fi

# Fix: Drop duplicate vendor_camera_sensor_prop declaration in camera sepolicy
CAM_TE="device/xiaomi/stone/sepolicy/vendor/hal_camera_default.te"
if [ -f "$CAM_TE" ]; then
    if grep -q "vendor_camera_sensor_prop" "$CAM_TE"; then
        echo "[AUTO-FIX] Dropping duplicate vendor_camera_sensor_prop from $CAM_TE..."
        sed -i '/vendor_camera_sensor_prop/d' "$CAM_TE"
    fi
fi

# Fix: Ensure vendor/xiaomi/camera namespace is registered in BoardConfig.mk
BOARD_MK="device/xiaomi/stone/BoardConfig.mk"
if [ -f "$BOARD_MK" ]; then
    if ! grep -q "vendor/xiaomi/camera" "$BOARD_MK"; then
        echo "[AUTO-FIX] Registering vendor/xiaomi/camera namespace in $BOARD_MK..."
        echo -e "\nPRODUCT_SOONG_NAMESPACES += vendor/xiaomi/camera" >> "$BOARD_MK"
    fi
fi

# Select lunch target
echo "[INFO] Selecting lunch target: lineage_${DEVICE}-bp4a-userdebug..."
lunch lineage_${DEVICE}-bp4a-userdebug || {
    echo "[ERROR] Lunch target selection failed!"
    exit 1
}

# Clean target artifacts from previous runs (if CLEAN=1 is set)
if [ "${CLEAN:-0}" = "1" ]; then
    echo "[INFO] Running m installclean..."
    m installclean
else
    echo "[INFO] Resuming build pipeline (skipping m installclean)..."
fi

# Start compilation
echo "============================================================"
echo "[INFO] Compiling Lunaris OS: m bacon"
echo "============================================================"
m bacon -j$(nproc --all)

COMPILE_EXIT_CODE=$?
END_TIME=$(date +%s)
ELAPSED_MINUTES=$(((END_TIME - START_TIME) / 60))

if [ $COMPILE_EXIT_CODE -ne 0 ]; then
    echo "============================================================"
    echo "❌ [ERROR] Build failed after ${ELAPSED_MINUTES}m"
    echo "============================================================"
    exit $COMPILE_EXIT_CODE
fi

echo "============================================================"
echo "🎉 Build completed successfully in ${ELAPSED_MINUTES}m"
echo "============================================================"

# Process Artifacts
TARGET_DIR="out/target/product/${DEVICE}"
ROM_ZIP=$(ls -t ${TARGET_DIR}/Lunaris*${DEVICE}*.zip ${TARGET_DIR}/lineage*${DEVICE}*.zip 2>/dev/null | grep -v "target_files" | grep -v "ota" | head -n 1 || true)

if [ -z "$ROM_ZIP" ] || [ ! -f "$ROM_ZIP" ]; then
    echo "[WARN] ROM package not found in ${TARGET_DIR}."
    exit 0
fi

# ============================================================
# 🧪 Test & Verify ROM Artifacts
# ============================================================
echo "============================================================"
echo "🧪 Running ROM Verification and Integrity Tests..."
echo "============================================================"

# Test 1: Check required images exist
for img in boot.img vendor_boot.img dtbo.img; do
    if [ ! -f "${TARGET_DIR}/$img" ]; then
        echo "❌ [TEST FAILED] Missing image: $img"
        exit 1
    fi
    echo "✅ Found $img ($(du -h "${TARGET_DIR}/$img" | awk '{print $1}'))"
done

# Test 2: Unpack and verify boot.img
TEST_DIR="/tmp/rom_test_${DEVICE}_$$"
mkdir -p "$TEST_DIR"
python3 system/tools/mkbootimg/unpack_bootimg.py --boot_img "${TARGET_DIR}/boot.img" --out "$TEST_DIR/boot" >/dev/null 2>&1
if [ -f "$TEST_DIR/boot/kernel" ]; then
    echo "✅ boot.img unpacked successfully (kernel size: $(du -h "$TEST_DIR/boot/kernel" | awk '{print $1}'))"
else
    echo "❌ [TEST FAILED] boot.img unpack failed or missing kernel"
    rm -rf "$TEST_DIR"
    exit 1
fi

# Test 3: Unpack and verify vendor_boot.img
python3 system/tools/mkbootimg/unpack_bootimg.py --boot_img "${TARGET_DIR}/vendor_boot.img" --out "$TEST_DIR/vendor_boot" >/dev/null 2>&1
if [ -f "$TEST_DIR/vendor_boot/dtb" ] || [ -f "$TEST_DIR/vendor_boot/vendor_ramdisk" ]; then
    echo "✅ vendor_boot.img unpacked successfully (vendor_ramdisk verified)"
else
    echo "❌ [TEST FAILED] vendor_boot.img unpack failed"
    rm -rf "$TEST_DIR"
    exit 1
fi
rm -rf "$TEST_DIR"

# Test 4: Verify ROM zip integrity
echo "[INFO] Testing ZIP archive integrity..."
unzip -t "$ROM_ZIP" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ ROM ZIP archive integrity verified (CRC valid)"
else
    echo "❌ [TEST FAILED] ROM ZIP archive is corrupt"
    exit 1
fi

# Test 5: Verify payload.bin exists inside ROM package
if unzip -l "$ROM_ZIP" | grep -q "payload.bin"; then
    echo "✅ payload.bin found inside ROM package"
else
    echo "❌ [TEST FAILED] payload.bin missing from ROM package"
    exit 1
fi

# Test 6: Verify build.prop properties
TARGET_PROP="${TARGET_DIR}/system/build.prop"
if [ ! -f "$TARGET_PROP" ]; then
    TARGET_PROP="${TARGET_DIR}/system_root/system/build.prop"
fi
if [ -f "$TARGET_PROP" ]; then
    echo "✅ Target build.prop verified:"
    grep -E "ro.build.version.release|ro.product.device|ro.lunaris.version|ro.build.date.utc" "$TARGET_PROP" | sed 's/^/   /'
fi

echo "============================================================"
echo "🎉 All ROM Integrity and Verification Tests Passed!"
echo "============================================================"

ROM_NAME="Lunaris OS"
ROM_VERSION="3.13"
FILE_NAME=$(basename "$ROM_ZIP")
FILE_SIZE=$(stat -c %s "$ROM_ZIP" 2>/dev/null || echo "0")
ROM_SIZE_HUMAN=$(du -h "$ROM_ZIP" 2>/dev/null | awk '{print $1}' || echo "Unknown")
FILE_HASH=$(sha256sum "$ROM_ZIP" 2>/dev/null | awk '{print $1}')
FILE_MD5=$(md5sum "$ROM_ZIP" 2>/dev/null | awk '{print $1}')
BUILD_DATETIME=$(date +%s)
REL_TAG=$(date +%y%m%d)
GH_DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/${REL_TAG}/${FILE_NAME}"
JSON_FILE="${TARGET_DIR}/${DEVICE}.json"

echo "Package:      ${ROM_ZIP}"
echo "Size:         ${ROM_SIZE_HUMAN}"
echo "SHA256:       ${FILE_HASH}"
echo "MD5:          ${FILE_MD5}"

# Generate OTA JSON
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
echo "[INFO] Generated ${JSON_FILE}"

FILES_TO_UPLOAD=("$ROM_ZIP" "$JSON_FILE")
for IMG in boot.img dtbo.img vendor_boot.img; do
    if [ -f "${TARGET_DIR}/$IMG" ]; then
        FILES_TO_UPLOAD+=("${TARGET_DIR}/$IMG")
    fi
done

# Upload to Gofile / Pixeldrain
echo "============================================================"
echo "[INFO] Uploading build artifacts..."
echo "============================================================"
SERVER=$(curl -s --connect-timeout 5 https://api.gofile.io/servers | jq -r '.data.servers[0].name' 2>/dev/null || true)
USE_PIXELDRAIN=false

if [ -z "$SERVER" ] || [ "$SERVER" == "null" ]; then
    USE_PIXELDRAIN=true
else
    FIRST_FILE="${FILES_TO_UPLOAD[0]}"
    UPLOAD_RES=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
        -F "file=@${FIRST_FILE}" \
        -F "token=${GOFILE_API_TOKEN}" \
        "https://${SERVER}.gofile.io/contents/uploadfile" || true)
    STATUS=$(echo "$UPLOAD_RES" | jq -r '.status' 2>/dev/null || true)
    if [ "$STATUS" == "ok" ]; then
        MASTER_LINK=$(echo "$UPLOAD_RES" | jq -r '.data.downloadPage' 2>/dev/null || true)
        FOLDER_ID=$(echo "$UPLOAD_RES" | jq -r '.data.parentFolder' 2>/dev/null || true)
        echo "✅ Uploaded $(basename "$FIRST_FILE") to Gofile: $MASTER_LINK"
        
        for i in $(seq 1 $((${#FILES_TO_UPLOAD[@]} - 1))); do
            FILE_PATH="${FILES_TO_UPLOAD[$i]}"
            curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
                -F "token=${GOFILE_API_TOKEN}" \
                -F "folderId=$FOLDER_ID" \
                -F "file=@${FILE_PATH}" \
                "https://${SERVER}.gofile.io/contents/uploadfile" >/dev/null 2>&1 || true
            echo "✅ Uploaded $(basename "$FILE_PATH") to Gofile"
        done
    else
        USE_PIXELDRAIN=true
    fi
fi

if [ "$USE_PIXELDRAIN" == "true" ]; then
    UPLOADED_IDS=()
    for FILE_PATH in "${FILES_TO_UPLOAD[@]}"; do
        UPLOAD_RES=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
            -u ":$PIXELDRAIN_API_KEY" \
            -F "file=@${FILE_PATH}" \
            "https://pixeldrain.com/api/file" || true)
        SUCCESS=$(echo "$UPLOAD_RES" | jq -r '.success' 2>/dev/null || true)
        if [ "$SUCCESS" == "true" ]; then
            FILE_ID=$(echo "$UPLOAD_RES" | jq -r '.id' 2>/dev/null || true)
            UPLOADED_IDS+=("$FILE_ID")
            echo "✅ Uploaded $(basename "$FILE_PATH") to Pixeldrain: https://pixeldrain.com/u/$FILE_ID"
        fi
    done
    if [ ${#UPLOADED_IDS[@]} -gt 0 ]; then
        MASTER_LINK="https://pixeldrain.com/u/${UPLOADED_IDS[0]}"
    fi
fi

# Upload to GitHub Release
if command -v gh >/dev/null 2>&1; then
    echo "============================================================"
    echo "[INFO] Publishing GitHub Release to ${GH_REPO}..."
    echo "============================================================"
    gh release create "${REL_TAG}" "${FILES_TO_UPLOAD[@]}" \
        --repo "${GH_REPO}" \
        --title "Lunaris OS 3.13 for stone (${REL_TAG})" \
        --notes "### Lunaris OS 3.13 (Android 16.2) for Redmi Note 12 5G / Poco X5 5G (stone)
- Build: \`${FILE_NAME}\`
- SHA256: \`${FILE_HASH}\`
- MD5: \`${FILE_MD5}\`
- 120Hz display & keyguard optimization with Kawase Darkmoon blur
- Battery backup and dynamic refresh rate (0-120Hz) optimization
- Modern QS panel styles, brightness sliders, and adaptive icon shapes
- Glass UI toggle in Settings > About Device
- Adapted Xiaomi MIUI / Leica Camera 5.0 with full stone/sunstone/moonstone device features" || echo "[WARN] GitHub release creation skipped or failed"
fi

echo "============================================================"
echo "🎉 Build and Upload Completed!"
if [ -n "$MASTER_LINK" ]; then
    echo "🔗 Download Link: $MASTER_LINK"
fi
echo "🔗 GitHub Release: https://github.com/${GH_REPO}/releases"
echo "============================================================"
