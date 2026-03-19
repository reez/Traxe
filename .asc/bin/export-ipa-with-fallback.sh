#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: export-ipa-with-fallback.sh \
  --archive-path /path/to/App.xcarchive \
  --export-options /path/to/ExportOptions.plist \
  --ipa-path /path/to/App.ipa \
  --team-id TEAMID
EOF
}

xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g'
}

run_export_capture() {
  local options_path="$1"
  local log_path="$2"
  shift 2

  if asc xcode export \
    --archive-path "$ARCHIVE_PATH" \
    --export-options "$options_path" \
    --ipa-path "$IPA_PATH" \
    --overwrite \
    "$@" \
    --output json >"$log_path" 2>&1; then
    cat "$log_path" >&2
    return 0
  fi

  return 1
}

ARCHIVE_PATH=""
EXPORT_OPTIONS_PATH=""
IPA_PATH=""
TEAM_ID=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive-path)
      ARCHIVE_PATH="${2:-}"
      shift 2
      ;;
    --export-options)
      EXPORT_OPTIONS_PATH="${2:-}"
      shift 2
      ;;
    --ipa-path)
      IPA_PATH="${2:-}"
      shift 2
      ;;
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for value_name in ARCHIVE_PATH EXPORT_OPTIONS_PATH IPA_PATH TEAM_ID; do
  if [ -z "${!value_name}" ]; then
    echo "Missing required argument: ${value_name}" >&2
    usage >&2
    exit 1
  fi
done

APPS_ROOT="$ARCHIVE_PATH/Products/Applications"
AUTO_LOG="$(mktemp)"
MANUAL_LOG=""

cleanup() {
  rm -f "$AUTO_LOG"
  if [ -n "$MANUAL_LOG" ]; then
    rm -f "$MANUAL_LOG"
  fi
}
trap cleanup EXIT

if run_export_capture "$EXPORT_OPTIONS_PATH" "$AUTO_LOG" --xcodebuild-flag=-allowProvisioningUpdates; then
  exit 0
fi

LOCAL_PROFILES_JSON="$(asc profiles local list --output json 2>/dev/null || true)"
if [ ! -d "$APPS_ROOT" ] || [ -z "$LOCAL_PROFILES_JSON" ]; then
  cat "$AUTO_LOG" >&2
  echo "Automatic export failed and no archive/profile data was available for manual export fallback." >&2
  exit 1
fi

DISTRIBUTION_CERT="$(
  security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\([^"]*Distribution: [^"]*\)".*/\1/p' |
    awk -v team="($TEAM_ID)" 'index($0, team) { print; exit }'
)"
if [ -z "$DISTRIBUTION_CERT" ]; then
  cat "$AUTO_LOG" >&2
  echo "Automatic export failed and no local distribution signing certificate matched team $TEAM_ID." >&2
  exit 1
fi

BUNDLE_IDS="$(
  find "$APPS_ROOT" \( -name '*.app' -o -name '*.appex' \) -print0 |
    while IFS= read -r -d '' bundle_path; do
      info_plist="$bundle_path/Info.plist"
      [ -f "$info_plist" ] || continue
      bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$info_plist" 2>/dev/null || true)"
      [ -n "$bundle_id" ] || continue
      printf '%s\n' "$bundle_id"
    done |
    sort -u
)"

if [ -z "$BUNDLE_IDS" ]; then
  cat "$AUTO_LOG" >&2
  echo "Automatic export failed and no archive bundle identifiers were discovered for manual export fallback." >&2
  exit 1
fi

PROVISIONING_XML="$(
  while IFS= read -r bundle_id; do
    [ -n "$bundle_id" ] || continue

    profile_name="$(
      printf '%s' "$LOCAL_PROFILES_JSON" |
        jq -r --arg team "$TEAM_ID" --arg bundle "$bundle_id" '
          [.items[]? | select(.teamId == $team and .bundleId == $bundle and (.expired | not))]
          | sort_by(.createdAt // "", .expiresAt // "")
          | reverse
          | .[0].name // empty
        '
    )"

    if [ -z "$profile_name" ]; then
      cat "$AUTO_LOG" >&2
      echo "Automatic export failed and no installed local App Store provisioning profile matched $bundle_id for team $TEAM_ID." >&2
      exit 1
    fi

    printf '    <key>%s</key>\n' "$bundle_id"
    printf '    <string>%s</string>\n' "$(xml_escape "$profile_name")"
  done <<EOF_BUNDLES
$BUNDLE_IDS
EOF_BUNDLES
)"

MANUAL_EXPORT_OPTIONS_PATH="$EXPORT_OPTIONS_PATH"
case "$MANUAL_EXPORT_OPTIONS_PATH" in
  *.plist)
    MANUAL_EXPORT_OPTIONS_PATH="${MANUAL_EXPORT_OPTIONS_PATH%.plist}.manual.plist"
    ;;
  *)
    MANUAL_EXPORT_OPTIONS_PATH="${MANUAL_EXPORT_OPTIONS_PATH}.manual.plist"
    ;;
esac

cat >"$MANUAL_EXPORT_OPTIONS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>method</key>
  <string>app-store-connect</string>
  <key>provisioningProfiles</key>
  <dict>
$PROVISIONING_XML
  </dict>
  <key>signingCertificate</key>
  <string>$(xml_escape "$DISTRIBUTION_CERT")</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>uploadBitcode</key>
  <false/>
</dict>
</plist>
EOF

echo "Automatic export failed; retrying with local profile mapping for team $TEAM_ID." >&2
MANUAL_LOG="$(mktemp)"
if run_export_capture "$MANUAL_EXPORT_OPTIONS_PATH" "$MANUAL_LOG"; then
  exit 0
fi

cat "$AUTO_LOG" >&2
cat "$MANUAL_LOG" >&2
echo "Manual export fallback also failed." >&2
exit 1
