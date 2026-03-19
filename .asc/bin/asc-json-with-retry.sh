#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: asc-json-with-retry.sh <command> [args...]

Runs a read-only ASC command with retry/backoff and prints successful stdout.
Retry behavior is controlled by environment variables:
  ASC_RETRY_ATTEMPTS
  ASC_RETRY_DELAY_SECONDS
  ASC_RETRY_JITTER_SECONDS
EOF
}

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 1
fi

ATTEMPTS="${ASC_RETRY_ATTEMPTS:-4}"
BASE_DELAY="${ASC_RETRY_DELAY_SECONDS:-2}"
JITTER_SECONDS="${ASC_RETRY_JITTER_SECONDS:-2}"

case "$ATTEMPTS" in
  ''|*[!0-9]*)
    echo "ASC_RETRY_ATTEMPTS must be a non-negative integer." >&2
    exit 1
    ;;
esac

case "$BASE_DELAY" in
  ''|*[!0-9]*)
    echo "ASC_RETRY_DELAY_SECONDS must be a non-negative integer." >&2
    exit 1
    ;;
esac

case "$JITTER_SECONDS" in
  ''|*[!0-9]*)
    echo "ASC_RETRY_JITTER_SECONDS must be a non-negative integer." >&2
    exit 1
    ;;
esac

if [ "$ATTEMPTS" -lt 1 ]; then
  echo "ASC_RETRY_ATTEMPTS must be at least 1." >&2
  exit 1
fi

attempt=1
while :; do
  stdout_log="$(mktemp)"
  stderr_log="$(mktemp)"

  if "$@" >"$stdout_log" 2>"$stderr_log"; then
    cat "$stdout_log"
    rm -f "$stdout_log" "$stderr_log"
    exit 0
  else
    status=$?
  fi
  if [ "$attempt" -ge "$ATTEMPTS" ]; then
    cat "$stderr_log" >&2
    rm -f "$stdout_log" "$stderr_log"
    exit "$status"
  fi

  cat "$stderr_log" >&2

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

  printf 'ASC command failed (attempt %s/%s); retrying in %ss.\n' "$attempt" "$ATTEMPTS" "$sleep_for" >&2
  rm -f "$stdout_log" "$stderr_log"
  sleep "$sleep_for"
  attempt=$(( attempt + 1 ))
done
