#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MONETIZATION_MODE="${MONETIZATION_MODE:-audit}" # audit|apply
CONFIRM_APPLY="${CONFIRM_APPLY:-0}"
STRICT_AUDIT="${STRICT_AUDIT:-0}"

case "${MONETIZATION_MODE}" in
  audit)
    echo "==> Running monetization audit (read-only)"
    STRICT_AUDIT="${STRICT_AUDIT}" "${ROOT_DIR}/asc_rc_audit.sh"
    ;;
  apply)
    if [[ "${CONFIRM_APPLY}" != "1" ]]; then
      echo "Refusing to apply without explicit confirmation." >&2
      echo "Set CONFIRM_APPLY=1 MONETIZATION_MODE=apply to proceed." >&2
      exit 1
    fi

    echo "==> Running pre-apply audit"
    STRICT_AUDIT=0 "${ROOT_DIR}/asc_rc_audit.sh"

    echo "==> Applying ASC catalog setup"
    "${ROOT_DIR}/setup_asc_catalog.sh"

    echo "==> Applying RevenueCat setup"
    "${ROOT_DIR}/setup_revenuecat_v2.sh"

    echo "==> Running post-apply audit"
    STRICT_AUDIT=1 "${ROOT_DIR}/asc_rc_audit.sh"
    ;;
  *)
    echo "Unsupported MONETIZATION_MODE=${MONETIZATION_MODE}. Use audit|apply" >&2
    exit 1
    ;;
esac
