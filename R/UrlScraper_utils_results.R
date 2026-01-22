#' @title Extract Table Results from DuckDB
#'
#' @description
#' Retrieves records from one of the internal DuckDB tables used by the
#' `UrlScraper` framework.  
#' Supported tables include:
#' * `"results"` – scraped HTML documents  
#' * `"logs"` – worker progress log entries  
#' * `"links"` – extracted hyperlinks  
#'
#' Optional SQL-style filtering is supported (e.g., `"url LIKE 'https://example.com/%'"`).
#'
#' @details
#' This helper function:
#' * Connects to the DuckDB database in **read‑only** mode  
#' * Validates the requested table name  
#' * Constructs a `SELECT * FROM <table>` query, optionally with a `WHERE` clause  
#' * Returns results as a `data.table`  
#'
#' If the underlying query fails (often due to malformed filters),
#' an informative message is printed and `NULL` is returned invisibly.
#'
#' @param db_file Path to the DuckDB file created by the scraper.
#' @param tab Character scalar specifying the table to query.
#'   Must be one of `"results"`, `"logs"`, or `"links"`.
#' @param filter Optional SQL `WHERE` clause (without the word `WHERE`) used
#'   to subset the results.
#'
#' @return
#' A `data.table` containing all rows from the selected table, optionally
#' filtered.  
#' Returns `NULL` invisibly if the query fails.
#'
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' ## Extract all scraped results:
#' .extract_results("results.duckdb", tab = "results")
#'
#' ## Extract links from a specific domain:
#' .extract_results("results.duckdb", tab = "links",
#'                   filter = "href LIKE 'https://example.com/%'")
#' }
.extract_results <- function(db_file, tab = "results", filter) {
  stopifnot(rlang::is_scalar_character(tab), tab %in% c("results", "logs", "links"))
  stopifnot(fs::file_exists(db_file))

  if (!is.null(filter)) {
    stopifnot(rlang::is_scalar_character(filter))
  }

  conn <- DBI::dbConnect(
    drv = duckdb::duckdb(db_file, read_only = TRUE)
  )
  on.exit(try(DBI::dbDisconnect(conn, shutdown = TRUE), silent = TRUE))

  sql <- glue::glue("select * from {tab}", tab = tab)
  if (!is.null(filter)) {
    sql <- glue::glue(sql, " where {filter}")
  }

  res <- tryCatch(
    expr = data.table::setDT(DBI::dbGetQuery(conn = conn, statement = sql))[],
    error = function(e) e
  )

  if (inherits(res, "error")) {
    cli::cli_alert_danger("DB-Query was not successful (Check your filter?)")
    cli::cli_alert_info(glue::glue("query: {shQuote(sql)}"))
    return(invisible(NULL))
  }
  return(res)
}


#' @title Execute Arbitrary SQL Query on DuckDB
#'
#' @description
#' Executes a custom SQL query against the DuckDB database used by the scraper.
#' This function provides maximum flexibility for advanced users who need to
#' run specialized SQL statements beyond the standard table extractors.
#'
#' @details
#' The function:
#' * Validates that the DuckDB file exists  
#' * Executes the provided SQL in **read‑only** mode  
#' * Converts the result to a `data.table`  
#' * Returns `NULL` invisibly if the query fails  
#'
#' This is a low‑level function intended for power users.  
#' Users must ensure their SQL queries are syntactically valid.
#'
#' @param db_file Path to the DuckDB database file.
#' @param query Character scalar containing a valid SQL query.
#'
#' @return
#' A `data.table` containing the retrieved results, or `NULL` invisibly if the query fails.
#'
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' ## List all domains stored in robots table:
#' .extract_query("results.duckdb", "SELECT domain FROM robots")
#'
#' ## Count pages scraped successfully:
#' .extract_query("results.duckdb",
#'                "SELECT COUNT(*) FROM results WHERE status = TRUE")
#' }
.extract_query <- function(db_file, query) {
  stopifnot(fs::file_exists(db_file))
  stopifnot(rlang::is_scalar_character(query))

  conn <- DBI::dbConnect(
    drv = duckdb::duckdb(db_file, read_only = TRUE)
  )
  on.exit(try(DBI::dbDisconnect(conn, shutdown = TRUE), silent = TRUE))

  res <- tryCatch(
    expr = data.table::setDT(DBI::dbGetQuery(conn = conn, statement = query))[],
    error = function(e) e
  )

  if (inherits(res, "error")) {
    cli::cli_alert_danger("DB-Query was not successful, check your query")
    return(invisible(NULL))
  }
  return(res)
}
