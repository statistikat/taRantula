#' Retrieve robots.txt and filter results table
#'
#' Fetches robots.txt files for new domains and validates pending URLs against
#' the retrieved access rules.
#'
#' This function identifies domains in the results table that require `robots.txt`
#' validation. It processes these domains in parallel to fetch access rules,
#' stores them in the database, and performs a bulk validation of all pending
#' URLs. The function ensures the database remains synchronized with access
#' policies without redundant network requests.
#'
#' @param db_file Character path to the DuckDB database file.
#' @param robots_config List containing configuration settings. Example:
#' \preformatted{
#'   # Extracting configuration from the parameter manager
#'   cfg <- paramsScraper()
#'   robots_config <- cfg$get("robots")
#'
#'   # Adjusting parameters for the worker
#'   robots_config$workers <- 5
#' }
#'
#' @return Invisibly returns NULL. Updates the robots table with new rules and
#' modifies the robotscheck_allowed flag in the results table.
#'
#' @keywords internal
#' @noRd
.handle_robots <- function(db_file, robots_config) {
  snapshot_every <- robots_config$snapshot_every
  workers <- robots_config$workers
  check <- robots_config$check
  user_agent <- robots_config$robots_user_agent

  conn <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = FALSE))
  on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)

  # Retrieve domains requiring processing
  todo_data <- DBI::dbGetQuery(conn, sql_queries$get_todo_urls)
  if (nrow(todo_data) == 0) return(invisible(NULL))

  todo_data$domain <- get_domain(todo_data$url, include_scheme = TRUE)
  unique_domains <- unique(todo_data$domain)

  # Determine which domains do not have existing robots data
  ex_domains <- DBI::dbGetQuery(conn, sql_queries$get_robots_existing)[[1]]
  domains_to_process <- setdiff(unique_domains, ex_domains)

  # Setup parallel execution
  oplan <- future::plan()
  on.exit(future::plan(oplan), add = TRUE)
  future::plan(strategy = future::multisession, workers = workers)

  # Retrieve and store robots.txt for new domains
  if (length(domains_to_process) > 0) {
    cli::cli_alert_info("Retrieving robots.txt for new domains with {workers} workers")
    chunks <- split(domains_to_process, f = ceiling(seq_along(domains_to_process) / snapshot_every))

    for (chunk in chunks) {
      res <- future.apply::future_lapply(chunk, function(d) {
        rt <- tryCatch(
          expr = {
            robotstxt::robotstxt(
              domain = d,
              user_agent = user_agent,
              warn = FALSE, force = TRUE
            )
          }, error = function(e) NULL
        )
        data.frame(domain = d, permissions = if (!is.null(rt)) as.character(rt$text) else "")
      }, future.seed = TRUE, future.packages = "robotstxt")

      df <- do.call(rbind, res)
      DBI::dbWriteTable(conn, "robots", df, append = TRUE)
    }
  }

  # Load stored rules for validation
  robots_data <- DBI::dbGetQuery(conn, sql_queries$get_robots_todo)

  cli::cli_alert_info("Validating URLs against robots.txt rules")

  # Reset validation flags before re-evaluation
  DBI::dbExecute(conn, sql_queries$reset_robots_flags)

  # Query permissions for each domain
  blocked_urls <- c()
  for (i in seq_len(nrow(robots_data))) {
    d <- robots_data$domain[i]
    rt <- robotstxt::robotstxt(domain = d, text = robots_data$permissions[i])
    urls_to_check <- todo_data$url[todo_data$domain == d]
    is_allowed <- sapply(urls_to_check, function(u) rt$check(u, bot = "*"))

    if (any(!is_allowed)) {
      blocked_urls <- c(blocked_urls, urls_to_check[!is_allowed])
    }
  }

  # Update database flags for blocked content due to robots.txt
  if (length(blocked_urls) > 0) {
    placeholders <- paste(rep("?", length(blocked_urls)), collapse = ",")
    query <- glue::glue(sql_queries$update_robots_allowed, placeholders = placeholders)
    DBI::dbExecute(conn, query, params = as.list(blocked_urls))
  }

  # Apply configuration-based status updates
  if (isTRUE(robots_config$check)) {
    DBI::dbExecute(conn, sql_queries$status_update_blocked)
  } else {
    DBI::dbExecute(conn, sql_queries$status_update_todo)
  }

  return(invisible(NULL))
}
