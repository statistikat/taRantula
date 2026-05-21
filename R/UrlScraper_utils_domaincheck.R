#' Verify domain reachability
#'
#' Performs a network reachability test for domains associated with pending
#' URLs in the database and updates their status if the domain is unreachable.
#'
#' This function identifies all unique domains currently marked as todo in the
#' results table. It executes parallel HEAD requests to verify if these domains
#' are responsive. Domains that fail to respond are flagged, and all associated
#' URLs in the database are updated to a failed status to prevent redundant
#' processing.
#'
#' @param db_file Path to the DuckDB database file.
#' @param workers Number of concurrent workers for parallel reachability checks.
#' @param timeout Request timeout duration in seconds for each domain check.
#'
#' @return NULL
#'
#' @keywords internal
#' @noRd
.handle_domaincheck <- function(db_file, workers = 20, timeout = 15) {
  .harmonize_url <- function(urls) {
    parsed <- urltools::url_parse(urls)
    
    # Build outputs
    out <- paste0(parsed$scheme, "://", parsed$domain)
    
    # Missing scheme -> use domain only
    missing_scheme <- is.na(parsed$scheme)
    out[missing_scheme] <- parsed$domain[missing_scheme]
    return(out)
  }  
  conn <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = FALSE))
  on.exit(DBI::dbDisconnect(conn, shutdown = TRUE))
  
  # Retrieve all URLs currently awaiting processing
  df_urls <- DBI::dbGetQuery(
    conn = conn,
    statement = sql_queries$get_todo_urls
  )
  
  if (nrow(df_urls) == 0) {
    return(NULL)
  }
  
  # Extract simple-urls for health check
  df_urls$domain <- .harmonize_url(df_urls$url)
  domains <- unique(df_urls$domain)

  # Construct HTTP HEAD request objects for parallel execution
  reqs <- lapply(domains, function(d) {
    httr2::request(d) |>
      httr2::req_method("HEAD") |>
      httr2::req_timeout(timeout) |>
      httr2::req_user_agent(.default_useragent()) |>
      httr2::req_options(
        ssl_verifypeer = 0L,
        ssl_verifyhost = 0L,
        followlocation = 0L
      ) |>
      httr2::req_error(is_error = function(resp) FALSE)
  })
  
  # Execute reachability tests in parallel
  resps <- httr2::req_perform_parallel(
    reqs = reqs,
    max_active = workers,
    on_error = "continue"
  )
  
  # Analyze response status to identify alive domains
  alive_status <- sapply(resps, function(r) {
    # answer -> (sub) urls may exist
    if (inherits(r, "httr2_response")) {
      return(TRUE)
    }
    
    # No answer (dns-error, connection refused, timeout, ...) -> domain not alive
    return(FALSE)
  })
  
  # Get domains and URLs that failed the reachability test
  dead_domains <- domains[!alive_status]
  dead_urls <- subset(df_urls, df_urls$domain %in% dead_domains)$url
  
  # Update database status for non-reachable domains
  if (length(dead_urls) > 0) {
    placeholders <- paste(rep("?", length(dead_urls)), collapse = ",")
    DBI::dbExecute(
      conn = conn,
      statement = glue::glue(sql_queries$status_update_failed),
      params = as.list(dead_urls)
    )
  }
  cli::cli_alert_info("Marked {length(dead_urls)} URLs as failed due to non-reachable domain(s)")
  return(invisible(NULL))
}
