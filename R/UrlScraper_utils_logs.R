#' @title Import and Store Scraping Log Files
#'
#' @description
#' Reads individual progress log files generated during scraping, parses
#' their contents, and inserts the collected entries into the `logs` table
#' of the DuckDB results database.  
#' After successful insertion, processed log files are removed from the
#' filesystem.
#'
#' @details
#' The function performs the following actions:
#'
#' * Scans the `progress_dir` for log files created by parallel scraper workers  
#' * Parses each log file line‑by‑line, splitting entries into:
#'   - timestamp  
#'   - chunk/work‑unit identifier  
#'   - URL currently being processed  
#' * Converts parsed entries into a data frame suitable for database storage  
#' * Inserts all log entries into the DuckDB `logs` table using  
#'   `"INSERT OR IGNORE"` to avoid duplicates  
#' * Removes successfully processed log files  
#'
#' Log files are expected to contain tab‑separated entries created by worker
#' processes. Files that are empty or unreadable are automatically discarded.
#'
#' @param progress_dir Path to the directory containing log files produced
#'   during scraping.
#' @param db_file Path to the DuckDB database file where logs should be stored.
#'
#' @return
#' Invisibly returns `TRUE` after logs have been imported and (if possible) the
#' corresponding files removed.
#'
#' @keywords internal
#'
#' @seealso
#' * The `logs` table created in the scraper database structure  
#' * Worker‑level logging functions within the scraper implementation
.handle_logs <- function(progress_dir, db_file) {
  .parse_single_logfile <- function(p) {
    if (length(p) >= 3L) {
      data.frame(
        progress_time = as.POSIXct(p[[1]], tz = Sys.timezone()),
        chunk_id = suppressWarnings(as.integer(p[[2]])),
        url = p[[3]],
        stringsAsFactors = FALSE
      )
    } else {
      data.frame(
        progress_time = as.POSIXct(p[[1]], tz = Sys.timezone()),
        chunk_id = NA_integer_,
        url = p[[2]],
        stringsAsFactors = FALSE
      )
    }
  }

  progress_files <- fs::dir_ls(progress_dir, type = "file", recurse = TRUE)

  if (length(progress_files) == 0) {
    return(invisible())
  }

  logs <- lapply(progress_files, function(x) {
    # Read progress lines
    lines <- readLines(x, warn = FALSE)
    if (!length(lines)) {
      fs::file_delete(x)
      return(NULL)
    }
    parts <- strsplit(lines, "\t", fixed = TRUE)
    df <- do.call(rbind, lapply(parts, .parse_single_logfile))

    if (nrow(df) == 0) {
      fs::file_delete(x)
      return(NULL)
    }
    df
  })

  df <- do.call("rbind", logs)

  stopifnot(fs::file_exists(db_file))
  con <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = FALSE))
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  res <- tryCatch(
    # "Insert or ignore" does implicit deduplication
    expr = DBI::dbWithTransaction(con, {
      DBI::dbWriteTable(con, "tmp_logs", df, overwrite = TRUE)
      DBI::dbExecute(con, "INSERT OR IGNORE INTO logs SELECT * FROM tmp_logs")
      DBI::dbExecute(con, "DROP TABLE tmp_logs")
    }),
    error = function(e) e
  )

  if (!inherits(res, "error")) {
    # they are now successfully inserted
    # into the database
    try(fs::file_delete(progress_files), silent = TRUE)
  }
  invisible(TRUE)
}
