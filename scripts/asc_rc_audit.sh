#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required env var: $name" >&2
    exit 1
  fi
}

json_true_if_nonempty() {
  local value="$1"
  if [[ -n "${value}" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

require_cmd asc
require_cmd curl
require_cmd jq

require_env ASC_KEY_ID
require_env ASC_ISSUER_ID
require_env ASC_PRIVATE_KEY_PATH
require_env RC_API_V2_SECRET_KEY

if [[ ! -f "${ASC_PRIVATE_KEY_PATH}" ]]; then
  echo "ASC_PRIVATE_KEY_PATH does not exist: ${ASC_PRIVATE_KEY_PATH}" >&2
  exit 1
fi

BUNDLE_ID="${BUNDLE_ID:-com.matthewramsden.Traxe}"
ASC_PROFILE_NAME="${ASC_PROFILE_NAME:-Traxe Personal}"

SUBSCRIPTION_GROUP_REF="${SUBSCRIPTION_GROUP_REF:-TraxePro}"
GROUP_LOCALIZED_NAME="${GROUP_LOCALIZED_NAME:-Traxe Pro}"
MONTHLY_PRODUCT_ID="${MONTHLY_PRODUCT_ID:-com.matthewramsden.Traxe.Monthly}"
MONTHLY_LOCALIZED_NAME="${MONTHLY_LOCALIZED_NAME:-Traxe Pro (Monthly)}"
MONTHLY_LOCALIZED_DESCRIPTION="${MONTHLY_LOCALIZED_DESCRIPTION:-Unlock the ability to manage more devices.}"
MONTHLY_PRICE_USD="${MONTHLY_PRICE_USD:-2.99}"
MINERS_PRODUCT_ID="${MINERS_PRODUCT_ID:-miners_5}"
MINERS_LOCALIZED_NAME="${MINERS_LOCALIZED_NAME:-Traxe Pro (One-Time, 5 Miners)}"
MINERS_LOCALIZED_DESCRIPTION="${MINERS_LOCALIZED_DESCRIPTION:-Unlock the ability to add up to 5 miners.}"
MINERS_PRICE_USD="${MINERS_PRICE_USD:-9.99}"

RC_BASE_URL="${RC_BASE_URL:-https://api.revenuecat.com/v2}"
RC_PROJECT_NAME="${RC_PROJECT_NAME:-Traxe}"
RC_PROJECT_ID="${RC_PROJECT_ID:-}"
RC_APP_ID="${RC_APP_ID:-}"
RC_OFFERING_LOOKUP="${RC_OFFERING_LOOKUP:-miners_5}"
RC_MONTHLY_PACKAGE_LOOKUP="${RC_MONTHLY_PACKAGE_LOOKUP:-monthly}"
RC_ONE_TIME_PACKAGE_LOOKUP="${RC_ONE_TIME_PACKAGE_LOOKUP:-miners_5}"
RC_PRO_ENTITLEMENT_LOOKUP="${RC_PRO_ENTITLEMENT_LOOKUP:-Pro}"
RC_MINERS_ENTITLEMENT_LOOKUP="${RC_MINERS_ENTITLEMENT_LOOKUP:-Miners_5}"
STRICT_AUDIT="${STRICT_AUDIT:-0}"
SUBSCRIPTION_VALIDATION_STRICT="${SUBSCRIPTION_VALIDATION_STRICT:-0}"
IAP_VALIDATION_STRICT="${IAP_VALIDATION_STRICT:-0}"
REPORT_PATH="${REPORT_PATH:-/tmp/traxe_monetization_audit.json}"

api() {
  local method="$1"
  local path="$2"
  local tmp
  local status

  tmp="$(mktemp)"
  status="$(curl -sS -o "${tmp}" -w "%{http_code}" \
    -X "${method}" \
    -H "Authorization: Bearer ${RC_API_V2_SECRET_KEY}" \
    "${RC_BASE_URL}${path}")"

  if [[ "${status}" -lt 200 || "${status}" -ge 300 ]]; then
    echo "RevenueCat API error: ${method} ${path} -> HTTP ${status}" >&2
    cat "${tmp}" >&2
    rm -f "${tmp}"
    exit 1
  fi

  cat "${tmp}"
  rm -f "${tmp}"
}

resolve_asc_app_id() {
  local apps_json="$1"

  printf '%s' "${apps_json}" | jq -r --arg bundle "${BUNDLE_ID}" '
[
  .. | objects
  | select((.bundleId? // .bundle_id? // .attributes.bundleId? // .attributes.bundle_id? // "") == $bundle)
  | (.id? // .app_id? // empty)
] | map(select(type == "string" and length > 0)) | .[0] // empty
'
}

resolve_subscription_group_id() {
  local groups_json="$1"

  printf '%s' "${groups_json}" | jq -r --arg ref "${SUBSCRIPTION_GROUP_REF}" '
[
  .. | objects
  | select((.referenceName? // .reference_name? // .attributes.referenceName? // .attributes.reference_name? // .name? // "") == $ref)
  | (.id? // .group_id? // empty)
] | map(select(type == "string" and length > 0)) | .[0] // empty
'
}

resolve_subscription_id() {
  local subscriptions_json="$1"
  local product_id="$2"

  printf '%s' "${subscriptions_json}" | jq -r --arg pid "${product_id}" '
[
  .. | objects
  | select((.productId? // .product_id? // .attributes.productId? // .attributes.product_id? // "") == $pid)
  | (.id? // .subscription_id? // empty)
] | map(select(type == "string" and length > 0)) | .[0] // empty
'
}

resolve_iap_id() {
  local iaps_json="$1"
  local product_id="$2"

  printf '%s' "${iaps_json}" | jq -r --arg pid "${product_id}" '
[
  .. | objects
  | select((.productId? // .product_id? // .attributes.productId? // .attributes.product_id? // "") == $pid)
  | (.id? // .inAppPurchaseId? // .iap_id? // empty)
] | map(select(type == "string" and length > 0)) | .[0] // empty
'
}

resolve_localization_id() {
  local json="$1"

  printf '%s' "${json}" | jq -r '
[
  .. | objects
  | select((.locale? // .attributes.locale? // "") == "en-US")
  | .id?
] | map(select(type == "string" and length > 0)) | .[0] // empty
'
}

resolve_rc_project_id() {
  local projects_json="$1"

  if [[ -n "${RC_PROJECT_ID}" ]]; then
    printf '%s' "${RC_PROJECT_ID}"
    return
  fi

  printf '%s' "${projects_json}" | jq -r --arg name "${RC_PROJECT_NAME}" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("proj")))
  | select((.name? // "") == $name)
  | .id
] | .[0] // empty
'
}

resolve_rc_app_id() {
  local apps_json="$1"

  if [[ -n "${RC_APP_ID}" ]]; then
    printf '%s' "${RC_APP_ID}"
    return
  fi

  printf '%s' "${apps_json}" | jq -r --arg bundle "${BUNDLE_ID}" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("app")))
  | select((.app_store.bundle_id? // .bundle_id? // .appStore.bundleId? // "") == $bundle)
  | .id
] | .[0] // empty
'
}

resolve_rc_product_id() {
  local products_json="$1"
  local store_identifier="$2"

  printf '%s' "${products_json}" | jq -r --arg sid "${store_identifier}" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("prod")))
  | select((.store_identifier? // .storeIdentifier? // "") == $sid)
  | .id
] | .[0] // empty
'
}

resolve_rc_entitlement_id() {
  local entitlements_json="$1"
  local lookup="$2"

  printf '%s' "${entitlements_json}" | jq -r --arg lookup "${lookup}" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("entl")))
  | select((.lookup_key? // .lookupKey? // "") == $lookup)
  | .id
] | .[0] // empty
'
}

resolve_rc_offering_id() {
  local offerings_json="$1"

  printf '%s' "${offerings_json}" | jq -r --arg lookup "${RC_OFFERING_LOOKUP}" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("ofrn")))
  | select((.lookup_key? // .lookupKey? // "") == $lookup)
  | .id
] | .[0] // empty
'
}

resolve_rc_package_id() {
  local packages_json="$1"
  local lookup="$2"

  printf '%s' "${packages_json}" | jq -r --arg lookup "${lookup}" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("pkg")))
  | select((.lookup_key? // .lookupKey? // "") == $lookup)
  | .id
] | .[0] // empty
'
}

json_contains_product_id() {
  local json="$1"
  local product_id="$2"

  if [[ -z "${product_id}" ]]; then
    printf 'false'
    return
  fi

  printf '%s' "${json}" | jq -r --arg pid "${product_id}" '
[
  .. | objects
  | select((.id? // .product.id? // .product_id? // "") == $pid)
  | (.id? // .product.id? // .product_id? // empty)
] | map(select(type == "string" and length > 0)) | length > 0
'
}

extract_price_amount() {
  local json="$1"
  printf '%s' "${json}" | jq -r '.subscriptions[0].currentPrice.amount // .iaps[0].currentPrice.amount // empty'
}

extract_localized_name() {
  local json="$1"
  printf '%s' "${json}" | jq -r '.data[0].attributes.name // empty'
}

extract_localized_description() {
  local json="$1"
  printf '%s' "${json}" | jq -r '.data[0].attributes.description // empty'
}

echo "==> Audit: authenticating asc API key"
asc auth login \
  --name "${ASC_PROFILE_NAME}" \
  --key-id "${ASC_KEY_ID}" \
  --issuer-id "${ASC_ISSUER_ID}" \
  --private-key "${ASC_PRIVATE_KEY_PATH}" \
  --network >/dev/null

echo "==> Audit: reading App Store Connect catalog"
ASC_APPS_JSON="$(asc apps list --bundle-id "${BUNDLE_ID}" --paginate --output json)"
APP_ID="$(resolve_asc_app_id "${ASC_APPS_JSON}")"

GROUP_ID=""
GROUP_LOCALIZATION_ID=""
SUBSCRIPTIONS_JSON='{}'
MONTHLY_SUBSCRIPTION_ID=""
MONTHLY_LOCALIZATION_ID=""
MONTHLY_LOCALIZATION_JSON='{}'
MONTHLY_PRICE_JSON='{}'
MONTHLY_CURRENT_PRICE=""
IAPS_JSON='{}'
MINERS_IAP_ID=""
MINERS_LOCALIZATION_ID=""
MINERS_LOCALIZATION_JSON='{}'
MINERS_PRICE_JSON='{}'
MINERS_CURRENT_PRICE=""
SUBSCRIPTION_VALIDATION_JSON='{}'
IAP_VALIDATION_JSON='{}'
SUBSCRIPTION_VALIDATION_WARNINGS="0"
IAP_VALIDATION_WARNINGS="0"

if [[ -n "${APP_ID}" ]]; then
  GROUPS_JSON="$(asc subscriptions groups list --app "${APP_ID}" --paginate --output json)"
  GROUP_ID="$(resolve_subscription_group_id "${GROUPS_JSON}")"

  if [[ -n "${GROUP_ID}" ]]; then
    GROUP_LOCALIZATIONS_JSON="$(asc subscriptions groups localizations list --group-id "${GROUP_ID}" --paginate --output json)"
    GROUP_LOCALIZATION_ID="$(resolve_localization_id "${GROUP_LOCALIZATIONS_JSON}")"
    SUBSCRIPTIONS_JSON="$(asc subscriptions list --group-id "${GROUP_ID}" --paginate --output json)"
    MONTHLY_SUBSCRIPTION_ID="$(resolve_subscription_id "${SUBSCRIPTIONS_JSON}" "${MONTHLY_PRODUCT_ID}")"
    if [[ -n "${MONTHLY_SUBSCRIPTION_ID}" ]]; then
      MONTHLY_LOCALIZATION_JSON="$(asc subscriptions localizations list --subscription-id "${MONTHLY_SUBSCRIPTION_ID}" --paginate --output json)"
      MONTHLY_LOCALIZATION_ID="$(resolve_localization_id "${MONTHLY_LOCALIZATION_JSON}")"
    fi
  fi

  if [[ -n "${MONTHLY_SUBSCRIPTION_ID}" ]]; then
    MONTHLY_PRICE_JSON="$(asc subscriptions pricing summary --app "${APP_ID}" --output json)"
    MONTHLY_CURRENT_PRICE="$(printf '%s' "${MONTHLY_PRICE_JSON}" | jq -r --arg pid "${MONTHLY_PRODUCT_ID}" '.subscriptions[]? | select(.productId == $pid) | .currentPrice.amount // empty' | head -n 1)"
  fi

  IAPS_JSON="$(asc iap list --app "${APP_ID}" --paginate --output json)"
  MINERS_IAP_ID="$(resolve_iap_id "${IAPS_JSON}" "${MINERS_PRODUCT_ID}")"
  if [[ -n "${MINERS_IAP_ID}" ]]; then
    MINERS_LOCALIZATION_JSON="$(asc iap localizations list --iap-id "${MINERS_IAP_ID}" --paginate --output json)"
    MINERS_LOCALIZATION_ID="$(resolve_localization_id "${MINERS_LOCALIZATION_JSON}")"
    MINERS_PRICE_JSON="$(asc iap pricing summary --iap-id "${MINERS_IAP_ID}" --output json)"
    MINERS_CURRENT_PRICE="$(extract_price_amount "${MINERS_PRICE_JSON}")"
  fi

  SUBSCRIPTION_VALIDATION_JSON="$(asc validate subscriptions --app "${APP_ID}" --output json)"
  IAP_VALIDATION_JSON="$(asc validate iap --app "${APP_ID}" --output json)"
  SUBSCRIPTION_VALIDATION_WARNINGS="$(printf '%s' "${SUBSCRIPTION_VALIDATION_JSON}" | jq -r '.summary.warnings // 0')"
  IAP_VALIDATION_WARNINGS="$(printf '%s' "${IAP_VALIDATION_JSON}" | jq -r '.summary.warnings // 0')"
fi

echo "==> Audit: reading RevenueCat catalog"
PROJECTS_JSON="$(api GET "/projects")"
RESOLVED_RC_PROJECT_ID="$(resolve_rc_project_id "${PROJECTS_JSON}")"
RESOLVED_RC_APP_ID=""
RC_PRODUCTS_JSON='{}'
RC_MONTHLY_PRODUCT_INTERNAL_ID=""
RC_MINERS_PRODUCT_INTERNAL_ID=""
RC_ENTITLEMENTS_JSON='{}'
RC_PRO_ENTITLEMENT_ID=""
RC_MINERS_ENTITLEMENT_ID=""
RC_PRO_ENTITLEMENT_PRODUCTS_JSON='{}'
RC_MINERS_ENTITLEMENT_PRODUCTS_JSON='{}'
RC_OFFERINGS_JSON='{}'
RC_OFFERING_ID=""
RC_PACKAGES_JSON='{}'
RC_MONTHLY_PACKAGE_ID=""
RC_ONE_TIME_PACKAGE_ID=""
RC_MONTHLY_PACKAGE_PRODUCTS_JSON='{}'
RC_ONE_TIME_PACKAGE_PRODUCTS_JSON='{}'

if [[ -n "${RESOLVED_RC_PROJECT_ID}" ]]; then
  RC_APPS_JSON="$(api GET "/projects/${RESOLVED_RC_PROJECT_ID}/apps")"
  RESOLVED_RC_APP_ID="$(resolve_rc_app_id "${RC_APPS_JSON}")"

  if [[ -n "${RESOLVED_RC_APP_ID}" ]]; then
    RC_PRODUCTS_JSON="$(api GET "/projects/${RESOLVED_RC_PROJECT_ID}/products?app_id=${RESOLVED_RC_APP_ID}")"
    RC_MONTHLY_PRODUCT_INTERNAL_ID="$(resolve_rc_product_id "${RC_PRODUCTS_JSON}" "${MONTHLY_PRODUCT_ID}")"
    RC_MINERS_PRODUCT_INTERNAL_ID="$(resolve_rc_product_id "${RC_PRODUCTS_JSON}" "${MINERS_PRODUCT_ID}")"
  fi

  RC_ENTITLEMENTS_JSON="$(api GET "/projects/${RESOLVED_RC_PROJECT_ID}/entitlements")"
  RC_PRO_ENTITLEMENT_ID="$(resolve_rc_entitlement_id "${RC_ENTITLEMENTS_JSON}" "${RC_PRO_ENTITLEMENT_LOOKUP}")"
  RC_MINERS_ENTITLEMENT_ID="$(resolve_rc_entitlement_id "${RC_ENTITLEMENTS_JSON}" "${RC_MINERS_ENTITLEMENT_LOOKUP}")"

  if [[ -n "${RC_PRO_ENTITLEMENT_ID}" ]]; then
    RC_PRO_ENTITLEMENT_PRODUCTS_JSON="$(api GET "/projects/${RESOLVED_RC_PROJECT_ID}/entitlements/${RC_PRO_ENTITLEMENT_ID}/products")"
  fi
  if [[ -n "${RC_MINERS_ENTITLEMENT_ID}" ]]; then
    RC_MINERS_ENTITLEMENT_PRODUCTS_JSON="$(api GET "/projects/${RESOLVED_RC_PROJECT_ID}/entitlements/${RC_MINERS_ENTITLEMENT_ID}/products")"
  fi

  RC_OFFERINGS_JSON="$(api GET "/projects/${RESOLVED_RC_PROJECT_ID}/offerings")"
  RC_OFFERING_ID="$(resolve_rc_offering_id "${RC_OFFERINGS_JSON}")"
  if [[ -n "${RC_OFFERING_ID}" ]]; then
    RC_PACKAGES_JSON="$(api GET "/projects/${RESOLVED_RC_PROJECT_ID}/offerings/${RC_OFFERING_ID}/packages")"
    RC_MONTHLY_PACKAGE_ID="$(resolve_rc_package_id "${RC_PACKAGES_JSON}" "${RC_MONTHLY_PACKAGE_LOOKUP}")"
    RC_ONE_TIME_PACKAGE_ID="$(resolve_rc_package_id "${RC_PACKAGES_JSON}" "${RC_ONE_TIME_PACKAGE_LOOKUP}")"
    if [[ -n "${RC_MONTHLY_PACKAGE_ID}" ]]; then
      RC_MONTHLY_PACKAGE_PRODUCTS_JSON="$(api GET "/projects/${RESOLVED_RC_PROJECT_ID}/packages/${RC_MONTHLY_PACKAGE_ID}/products")"
    fi
    if [[ -n "${RC_ONE_TIME_PACKAGE_ID}" ]]; then
      RC_ONE_TIME_PACKAGE_PRODUCTS_JSON="$(api GET "/projects/${RESOLVED_RC_PROJECT_ID}/packages/${RC_ONE_TIME_PACKAGE_ID}/products")"
    fi
  fi
fi

FAILURES=()

[[ -n "${APP_ID}" ]] || FAILURES+=("ASC app missing for bundle ${BUNDLE_ID}")
[[ -n "${GROUP_ID}" ]] || FAILURES+=("ASC subscription group missing (${SUBSCRIPTION_GROUP_REF})")
[[ -n "${GROUP_LOCALIZATION_ID}" ]] || FAILURES+=("ASC subscription group localization missing (en-US)")
[[ -n "${MONTHLY_SUBSCRIPTION_ID}" ]] || FAILURES+=("ASC monthly subscription missing (${MONTHLY_PRODUCT_ID})")
[[ -n "${MONTHLY_LOCALIZATION_ID}" ]] || FAILURES+=("ASC monthly subscription localization missing (en-US)")
[[ -n "${MINERS_IAP_ID}" ]] || FAILURES+=("ASC one-time IAP missing (${MINERS_PRODUCT_ID})")
[[ -n "${MINERS_LOCALIZATION_ID}" ]] || FAILURES+=("ASC one-time IAP localization missing (en-US)")

if [[ -n "${GROUP_LOCALIZATION_ID}" ]]; then
  GROUP_LOCALIZED_NAME_ACTUAL="$(printf '%s' "${GROUP_LOCALIZATIONS_JSON}" | jq -r '.data[0].attributes.name // empty')"
  [[ "${GROUP_LOCALIZED_NAME_ACTUAL}" == "${GROUP_LOCALIZED_NAME}" ]] || FAILURES+=("ASC group localization name drift (${GROUP_LOCALIZED_NAME_ACTUAL:-<missing>} != ${GROUP_LOCALIZED_NAME})")
fi

if [[ -n "${MONTHLY_LOCALIZATION_ID}" ]]; then
  [[ "$(extract_localized_name "${MONTHLY_LOCALIZATION_JSON}")" == "${MONTHLY_LOCALIZED_NAME}" ]] || FAILURES+=("ASC monthly localization name drift")
  [[ "$(extract_localized_description "${MONTHLY_LOCALIZATION_JSON}")" == "${MONTHLY_LOCALIZED_DESCRIPTION}" ]] || FAILURES+=("ASC monthly localization description drift")
fi

if [[ -n "${MINERS_LOCALIZATION_ID}" ]]; then
  [[ "$(extract_localized_name "${MINERS_LOCALIZATION_JSON}")" == "${MINERS_LOCALIZED_NAME}" ]] || FAILURES+=("ASC one-time localization name drift")
  [[ "$(extract_localized_description "${MINERS_LOCALIZATION_JSON}")" == "${MINERS_LOCALIZED_DESCRIPTION}" ]] || FAILURES+=("ASC one-time localization description drift")
fi

if [[ -n "${MONTHLY_CURRENT_PRICE}" && "${MONTHLY_CURRENT_PRICE}" != "${MONTHLY_PRICE_USD}" ]]; then
  FAILURES+=("ASC monthly price drift (${MONTHLY_CURRENT_PRICE} != ${MONTHLY_PRICE_USD})")
fi

if [[ -n "${MINERS_CURRENT_PRICE}" && "${MINERS_CURRENT_PRICE}" != "${MINERS_PRICE_USD}" ]]; then
  FAILURES+=("ASC one-time price drift (${MINERS_CURRENT_PRICE} != ${MINERS_PRICE_USD})")
fi

[[ -n "${RESOLVED_RC_PROJECT_ID}" ]] || FAILURES+=("RevenueCat project missing (${RC_PROJECT_NAME})")
[[ -n "${RESOLVED_RC_APP_ID}" ]] || FAILURES+=("RevenueCat app missing for bundle ${BUNDLE_ID}")
[[ -n "${RC_MONTHLY_PRODUCT_INTERNAL_ID}" ]] || FAILURES+=("RevenueCat monthly product missing (${MONTHLY_PRODUCT_ID})")
[[ -n "${RC_MINERS_PRODUCT_INTERNAL_ID}" ]] || FAILURES+=("RevenueCat one-time product missing (${MINERS_PRODUCT_ID})")
[[ -n "${RC_PRO_ENTITLEMENT_ID}" ]] || FAILURES+=("RevenueCat entitlement missing (${RC_PRO_ENTITLEMENT_LOOKUP})")
[[ -n "${RC_MINERS_ENTITLEMENT_ID}" ]] || FAILURES+=("RevenueCat entitlement missing (${RC_MINERS_ENTITLEMENT_LOOKUP})")
[[ -n "${RC_OFFERING_ID}" ]] || FAILURES+=("RevenueCat offering missing (${RC_OFFERING_LOOKUP})")
[[ -n "${RC_MONTHLY_PACKAGE_ID}" ]] || FAILURES+=("RevenueCat monthly package missing (${RC_MONTHLY_PACKAGE_LOOKUP})")
[[ -n "${RC_ONE_TIME_PACKAGE_ID}" ]] || FAILURES+=("RevenueCat one-time package missing (${RC_ONE_TIME_PACKAGE_LOOKUP})")

[[ "$(json_contains_product_id "${RC_PRO_ENTITLEMENT_PRODUCTS_JSON}" "${RC_MONTHLY_PRODUCT_INTERNAL_ID}")" == "true" ]] || FAILURES+=("Monthly product not attached to Pro entitlement")
[[ "$(json_contains_product_id "${RC_MINERS_ENTITLEMENT_PRODUCTS_JSON}" "${RC_MINERS_PRODUCT_INTERNAL_ID}")" == "true" ]] || FAILURES+=("One-time product not attached to Miners_5 entitlement")
[[ "$(json_contains_product_id "${RC_MONTHLY_PACKAGE_PRODUCTS_JSON}" "${RC_MONTHLY_PRODUCT_INTERNAL_ID}")" == "true" ]] || FAILURES+=("Monthly product not attached to monthly package")
[[ "$(json_contains_product_id "${RC_ONE_TIME_PACKAGE_PRODUCTS_JSON}" "${RC_MINERS_PRODUCT_INTERNAL_ID}")" == "true" ]] || FAILURES+=("One-time product not attached to one-time package")

if [[ "$(printf '%s' "${SUBSCRIPTION_VALIDATION_JSON}" | jq -r '.summary.errors // 0')" -gt 0 || "$(printf '%s' "${SUBSCRIPTION_VALIDATION_JSON}" | jq -r '.summary.blocking // 0')" -gt 0 ]]; then
  while IFS= read -r item; do
    [[ -n "${item}" ]] || continue
    FAILURES+=("Subscription validation: ${item}")
  done < <(printf '%s' "${SUBSCRIPTION_VALIDATION_JSON}" | jq -r '.checks[]? | select((.severity // "") != "warning" and (.severity // "") != "info") | .message')
fi

if [[ "${SUBSCRIPTION_VALIDATION_STRICT}" == "1" && "${SUBSCRIPTION_VALIDATION_WARNINGS}" -gt 0 ]]; then
  while IFS= read -r item; do
    [[ -n "${item}" ]] || continue
    FAILURES+=("Subscription validation warning: ${item}")
  done < <(printf '%s' "${SUBSCRIPTION_VALIDATION_JSON}" | jq -r '.checks[]? | select((.severity // "") == "warning") | .message')
fi

if [[ "$(printf '%s' "${IAP_VALIDATION_JSON}" | jq -r '.summary.errors // 0')" -gt 0 || "$(printf '%s' "${IAP_VALIDATION_JSON}" | jq -r '.summary.blocking // 0')" -gt 0 ]]; then
  while IFS= read -r item; do
    [[ -n "${item}" ]] || continue
    FAILURES+=("IAP validation: ${item}")
  done < <(printf '%s' "${IAP_VALIDATION_JSON}" | jq -r '.checks[]? | select((.severity // "") != "warning" and (.severity // "") != "info") | .message')
fi

if [[ "${IAP_VALIDATION_STRICT}" == "1" && "${IAP_VALIDATION_WARNINGS}" -gt 0 ]]; then
  while IFS= read -r item; do
    [[ -n "${item}" ]] || continue
    FAILURES+=("IAP validation warning: ${item}")
  done < <(printf '%s' "${IAP_VALIDATION_JSON}" | jq -r '.checks[]? | select((.severity // "") == "warning") | .message')
fi

DRIFT_COUNT="${#FAILURES[@]}"

FAILURES_JSON='[]'
if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  FAILURES_JSON="$(printf '%s\n' "${FAILURES[@]}" | jq -R . | jq -s '.')"
fi

jq -n \
  --arg bundle_id "${BUNDLE_ID}" \
  --arg app_id "${APP_ID}" \
  --arg group_id "${GROUP_ID}" \
  --arg group_localization_id "${GROUP_LOCALIZATION_ID}" \
  --arg monthly_subscription_id "${MONTHLY_SUBSCRIPTION_ID}" \
  --arg monthly_localization_id "${MONTHLY_LOCALIZATION_ID}" \
  --arg monthly_current_price "${MONTHLY_CURRENT_PRICE}" \
  --arg miners_iap_id "${MINERS_IAP_ID}" \
  --arg miners_localization_id "${MINERS_LOCALIZATION_ID}" \
  --arg miners_current_price "${MINERS_CURRENT_PRICE}" \
  --arg rc_project_id "${RESOLVED_RC_PROJECT_ID}" \
  --arg rc_app_id "${RESOLVED_RC_APP_ID}" \
  --arg rc_monthly_product_internal_id "${RC_MONTHLY_PRODUCT_INTERNAL_ID}" \
  --arg rc_miners_product_internal_id "${RC_MINERS_PRODUCT_INTERNAL_ID}" \
  --arg rc_pro_entitlement_id "${RC_PRO_ENTITLEMENT_ID}" \
  --arg rc_miners_entitlement_id "${RC_MINERS_ENTITLEMENT_ID}" \
  --arg rc_offering_id "${RC_OFFERING_ID}" \
  --arg rc_monthly_package_id "${RC_MONTHLY_PACKAGE_ID}" \
  --arg rc_one_time_package_id "${RC_ONE_TIME_PACKAGE_ID}" \
  --argjson subscription_validation "${SUBSCRIPTION_VALIDATION_JSON}" \
  --argjson iap_validation "${IAP_VALIDATION_JSON}" \
  --argjson drift_count "${DRIFT_COUNT}" \
  --argjson failures "${FAILURES_JSON}" \
  '{
    bundle_id: $bundle_id,
    asc: {
      app_id: $app_id,
      subscription_group_id: $group_id,
      subscription_group_localization_id: $group_localization_id,
      monthly_subscription_id: $monthly_subscription_id,
      monthly_localization_id: $monthly_localization_id,
      monthly_current_price: $monthly_current_price,
      miners_iap_id: $miners_iap_id,
      miners_localization_id: $miners_localization_id,
      miners_current_price: $miners_current_price
    },
    subscription_validation: $subscription_validation,
    iap_validation: $iap_validation,
    revenuecat: {
      project_id: $rc_project_id,
      app_id: $rc_app_id,
      monthly_product_internal_id: $rc_monthly_product_internal_id,
      miners_product_internal_id: $rc_miners_product_internal_id,
      pro_entitlement_id: $rc_pro_entitlement_id,
      miners_entitlement_id: $rc_miners_entitlement_id,
      offering_id: $rc_offering_id,
      monthly_package_id: $rc_monthly_package_id,
      one_time_package_id: $rc_one_time_package_id
    },
    drift_count: $drift_count,
    failures: $failures
  }' > "${REPORT_PATH}"

echo
echo "Traxe monetization audit summary"
echo "- Bundle: ${BUNDLE_ID}"
echo "- ASC app: ${APP_ID:-<missing>}"
echo "- ASC group: ${GROUP_ID:-<missing>}"
echo "- ASC monthly subscription: ${MONTHLY_SUBSCRIPTION_ID:-<missing>}"
echo "- ASC one-time IAP: ${MINERS_IAP_ID:-<missing>}"
echo "- Subscription validator: warnings=${SUBSCRIPTION_VALIDATION_WARNINGS}"
echo "- IAP validator: warnings=${IAP_VALIDATION_WARNINGS}"
echo "- RC project: ${RESOLVED_RC_PROJECT_ID:-<missing>}"
echo "- RC app: ${RESOLVED_RC_APP_ID:-<missing>}"
echo "- RC offering: ${RC_OFFERING_ID:-<missing>}"
echo "- Drift count: ${DRIFT_COUNT}"
echo
echo "Audit JSON report: ${REPORT_PATH}"

if [[ "${DRIFT_COUNT}" -gt 0 ]]; then
  echo
  echo "Drift items:"
  for item in "${FAILURES[@]}"; do
    echo "  - ${item}"
  done
fi

if [[ "${STRICT_AUDIT}" == "1" && "${DRIFT_COUNT}" -gt 0 ]]; then
  exit 2
fi
