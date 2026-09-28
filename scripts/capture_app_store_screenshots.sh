#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_PATH="${PROJECT_PATH:-$REPOSITORY_ROOT/Traxe.xcodeproj}"
SCHEME="${SCHEME:-Traxe}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro Max}"
UDID="${UDID:-}"
RAW_DIR="${RAW_DIR:-${TMPDIR:-/tmp}}"
FRAME_ENABLED="${FRAME_ENABLED:-0}"
FRAME_DEVICE="${FRAME_DEVICE:-iphone-17-pro}"
VALIDATE="${VALIDATE:-1}"
DEVICE_TYPE="${DEVICE_TYPE:-IPHONE_67}"
RENDER_TEST="${RENDER_TEST:-TraxeTests/AppStoreScreenshotRenderTests/testRenderAppStoreScreenshots}"
owned_simulator=""
owned_derived_data=""

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

# Resolve symlinks before accepting any artifact destination, including nonexistent children.
external_path() {
  python3 - "$1" "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1]).expanduser()
if not path.is_absolute():
    raise SystemExit("Artifact paths must be absolute and outside the repository.")
path = path.resolve()
repo = Path(sys.argv[2]).resolve()
if path == repo or repo in path.parents:
    raise SystemExit("Artifact output cannot be inside the repository: " + str(path))
print(path)
PY
}

cleanup() {
  if [[ -n "$owned_simulator" ]]; then
    if ! xcrun simctl delete "$owned_simulator"; then
      echo "Could not delete temporary simulator $owned_simulator" >&2
    fi
  fi
  if [[ -n "$owned_derived_data" ]]; then
    rm -rf "$owned_derived_data"
  fi
}
trap cleanup EXIT

create_simulator_if_needed() {
  [[ -z "$UDID" ]] || return 0
  local configuration device_type runtime xcode_major
  xcode_major="$(xcodebuild -version | awk '/^Xcode / { split($2, parts, "."); print parts[1] }')"
  configuration="$(xcrun simctl list -j | python3 -c '
import json, re, sys
state = json.load(sys.stdin)
device = next((d for d in state["devicetypes"] if d["name"] == sys.argv[1]), None)
runtimes = [r for r in state["runtimes"] if r.get("isAvailable")
            and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
            and int(r["version"].split(".")[0]) <= int(sys.argv[2])
            and re.fullmatch(r"\d+[A-Z]\d{1,3}", r["buildversion"])]
if not device or not runtimes:
    raise SystemExit("No matching device type and stable iOS runtime; supply a task-owned UDID.")
runtime = max(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))
print(device["identifier"], runtime["identifier"])
' "$DEVICE_NAME" "$xcode_major")"
  read -r device_type runtime <<< "$configuration"
  UDID="$(xcrun simctl create 'Codex Temp Traxe Screenshots' "$device_type" "$runtime")"
  owned_simulator="$UDID"
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b
}

frame_outputs() {
  local portrait_directory="$1" screenshot base_name
  [[ "$FRAME_ENABLED" == "1" ]] || return 0
  mkdir -p "$framed_directory" "$review_directory"
  for screenshot in "$portrait_directory"/*.png; do
    base_name="$(basename "$screenshot" .png)"
    asc screenshots frame --input "$screenshot" --name "$base_name" \
      --device "$FRAME_DEVICE" --output-dir "$framed_directory" --output json >/dev/null
  done
  asc screenshots review-generate --framed-dir "$framed_directory" \
    --output-dir "$review_directory" --output json >/dev/null
}

main() {
  require_command python3
  require_command xcodebuild
  if [[ "$VALIDATE" == "1" || "$FRAME_ENABLED" == "1" ]]; then
    require_command asc
  fi
  if [[ "$FRAME_ENABLED" == "1" ]]; then
    require_command kou
  fi

  local expected_count includes_portrait
  case "$RENDER_TEST" in
    TraxeTests/AppStoreScreenshotRenderTests/testRenderAppStoreScreenshots)
      expected_count=7; includes_portrait=1 ;;
    TraxeTests/AppStoreScreenshotRenderTests/testRenderLandscapeAndLiveResizeScreenshots)
      expected_count=13; includes_portrait=0 ;;
    TraxeTests/AppStoreScreenshotRenderTests)
      expected_count=20; includes_portrait=1 ;;
    *) echo "Unsupported screenshot test: $RENDER_TEST" >&2; exit 1 ;;
  esac
  if [[ "$FRAME_ENABLED" == "1" && "$includes_portrait" == "0" ]]; then
    echo 'Framing requires the portrait App Store set.' >&2
    exit 1
  fi

  # RAW_DIR is a parent, never a directory to clear or overwrite.
  local raw_parent derived_data framed_parent review_parent source_packages
  raw_parent="$(external_path "$RAW_DIR")"
  if [[ -n "${DERIVED_DATA_PATH:-}" ]]; then
    derived_data="$(external_path "$DERIVED_DATA_PATH")"
  fi
  if [[ -n "${SOURCE_PACKAGES_DIR:-}" ]]; then
    source_packages="$(external_path "$SOURCE_PACKAGES_DIR")"
  fi
  if [[ -n "${FRAMED_DIR:-}" ]]; then
    framed_parent="$(external_path "$FRAMED_DIR")"
  fi
  if [[ -n "${REVIEW_DIR:-}" ]]; then
    review_parent="$(external_path "$REVIEW_DIR")"
  fi
  mkdir -p "$raw_parent"
  local run_directory raw_directory
  run_directory="$(mktemp -d "$raw_parent/Traxe-screenshots.XXXXXXXX")"
  raw_directory="$run_directory/raw"
  mkdir -p "$raw_directory"
  if [[ -z "${DERIVED_DATA_PATH:-}" ]]; then
    derived_data="$run_directory/DerivedData"
    owned_derived_data="$derived_data"
  fi
  framed_directory="$run_directory/framed"
  review_directory="$run_directory/review"
  if [[ -n "${FRAMED_DIR:-}" ]]; then
    mkdir -p "$framed_parent"
    framed_directory="$(mktemp -d "$framed_parent/Traxe-framed.XXXXXXXX")"
  fi
  if [[ -n "${REVIEW_DIR:-}" ]]; then
    mkdir -p "$review_parent"
    review_directory="$(mktemp -d "$review_parent/Traxe-review.XXXXXXXX")"
  fi
  local package_arguments=()
  if [[ -n "${SOURCE_PACKAGES_DIR:-}" ]]; then
    package_arguments=(-clonedSourcePackagesDirPath "$source_packages" -disableAutomaticPackageResolution)
  fi
  create_simulator_if_needed
  echo "Screenshot run: $run_directory"
  TEST_RUNNER_TRAXE_SCREENSHOT_OUTPUT_DIR="$raw_directory" \
    xcodebuild test -project "$PROJECT_PATH" -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" -destination "platform=iOS Simulator,id=$UDID" \
      -derivedDataPath "$derived_data" -resultBundlePath "$run_directory/Render.xcresult" \
      -parallel-testing-enabled NO -collect-test-diagnostics never \
      ${package_arguments[@]+"${package_arguments[@]}"} \
      -only-testing:"$RENDER_TEST" CODE_SIGNING_ALLOWED=NO

  local count portrait_file portrait_directory
  count="$(find "$raw_directory" -type f -name '*.png' | wc -l | tr -d ' ')"
  if [[ "$count" != "$expected_count" ]]; then
    echo "Expected $expected_count screenshots, found $count in $raw_directory" >&2
    exit 1
  fi
  if [[ "$includes_portrait" == "1" ]]; then
    portrait_file="$(find "$raw_directory" -type f -name '01_fleet-dashboard.png')"
    if [[ -z "$portrait_file" || "$portrait_file" == *$'\n'* ]]; then
      echo 'Expected one portrait screenshot set.' >&2
      exit 1
    fi
    portrait_directory="$(dirname "$portrait_file")"
    if [[ "$VALIDATE" == "1" ]]; then
      asc screenshots validate --path "$portrait_directory" \
        --device-type "$DEVICE_TYPE" --output json --pretty
    fi
    frame_outputs "$portrait_directory"
  fi
  echo "Raw screenshots: $raw_directory"
  if [[ "$FRAME_ENABLED" == "1" ]]; then
    echo "Framed screenshots: $framed_directory"
    echo "Review output: $review_directory"
  fi
}

main "$@"
