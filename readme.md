# Crave Build Scripts

Automated build pipeline for custom Android ROM compilation on Crave environments.

## Build Trigger

To initiate a build on your Crave workspace:

### Xiaomi Poco X5 / Redmi Note 12 5G (stone)

#### Lunaris OS (Android 16.2)
```bash
crave run --no-patch -- "curl -s https://raw.githubusercontent.com/frnAlt/Scripts/refs/heads/lunaris/build.sh | bash -s stone 1"
```
