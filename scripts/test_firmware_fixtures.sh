#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-Traxe.xcodeproj}"
SCHEME="${SCHEME:-Traxe}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.build/firmware-fixtures-derived-data}"
DESTINATION="${DESTINATION:-}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"

choose_destination() {
  if [[ -n "$DESTINATION" ]]; then
    printf '%s\n' "$DESTINATION"
    return
  fi

  if xcrun simctl list devices available | grep -q "$DEVICE_NAME"; then
    printf 'platform=iOS Simulator,name=%s\n' "$DEVICE_NAME"
    return
  fi

  local udid
  udid="$(
    xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json
import sys

data = json.load(sys.stdin)
for runtime, devices in data.get("devices", {}).items():
    if not runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS"):
        continue
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone simulator found")
'
  )"

  printf 'platform=iOS Simulator,id=%s\n' "$udid"
}

destination="$(choose_destination)"

xcodebuild test \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$destination" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -only-testing:TraxeTests/MinerTelemetryDTOTests \
  -only-testing:TraxeTests/NetworkServiceTests/testFetchMinerTelemetryDecodesPayloadThatFullSystemInfoRejects \
  -only-testing:TraxeTests/DashboardViewModelTests/testConnectWithTelemetryFromPayloadThatBreaksFullSettingsDecodeStaysConnected \
  -only-testing:TraxeTests/SettingsViewModelTests/testTelemetryOnlySettingsFallbackDisablesSettingsWrites
