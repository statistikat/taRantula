#' Retrieve Scraped URLs from a DuckDB Database
#'
#' Reads successfully scraped URLs from the results table of a DuckDB database.
#'
#' This function establishes a read-only connection to the database and extracts
#' metadata for URLs that have been processed successfully. It returns a
#' data frame containing the requested URL fields. The connection is
#' automatically terminated upon exit to ensure database integrity.
#'
#' @param db_file Character path to the DuckDB database file.
#'
#' @return A data frame with the columns url, url_actual, and status.
#' Returns an empty data frame if the database file or the results table
#' is missing.
.get_scraped_urls <- function(db_file) {
  df_null <- data.frame(url = character(), url_redirect = character(), status = character())

  # Check DB Existence and connect to DB
  if (!file.exists(db_file)) {
    return(df_null)
  }
  con <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = TRUE))
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE))

  # Verify table availability
  if (!DBI::dbExistsTable(con, "results")) {
    return(df_null)
  }
  # Execute query and return results
  df <- DBI::dbGetQuery(con, sql_queries$get_scraped_urls)
  return(df)
}
