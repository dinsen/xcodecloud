<?php
declare(strict_types=1);

function db_connect(): mysqli
{
    $host = getenv('DB_HOST') ?: '127.0.0.1';
    $user = getenv('DB_USER') ?: '';
    $pass = getenv('DB_PASS') ?: '';
    $name = getenv('DB_NAME') ?: '';
    $port = (int) (getenv('DB_PORT') ?: '3306');

    $db = new mysqli($host, $user, $pass, $name, $port);
    if ($db->connect_errno) {
        http_response_code(500);
        header('Content-Type: application/json');
        echo json_encode([
            'ok' => false,
            'error' => 'database connection failed',
        ]);
        exit;
    }

    $db->set_charset('utf8mb4');
    return $db;
}

function json_response(int $statusCode, array $payload): void
{
    http_response_code($statusCode);
    header('Content-Type: application/json');
    echo json_encode($payload);
    exit;
}

function read_json_body(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || $raw === '') {
        return [];
    }

    try {
        $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        return is_array($decoded) ? $decoded : [];
    } catch (Throwable) {
        return [];
    }
}
