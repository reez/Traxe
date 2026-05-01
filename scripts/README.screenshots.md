# App Store Screenshots

Capture deterministic iPhone App Store screenshots with:

```bash
./scripts/capture_app_store_screenshots.sh
```

The script runs the `TraxeTests/AppStoreScreenshotRenderTests` test case, which renders
SwiftUI screenshot fixtures from the test target and writes PNGs to:

```text
screenshots/raw/en-US/APP_IPHONE_67
```

This keeps screenshot-only fixture and rendering logic outside the shipping `Traxe.app`
entry point and view/view-model implementation.

Useful overrides:

```bash
DEVICE_NAME="iPhone 17 Pro Max" ./scripts/capture_app_store_screenshots.sh
UDID="D2F4632C-D693-4976-8E5D-7A660B668848" ./scripts/capture_app_store_screenshots.sh
RAW_DIR="screenshots/raw/en-US/APP_IPHONE_67" ./scripts/capture_app_store_screenshots.sh
VALIDATE=0 ./scripts/capture_app_store_screenshots.sh
FRAME_ENABLED=1 ./scripts/capture_app_store_screenshots.sh
```

Framing uses `asc screenshots frame` and requires Koubou:

```bash
pip install koubou==0.13.0
```

Current live App Store screenshots can be downloaded for comparison with:

```bash
asc --profile "Personal CLI" screenshots download \
  --version-localization "4a5361ee-6d15-4826-942c-61aae923d843" \
  --output-dir "screenshots/current-app-store/en-US" \
  --overwrite
```
