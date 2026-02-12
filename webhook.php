<?php
declare(strict_types=1);

require_once __DIR__ . '/config.php';

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    json_response(405, ['ok' => false, 'error' => 'method not allowed']);
}

$rawBody = file_get_contents('php://input');
if ($rawBody === false || $rawBody === '') {
    json_response(400, ['ok' => false, 'error' => 'empty payload']);
}

$secret = (string) (getenv('XCC_WEBHOOK_SECRET') ?: '');
if ($secret !== '' && !verify_signature($rawBody, $secret)) {
    json_response(401, ['ok' => false, 'error' => 'invalid signature']);
}

$payload = read_json_body();
if ($payload === []) {
    json_response(400, ['ok' => false, 'error' => 'invalid json payload']);
}

$eventType = event_type($payload);
$buildId = value_at($payload, ['ciBuildRun', 'id']) ?? value_at($payload, ['data', 'id']);
$appId = value_at($payload, ['app', 'id']) ?? value_at($payload, ['data', 'relationships', 'app', 'data', 'id']);
$workflowId = value_at($payload, ['ciWorkflow', 'id']) ?? value_at($payload, ['data', 'relationships', 'ciWorkflow', 'data', 'id']);

if ($eventType === '' || $buildId === '' || $appId === '') {
    json_response(422, ['ok' => false, 'error' => 'missing event fields']);
}

$db = db_connect();

if (is_build_started_event($eventType)) {
    $stmt = $db->prepare(
        'INSERT INTO xcc_running_builds (build_id, app_id, workflow_id, started_at, updated_at)
         VALUES (?, ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE
            app_id = VALUES(app_id),
            workflow_id = VALUES(workflow_id),
            updated_at = NOW()'
    );
    if (!$stmt) {
        json_response(500, ['ok' => false, 'error' => 'query prepare failed']);
    }
    $stmt->bind_param('sss', $buildId, $appId, $workflowId);
    $stmt->execute();
    $stmt->close();

    cleanup_stale_rows($db);
    json_response(200, ['ok' => true, 'event' => $eventType, 'state' => 'running']);
}

if (is_build_finished_event($eventType)) {
    $stmt = $db->prepare('DELETE FROM xcc_running_builds WHERE build_id = ?');
    if (!$stmt) {
        json_response(500, ['ok' => false, 'error' => 'query prepare failed']);
    }
    $stmt->bind_param('s', $buildId);
    $stmt->execute();
    $stmt->close();

    cleanup_stale_rows($db);
    json_response(200, ['ok' => true, 'event' => $eventType, 'state' => 'completed']);
}

json_response(204, ['ok' => true, 'event' => $eventType, 'ignored' => true]);

function verify_signature(string $rawBody, string $secret): bool
{
    $header = (string) ($_SERVER['HTTP_X_APPLE_SIGNATURE'] ?? '');
    if ($header === '') {
        return false;
    }

    $prefix = 'hmacsha256=';
    if (stripos($header, $prefix) === 0) {
        $header = substr($header, strlen($prefix));
    }

    $expected = hash_hmac('sha256', $rawBody, $secret);
    return hash_equals(strtolower($expected), strtolower(trim($header)));
}

function event_type(array $payload): string
{
    $event = value_at($payload, ['metadata', 'attributes', 'eventType'])
        ?? value_at($payload, ['data', 'type'])
        ?? '';

    return strtoupper((string) $event);
}

function is_build_started_event(string $eventType): bool
{
    return in_array($eventType, [
        'BUILD_CREATED',
        'BUILD_STARTED',
    ], true);
}

function is_build_finished_event(string $eventType): bool
{
    return in_array($eventType, [
        'BUILD_COMPLETED',
        'BUILD_FAILED',
        'BUILD_CANCELED',
    ], true);
}

function cleanup_stale_rows(mysqli $db): void
{
    $db->query("DELETE FROM xcc_running_builds WHERE updated_at < (NOW() - INTERVAL 12 HOUR)");
}

function value_at(array $payload, array $path): ?string
{
    $cursor = $payload;
    foreach ($path as $segment) {
        if (!is_array($cursor) || !array_key_exists($segment, $cursor)) {
            return null;
        }
        $cursor = $cursor[$segment];
    }

    if (!is_scalar($cursor)) {
        return null;
    }

    $value = trim((string) $cursor);
    return $value === '' ? null : $value;
}
