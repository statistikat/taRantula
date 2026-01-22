#' Retrieve Scraped URLs from a DuckDB Database
#'
#' This function reads previously scraped URLs from a DuckDB database file.
#' It returns a data frame containing the original URLs and any corresponding
#' redirect URLs stored in the `results` table.
#'
#' @param db_file Character string specifying the path to the DuckDB database file.
#'   If the file does not exist, `NULL` is returned.
#'
#' @return
#' * `NULL` if the database file does not exist.  
#' * An empty character vector if the table `results` is not available.  
#' * A data frame with the columns `url` and `url_redirect` otherwise.
#'
#' @details
#' The function safely opens the DuckDB database in read‑only mode and ensures
#' that the connection is properly closed upon exit. Only the table `results`
#' is queried. If the table is missing, no error is thrown.
#' 
#' @keywords internal
#' 
#' @examples
#' \dontrun{
#' # Load previously scraped URLs
#' scraped <- .get_scraped_urls("my_scraper_db.duckdb")
#' }
.get_scraped_urls <- function(db_file) {
  if (!file.exists(db_file)) {
    return(NULL)
  }
  con <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = TRUE))
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE))
  if (!DBI::dbExistsTable(con, "results")) {
    return(character())
  }
  df <- DBI::dbGetQuery(con, "SELECT url, url_redirect FROM results")
  return(df)
}


#' Filter New URLs by Removing Duplicates and Already-Scraped URLs
#'
#' This function filters a vector of newly collected URLs by excluding those
#' that were already scraped or that appear more than once in the new input.
#' URL parsing is performed using `urltools`, and duplicates are detected after
#' normalization of URLs.
#'
#' @param urls_scraped Optional list or vector containing URLs that were already scraped.
#'   If `NULL`, only internal duplicates in `urls_new` are removed.
#' @param urls_new Character vector of new URLs to be filtered.
#' @param return_index Logical; if `TRUE`, the function returns the indices of
#'   duplicates and previously scraped URLs instead of filtered URLs.
#'
#' @return
#' * If `return_index = FALSE` (default): a character vector of filtered URLs.  
#' * If `return_index = TRUE`: a list with elements  
#'   - `index_old`: indices of URLs found in `urls_scraped`  
#'   - `index_duplicate`: indices of duplicated URLs within `urls_new`
#'
#' @details
#' URL parsing is handled internally via a helper function that extracts URL
#' components, removes the `scheme` field, and attaches the domain. Matching
#' between new and previously scraped URLs is done using data.table's keyed
#' joins to efficiently identify overlaps.
#'
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' # Example URLs
#' new_urls <- c("https://example.com", "https://example.com/page",
#'               "https://example.com")
#'
#' old_urls <- c("https://example.com/page")
#'
#' # Filter new URLs
#' filtered <- .filter_new_urls(urls_scraped = old_urls, urls_new = new_urls)
#'
#' # Inspect indices of removed URLs
#' idx <- .filter_new_urls(urls_scraped = old_urls, urls_new = new_urls,
#'                         return_index = TRUE)
#' }
#'
.filter_new_urls <- function(urls_scraped = NULL,
                             urls_new,
                             return_index = FALSE) {
  help_parse <- function(urls) {
    scheme <- NULL
    urls_parsed <- urltools::url_parse(urls = urls)
    setDT(urls_parsed)
    set(urls_parsed, j = "domain", value = get_domain(urls))
    urls_parsed[, scheme := NULL]
    return(urls_parsed)
  }

  urls_parsed <- help_parse(urls_new)
  index_duplicate <- which(duplicated(urls_parsed))

  index_old_url <- integer(0)
  if (!is.null(urls_scraped)) {
    # get already scraped urls
    already <- unlist(urls_scraped)
    already <- unique(already)
    already <- already[!is.na(already)]
    already <- help_parse(already)

    on_names <- colnames(urls_parsed)
    index_old_url <- urls_parsed[already, on = c(on_names), which = TRUE, nomatch = NULL]
  }

  if (return_index == TRUE) {
    return(list(index_old = index_old_url, index_duplicate = index_duplicate))
  }

  index_drop <- unique(c(index_old_url, index_duplicate))
  index_keep <- setdiff(seq_along(urls_new), index_drop)
  return(urls_new[index_keep])
}
