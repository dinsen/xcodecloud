CREATE TABLE IF NOT EXISTS xcc_running_builds (
  build_id VARCHAR(128) NOT NULL PRIMARY KEY,
  app_id VARCHAR(128) NOT NULL,
  workflow_id VARCHAR(128) NULL,
  started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_app_id (app_id),
  KEY idx_updated_at (updated_at)
);

CREATE TABLE IF NOT EXISTS xcc_device_subscriptions (
  device_token VARCHAR(255) NOT NULL,
  app_id VARCHAR(128) NOT NULL,
  app_bundle_id VARCHAR(255) NOT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_push_at DATETIME NULL,
  PRIMARY KEY (device_token, app_id),
  KEY idx_device_subscriptions_app_id (app_id),
  KEY idx_device_subscriptions_updated_at (updated_at)
);
