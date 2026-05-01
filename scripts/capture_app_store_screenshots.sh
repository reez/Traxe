#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-Traxe.xcodeproj}"
SCHEME="${SCHEME:-Traxe}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro Max}"
UDID="${UDID:-}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.build/screenshots-derived-data}"
RAW_DIR="${RAW_DIR:-screenshots/raw/en-US/APP_IPHONE_67}"
FRAMED_DIR="${FRAMED_DIR:-screenshots/framed/en-US/APP_IPHONE_67}"
REVIEW_DIR="${REVIEW_DIR:-screenshots/review}"
FRAME_ENABLED="${FRAME_ENABLED:-0}"
FRAME_DEVICE="${FRAME_DEVICE:-iphone-17-pro}"
VALIDATE="${VALIDATE:-1}"
DEVICE_TYPE="${DEVICE_TYPE:-IPHONE_67}"
RENDER_TEST="${RENDER_TEST:-TraxeTests/AppStoreScreenshotRenderTests}"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

destination() {
  if [[ -n "$UDID" ]]; then
    printf 'platform=iOS Simulator,id=%s\n' "$UDID"
  else
    printf 'platform=iOS Simulator,name=%s\n' "$DEVICE_NAME"
  fi
}

frame_outputs() {
  if [[ "$FRAME_ENABLED" != "1" ]]; then
    return
  fi

  if ! command -v kou >/dev/null 2>&1; then
    echo "Skipping framing because Koubou is not installed. Install with: pip install koubou==0.13.0" >&2
    return
  fi

  mkdir -p "$FRAMED_DIR"
  rm -f "$FRAMED_DIR"/*.png

  for screenshot in "$RAW_DIR"/*.png; do
    [[ -f "$screenshot" ]] || continue
    local base_name
    base_name="$(basename "$screenshot" .png)"
    asc screenshots frame \
      --input "$screenshot" \
      --name "$base_name" \
      --device "$FRAME_DEVICE" \
      --output-dir "$FRAMED_DIR" \
      --output json >/dev/null
  done

  asc screenshots review-generate \
    --framed-dir "$FRAMED_DIR" \
    --output-dir "$REVIEW_DIR" \
    --output json >/dev/null
}

main() {
  require_command xcodebuild
  require_command asc

  local raw_dir_absolute
  if [[ "$RAW_DIR" = /* ]]; then
    raw_dir_absolute="$RAW_DIR"
  else
    raw_dir_absolute="$PWD/$RAW_DIR"
  fi

  mkdir -p "$raw_dir_absolute"
  rm -f "$raw_dir_absolute"/*.png

  local destination
  destination="$(destination)"

  echo "Rendering App Store screenshots via $RENDER_TEST"
  XCODE_RUNNING_FOR_PREVIEWS=1 \
    TRAXE_SCREENSHOT_OUTPUT_DIR="$raw_dir_absolute" \
    xcodebuild test \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination "$destination" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -only-testing:"$RENDER_TEST"

  local count
  count="$(find "$raw_dir_absolute" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
  if [[ "$count" != "7" ]]; then
    echo "Expected 7 screenshots, found $count in $RAW_DIR" >&2
    exit 1
  fi

  if [[ "$VALIDATE" == "1" ]]; then
    asc screenshots validate \
      --path "$raw_dir_absolute" \
      --device-type "$DEVICE_TYPE" \
      --output json \
      --pretty
  fi

  frame_outputs

  echo "Raw screenshots: $RAW_DIR"
  if [[ "$FRAME_ENABLED" == "1" ]]; then
    echo "Framed screenshots: $FRAMED_DIR"
    echo "Review output: $REVIEW_DIR"
  fi
}

main "$@"
