# PHP Endpoints (mysqli)

## Files
- `schema.sql`: creates the minimal running-builds table.
- `webhook.php`: receives Xcode Cloud webhook events and keeps only active running builds.
- `status.php`: returns running build status (`buildsRunning`, `runningCount`, optional `singleBuildStartedAt`, `checkedAt`).
- `register_device.php`: stores iOS device tokens by monitored App Store Connect app ID.

## Environment Variables
- `DB_HOST` (default `127.0.0.1`)
- `DB_PORT` (default `3306`)
- `DB_USER`
- `DB_PASS`
- `DB_NAME`
- `XCC_WEBHOOK_SECRET` (optional but recommended)
- `APNS_TEAM_ID` (required for wake push delivery)
- `APNS_KEY_ID` (required for wake push delivery)
- `APNS_PRIVATE_KEY_PEM` (contents of `.p8` key) or `APNS_PRIVATE_KEY_PATH` (path to `.p8`)
- `APNS_PRIVATE_KEY_PASSPHRASE` (optional)
- `APNS_USE_SANDBOX` (`true`/`1` for development push environment)

## Notes
- `status.php` supports optional `?appId=<ASC_APP_ID>` to scope counts to one app.
- `webhook.php` verifies `x-apple-signature` using `HMAC-SHA256` when `XCC_WEBHOOK_SECRET` is set.
- `register_device.php` expects JSON body: `{ "appId": "...", "deviceToken": "...", "appBundleId": "..." }`.
- `webhook.php` now pushes background APNs notifications to wake iOS, so the app can refresh live status and start/update Live Activity even when closed.
- Data retention is minimal: currently running builds plus recent device subscriptions.
