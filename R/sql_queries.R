sql_queries <- list()

# --- TABLE INITIALIZATION ---
sql_queries$init_table_urls <- "
  CREATE TABLE IF NOT EXISTS urls (
    url          TEXT PRIMARY KEY,
    level        INTEGER DEFAULT 1,
    added_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )"

sql_queries$init_table_results <- "
  CREATE TABLE IF NOT EXISTS results (
    url                 TEXT NOT NULL,
    url_actual          TEXT,
    url_redirect        TEXT,
    status              TEXT NOT NULL CHECK (status IN ('todo', 'success', 'failed_domain', 'failed_scraping', 'blocked')),
    file_path           TEXT,
    robotscheck_allowed BOOLEAN DEFAULT TRUE,
    scraped_at          TIMESTAMP,
    PRIMARY KEY (url, status)
  )"

sql_queries$init_table_logs <- "
  CREATE TABLE IF NOT EXISTS logs (
    progress_time TIMESTAMP,
    chunk_id      INTEGER,
    url           TEXT,
    PRIMARY KEY (progress_time, url)
  )"

sql_queries$init_table_robots <- "
  CREATE TABLE IF NOT EXISTS robots (
    domain      TEXT PRIMARY KEY,
    permissions TEXT
  )"

# --- VIEWS & TEMPORARY OPERATIONS ---
# View joining results with parquet data for full content access
sql_queries$view_full_results_data <- "
  CREATE OR REPLACE VIEW full_results AS
  SELECT
    r.url,
    r.status,
    r.url_redirect,
    p.src,
    p.links,
    r.scraped_at
  FROM results r
  LEFT JOIN '{data_dir}/*.parquet' p
    ON RTRIM(r.url, '/') = RTRIM(p.url, '/')
    AND r.scraped_at = p.scraped_at"

# Placeholder view for empty states
sql_queries$view_full_results_empty <- "
  CREATE OR REPLACE VIEW full_results AS
  SELECT url, status, url_redirect, CAST(NULL AS TEXT) AS src, scraped_at
  FROM results
  WHERE 1=0"

# View providing link-level mapping
sql_queries$view_link_data <- "
  CREATE OR REPLACE VIEW links AS
  SELECT
    r.url AS source_url,
    RTRIM(unnest(p.links).href, '/') AS target_url,
    unnest(p.links).label AS label,
    r.scraped_at
  FROM results r
  JOIN '{data_dir}/*.parquet' p
    ON RTRIM(r.url, '/') = RTRIM(p.url, '/')
    AND r.scraped_at = p.scraped_at
  WHERE r.status = 'success'"

sql_queries$view_link_data_empty <- "
  CREATE OR REPLACE VIEW links AS
  SELECT
    CAST(NULL AS TEXT) AS source_url,
    CAST(NULL AS TEXT) AS target_url,
    CAST(NULL AS TEXT) AS label,
    CAST(NULL AS TIMESTAMP) AS scraped_at
  WHERE 1=0"

# --- CLEANUP OPERATIONS ---
sql_queries$drop_tmp_logs_table    <- "DROP TABLE IF EXISTS tmp_logs"
sql_queries$drop_tmp_status_update <- "DROP TABLE IF EXISTS tmp_status_update"
sql_queries$drop_tmp_urls          <- "DROP TABLE IF EXISTS tmp_urls"

# --- DATA RETRIEVAL ---
sql_queries$get_scraped_urls    <- "SELECT url, url_actual, status FROM results WHERE status = 'success'"
sql_queries$get_todo_urls       <- "SELECT DISTINCT url FROM results WHERE status = 'todo'"
sql_queries$get_robots_existing <- "SELECT domain FROM robots"
sql_queries$get_robots_todo     <- "SELECT domain, permissions FROM robots WHERE domain IN (SELECT DISTINCT domain FROM results WHERE status = 'todo')"

# Aggregated statistics for scraping progress monitoring
sql_queries$get_url_statistics <- "
  SELECT
    COALESCE(COUNT(*), 0)                                   AS nr_urls,
    COALESCE(SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END), 0)       AS nr_scraped,
    COALESCE(SUM(CASE WHEN status = 'failed_domain' THEN 1 ELSE 0 END), 0) AS nr_failed_domaincheck,
    COALESCE(SUM(CASE WHEN status = 'failed_scraping' THEN 1 ELSE 0 END), 0) AS nr_failed_scraping,
    COALESCE(SUM(CASE WHEN status = 'todo' THEN 1 ELSE 0 END), 0)          AS nr_todo,
    COALESCE(SUM(CASE WHEN status = 'blocked' THEN 1 ELSE 0 END), 0)       AS nr_blocked
  FROM results"

sql_queries$get_tmp_urls      <- "SELECT url FROM tmp_urls"
sql_queries$select_generic    <- "SELECT * FROM {tab}"
sql_queries$select_filtered   <- "SELECT * FROM {tab} WHERE {filter}"

# --- DATA MANIPULATION ---
sql_queries$import_logs_tmp      <- "INSERT OR IGNORE INTO logs SELECT * FROM tmp_logs"
sql_queries$import_urls_tmp      <- "INSERT OR IGNORE INTO urls (url) SELECT url FROM tmp_urls"
sql_queries$delete_results_by_url <- "DELETE FROM results WHERE url IN ({urls_in_batch})"
sql_queries$reset_robots_flags    <- "UPDATE results SET robotscheck_allowed = TRUE"
sql_queries$update_robots_allowed <- "UPDATE results SET robotscheck_allowed = FALSE WHERE url IN ({placeholders})"
sql_queries$status_update_blocked <- "UPDATE results SET status = 'blocked' WHERE robotscheck_allowed = FALSE AND status = 'todo'"
sql_queries$status_update_todo    <- "UPDATE results SET status = 'todo' WHERE status = 'blocked' AND robotscheck_allowed = FALSE"
sql_queries$status_update_failed  <- "UPDATE results SET status = 'failed_domain' WHERE url IN ({placeholders}) AND status = 'todo'"

# --- URL MANAGEMENT ---
sql_queries$tmp_urls_create <- "CREATE TEMPORARY TABLE tmp_urls (url TEXT)"

# Delete specific pending URLs from the scrape queue
sql_queries$delete_todo_urls <- "DELETE FROM results WHERE status = 'todo'  AND url = ?"

# Synchronize results table forcing new state for todo URLs
sql_queries$results_force_up <- "
  DELETE FROM results WHERE status = 'todo' AND url IN (SELECT url FROM tmp_urls);
  INSERT INTO results (url, status) SELECT url, 'todo' FROM tmp_urls;"

# Insert new todo entries only if they do not exist in results
sql_queries$results_sync_new_todo_insert <- "
  INSERT INTO results (url, status)
  SELECT t.url, 'todo'
  FROM tmp_urls t
  WHERE NOT EXISTS (SELECT 1 FROM results r WHERE r.url = t.url);"