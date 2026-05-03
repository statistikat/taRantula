#' Initialize scraper configuration
#'
#' Prepares and normalizes the configuration settings for the UrlScraper class.
#'
#' This function validates the configuration object, sets up the project directory
#' structure, and defines file paths for snapshots, logs, and the DuckDB
#' database. It retrieves previously scraped URLs if an existing database
#' is detected and applies global options required for the scraping engine.
#'
#' The function follows these steps:
#'
#' - Validates that the input is a valid `cfg_scraper` instance.
#' - Constructs the project directory within the specified base directory.
#' - Creates essential subfolders for snapshots, progress logs, and raw data.
#' - Initializes the DuckDB database path and verifies existing progress.
#' - Saves global options and applies scraping-specific default configurations.
#'
#' @param config A `cfg_scraper` configuration object.
#'
#' @return A normalized configuration list for the scraping engine.
#'
#' @seealso [cfg_scraper], [UrlScraper]
#'
#' @keywords internal
#' @noRd
.initialize <- function(config) {
  stopifnot(inherits(config, "cfg_scraper"))
  config <- config$show_config()

  stopifnot(fs::dir_exists(config$base_dir))

  # Define project directory and ensure its existence
  config$project_dir <- fs::path(config$base_dir, config$project)
  fs::dir_create(config$project_dir, recurse = TRUE)

  # Define database path
  config$db_file <- file.path(config$project_dir, "results.duckdb")

  # Define and Create required subdirectories
  for (d in c("snapshot", "progress", "data")) {
    dn <- glue::glue("{d}_dir")
    config[[dn]] <- fs::path(config$project_dir, d)
    fs::dir_create(config[[dn]], recurse = TRUE)
  }

  # Define path for the termination signal file
  config$stop_file <- fs::path(config$snapshot_dir, glue::glue("{config$project}.stop"))

  # Retrieve previously scraped URLs if the database already exists
  config$urls <- character(0)
  urls_scraped <- NULL
  if (fs::file_exists(config$db_file)) {
    urls_scraped <- .get_scraped_urls(db_file = config$db_file)
    if (nrow(urls_scraped) == 0) {
      urls_scraped <- NULL
    }
  }

  # Apply scraper-specific defaults and save current global options
  config$saved_options <- options()
  options(datatable.prettyprint.char = 50)

  return(config)
}

#' Refresh database views for results and links
#'
#' Synchronizes the DuckDB views 'full_results' and 'links' with the
#' available Parquet archive. The function determines if data files exist to
#' either create a live view joining metadata with Parquet content or to
#' initialize empty views with a static schema to ensure query compatibility.
#'
#' @param conn A DuckDB connection object.
#' @param data_dir Character path to the directory containing Parquet files.
#'
#' @return Invisible TRUE on success.
#' @keywords internal
#' @noRd
.setup_database_views <- function(conn, data_dir) {
  files <- fs::dir_ls(data_dir, glob = "*.parquet")
  has_data <- length(files) > 0

  if (has_data) {
    # Update results view
    query_res <- glue::glue(sql_queries$view_full_results_data, data_dir = data_dir)
    DBI::dbExecute(conn, query_res)

    # Update links view
    query_link <- glue::glue(sql_queries$view_link_data, data_dir = data_dir)
    DBI::dbExecute(conn, query_link)
  } else {
    # Initialize empty structures
    DBI::dbExecute(conn, sql_queries$view_full_results_empty)
    DBI::dbExecute(conn, sql_queries$view_link_data_empty)
  }

  return(invisible(TRUE))
}


#' Initialize DuckDB storage structure
#'
#' Sets up the internal DuckDB schema and required filesystem directories if they
#' do not yet exist.
#'
#' This function establishes the necessary project directory structure for
#' snapshots, progress logs, and data files. It then initializes the DuckDB
#' database by creating core tables for results, links, logs, and robots
#' permissions. If the database file is already present, the function performs
#' no destructive actions and returns immediately.
#'
#' @param db_file Path to the DuckDB database file.
#' @param snapshot_dir Directory for intermediate snapshot storage.
#' @param progress_dir Directory for incremental progress logs.
#' @param data_dir Directory for final parquet data files.
#'
#' @return Invisibly returns TRUE upon successful verification or initialization.
#'
#' @seealso [UrlScraper]
#' @keywords internal
#' @noRd
.init_storage <- function(db_file, snapshot_dir, progress_dir, data_dir) {
  # Establish required filesystem directories
  fs::dir_create(snapshot_dir, recurse = TRUE)
  fs::dir_create(progress_dir, recurse = TRUE)
  fs::dir_create(data_dir, recurse = TRUE)

  # Terminate if the database already exists
  if (fs::file_exists(db_file)) {
    return(invisible(TRUE))
  }

  # Connect to the database
  conn <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = FALSE))
  on.exit(try(DBI::dbDisconnect(conn, shutdown = TRUE), silent = TRUE))

  # Execute schema initialization within a transaction to ensure integrity
  DBI::dbWithTransaction(conn = conn, code = {
    # Initialize URL master table
    DBI::dbExecute(conn, sql_queries$init_table_urls)

    # Initialize results table
    DBI::dbExecute(conn, sql_queries$init_table_results)

    # Initialize logs table
    DBI::dbExecute(conn, sql_queries$init_table_logs)

    # Initialize robots permission table
    DBI::dbExecute(conn, sql_queries$init_table_robots)

    # Create database view "full_results" that contains src and links
    .setup_database_views(conn, data_dir)
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
