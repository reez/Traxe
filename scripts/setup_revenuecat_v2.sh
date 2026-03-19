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

first_id_with_prefix() {
  local prefix="$1"
  jq -r --arg prefix "$prefix" '
[
  .. | objects
  | .id?
  | select(type == "string" and startswith($prefix))
] | .[0] // empty
'
}

require_cmd curl
require_cmd jq

require_env RC_API_V2_SECRET_KEY

RC_BASE_URL="${RC_BASE_URL:-https://api.revenuecat.com/v2}"

BUNDLE_ID="${BUNDLE_ID:-com.matthewramsden.Traxe}"
RC_PROJECT_NAME="${RC_PROJECT_NAME:-Traxe}"
RC_PROJECT_ID="${RC_PROJECT_ID:-}"
RC_APP_NAME="${RC_APP_NAME:-Traxe iOS}"
RC_APP_ID="${RC_APP_ID:-}"

MONTHLY_PRODUCT_ID="${MONTHLY_PRODUCT_ID:-com.matthewramsden.Traxe.Monthly}"
MONTHLY_DISPLAY_NAME="${MONTHLY_DISPLAY_NAME:-Traxe Pro (Monthly)}"
MINERS_PRODUCT_ID="${MINERS_PRODUCT_ID:-miners_5}"
MINERS_DISPLAY_NAME="${MINERS_DISPLAY_NAME:-Traxe Pro (One-Time, 5 Miners)}"

RC_PRO_ENTITLEMENT_LOOKUP="${RC_PRO_ENTITLEMENT_LOOKUP:-Pro}"
RC_PRO_ENTITLEMENT_DISPLAY="${RC_PRO_ENTITLEMENT_DISPLAY:-Traxe Pro}"
RC_MINERS_ENTITLEMENT_LOOKUP="${RC_MINERS_ENTITLEMENT_LOOKUP:-Miners_5}"
RC_MINERS_ENTITLEMENT_DISPLAY="${RC_MINERS_ENTITLEMENT_DISPLAY:-5 Miners Unlock}"

RC_OFFERING_LOOKUP="${RC_OFFERING_LOOKUP:-miners_5}"
RC_OFFERING_DISPLAY="${RC_OFFERING_DISPLAY:-Traxe Plans}"
RC_MONTHLY_PACKAGE_LOOKUP="${RC_MONTHLY_PACKAGE_LOOKUP:-monthly}"
RC_MONTHLY_PACKAGE_DISPLAY="${RC_MONTHLY_PACKAGE_DISPLAY:-Monthly}"
RC_ONE_TIME_PACKAGE_LOOKUP="${RC_ONE_TIME_PACKAGE_LOOKUP:-miners_5}"
RC_ONE_TIME_PACKAGE_DISPLAY="${RC_ONE_TIME_PACKAGE_DISPLAY:-One-Time}"

api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local tmp
  local status

  tmp="$(mktemp)"
  if [[ -n "${body}" ]]; then
    status="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "Authorization: Bearer ${RC_API_V2_SECRET_KEY}" \
      -H "Content-Type: application/json" \
      "${RC_BASE_URL}${path}" \
      --data "${body}")"
  else
    status="$(curl -sS -o "${tmp}" -w "%{http_code}" \
      -X "${method}" \
      -H "Authorization: Bearer ${RC_API_V2_SECRET_KEY}" \
      "${RC_BASE_URL}${path}")"
  fi

  if [[ "${status}" -lt 200 || "${status}" -ge 300 ]]; then
    echo "RevenueCat API error: ${method} ${path} -> HTTP ${status}" >&2
    cat "${tmp}" >&2
    rm -f "${tmp}"
    exit 1
  fi

  cat "${tmp}"
  rm -f "${tmp}"
}

find_project_id_by_name() {
  local name="$1"
  local json="$2"

  printf '%s' "${json}" | jq -r --arg name "${name}" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("proj")))
  | select((.name? // "") == $name)
  | .id
] | .[0] // empty
'
}

find_app_id_by_bundle() {
  local bundle="$1"
  local json="$2"

  printf '%s' "${json}" | jq -r --arg bundle "${bundle}" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("app")))
  | select((.app_store.bundle_id? // .bundle_id? // .appStore.bundleId? // "") == $bundle)
  | .id
] | .[0] // empty
'
}

find_product_id_by_store_identifier() {
  local store_identifier="$1"
  local json="$2"

  printf '%s' "${json}" | jq -r --arg sid "${store_identifier}" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("prod")))
  | select((.store_identifier? // .storeIdentifier? // "") == $sid)
  | .id
] | .[0] // empty
'
}

find_entitlement_id_by_lookup() {
  local lookup="$1"
  local json="$2"

  printf '%s' "${json}" | jq -r --arg lookup "$lookup" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("entl")))
  | select((.lookup_key? // .lookupKey? // "") == $lookup)
  | .id
] | .[0] // empty
'
}

find_offering_id_by_lookup() {
  local lookup="$1"
  local json="$2"

  printf '%s' "${json}" | jq -r --arg lookup "$lookup" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("ofrn")))
  | select((.lookup_key? // .lookupKey? // "") == $lookup)
  | .id
] | .[0] // empty
'
}

find_package_id_by_lookup() {
  local lookup="$1"
  local json="$2"

  printf '%s' "${json}" | jq -r --arg lookup "$lookup" '
[
  .. | objects
  | select((.id? | type == "string") and (.id | startswith("pkg")))
  | select((.lookup_key? // .lookupKey? // "") == $lookup)
  | .id
] | .[0] // empty
'
}

list_entitlement_products() {
  local entitlement_id="$1"
  api GET "/projects/${RC_PROJECT_ID}/entitlements/${entitlement_id}/products"
}

list_package_products() {
  local package_id="$1"
  api GET "/projects/${RC_PROJECT_ID}/packages/${package_id}/products"
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

ensure_product() {
  local store_identifier="$1"
  local display_name="$2"
  local product_type="$3"
  local products_json
  local product_id
  local payload
  local created_json

  products_json="$(api GET "/projects/${RC_PROJECT_ID}/products?app_id=${RC_APP_ID}")"
  product_id="$(find_product_id_by_store_identifier "${store_identifier}" "${products_json}")"

  if [[ -z "${product_id}" ]]; then
    payload="$(jq -nc \
      --arg sid "${store_identifier}" \
      --arg app_id "${RC_APP_ID}" \
      --arg type "${product_type}" \
      --arg display "${display_name}" \
      '{store_identifier: $sid, app_id: $app_id, type: $type, display_name: $display}')"
    created_json="$(api POST "/projects/${RC_PROJECT_ID}/products" "${payload}")"
    product_id="$(printf '%s' "${created_json}" | first_id_with_prefix "prod")"
  fi

  if [[ -z "${product_id}" ]]; then
    echo "Failed to create/find RevenueCat product for ${store_identifier}" >&2
    exit 1
  fi

  printf '%s' "${product_id}"
}

ensure_entitlement() {
  local lookup="$1"
  local display_name="$2"
  local entitlements_json
  local entitlement_id
  local payload
  local created_json

  entitlements_json="$(api GET "/projects/${RC_PROJECT_ID}/entitlements")"
  entitlement_id="$(find_entitlement_id_by_lookup "${lookup}" "${entitlements_json}")"

  if [[ -z "${entitlement_id}" ]]; then
    payload="$(jq -nc --arg lookup "${lookup}" --arg display "${display_name}" '{lookup_key: $lookup, display_name: $display}')"
    created_json="$(api POST "/projects/${RC_PROJECT_ID}/entitlements" "${payload}")"
    entitlement_id="$(printf '%s' "${created_json}" | first_id_with_prefix "entl")"
  fi

  if [[ -z "${entitlement_id}" ]]; then
    echo "Failed to create/find entitlement ${lookup}" >&2
    exit 1
  fi

  printf '%s' "${entitlement_id}"
}

ensure_entitlement_attached_product() {
  local entitlement_id="$1"
  local product_id="$2"
  local existing_json
  local attached
  local payload

  existing_json="$(list_entitlement_products "${entitlement_id}")"
  attached="$(json_contains_product_id "${existing_json}" "${product_id}")"

  if [[ "${attached}" != "true" ]]; then
    payload="$(jq -nc --arg pid "${product_id}" '{product_ids: [$pid]}')"
    api POST "/projects/${RC_PROJECT_ID}/entitlements/${entitlement_id}/actions/attach_products" "${payload}" >/dev/null
  fi
}

ensure_package() {
  local offering_id="$1"
  local lookup="$2"
  local display_name="$3"
  local position="$4"
  local packages_json
  local package_id
  local payload
  local created_json

  packages_json="$(api GET "/projects/${RC_PROJECT_ID}/offerings/${offering_id}/packages")"
  package_id="$(find_package_id_by_lookup "${lookup}" "${packages_json}")"

  if [[ -z "${package_id}" ]]; then
    payload="$(jq -nc \
      --arg lookup "${lookup}" \
      --arg display "${display_name}" \
      --argjson position "${position}" \
      '{lookup_key: $lookup, display_name: $display, position: $position}')"
    created_json="$(api POST "/projects/${RC_PROJECT_ID}/offerings/${offering_id}/packages" "${payload}")"
    package_id="$(printf '%s' "${created_json}" | first_id_with_prefix "pkg")"
  fi

  if [[ -z "${package_id}" ]]; then
    echo "Failed to create/find package ${lookup}" >&2
    exit 1
  fi

  printf '%s' "${package_id}"
}

ensure_package_attached_product() {
  local package_id="$1"
  local product_id="$2"
  local existing_json
  local attached
  local payload

  existing_json="$(list_package_products "${package_id}")"
  attached="$(json_contains_product_id "${existing_json}" "${product_id}")"

  if [[ "${attached}" != "true" ]]; then
    payload="$(jq -nc --arg pid "${product_id}" '{products: [{product_id: $pid, eligibility_criteria: "all"}]}')"
    api POST "/projects/${RC_PROJECT_ID}/packages/${package_id}/actions/attach_products" "${payload}" >/dev/null
  fi
}

echo "==> Resolving RevenueCat project"
if [[ -z "${RC_PROJECT_ID}" ]]; then
  PROJECTS_JSON="$(api GET "/projects")"
  RC_PROJECT_ID="$(find_project_id_by_name "${RC_PROJECT_NAME}" "${PROJECTS_JSON}")"
  if [[ -z "${RC_PROJECT_ID}" ]]; then
    CREATE_PROJECT_PAYLOAD="$(jq -nc --arg name "${RC_PROJECT_NAME}" '{name: $name}')"
    PROJECT_CREATED_JSON="$(api POST "/projects" "${CREATE_PROJECT_PAYLOAD}")"
    RC_PROJECT_ID="$(printf '%s' "${PROJECT_CREATED_JSON}" | first_id_with_prefix "proj")"
  fi
fi

if [[ -z "${RC_PROJECT_ID}" ]]; then
  echo "Failed to resolve RevenueCat project." >&2
  exit 1
fi

echo "Resolved RC_PROJECT_ID=${RC_PROJECT_ID}"

echo "==> Resolving RevenueCat app"
if [[ -z "${RC_APP_ID}" ]]; then
  APPS_JSON="$(api GET "/projects/${RC_PROJECT_ID}/apps")"
  RC_APP_ID="$(find_app_id_by_bundle "${BUNDLE_ID}" "${APPS_JSON}")"
  if [[ -z "${RC_APP_ID}" ]]; then
    CREATE_APP_PAYLOAD="$(jq -nc \
      --arg name "${RC_APP_NAME}" \
      --arg bundle "${BUNDLE_ID}" \
      '{name: $name, type: "app_store", app_store: {bundle_id: $bundle}}')"
    APP_CREATED_JSON="$(api POST "/projects/${RC_PROJECT_ID}/apps" "${CREATE_APP_PAYLOAD}")"
    RC_APP_ID="$(printf '%s' "${APP_CREATED_JSON}" | first_id_with_prefix "app")"
  fi
fi

if [[ -z "${RC_APP_ID}" ]]; then
  echo "Failed to resolve RevenueCat app." >&2
  exit 1
fi

echo "Resolved RC_APP_ID=${RC_APP_ID}"

echo "==> Ensuring RevenueCat products"
RC_MONTHLY_PRODUCT_INTERNAL_ID="$(ensure_product "${MONTHLY_PRODUCT_ID}" "${MONTHLY_DISPLAY_NAME}" "subscription")"
RC_MINERS_PRODUCT_INTERNAL_ID="$(ensure_product "${MINERS_PRODUCT_ID}" "${MINERS_DISPLAY_NAME}" "non_consumable")"
echo "Resolved RC_MONTHLY_PRODUCT_INTERNAL_ID=${RC_MONTHLY_PRODUCT_INTERNAL_ID}"
echo "Resolved RC_MINERS_PRODUCT_INTERNAL_ID=${RC_MINERS_PRODUCT_INTERNAL_ID}"

echo "==> Ensuring RevenueCat entitlements"
RC_PRO_ENTITLEMENT_ID="$(ensure_entitlement "${RC_PRO_ENTITLEMENT_LOOKUP}" "${RC_PRO_ENTITLEMENT_DISPLAY}")"
RC_MINERS_ENTITLEMENT_ID="$(ensure_entitlement "${RC_MINERS_ENTITLEMENT_LOOKUP}" "${RC_MINERS_ENTITLEMENT_DISPLAY}")"
echo "Resolved RC_PRO_ENTITLEMENT_ID=${RC_PRO_ENTITLEMENT_ID}"
echo "Resolved RC_MINERS_ENTITLEMENT_ID=${RC_MINERS_ENTITLEMENT_ID}"

echo "==> Attaching products to entitlements"
ensure_entitlement_attached_product "${RC_PRO_ENTITLEMENT_ID}" "${RC_MONTHLY_PRODUCT_INTERNAL_ID}"
ensure_entitlement_attached_product "${RC_MINERS_ENTITLEMENT_ID}" "${RC_MINERS_PRODUCT_INTERNAL_ID}"

echo "==> Ensuring offering"
OFFERINGS_JSON="$(api GET "/projects/${RC_PROJECT_ID}/offerings")"
RC_OFFERING_ID="$(find_offering_id_by_lookup "${RC_OFFERING_LOOKUP}" "${OFFERINGS_JSON}")"
if [[ -z "${RC_OFFERING_ID}" ]]; then
  CREATE_OFFERING_PAYLOAD="$(jq -nc --arg lookup "${RC_OFFERING_LOOKUP}" --arg display "${RC_OFFERING_DISPLAY}" '{lookup_key: $lookup, display_name: $display}')"
  OFFERING_CREATED_JSON="$(api POST "/projects/${RC_PROJECT_ID}/offerings" "${CREATE_OFFERING_PAYLOAD}")"
  RC_OFFERING_ID="$(printf '%s' "${OFFERING_CREATED_JSON}" | first_id_with_prefix "ofrn")"
fi

if [[ -z "${RC_OFFERING_ID}" ]]; then
  echo "Failed to resolve RevenueCat offering." >&2
  exit 1
fi

echo "Resolved RC_OFFERING_ID=${RC_OFFERING_ID}"

echo "==> Setting current offering"
api POST "/projects/${RC_PROJECT_ID}/offerings/${RC_OFFERING_ID}" '{"is_current":true}' >/dev/null

echo "==> Ensuring packages"
RC_MONTHLY_PACKAGE_ID="$(ensure_package "${RC_OFFERING_ID}" "${RC_MONTHLY_PACKAGE_LOOKUP}" "${RC_MONTHLY_PACKAGE_DISPLAY}" 1)"
RC_ONE_TIME_PACKAGE_ID="$(ensure_package "${RC_OFFERING_ID}" "${RC_ONE_TIME_PACKAGE_LOOKUP}" "${RC_ONE_TIME_PACKAGE_DISPLAY}" 2)"
echo "Resolved RC_MONTHLY_PACKAGE_ID=${RC_MONTHLY_PACKAGE_ID}"
echo "Resolved RC_ONE_TIME_PACKAGE_ID=${RC_ONE_TIME_PACKAGE_ID}"

echo "==> Attaching products to packages"
ensure_package_attached_product "${RC_MONTHLY_PACKAGE_ID}" "${RC_MONTHLY_PRODUCT_INTERNAL_ID}"
ensure_package_attached_product "${RC_ONE_TIME_PACKAGE_ID}" "${RC_MINERS_PRODUCT_INTERNAL_ID}"

echo "==> Fetching iOS public API key"
PUBLIC_KEYS_JSON="$(api GET "/projects/${RC_PROJECT_ID}/apps/${RC_APP_ID}/public_api_keys")"
IOS_PUBLIC_API_KEY="$(printf '%s' "${PUBLIC_KEYS_JSON}" | jq -r '
[
  .. | objects
  | select((.environment? // "") == "production")
  | (.key? // empty)
  | select(type == "string" and startswith("appl_"))
] | .[0] // empty
')"

if [[ -n "${IOS_PUBLIC_API_KEY}" ]]; then
  echo "IOS_PUBLIC_API_KEY=${IOS_PUBLIC_API_KEY}"
else
  echo "No production iOS public key found yet for app ${RC_APP_ID}." >&2
fi

echo
echo "RevenueCat setup complete"
echo "RC_PROJECT_ID=${RC_PROJECT_ID}"
echo "RC_APP_ID=${RC_APP_ID}"
echo "RC_OFFERING_ID=${RC_OFFERING_ID}"
echo "RC_MONTHLY_PRODUCT_INTERNAL_ID=${RC_MONTHLY_PRODUCT_INTERNAL_ID}"
echo "RC_MINERS_PRODUCT_INTERNAL_ID=${RC_MINERS_PRODUCT_INTERNAL_ID}"
echo "RC_PRO_ENTITLEMENT_ID=${RC_PRO_ENTITLEMENT_ID}"
echo "RC_MINERS_ENTITLEMENT_ID=${RC_MINERS_ENTITLEMENT_ID}"
echo "RC_MONTHLY_PACKAGE_ID=${RC_MONTHLY_PACKAGE_ID}"
echo "RC_ONE_TIME_PACKAGE_ID=${RC_ONE_TIME_PACKAGE_ID}"
