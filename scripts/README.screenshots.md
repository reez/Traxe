# App Store Screenshots

Capture the seven portrait App Store screenshots with:

```bash
./scripts/capture_app_store_screenshots.sh
```

Each run creates a new `Traxe-screenshots.*` directory outside the repository,
under `$TMPDIR` by default. The test harness writes a separate `raw/Traxe-*`
subdirectory for each test. The script discovers those directories, checks the
expected count, and validates only the portrait App Store set. Existing PNGs are
never deleted or overwritten. The printed run directory contains the images and
test result bundle; remove it when the artifacts are no longer needed.

Without `UDID`, the script creates and deletes its own temporary simulator using
`DEVICE_NAME` and the newest installed release iOS runtime supported by Xcode.
An explicit `UDID` must belong to your current task; its lifecycle stays with you.
No simulator runtime is installed automatically.

Useful overrides (all artifact directories must be absolute and outside the
repository, including paths through symlinks):

```bash
DEVICE_NAME="iPhone 17 Pro Max" ./scripts/capture_app_store_screenshots.sh
UDID="YOUR-TASK-SIMULATOR-UDID" ./scripts/capture_app_store_screenshots.sh
RAW_DIR="$TMPDIR" ./scripts/capture_app_store_screenshots.sh
VALIDATE=0 ./scripts/capture_app_store_screenshots.sh
FRAME_ENABLED=1 ./scripts/capture_app_store_screenshots.sh
```

`RAW_DIR`, `FRAMED_DIR`, and `REVIEW_DIR` are parent directories: each run creates
new children. `DERIVED_DATA_PATH` can point to an external reusable build cache;
otherwise the script creates its own build directory and removes it on exit.
`SOURCE_PACKAGES_DIR` optionally reuses an external resolved Swift package cache.
Python 3 and Xcode are required; `asc` is required for validation or framing.

For the thirteen landscape, resizing, and onboarding captures, run:

```bash
RENDER_TEST=TraxeTests/AppStoreScreenshotRenderTests/testRenderLandscapeAndLiveResizeScreenshots \
  VALIDATE=0 ./scripts/capture_app_store_screenshots.sh
```

Set `RENDER_TEST=TraxeTests/AppStoreScreenshotRenderTests` to capture both sets
(twenty PNGs total). The mixed layout sizes are not submitted to App Store size
validation or framing. Framing applies only to the seven portrait images and
requires Koubou to already be installed.

Test script isolation and output discovery without launching Xcode:

```bash
python3 scripts/test_capture_app_store_screenshots.py
```

To download current App Store screenshots for comparison, choose an external
destination:

```bash
asc --profile "Personal CLI" screenshots download \
  --version-localization "4a5361ee-6d15-4826-942c-61aae923d843" \
  --output-dir "$TMPDIR/traxe-current-app-store" \
  --overwrite
```
