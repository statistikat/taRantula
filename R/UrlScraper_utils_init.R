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
  if (fs::file_exists(config$db_file)) {
    urls_scraped <- .get_scraped_urls(db_file = config$db_file)
    if (nrow(urls_scraped) > 0) {
      config$urls_todo <- .filter_new_urls(
        urls_scraped = urls_scraped,
        urls_new = config$urls_todo
      )
    }
  } else {
    # drop duplicated URLs in $urls_todo
    config$urls_todo <- .filter_new_urls(
      urls_scraped = NULL,
      urls_new = config$urls_todo
    )
  }

  config$saved_options <- options()
  options(datatable.prettyprint.char = 50)
  return(config)
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
      src TEXT,
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
#' and `httr` requests when no custom value is supplied.
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
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5_2) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
