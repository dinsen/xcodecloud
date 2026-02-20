<?php
declare(strict_types=1);

require_once __DIR__ . '/config.php';

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    json_response(405, ['ok' => false, 'error' => 'method not allowed']);
}

$appId = trim((string) ($_GET['appId'] ?? ''));
$db = db_connect();

if ($appId !== '') {
    $stmt = $db->prepare(
        'SELECT
            COUNT(*) AS running_count,
            CASE WHEN COUNT(*) = 1 THEN MIN(started_at) ELSE NULL END AS single_build_started_at
         FROM xcc_running_builds
         WHERE app_id = ?'
    );
    if (!$stmt) {
        json_response(500, ['ok' => false, 'error' => 'query prepare failed']);
    }
    $stmt->bind_param('s', $appId);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result ? $result->fetch_assoc() : null;
    $count = (int) ($row['running_count'] ?? 0);
    $stmt->close();
} else {
    $result = $db->query(
        'SELECT
            COUNT(*) AS running_count,
            CASE WHEN COUNT(*) = 1 THEN MIN(started_at) ELSE NULL END AS single_build_started_at
         FROM xcc_running_builds'
    );
    if (!$result) {
        json_response(500, ['ok' => false, 'error' => 'query failed']);
    }
    $row = $result->fetch_assoc();
    $count = (int) ($row['running_count'] ?? 0);
}

$singleBuildStartedAt = mysql_datetime_to_iso8601($row['single_build_started_at'] ?? null);

json_response(200, [
    'buildsRunning' => $count > 0,
    'runningCount' => $count,
    'singleBuildStartedAt' => $singleBuildStartedAt,
    'checkedAt' => gmdate('c'),
]);

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
