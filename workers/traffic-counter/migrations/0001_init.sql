CREATE TABLE IF NOT EXISTS daily_counts (
  app TEXT NOT NULL,
  date TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (app, date)
);

CREATE TABLE IF NOT EXISTS client_cooldowns (
  app TEXT NOT NULL,
  date TEXT NOT NULL,
  client_key TEXT NOT NULL,
  last_counted_at INTEGER NOT NULL,
  PRIMARY KEY (app, date, client_key)
);

CREATE INDEX IF NOT EXISTS idx_client_cooldowns_date
  ON client_cooldowns (app, date);
