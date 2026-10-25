# Crave Scripts (Axion OS)

> **Automated pipeline for building Android ROMs on Crave and uploading the output to Gofile.**

## 🛠️ About

This repository contains a single, focused `build.sh` script used to automate custom ROM compilation on Crave environments. It handles the complete build process, generates OTA metadata, and uploads the final artifacts to Gofile.

## 🚀 Triggering a Build

To start a build on your Crave environment, simply copy and paste the command for your desired ROM into your terminal:

### 📱 Xiaomi Poco X5 / Redmi Note 12 5G (`stone`)

**Axion OS (Default)**
```bash
crave run --no-patch -- "curl -s https://raw.githubusercontent.com/frnAlt/Scripts/refs/heads/axion-16/build.sh | bash -s stone 1"
```

