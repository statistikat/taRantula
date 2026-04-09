#' Scrape a Single URL
#'
#' This function retrieves and processes the content of a single URL using either
#' a Selenium session or an HTTP request. It extracts the HTML source, identifies
#' potential redirects, parses links on the page, and returns a structured
#' `data.table` containing the scraping results.
#'
#' @param db_file Character string specifying the path to the DuckDB database file
#'    used for robots.txt rule evaluation.
#' @param sid Either a Selenium session object (`SeleniumSession`) or a named list of
#'    HTTP headers to be used with `httr::GET()`.
#' @param url Character string containing the URL to be scraped.
#' @param robots_check Logical indicating whether robots.txt rules should be validated
#'    before scraping.
#'
#' @return A `data.table` with the following columns:
#'     - **url**: Final URL after potential redirection.
#'     - **url_redirect**: Original URL, if a redirect occurred; otherwise `NA`.
#'     - **status**: Logical indicating whether scraping succeeded.
#'     - **src**: HTML source (or `NA` if scraping failed or disallowed).
#'     - **links**: A list-column containing extracted link information as a `data.table`.
#'     - **scraped_at**: POSIXct timestamp indicating when the scrape occurred.
#'
#' @details
#' The function first checks robots.txt rules using `check_robotsdata()`.
#' If scraping is disallowed, a standardized record is returned.
#' When using Selenium, the browser is navigated to the URL and the potentially
#' redirected final URL is captured. For non-Selenium inputs, an HTTP GET request
#' is performed.
#' Errors during scraping are caught and converted into structured output.
#'
#' @keywords internal
.scrape_single_url <- function(db_file, sid, url, robots_check) {
  identical_urls <- function(url1, url2) {
    url_parsed <- urltools::url_parse(c(url1, url2))
    setDT(url_parsed)
    url_parsed <- unique(url_parsed)
    return(nrow(url_parsed) == 1)
  }

  ts <- as.POSIXct(format(Sys.time()), tz = "UTC")

  dt_links_default <- data.table::data.table(
    href = character(),
    label = character(),
    source_url = character(),
    level = integer(),
    scraped_at = as.POSIXct(character(0))
  )

  if (robots_check == TRUE & isFALSE(check_robotsdata(db_file = db_file, url = url))) {
    # scraping is not allowed
    return(
      data.table::data.table(
        url = url,
        url_redirect = NA,
        status = FALSE,
        src = "disallowed due to robots.txt",
        links = list(dt_links_default),
        scraped_at = ts
      )
    )
  }

  r <- tryCatch(
    expr = {
      if ("SeleniumSession" %in% class(sid)) {
        sid$navigate(url = url)
        current_url <- sid$current_url()
        redirect <- !identical_urls(url, current_url)

        url_redirect <- NA_character_
        if (redirect) {
          url_redirect <- url
        }
        url <- current_url
        html_source <- sid$get_page_source()
      } else {
        html_source <- httr::GET(url = url, httr::add_headers(.headers = sid))
        html_source <- httr::content(html_source, as = "text")
        url_redirect <- NA_character_
      }

      dt_links <- extractLinks(
        doc = html_source,
        baseurl = url
      )

      data.table::data.table(
        url = url,
        url_redirect = url_redirect,
        status = TRUE,
        src = html_source,
        links = list(dt_links),
        scraped_at = ts
      )
    },
    error = function(e) {
      message("Scrape failed for: ", url)
      data.table::data.table(
        url = url,
        url_redirect = NA,
        status = FALSE,
        src = NA,
        links = list(dt_links_default),
        scraped_at = ts
      )
    }
  )
  return(r)
}


#' Worker Function for Batched URL Scraping
#'
#' This internal function orchestrates the scraping of multiple URLs in parallel
#' processing contexts. It manages progress logging, intermediate snapshot 
#' creation, and multi-stage retry logic ("double-dipping") for failed URLs.
#'
#' @param urls A character vector of the URLs assigned to this specific worker chunk.
#' @param chunk_id A numeric or character identifier for the current worker, used 
#'   to organize log files and name snapshots.
#' @param p A progressor function (from the `progressr` package) used to update 
#'   the global progress bar.
#' @param config A named list containing the scraping configuration, including:
#'   - **db_file**: Path to the DuckDB file for robots.txt caching.
#'   - **robots$check**: Logical; whether to respect robots.txt rules.
#'   - **selenium**: A list containing Selenium settings (port, host, 
#'     browser, and `snapshot_every`).
#'   - **snapshot_dir**: Directory where `.rds` snapshots are saved.
#'   - **stop_file**: Path to a file that, if created, signals the 
#'     worker to terminate early.
#'   - **progress_dir**: Directory where worker-specific progress 
#'     logs are stored.
#'
#' @return Invisibly returns `TRUE` if the worker finishes successfully, 
#'   or `FALSE` if a Selenium session could not be initialized.
#'
#' @details
#' The function follows a two-pass execution strategy:
#' 
#' 1. **Main Loop**: Each URL is attempted once. If Selenium is enabled 
#'    and a page fails to load (returning `NA`), the URL is added to a 
#'    retry queue.
#' 2. **Retry Loop**: After the primary loop, the Selenium session is 
#'    refreshed, and failed URLs are attempted up to two more times.
#' 
#' Throughout both loops, the function periodically flushes data to disk via 
#' `.write_snapshot()` based on the `snapshot_every` frequency defined 
#' in the config.
#'
#' @keywords internal
.worker_scrape <- function(urls, chunk_id, p, config) {
  # check, if session still alive/valid
  .check_session_active <- function(sid) {
    active <- tryCatch({
      sid$current_url()
      TRUE
    }, error = function(e) {
      FALSE
    })
    return(active)
  }  
  
  # Safely create a Selenium Session
  .create_sid <- function(cfg, timeout = 300) {
    if (!isTRUE(cfg$selenium$use_selenium)) {
      return(c(user_agent = cfg$httr$user_agent))
    }
    tryCatch({
      sel_cfg <- cfg$selenium
      
      # w3c-compatible
      caps <- list(
        browserName = sel_cfg$browser,
        pageLoadStrategy = sel_cfg$pageLoadStrategy,
        timeouts = list(
          implicit = 5000,    # 5 Sekunden Puffer für Elemente
          pageLoad = 60000,   # 60 Sekunden Max für Seitenaufbau
          script = 30000      # 30 Sekunden für Scripte
        )
      )
    
      chrome_stuff <- selenium::chrome_options(
        args = sel_cfg$ecaps$args,
        prefs = as.list(sel_cfg$ecaps$prefs),
        excludeSwitches = as.list(sel_cfg$ecaps$excludeSwitches)
      )

      selenium::SeleniumSession$new(
        host = sel_cfg$host,
        port = sel_cfg$port,
        verbose = sel_cfg$verbose,
        browser = sel_cfg$browser,
        capabilities = c(caps, chrome_stuff),
        timeout = timeout
      )
    }, error = function(e) NULL)
  }
  
  # a random short sleep
  .random_sleep <- function(long = FALSE) {
    if (isTRUE(long)) {
      Sys.sleep(runif(1, 3, 7)) 
    } else {
      Sys.sleep(runif(1, 0.5, 2.5))
    }
  }
  
  # consistent logging and progress-updating
  .log_and_progress <- function(p, u_str, is_retry = FALSE, status = NULL) {
    # update progress bar
    if (!missing(p)) {
      prefix <- if (is_retry) "Retry " else ""
      p(message = glue::glue("{prefix}W{chunk_id}: {basename(u_str)}"), amount = 1)
    }
    
    # write to log
    status_suffix <- if (!is.null(status)) glue::glue("\tRETRY_{status}") else ""
    glue::glue("{format(Sys.time())}\t{chunk_id}\t{u_str}{status_suffix}") |> 
      cat(file = progress_file, append = TRUE, sep = "\n")
  }
  
  # setup vars
  db_file <- config$db_file
  robots_check <- config$robots$check
  snapshot_every <- config$selenium$snapshot_every
  snapshot_dir <- config$snapshot_dir
  stop_file <- config$stop_file
  progress_file  <- fs::path(config$progress_dir, chunk_id, "progress.log")
  fs::dir_create(fs::path_dir(progress_file), recurse = TRUE)
  fs::dir_create(snapshot_dir, recurse = TRUE)
  
  sid <- .create_sid(cfg = config)
  if (is.null(sid) && isTRUE(config$selenium$use_selenium)) {
    return(FALSE)
  }
  
  on.exit({
    if ("SeleniumSession" %in% class(sid)) {
      try(sid$close(), silent = TRUE)
    }
  }, add = TRUE)
  
  out <- NULL
  retry_queue <- character()
  consecutive_failures <- 0
  
  # main scraping loop; try every url once and move
  # failed urls to retry_queue
  for (i in seq_along(urls)) {
    if (fs::file_exists(stop_file)) break
    
    # pro-active check
    if (i %% 50 == 0) {
      if (!.check_session_active(sid)) {
        message(glue::glue("W{chunk_id}: Session not found. Creating new session"))
        sid <- .create_sid(cfg = config)
      }
    }
    
    u <- as.character(urls[[i]])
    
    # scrape (intern tryCatch!)
    rec <- .scrape_single_url(
      db_file = db_file, 
      sid = sid, 
      url = u, 
      robots_check = robots_check
    )
    
    # error-handling
    if (is.na(rec$src) && isTRUE(config$selenium$use_selenium)) {
      retry_queue <- c(retry_queue, u)
      consecutive_failures <- consecutive_failures + 1
      
      # Check: session after error still alive?
      if (!.check_session_active(sid)) {
        message(glue::glue("W{chunk_id}: Session no longer available: Url: {u}."))
        try(sid$close(), silent = TRUE)
        sid <- .create_sid(cfg = config)
        consecutive_failures <- 0
      }
    } else {
      consecutive_failures <- 0
      .random_sleep()
    }
    
    # fully reset after 5 subsequent errors
    if (consecutive_failures >= 5) {
      cat(glue::glue("W{chunk_id}: 5 subsequent errors; Forcing new session."), 
          file = progress_file, append = TRUE, sep = "\n")
      try(sid$close(), silent = TRUE)
      sid <- .create_sid(cfg = config)
      consecutive_failures <- 0
    }
    
    .log_and_progress(p = p, u_str = u)
    out <- data.table::rbindlist(list(out, rec), use.names = TRUE, fill = TRUE)
    
    if ((i %% snapshot_every) == 0L && !is.null(out)) {
      out <- .write_snapshot(dt = out, chunk_id = chunk_id, snapshot_dir = snapshot_dir)
    }
  }
  
  # retry logic for initially failed urls (if any)
  if (length(retry_queue) > 0 && !fs::file_exists(stop_file)) {

    # start with new session for retry queue
    try(sid$close(), silent = TRUE)
    sid <- .create_sid(cfg = config)
    
    if (!is.null(sid)) {
      for (idx in seq_along(retry_queue)) {
        if (fs::file_exists(stop_file)) break
        u <- retry_queue[[idx]]
        
        # sleep a bit longer when dealing with problematic urls
        .random_sleep(long = TRUE)
        
        success <- FALSE
        # max 2 additional retries
        for (attempt in 1:2) {
          rec <- .scrape_single_url(
            db_file = db_file, 
            sid = sid, 
            url = u, 
            robots_check = robots_check
          )
          if (!is.na(rec$src)) { 
            success <- TRUE
            break 
          }
          if (!.check_session_active(sid)) {
            sid <- .create_sid(cfg = config)
          }
          Sys.sleep(2)
        }
        
        .log_and_progress(p = p, u_str = u, is_retry = TRUE, status = if(success) "OK" else "FAIL")
        out <- data.table::rbindlist(list(out, rec), use.names = TRUE, fill = TRUE)
        
        # Snapshot check for long retry queues
        if ((idx %% snapshot_every) == 0L && !is.null(out)) {
          out <- .write_snapshot(dt = out, chunk_id = chunk_id, snapshot_dir = snapshot_dir)
        }
      }
    }
  }
  
  # finalize
  if (!is.null(out) && nrow(out) > 0) {
    .write_snapshot(dt = out, chunk_id = chunk_id, snapshot_dir = snapshot_dir)
  }
  
  invisible(TRUE)
}
