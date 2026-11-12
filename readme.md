# Lunaris OS Build Scripts

Automated build pipelines and patch utilities for Lunaris OS (Android 16.2) on Xiaomi Poco X5 5G / Redmi Note 12 5G (`stone`).

## Pipelines

### 1. Crave Cloud Build Pipeline (`build.sh`)
Automated cloud compilation script featuring dynamic repo synchronization, Clang r614150 toolchain setup, workspace auto-sanitization, Leica/MIUI camera integration, VINTF HAL auto-patching, integrity testing, and automated release uploads.

```bash
crave run --no-patch -- "curl -s https://raw.githubusercontent.com/frnAlt/Scripts/refs/heads/lunaris/build.sh | bash -s stone 1"
```

### 2. Local Server Build Pipeline (`build_stone.sh`)
Direct build pipeline optimized for local build servers:
- Automatic VINTF compatibility matrix checks (`vendor.xiaomi.hardware.misys` HAL 1.0-4.0)
- MIUI/Leica Camera 5.0 integration with check_elf_files safety
- Automated ROM integrity verification and OTA JSON generation
- Multi-threaded upload to Pixeldrain and Gofile
- Automated GitHub release publishing on [`frnAlt/Lunaris_stone`](https://github.com/frnAlt/Lunaris_stone)

```bash
bash build_stone.sh
```
