# PHP Endpoints (mysqli)

## Files
- `schema.sql`: creates the minimal running-builds table.
- `webhook.php`: receives Xcode Cloud webhook events and keeps only active running builds.
- `status.php`: returns running build count (`buildsRunning`, `runningCount`, `checkedAt`).

## Environment Variables
- `DB_HOST` (default `127.0.0.1`)
- `DB_PORT` (default `3306`)
- `DB_USER`
- `DB_PASS`
- `DB_NAME`
- `XCC_WEBHOOK_SECRET` (optional but recommended)

## Notes
- `status.php` supports optional `?appId=<ASC_APP_ID>` to scope counts to one app.
- `webhook.php` verifies `x-apple-signature` using `HMAC-SHA256` when `XCC_WEBHOOK_SECRET` is set.
- Data retention is minimal: only currently running builds are stored.
