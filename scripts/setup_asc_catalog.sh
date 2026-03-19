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

first_string_id() {
  jq -r '[.. | objects | .id? | select(type == "string" and length > 0)] | .[0] // empty'
}

require_cmd asc
require_cmd jq

require_env ASC_KEY_ID
require_env ASC_ISSUER_ID
require_env ASC_PRIVATE_KEY_PATH

if [[ ! -f "${ASC_PRIVATE_KEY_PATH}" ]]; then
  echo "ASC_PRIVATE_KEY_PATH does not exist: ${ASC_PRIVATE_KEY_PATH}" >&2
  exit 1
fi

BUNDLE_ID="${BUNDLE_ID:-com.matthewramsden.Traxe}"
APP_NAME="${APP_NAME:-Traxe}"
APP_SKU="${APP_SKU:-TRAXE001}"
APP_PRIMARY_LOCALE="${APP_PRIMARY_LOCALE:-en-US}"
ASC_PROFILE_NAME="${ASC_PROFILE_NAME:-Traxe Personal}"
CREATE_ASC_APP="${CREATE_ASC_APP:-0}"

SUBSCRIPTION_GROUP_REF="${SUBSCRIPTION_GROUP_REF:-TraxePro}"
GROUP_LOCALIZED_NAME="${GROUP_LOCALIZED_NAME:-Traxe Pro}"

MONTHLY_PRODUCT_ID="${MONTHLY_PRODUCT_ID:-com.matthewramsden.Traxe.Monthly}"
MONTHLY_REF_NAME="${MONTHLY_REF_NAME:-Monthly}"
MONTHLY_LOCALIZED_NAME="${MONTHLY_LOCALIZED_NAME:-Traxe Pro (Monthly)}"
MONTHLY_LOCALIZED_DESCRIPTION="${MONTHLY_LOCALIZED_DESCRIPTION:-Unlock the ability to manage more devices.}"
MONTHLY_PRICE_USD="${MONTHLY_PRICE_USD:-2.99}"
MONTHLY_PRICE_TERRITORY="${MONTHLY_PRICE_TERRITORY:-USA}"

MINERS_PRODUCT_ID="${MINERS_PRODUCT_ID:-miners_5}"
MINERS_REF_NAME="${MINERS_REF_NAME:-Miners_5}"
MINERS_LOCALIZED_NAME="${MINERS_LOCALIZED_NAME:-Traxe Pro (One-Time, 5 Miners)}"
MINERS_LOCALIZED_DESCRIPTION="${MINERS_LOCALIZED_DESCRIPTION:-Unlock the ability to add up to 5 miners.}"
MINERS_PRICE_USD="${MINERS_PRICE_USD:-9.99}"
MINERS_BASE_TERRITORY="${MINERS_BASE_TERRITORY:-USA}"

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

ensure_group_localization() {
  local locs_json
  local loc_id

  locs_json="$(asc subscriptions groups localizations list --group-id "${GROUP_ID}" --paginate --output json)"
  loc_id="$(printf '%s' "${locs_json}" | jq -r '
[
  .. | objects
  | select((.locale? // .attributes.locale? // "") == "en-US")
  | .id?
] | map(select(type == "string" and length > 0)) | .[0] // empty
')"

  if [[ -z "${loc_id}" ]]; then
    asc subscriptions groups localizations create \
      --group-id "${GROUP_ID}" \
      --locale "en-US" \
      --name "${GROUP_LOCALIZED_NAME}" \
      --output json >/dev/null
  else
    asc subscriptions groups localizations update \
      --id "${loc_id}" \
      --name "${GROUP_LOCALIZED_NAME}" \
      --output json >/dev/null
  fi
}

ensure_subscription_localization() {
  local subscription_id="$1"
  local loc_name="$2"
  local loc_description="$3"
  local locs_json
  local loc_id

  locs_json="$(asc subscriptions localizations list --subscription-id "${subscription_id}" --paginate --output json)"
  loc_id="$(printf '%s' "${locs_json}" | jq -r '
[
  .. | objects
  | select((.locale? // .attributes.locale? // "") == "en-US")
  | .id?
] | map(select(type == "string" and length > 0)) | .[0] // empty
')"

  if [[ -z "${loc_id}" ]]; then
    asc subscriptions localizations create \
      --subscription-id "${subscription_id}" \
      --locale "en-US" \
      --name "${loc_name}" \
      --description "${loc_description}" \
      --output json >/dev/null
  else
    asc subscriptions localizations update \
      --id "${loc_id}" \
      --name "${loc_name}" \
      --description "${loc_description}" \
      --output json >/dev/null
  fi
}

ensure_monthly_subscription() {
  local subs_json
  local subscription_id
  local created_json

  subs_json="$(asc subscriptions list --group-id "${GROUP_ID}" --paginate --output json)"
  subscription_id="$(resolve_subscription_id "${subs_json}" "${MONTHLY_PRODUCT_ID}")"

  if [[ -z "${subscription_id}" ]]; then
    created_json="$(asc subscriptions setup \
      --group-id "${GROUP_ID}" \
      --reference-name "${MONTHLY_REF_NAME}" \
      --product-id "${MONTHLY_PRODUCT_ID}" \
      --subscription-period ONE_MONTH \
      --locale "en-US" \
      --display-name "${MONTHLY_LOCALIZED_NAME}" \
      --description "${MONTHLY_LOCALIZED_DESCRIPTION}" \
      --price "${MONTHLY_PRICE_USD}" \
      --price-territory "${MONTHLY_PRICE_TERRITORY}" \
      --territories "${MONTHLY_PRICE_TERRITORY}" \
      --output json)"
    subscription_id="$(printf '%s' "${created_json}" | first_string_id)"
  fi

  if [[ -z "${subscription_id}" ]]; then
    echo "Failed to create/find monthly subscription." >&2
    exit 1
  fi

  ensure_subscription_localization \
    "${subscription_id}" \
    "${MONTHLY_LOCALIZED_NAME}" \
    "${MONTHLY_LOCALIZED_DESCRIPTION}"

  asc subscriptions pricing prices set \
    --subscription-id "${subscription_id}" \
    --price "${MONTHLY_PRICE_USD}" \
    --territory "${MONTHLY_PRICE_TERRITORY}" \
    --preserved \
    --output json >/dev/null

  printf '%s' "${subscription_id}"
}

ensure_iap_localization() {
  local iap_id="$1"
  local loc_name="$2"
  local loc_description="$3"
  local locs_json
  local loc_id

  locs_json="$(asc iap localizations list --iap-id "${iap_id}" --paginate --output json)"
  loc_id="$(printf '%s' "${locs_json}" | jq -r '
[
  .. | objects
  | select((.locale? // .attributes.locale? // "") == "en-US")
  | .id?
] | map(select(type == "string" and length > 0)) | .[0] // empty
')"

  if [[ -z "${loc_id}" ]]; then
    asc iap localizations create \
      --iap-id "${iap_id}" \
      --locale "en-US" \
      --name "${loc_name}" \
      --description "${loc_description}" \
      --output json >/dev/null
  else
    asc iap localizations update \
      --localization-id "${loc_id}" \
      --name "${loc_name}" \
      --description "${loc_description}" \
      --output json >/dev/null
  fi
}

ensure_miners_iap() {
  local iaps_json
  local iap_id
  local created_json

  iaps_json="$(asc iap list --app "${APP_ID}" --paginate --output json)"
  iap_id="$(resolve_iap_id "${iaps_json}" "${MINERS_PRODUCT_ID}")"

  if [[ -z "${iap_id}" ]]; then
    created_json="$(asc iap setup \
      --app "${APP_ID}" \
      --type NON_CONSUMABLE \
      --reference-name "${MINERS_REF_NAME}" \
      --product-id "${MINERS_PRODUCT_ID}" \
      --locale "en-US" \
      --display-name "${MINERS_LOCALIZED_NAME}" \
      --description "${MINERS_LOCALIZED_DESCRIPTION}" \
      --price "${MINERS_PRICE_USD}" \
      --base-territory "${MINERS_BASE_TERRITORY}" \
      --output json)"
    iap_id="$(printf '%s' "${created_json}" | first_string_id)"
  fi

  if [[ -z "${iap_id}" ]]; then
    echo "Failed to create/find Miners 5 IAP." >&2
    exit 1
  fi

  ensure_iap_localization \
    "${iap_id}" \
    "${MINERS_LOCALIZED_NAME}" \
    "${MINERS_LOCALIZED_DESCRIPTION}"

  printf '%s' "${iap_id}"
}

echo "==> Authenticating asc API key"
asc auth login \
  --name "${ASC_PROFILE_NAME}" \
  --key-id "${ASC_KEY_ID}" \
  --issuer-id "${ASC_ISSUER_ID}" \
  --private-key "${ASC_PRIVATE_KEY_PATH}" \
  --network >/dev/null

echo "==> Resolving App Store Connect app"
ASC_APPS_JSON="$(asc apps list --bundle-id "${BUNDLE_ID}" --paginate --output json)"
APP_ID="$(resolve_asc_app_id "${ASC_APPS_JSON}")"

if [[ -z "${APP_ID}" && "${CREATE_ASC_APP}" == "1" ]]; then
  APP_CREATE_JSON="$(asc apps create \
    --name "${APP_NAME}" \
    --bundle-id "${BUNDLE_ID}" \
    --sku "${APP_SKU}" \
    --primary-locale "${APP_PRIMARY_LOCALE}" \
    --platform IOS \
    --output json)"
  APP_ID="$(printf '%s' "${APP_CREATE_JSON}" | first_string_id)"
fi

if [[ -z "${APP_ID}" ]]; then
  echo "Could not resolve ASC app ID for ${BUNDLE_ID}." >&2
  exit 1
fi

echo "Resolved APP_ID=${APP_ID}"

echo "==> Ensuring subscription group"
GROUPS_JSON="$(asc subscriptions groups list --app "${APP_ID}" --paginate --output json)"
GROUP_ID="$(resolve_subscription_group_id "${GROUPS_JSON}")"
if [[ -z "${GROUP_ID}" ]]; then
  GROUP_CREATE_JSON="$(asc subscriptions groups create --app "${APP_ID}" --reference-name "${SUBSCRIPTION_GROUP_REF}" --output json)"
  GROUP_ID="$(printf '%s' "${GROUP_CREATE_JSON}" | first_string_id)"
fi

if [[ -z "${GROUP_ID}" ]]; then
  echo "Failed to create/find subscription group." >&2
  exit 1
fi

echo "Resolved GROUP_ID=${GROUP_ID}"

echo "==> Ensuring subscription group localization"
ensure_group_localization

echo "==> Ensuring monthly subscription"
MONTHLY_SUBSCRIPTION_ID="$(ensure_monthly_subscription)"
echo "Resolved MONTHLY_SUBSCRIPTION_ID=${MONTHLY_SUBSCRIPTION_ID}"

echo "==> Ensuring one-time IAP"
MINERS_IAP_ID="$(ensure_miners_iap)"
echo "Resolved MINERS_IAP_ID=${MINERS_IAP_ID}"
