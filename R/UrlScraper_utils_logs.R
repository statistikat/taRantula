#' Import and store scraping log files
#'
#' Reads worker-generated progress log files, parses their content, and imports
#' the entries into the logs table of the DuckDB database.
#'
#' This function iterates through the progress directory to collect log files
#' produced by parallel workers. It processes each file line-by-line to
#' extract timestamps, chunk identifiers, and URLs. The parsed data is then
#' imported into the database using a temporary staging table to ensure efficient
#' deduplication. Processed log files are deleted from the filesystem upon
#' successful database insertion.
#'
#' @param progress_dir Path to the directory containing worker log files.
#' @param db_file Path to the DuckDB database file.
#'
#' @return Invisibly returns TRUE after logs are imported and files are removed.
#'
#' @keywords internal
#' @noRd
.handle_logs <- function(progress_dir, db_file) {
  # Parse a single line from a log file into a data frame
  .parse_single_logfile <- function(p) {
    if (length(p) >= 3L) {
      data.frame(
        progress_time = as.POSIXct(p[[1]], tz = "UTC"),
        chunk_id = suppressWarnings(as.integer(p[[2]])),
        url = p[[3]],
        stringsAsFactors = FALSE
      )
    } else {
      data.frame(
        progress_time = as.POSIXct(p[[1]], tz = "UTC"),
        chunk_id = NA_integer_,
        url = p[[2]],
        stringsAsFactors = FALSE
      )
    }
  }

  # Identify available log files
  progress_files <- fs::dir_ls(progress_dir, type = "file", recurse = TRUE)
  if (length(progress_files) == 0) {
    return(invisible())
  }

  # Parse log content from all files
  logs <- lapply(progress_files, function(x) {
    lines <- readLines(x, warn = FALSE)
    lines <- lines[!grepl("forcing new session", tolower(lines))]

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

  # Connect to DB
  stopifnot(fs::file_exists(db_file))
  con <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = FALSE))
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  # Import log data via transaction using a temporary staging table
  res <- tryCatch(
    expr = DBI::dbWithTransaction(conn = con, code = {
      DBI::dbWriteTable(con, "tmp_logs", df, overwrite = TRUE)
      DBI::dbExecute(con, sql_queries$import_logs_tmp)
      DBI::dbExecute(con, sql_queries$drop_tmp_logs_table)
    }),
    error = function(e) e
  )

  # Remove log files only if database operations succeeded
  if (!inherits(res, "error")) {
    try(fs::file_delete(progress_files), silent = TRUE)
  }

  invisible(TRUE)
}
