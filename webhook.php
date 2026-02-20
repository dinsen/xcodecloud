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
    $pushStats = push_live_status_wake_notifications($db, $appId, $eventType);
    json_response(200, [
        'ok' => true,
        'event' => $eventType,
        'state' => 'running',
        'push' => $pushStats,
    ]);
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
    $pushStats = push_live_status_wake_notifications($db, $appId, $eventType);
    json_response(200, [
        'ok' => true,
        'event' => $eventType,
        'state' => 'completed',
        'push' => $pushStats,
    ]);
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
    $db->query("DELETE FROM xcc_device_subscriptions WHERE updated_at < (NOW() - INTERVAL 30 DAY)");
}

function push_live_status_wake_notifications(mysqli $db, string $appId, string $eventType): array
{
    $subscriptions = fetch_device_subscriptions($db, $appId);
    if ($subscriptions === []) {
        return ['attempted' => 0, 'sent' => 0, 'invalidTokensRemoved' => 0, 'skipped' => 'no subscriptions'];
    }

    $credentials = apns_credentials();
    if ($credentials === null) {
        return ['attempted' => 0, 'sent' => 0, 'invalidTokensRemoved' => 0, 'skipped' => 'missing APNS credentials'];
    }

    $status = fetch_running_status($db, $appId);
    $payload = [
        'aps' => [
            'content-available' => 1,
        ],
        'type' => 'live_status_wake',
        'appId' => $appId,
        'eventType' => $eventType,
        'buildsRunning' => $status['runningCount'] > 0,
        'runningCount' => $status['runningCount'],
        'singleBuildStartedAt' => $status['singleBuildStartedAt'],
        'checkedAt' => gmdate('c'),
    ];

    $attempted = 0;
    $sent = 0;
    $invalidTokensRemoved = 0;

    foreach ($subscriptions as $subscription) {
        $attempted++;

        $topic = (string) $subscription['app_bundle_id'];
        $token = (string) $subscription['device_token'];
        $subscriptionAppID = (string) $subscription['app_id'];
        $result = send_apns_background_notification($credentials, $topic, $token, $payload);

        if ($result['ok']) {
            $sent++;
            $stmt = $db->prepare(
                'UPDATE xcc_device_subscriptions
                 SET last_push_at = NOW(), updated_at = NOW()
                 WHERE device_token = ? AND app_id = ?'
            );
            if ($stmt) {
                $stmt->bind_param('ss', $token, $subscriptionAppID);
                $stmt->execute();
                $stmt->close();
            }
            continue;
        }

        if ($result['removeToken']) {
            $stmt = $db->prepare('DELETE FROM xcc_device_subscriptions WHERE device_token = ? AND app_id = ?');
            if ($stmt) {
                $stmt->bind_param('ss', $token, $subscriptionAppID);
                $stmt->execute();
                $stmt->close();
            }
            $invalidTokensRemoved++;
        }
    }

    return [
        'attempted' => $attempted,
        'sent' => $sent,
        'invalidTokensRemoved' => $invalidTokensRemoved,
    ];
}

function fetch_device_subscriptions(mysqli $db, string $appId): array
{
    $stmt = $db->prepare(
        'SELECT device_token, app_bundle_id, app_id
         FROM xcc_device_subscriptions
         WHERE app_id = ? OR app_id = "*"'
    );

    if (!$stmt) {
        return [];
    }

    $stmt->bind_param('s', $appId);
    $stmt->execute();
    $result = $stmt->get_result();

    $rows = [];
    if ($result) {
        while ($row = $result->fetch_assoc()) {
            if (is_array($row)) {
                $rows[] = $row;
            }
        }
    }

    $stmt->close();
    return $rows;
}

function fetch_running_status(mysqli $db, string $appId): array
{
    $stmt = $db->prepare(
        'SELECT
            COUNT(*) AS running_count,
            CASE WHEN COUNT(*) = 1 THEN MIN(started_at) ELSE NULL END AS single_build_started_at
         FROM xcc_running_builds
         WHERE app_id = ?'
    );

    if (!$stmt) {
        return ['runningCount' => 0, 'singleBuildStartedAt' => null];
    }

    $stmt->bind_param('s', $appId);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result ? $result->fetch_assoc() : null;
    $stmt->close();

    $count = (int) ($row['running_count'] ?? 0);
    $singleBuildStartedAt = mysql_datetime_to_iso8601($row['single_build_started_at'] ?? null);

    return [
        'runningCount' => $count,
        'singleBuildStartedAt' => $singleBuildStartedAt,
    ];
}

function apns_credentials(): ?array
{
    static $cached = null;
    static $loaded = false;

    if ($loaded) {
        return $cached;
    }

    $loaded = true;
    $teamId = trim((string) (getenv('APNS_TEAM_ID') ?: ''));
    $keyId = trim((string) (getenv('APNS_KEY_ID') ?: ''));
    $privateKeyPem = trim((string) (getenv('APNS_PRIVATE_KEY_PEM') ?: ''));
    $privateKeyPath = trim((string) (getenv('APNS_PRIVATE_KEY_PATH') ?: ''));

    if ($privateKeyPem === '' && $privateKeyPath !== '' && is_file($privateKeyPath)) {
        $fileContents = file_get_contents($privateKeyPath);
        if (is_string($fileContents)) {
            $privateKeyPem = trim($fileContents);
        }
    }

    if ($teamId === '' || $keyId === '' || $privateKeyPem === '') {
        $cached = null;
        return $cached;
    }

    $cached = [
        'teamId' => $teamId,
        'keyId' => $keyId,
        'privateKeyPem' => $privateKeyPem,
        'privateKeyPassphrase' => (string) (getenv('APNS_PRIVATE_KEY_PASSPHRASE') ?: ''),
        'host' => apns_host(),
    ];

    return $cached;
}

function apns_host(): string
{
    $sandbox = strtolower(trim((string) (getenv('APNS_USE_SANDBOX') ?: '')));
    if (in_array($sandbox, ['1', 'true', 'yes', 'on'], true)) {
        return 'https://api.sandbox.push.apple.com';
    }

    return 'https://api.push.apple.com';
}

function send_apns_background_notification(array $credentials, string $topic, string $deviceToken, array $payload): array
{
    $jwt = apns_jwt($credentials);
    if ($jwt === null) {
        return ['ok' => false, 'removeToken' => false];
    }

    $url = rtrim((string) $credentials['host'], '/') . '/3/device/' . rawurlencode($deviceToken);

    $ch = curl_init($url);
    if ($ch === false) {
        return ['ok' => false, 'removeToken' => false];
    }

    $body = json_encode($payload);
    if (!is_string($body)) {
        curl_close($ch);
        return ['ok' => false, 'removeToken' => false];
    }

    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_2_0,
        CURLOPT_HTTPHEADER => [
            'authorization: bearer ' . $jwt,
            'apns-topic: ' . $topic,
            'apns-push-type: background',
            'apns-priority: 5',
            'apns-expiration: 0',
            'content-type: application/json',
        ],
        CURLOPT_POSTFIELDS => $body,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 10,
    ]);

    $responseBody = curl_exec($ch);
    $statusCode = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);

    if ($statusCode === 200) {
        return ['ok' => true, 'removeToken' => false];
    }

    $reason = '';
    if (is_string($responseBody) && $responseBody !== '') {
        $decoded = json_decode($responseBody, true);
        if (is_array($decoded) && isset($decoded['reason']) && is_string($decoded['reason'])) {
            $reason = $decoded['reason'];
        }
    }

    $removeToken = in_array($reason, [
        'BadDeviceToken',
        'DeviceTokenNotForTopic',
        'Unregistered',
    ], true) || $statusCode === 410;

    return [
        'ok' => false,
        'removeToken' => $removeToken,
    ];
}

function apns_jwt(array $credentials): ?string
{
    static $cachedToken = null;
    static $cachedIssuedAt = 0;

    $now = time();
    if (is_string($cachedToken) && ($now - $cachedIssuedAt) < 50 * 60) {
        return $cachedToken;
    }

    $header = ['alg' => 'ES256', 'kid' => (string) $credentials['keyId']];
    $claims = ['iss' => (string) $credentials['teamId'], 'iat' => $now];

    $encodedHeader = base64url_encode((string) json_encode($header));
    $encodedClaims = base64url_encode((string) json_encode($claims));
    $unsignedToken = $encodedHeader . '.' . $encodedClaims;

    $privateKey = openssl_pkey_get_private(
        (string) $credentials['privateKeyPem'],
        (string) $credentials['privateKeyPassphrase']
    );

    if ($privateKey === false) {
        return null;
    }

    $signature = '';
    $signed = openssl_sign($unsignedToken, $signature, $privateKey, OPENSSL_ALGO_SHA256);
    if (is_resource($privateKey) || $privateKey instanceof OpenSSLAsymmetricKey) {
        openssl_free_key($privateKey);
    }

    if (!$signed || $signature === '') {
        return null;
    }

    $cachedToken = $unsignedToken . '.' . base64url_encode($signature);
    $cachedIssuedAt = $now;
    return $cachedToken;
}

function base64url_encode(string $value): string
{
    return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
}

function mysql_datetime_to_iso8601(mixed $value): ?string
{
    if (!is_string($value)) {
        return null;
    }

    $value = trim($value);
    if ($value === '') {
        return null;
    }

    try {
        $date = new DateTimeImmutable($value);
        return $date->format(DateTimeInterface::ATOM);
    } catch (Throwable) {
        return null;
    }
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
