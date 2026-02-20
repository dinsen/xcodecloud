<?php
declare(strict_types=1);

require_once __DIR__ . '/config.php';

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    json_response(405, ['ok' => false, 'error' => 'method not allowed']);
}

$payload = read_json_body();
if ($payload === []) {
    json_response(400, ['ok' => false, 'error' => 'invalid json payload']);
}

$appId = trim((string) ($payload['appId'] ?? ''));
$deviceToken = strtolower(trim((string) ($payload['deviceToken'] ?? '')));
$appBundleId = trim((string) ($payload['appBundleId'] ?? ''));

if ($appId === '' || $appBundleId === '' || !preg_match('/^[a-f0-9]{64,200}$/', $deviceToken)) {
    json_response(422, ['ok' => false, 'error' => 'missing or invalid registration fields']);
}

$db = db_connect();
$stmt = $db->prepare(
    'INSERT INTO xcc_device_subscriptions (device_token, app_id, app_bundle_id, updated_at)
     VALUES (?, ?, ?, NOW())
     ON DUPLICATE KEY UPDATE
        app_bundle_id = VALUES(app_bundle_id),
        updated_at = NOW()'
);

if (!$stmt) {
    json_response(500, ['ok' => false, 'error' => 'query prepare failed']);
}

$stmt->bind_param('sss', $deviceToken, $appId, $appBundleId);
$stmt->execute();
$stmt->close();

$db->query("DELETE FROM xcc_device_subscriptions WHERE updated_at < (NOW() - INTERVAL 30 DAY)");

json_response(200, ['ok' => true]);
