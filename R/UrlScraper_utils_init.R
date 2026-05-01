#' @title Initialize Scraper Configuration
#'
#' @description
#' Internal utility that prepares and normalizes the configuration list used by
#' the `UrlScraper` class.
#' This includes creating required directories, setting file paths, determining
#' pending URLs, and applying global options needed during scraping.
#'
#' @details
#' The function performs the following steps:
#'
#' * Validates that the provided configuration object is a `cfg_scraper` instance
#' * Constructs the project directory under `base_dir`
#' * Creates required subfolders for snapshots, progress files, and the DuckDB
#'   database
#' * Initializes the URL queue (`urls_todo`) and marks none as scraped initially
#' * If an existing DuckDB file is found, previously scraped URLs are loaded and
#'   removed from the queue
#' * Stores the current global R options and applies scraper‑specific defaults
#'
#' This function is called automatically inside the `UrlScraper` constructor and
#' should not be used directly.
#'
#' @param config A `cfg_scraper` configuration object.
#'
#' @return
#' A normalized configuration list ready for use by the scraping engine.
#'
#' @keywords internal
#'
#' @seealso [cfg_scraper], [UrlScraper]
#'
.initialize <- function(config) {
  stopifnot(inherits(config, "cfg_scraper"))
  config <- config$show_config()

  stopifnot(fs::dir_exists(config$base_dir))

  config$project_dir <- fs::path(config$base_dir, config$project)
  fs::dir_create(config$project_dir, recurse = TRUE)

  # Path
  config$db_file <- file.path(config$project_dir, "results.duckdb")
  config$snapshot_dir <- file.path(config$project_dir, "snapshots")
  fs::dir_create(config$snapshot_dir, recurse = TRUE)

  config$progress_dir <- file.path(config$project_dir, "progress")
  fs::dir_create(config$progress_dir, recurse = TRUE)

  config$stop_file <- fs::path(config$snapshot_dir, glue::glue("{config$project}.stop"))

  # URLs
  config$urls_todo <- config$urls # init urls to scrape
  config$urls <- character(0) # init already scraped urls
  urls_scraped <- NULL
  if (fs::file_exists(config$db_file)) {
    urls_scraped <- .get_scraped_urls(db_file = config$db_file)
    if (nrow(urls_scraped) == 0) {
      urls_scraped <- NULL
    }
  }
  # drop duplicated URLs in $urls_todo
  config$urls_todo <- .filter_new_urls(
    urls_scraped = urls_scraped,
    urls_new = config$urls_todo
  )

  config$saved_options <- options()
  options(datatable.prettyprint.char = 50)
  return(config)
}

#' Get and Initialize the Data Directory
#'
#' Determines the path for storing Parquet archives based on the snapshot directory
#' and ensures the directory exists on the file system.
#'
#' @description
#' The function resolves the storage path by navigating one level up from the
#' `snapshot_dir` and appending a `/data` subdirectory. It then uses
#' `fs::dir_create` to ensure the target directory is available for writing.
#'
#' @param snapshot_dir `character`. The directory path where snapshot `.rds`
#'   files are stored.
#'
#' @return A `character` string representing the absolute path to the Parquet
#'   storage directory.
#'
#' @keywords internal
#' @noRd
.parquet_data_dir <- function(snapshot_dir) {
  data_dir <- fs::path(fs::path_dir(snapshot_dir), "data")
  fs::dir_create(data_dir)
  data_dir
}

#' Create/Refresh the 'full_results' Database View
#'
#' Synchronizes the DuckDB `full_results` view with the current Parquet archive.
#' This function dynamically creates a SQL view that joins the `results`
#' metadata table with scraped HTML content stored in external Parquet files.
#'
#' @description
#' The view is managed to ensure consistent API access regardless of whether
#' Parquet files are present. If Parquet files exist, the view performs a
#' `LEFT JOIN` on `url` and `scraped_at`. If no files are found, it initializes
#' an empty view with the expected column structure to prevent SQL errors
#' during runtime.
#'
#' @param conn A DuckDB connection object.
#' @param snapshot_dir `character`. The directory containing snapshot files.
#'   The function derives the Parquet storage location from this path
#'   (one level up in a `/data` folder).
#'
#' @return `invisible(TRUE)` on success.
#'
#' @details
#' This function is designed to be called:
#' - Upon initialization of the scraping object.
#' - After batch processing snapshots to ensure the view reflects newly added data.
#' @keywords internal
#' @noRd
.setup_full_results_view <- function(conn, snapshot_dir) {
  parquet_dir <- .parquet_data_dir(snapshot_dir)
  if (length(fs::dir_ls(parquet_dir, glob = "*.parquet")) > 0) {
    # Case 1: Parquet-Files exist: we can create the View using a join
    query <- glue::glue("
      CREATE OR REPLACE VIEW full_results AS
      SELECT
        r.url, r.url_redirect, r.status, p.src, r.scraped_at
      FROM results r
      LEFT JOIN '{parquet_dir}/*.parquet' p
        ON r.url = p.url AND r.scraped_at = p.scraped_at
    ")
  } else {
    # Case 2: no Parquet-Files yet: View just mirrors "results" table and an "empty" src column
    query <- "
      CREATE OR REPLACE VIEW full_results AS
      SELECT
        url, url_redirect, status, CAST(NULL AS TEXT) AS src, scraped_at
      FROM results
      WHERE 1=0
    "
  }
  DBI::dbExecute(conn, query)
}

#' @title Initialize DuckDB Storage Structure
#'
#' @description
#' Creates the internal DuckDB storage schema if it does not yet exist.
#' Required directories are created and tables for results, links, logs, and
#' robots‑permissions are initialized.
#'
#' @details
#' When a DuckDB database already exists, this function performs no destructive
#' actions and simply returns.
#' Otherwise, it:
#'
#' * Connects to the DuckDB file
#' * Creates four tables (if not already present):
#'   - **results** – scraped pages with status, HTML, timestamps
#'   - **links** – extracted hyperlinks with labels and metadata
#'   - **logs** – progress tracking entries
#'   - **robots** – stored robots.txt permissions for visited domains
#'
#' All table definitions include primary keys to ensure data integrity.
#'
#' @param db_file Path to the DuckDB database file.
#' @param snapshot_dir Directory in which intermediate snapshots are stored.
#' @param progress_dir Directory for incremental progress logs.
#'
#' @return
#' Invisibly returns `TRUE` after ensuring that storage is ready.
#'
#' @keywords internal
#'
#' @seealso [UrlScraper]
.init_storage <- function(db_file, snapshot_dir, progress_dir) {
  fs::dir_create(snapshot_dir, recurse = TRUE)
  fs::dir_create(progress_dir, recurse = TRUE)

  if (fs::file_exists(db_file)) {
    # tables already exist
    return(invisible(TRUE))
  }

  conn <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = FALSE))
  on.exit(try(DBI::dbDisconnect(conn, shutdown = TRUE), silent = TRUE))

  DBI::dbWithTransaction(conn = conn, code = {
    DBI::dbExecute(
      conn = conn,
      statement = "CREATE TABLE IF NOT EXISTS results (
      url TEXT,
      url_redirect TEXT,
      status BOOLEAN,
      file_path TEXT,
      scraped_at TIMESTAMP,
      PRIMARY KEY (url, scraped_at))"
    )

    DBI::dbExecute(
      conn = conn,
      statement = "CREATE TABLE IF NOT EXISTS links (
      href TEXT,
      label TEXT,
      source_url TEXT,
      level INTEGER,
      scraped_at TIMESTAMP,
      PRIMARY KEY (href, scraped_at));"
    )

    DBI::dbExecute(
      conn = conn,
      statement = "CREATE TABLE IF NOT EXISTS logs (
      progress_time TIMESTAMP,
      chunk_id INTEGER,
      url TEXT,
      PRIMARY KEY (progress_time, url))"
    )

    DBI::dbExecute(
      conn = conn,
      statement = "CREATE TABLE IF NOT EXISTS robots (
      domain TEXT PRIMARY KEY,
      permissions TEXT)"
    )

    # Create View `full_results` for results including src
    .setup_full_results_view(conn, snapshot_dir)
  })
  return(invisible(TRUE))
}

#' @title Format Numeric Values
#'
#' @description
#' Simple wrapper around `formatC()` used internally for preparing numeric
#' output (e.g., percentages or durations) in scraper messages.
#'
#' @param x A numeric value.
#' @param format Character string indicating the desired output format; passed
#'   to `formatC()`. Defaults to `"f"`.
#' @param digits Number of digits after the decimal point. Defaults to `3`.
#'
#' @return
#' A character string with formatted numeric output.
#'
#' @keywords internal
.fmt <- function(x, format = "f", digits = 3) {
  formatC(x, format = "f", digits = digits)
}

#' @title Default User‑Agent String
#'
#' @description
#' Provides a default desktop Safari‑style user‑agent string for both Selenium
#' and `httr2` requests when no custom value is supplied.
#'
#' @details
#' The user‑agent string is chosen to mimic a typical macOS Safari browser
#' environment to reduce the likelihood of being blocked by websites for using
#' automated scraping tools.
#'
#' @return
#' A character scalar representing a valid browser user‑agent.
#'
#' @keywords internal
.default_useragent <- function() {
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
}
