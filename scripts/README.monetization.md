# CLI Monetization Setup (Audit-First ASC + RevenueCat)

Traxe now has the same repo-local monetization pattern as Pray:
1. Audit App Store Connect and RevenueCat drift without making changes
2. Apply changes only with explicit confirmation
3. Re-audit and fail if expected catalog state still does not match

This repo’s expected catalog is:
- one auto-renewable subscription group: `TraxePro`
- one monthly subscription: `com.matthewramsden.Traxe.Monthly`
- one non-consumable IAP: `miners_5`
- RevenueCat entitlements: `Pro`, `Miners_5`
- RevenueCat offering: `miners_5`

## Scripts

- `scripts/asc_rc_audit.sh`
- `scripts/setup_asc_catalog.sh`
- `scripts/setup_revenuecat_v2.sh`
- `scripts/setup_monetization.sh`

## Required env vars

```bash
export ASC_KEY_ID="YOUR_ASC_KEY_ID"
export ASC_ISSUER_ID="YOUR_ASC_ISSUER_ID"
export ASC_PRIVATE_KEY_PATH="/absolute/path/to/AuthKey_XXXX.p8"

export RC_API_V2_SECRET_KEY="YOUR_RC_API_V2_SECRET_KEY"
```

## Useful defaults

```bash
export BUNDLE_ID="com.matthewramsden.Traxe"
export SUBSCRIPTION_GROUP_REF="TraxePro"
export MONTHLY_PRODUCT_ID="com.matthewramsden.Traxe.Monthly"
export MINERS_PRODUCT_ID="miners_5"

export RC_PROJECT_NAME="Traxe"
export RC_OFFERING_LOOKUP="miners_5"
export RC_PRO_ENTITLEMENT_LOOKUP="Pro"
export RC_MINERS_ENTITLEMENT_LOOKUP="Miners_5"
export RC_MONTHLY_PACKAGE_LOOKUP="monthly"
export RC_ONE_TIME_PACKAGE_LOOKUP="miners_5"
```

## Audit only

```bash
cd /Users/matthewramsden/Developer/Traxe
./scripts/setup_monetization.sh
```

## Apply mode

```bash
cd /Users/matthewramsden/Developer/Traxe
CONFIRM_APPLY=1 MONETIZATION_MODE=apply ./scripts/setup_monetization.sh
```

This runs:
1. pre-apply audit
2. ASC catalog setup
3. RevenueCat setup
4. strict post-apply audit

## Strict audit

```bash
cd /Users/matthewramsden/Developer/Traxe
STRICT_AUDIT=1 MONETIZATION_MODE=audit ./scripts/setup_monetization.sh
```

## Optional validator gates

`asc validate subscriptions` currently warns if the monthly subscription is missing a promotional image. If you want those warnings to fail the audit too:

```bash
cd /Users/matthewramsden/Developer/Traxe
STRICT_AUDIT=1 SUBSCRIPTION_VALIDATION_STRICT=1 MONETIZATION_MODE=audit ./scripts/setup_monetization.sh
```

The same pattern exists for IAP warnings:

```bash
cd /Users/matthewramsden/Developer/Traxe
STRICT_AUDIT=1 IAP_VALIDATION_STRICT=1 MONETIZATION_MODE=audit ./scripts/setup_monetization.sh
```

## Notes

- Scripts are intended to be safe to re-run.
- ASC app creation remains optional and only matters if the app record does not exist yet.
- The built-in validators cover App Store review readiness; the custom audit covers the expected Traxe catalog shape across ASC and RevenueCat.
- Audit report output defaults to `/tmp/traxe_monetization_audit.json`.
