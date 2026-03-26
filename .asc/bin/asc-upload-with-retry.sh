#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: asc-upload-with-retry.sh --mode upload|publish --app APP_ID --ipa IPA_PATH --version VERSION --build-number BUILD_NUMBER [options]

Retries transient App Store Connect upload failures and recovers from ambiguous
network drops by checking whether the build already appeared in ASC.

Options:
  --profile PROFILE
  --group GROUP_ID
  --notify-testers 0|1
  --wait-for-processing 0|1
  --locale LOCALE
  --test-notes-path PATH

Retry behavior is controlled by:
  ASC_UPLOAD_RETRY_ATTEMPTS
  ASC_UPLOAD_RETRY_DELAY_SECONDS
  ASC_UPLOAD_RETRY_JITTER_SECONDS
  ASC_BUILD_DISCOVERY_ATTEMPTS
  ASC_BUILD_DISCOVERY_DELAY_SECONDS
  ASC_UPLOAD_TIMEOUT
EOF
}

MODE=""
PROFILE=""
APP_ID=""
IPA_PATH=""
VERSION=""
BUILD_NUMBER=""
GROUP_ID=""
NOTIFY_TESTERS="0"
WAIT_FOR_PROCESSING="1"
LOCALE=""
TEST_NOTES_PATH=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --app)
      APP_ID="${2:-}"
      shift 2
      ;;
    --ipa)
      IPA_PATH="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --group)
      GROUP_ID="${2:-}"
      shift 2
      ;;
    --notify-testers)
      NOTIFY_TESTERS="${2:-}"
      shift 2
      ;;
    --wait-for-processing)
      WAIT_FOR_PROCESSING="${2:-}"
      shift 2
      ;;
    --locale)
      LOCALE="${2:-}"
      shift 2
      ;;
    --test-notes-path)
      TEST_NOTES_PATH="${2:-}"
      shift 2
      ;;
    --help|-h)
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

case "$MODE" in
  upload|publish) ;;
  *)
    echo "--mode must be upload or publish." >&2
    exit 1
    ;;
esac

for required in APP_ID IPA_PATH VERSION BUILD_NUMBER; do
  if [ -z "${!required}" ]; then
    echo "Missing required argument: ${required}" >&2
    exit 1
  fi
done

if [ "$MODE" = "publish" ] && [ -z "$GROUP_ID" ]; then
  echo "--group is required for publish mode." >&2
  exit 1
fi

ASC_CMD=(asc)
if [ -n "$PROFILE" ]; then
  ASC_CMD+=(--profile "$PROFILE")
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
READ_HELPER="$SCRIPT_DIR/asc-json-with-retry.sh"
if [ ! -x "$READ_HELPER" ]; then
  echo "Missing helper: $READ_HELPER" >&2
  exit 1
fi

ATTEMPTS="${ASC_UPLOAD_RETRY_ATTEMPTS:-3}"
BASE_DELAY="${ASC_UPLOAD_RETRY_DELAY_SECONDS:-15}"
JITTER_SECONDS="${ASC_UPLOAD_RETRY_JITTER_SECONDS:-10}"
DISCOVERY_ATTEMPTS="${ASC_BUILD_DISCOVERY_ATTEMPTS:-6}"
DISCOVERY_DELAY="${ASC_BUILD_DISCOVERY_DELAY_SECONDS:-10}"
UPLOAD_TIMEOUT="${ASC_UPLOAD_TIMEOUT:-600s}"

for numeric_var in ATTEMPTS BASE_DELAY JITTER_SECONDS DISCOVERY_ATTEMPTS DISCOVERY_DELAY; do
  case "${!numeric_var}" in
    ''|*[!0-9]*)
      echo "${numeric_var} must be a non-negative integer." >&2
      exit 1
      ;;
  esac
done

if [ "$ATTEMPTS" -lt 1 ]; then
  echo "ASC_UPLOAD_RETRY_ATTEMPTS must be at least 1." >&2
  exit 1
fi

read_test_notes() {
  if [ -n "$TEST_NOTES_PATH" ] && [ -f "$TEST_NOTES_PATH" ]; then
    cat "$TEST_NOTES_PATH"
  fi
}

build_lookup_json() {
  "$READ_HELPER" "${ASC_CMD[@]}" builds list \
    --app "$APP_ID" \
    --platform IOS \
    --version "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --processing-state all \
    --paginate \
    --output json
}

build_exists_from_json() {
  local json="$1"
  printf '%s' "$json" | jq -e '[.. | objects | select(((.version? // .attributes.version? // .attributes.versionString? // "") == $version) and ((.buildNumber? // .attributes.buildNumber? // "") == $build))] | length > 0' \
    --arg version "$VERSION" \
    --arg build "$BUILD_NUMBER" >/dev/null
}

wait_for_existing_build() {
  local attempt=1
  while [ "$attempt" -le "$DISCOVERY_ATTEMPTS" ]; do
    local build_json
    if build_json="$(build_lookup_json)"; then
      if build_exists_from_json "$build_json"; then
        if [ "$WAIT_FOR_PROCESSING" != "1" ]; then
          printf '%s' "$build_json"
          return 0
        fi

        local state
        state="$(printf '%s' "$build_json" | jq -r --arg version "$VERSION" --arg build "$BUILD_NUMBER" '[.. | objects | select(((.version? // .attributes.version? // .attributes.versionString? // "") == $version) and ((.buildNumber? // .attributes.buildNumber? // "") == $build)) | (.processingState? // .attributes.processingState? // "")] | map(select(type == "string" and length > 0)) | .[0] // ""')"
        case "$state" in
          ""|PROCESSING)
            ;;
          VALID)
            printf '%s' "$build_json"
            return 0
            ;;
          FAILED|INVALID)
            echo "Build $VERSION ($BUILD_NUMBER) reached processing state $state after upload recovery." >&2
            return 1
            ;;
          *)
            printf '%s' "$build_json"
            return 0
            ;;
        esac
      fi
    fi

    if [ "$attempt" -lt "$DISCOVERY_ATTEMPTS" ]; then
      sleep "$DISCOVERY_DELAY"
    fi
    attempt=$(( attempt + 1 ))
  done

  return 1
}

is_transient_upload_error() {
  local stderr_log="$1"
  grep -Eqi 'context deadline exceeded|connection reset by peer|retry limit exceeded|upload request failed|timeout|temporary failure|can'\''t assign requested address|EOF$' "$stderr_log"
}

run_upload_command() {
  local notes="$1"
  local cmd=("${ASC_CMD[@]}")

  if [ "$MODE" = "publish" ]; then
    cmd+=(publish testflight --app "$APP_ID" --ipa "$IPA_PATH" --group "$GROUP_ID" --version "$VERSION" --build-number "$BUILD_NUMBER" --output json --timeout "$UPLOAD_TIMEOUT")
    if [ "$NOTIFY_TESTERS" = "1" ]; then
      cmd+=(--notify)
    fi
  else
    cmd+=(builds upload --app "$APP_ID" --ipa "$IPA_PATH" --version "$VERSION" --build-number "$BUILD_NUMBER" --output json)
  fi

  if [ "$WAIT_FOR_PROCESSING" = "1" ]; then
    cmd+=(--wait)
  fi
  if [ -n "$notes" ]; then
    cmd+=(--test-notes "$notes" --locale "$LOCALE")
  fi

  "${cmd[@]}"
}

publish_existing_build() {
  local notes="$1"
  local cmd=("${ASC_CMD[@]}" publish testflight --app "$APP_ID" --build-number "$BUILD_NUMBER" --version "$VERSION" --group "$GROUP_ID" --platform IOS --output json --timeout "$UPLOAD_TIMEOUT")
  if [ "$WAIT_FOR_PROCESSING" = "1" ]; then
    cmd+=(--wait)
  fi
  if [ "$NOTIFY_TESTERS" = "1" ]; then
    cmd+=(--notify)
  fi
  if [ -n "$notes" ]; then
    cmd+=(--test-notes "$notes" --locale "$LOCALE")
  fi

  "${cmd[@]}"
}

TEST_NOTES="$(read_test_notes)"
attempt=1

while :; do
  stdout_log="$(mktemp)"
  stderr_log="$(mktemp)"
  recovery_json_log="$(mktemp)"
  recovery_stderr_log="$(mktemp)"

  if run_upload_command "$TEST_NOTES" >"$stdout_log" 2>"$stderr_log"; then
    cat "$stdout_log"
    rm -f "$stdout_log" "$stderr_log" "$recovery_json_log" "$recovery_stderr_log"
    exit 0
  else
    status=$?
  fi
  cat "$stderr_log" >&2

  if wait_for_existing_build >"$recovery_json_log" 2>"$recovery_stderr_log"; then
    recovery_json="$(cat "$recovery_json_log")"
    if [ "$MODE" = "publish" ]; then
      if publish_existing_build "$TEST_NOTES"; then
        rm -f "$stdout_log" "$stderr_log" "$recovery_json_log" "$recovery_stderr_log"
        exit 0
      fi
    else
      printf '%s' "$recovery_json"
      rm -f "$stdout_log" "$stderr_log" "$recovery_json_log" "$recovery_stderr_log"
      exit 0
    fi
  else
    if [ -s "$recovery_stderr_log" ]; then
      cat "$recovery_stderr_log" >&2
    fi
  fi

  if ! is_transient_upload_error "$stderr_log" || [ "$attempt" -ge "$ATTEMPTS" ]; then
    rm -f "$stdout_log" "$stderr_log" "$recovery_json_log" "$recovery_stderr_log"
    exit "$status"
  fi

  delay=$(( BASE_DELAY * attempt ))
  if [ "$JITTER_SECONDS" -gt 0 ]; then
    jitter=$(( RANDOM % (JITTER_SECONDS + 1) ))
  else
    jitter=0
  fi
  sleep_for=$(( delay + jitter ))
  if [ "$sleep_for" -lt 1 ]; then
    sleep_for=1
  fi

  printf 'ASC upload failed (attempt %s/%s); retrying in %ss.\n' "$attempt" "$ATTEMPTS" "$sleep_for" >&2
  rm -f "$stdout_log" "$stderr_log" "$recovery_json_log" "$recovery_stderr_log"
  sleep "$sleep_for"
  attempt=$(( attempt + 1 ))
done
