#' Extract table results from DuckDB
#'
#' Retrieves records from specified internal DuckDB tables used by the
#' scraper framework.
#'
#' This function establishes a read-only connection to the database, validates
#' the requested table, and executes a query. It supports optional SQL-style
#' filtering via a WHERE clause and converts the output to a data table.
#'
#' @param db_file Path to the DuckDB file.
#' @param tab Character scalar specifying the table to query. Must be one of
#' "full_results", "results", "logs", "urls", or "links".
#' @param filter Optional SQL WHERE clause used to subset results.
#'
#' @return A data table containing requested rows. Returns NULL invisibly on failure.
#'
#' @keywords internal
#' @noRd
.extract_results <- function(db_file, tab = "full_results", filter = NULL) {
  links <- NULL
  stopifnot(rlang::is_scalar_character(tab),
    tab %in% c("results", "full_results", "logs", "links", "urls"))
  stopifnot(fs::file_exists(db_file))

  # Construct query based on provided filters
  if (is.null(filter)) {
    sql <- glue::glue(sql_queries$select_generic, tab = tab)
  } else {
    stopifnot(rlang::is_scalar_character(filter))
    sql <- glue::glue(sql_queries$select_filtered, tab = tab, filter = filter)
  }

  conn <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = TRUE))
  on.exit(try(DBI::dbDisconnect(conn, shutdown = TRUE), silent = TRUE))

  # Execute query and handle potential errors
  res <- tryCatch(
    expr = data.table::setDT(DBI::dbGetQuery(conn = conn, statement = sql))[],
    error = function(e) e
  )

  if (inherits(res, "error")) {
    cli::cli_alert_danger("DB-Query failed. Verify table name and filter syntax.")
    cli::cli_alert_info(glue::glue("Query: {shQuote(sql)}"))
    return(invisible(NULL))
  }

  # Ensure consistent link column structure
  if ("links" %in% names(res)) {
    res[, links := lapply(links, function(x) {
      if (is.null(x) || (is.data.frame(x) && nrow(x) == 0)) {
        return(data.table::data.table(href = character(), label = character(),
          source_url = character(), level = numeric(),
          scraped_at = as.POSIXct(character())))
      }
      if (is.data.frame(x) && !data.table::is.data.table(x)) {
        return(data.table::as.data.table(x))
      }
      return(x)
    })]
  }
  return(res[])
}

#' Execute arbitrary SQL query on DuckDB
#'
#' Executes a custom SQL query against the scraper database.
#'
#' This low-level function allows for advanced SQL operations beyond standard
#' table extraction. It handles database connection, query execution, and
#' conversion to a data table.
#'
#' @param db_file Path to the DuckDB database file.
#' @param query Character scalar containing a valid SQL query.
#'
#' @return A data table containing the retrieved results. Returns NULL invisibly
#' on failure.
#'
#' @keywords internal
#' @noRd
.extract_query <- function(db_file, query) {
  stopifnot(fs::file_exists(db_file))
  stopifnot(rlang::is_scalar_character(query))

  # Connect to DB
  conn <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = TRUE))
  on.exit(try(DBI::dbDisconnect(conn, shutdown = TRUE), silent = TRUE))

  # Execute custom query and handle potential errors
  res <- tryCatch(
    expr = data.table::setDT(DBI::dbGetQuery(conn = conn, statement = query))[],
    error = function(e) e
  )

  if (inherits(res, "error")) {
    cli::cli_alert_danger("DB-Query failed. Check your syntax.")
    return(invisible(NULL))
  }
  return(res)
}
