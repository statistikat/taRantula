#' Scrape a Single URL
#'
#' Retrieves and processes content from a single URL using either a Selenium
#' session or an HTTP request.
#'
#' This function performs navigation, captures the final URL to account for
#' potential redirects, and executes the link extraction process. It uses the
#' `sid` parameter to determine the scraping method: if `sid` is an instance
#' of a SeleniumSession object, Selenium is used; otherwise, the function
#' defaults to an `httr2` request.
#'
#' @param sid A SeleniumSession object for browser-based scraping or a request
#' configuration list for HTTP-based scraping.
#' @param url Character string specifying the URL to be scraped.
#'
#' @return A `data.table` with the following columns:
#'    - **url**: The URL that was requested.
#'    - **url_actual**: Final URL after potential redirection.
#'    - **url_redirect**: The original URL if a redirect occurred, otherwise `NA`.
#'    - **status**: Logical indicating whether scraping succeeded.
#'    - **src**: HTML source (or `NA` if scraping failed).
#'    - **links**: A list-column containing extracted link information as a `data.table`.
#'    - **scraped_at**: POSIXct timestamp indicating when the scrape occurred.
#'
#' @keywords internal
#' @noRd
.scrape_single_url <- function(sid, url) {
  ts <- as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), tz = "UTC")

  # Default structure for failed attempts
  dt_links_default <- data.table::data.table(
    href = character(),
    label = character(),
    source_url = character(),
    scraped_at = as.POSIXct(character(0))
  )

  # Execute scraping operation with error handling
  r <- tryCatch(
    expr = {
      if ("SeleniumSession" %in% class(sid)) {
        sid$navigate(url = url)
        final_url <- sid$current_url()
        html_source <- sid$get_page_source()
      } else {
        req <- httr2::request(url) |> httr2::req_method("GET")
        resp <- httr2::req_perform(req)
        final_url <- resp$url
        html_source <- httr2::resp_body_string(resp)
      }

      # Determine if a redirection occurred (including url-cleanup)
      is_redirect <- clean_url(url) != clean_url(final_url)
      data.table::data.table(
        url = url,
        url_actual = final_url,
        url_redirect = if (is_redirect) final_url else NA_character_,
        status = TRUE,
        src = html_source,
        links = list(extractLinks(doc = html_source, baseurl = url)),
        scraped_at = ts
      )
    },
    error = function(e) {
      cli::cli_alert_danger(
        glue::glue("Error when scraping URL {url}: {e$message}")
      )
      # Return failure metadata structure
      data.table::data.table(
        url = url,
        url_actual = NA_character_,
        url_redirect = NA_character_,
        status = FALSE,
        src = NA_character_,
        links = list(dt_links_default),
        scraped_at = ts
      )
    }
  )
  return(r)
}

#' Worker Function for Batched URL Scraping
#'
#' Orchestrates the scraping of multiple URLs in parallel contexts, managing
#' progress tracking, intermediate snapshots, and failure recovery logic.
#'
#' The function follows a two-pass execution strategy. In the primary loop,
#' each URL from the provided list is attempted once. If Selenium is enabled
#' and a page fails to load, the URL is added to a retry queue. In the second
#' pass, the function refreshes the session and attempts to recover the failed
#' URLs up to two additional times. Progress is periodically flushed to disk
#' based on the configured snapshot frequency.
#'
#' @param urls Character vector of URLs to be scraped.
#' @param chunk_id Identifier for the worker used for file naming and logging.
#' @param p Progressor function from the progressr package.
#' @param config Named list containing the scraping configuration:
#'    - **db_file**: Path to the DuckDB file for robots.txt caching.
#'    - **robots$check**: Logical; whether to respect robots.txt rules.
#'    - **selenium**: A list containing Selenium settings (port, host,
#'      browser, and snapshot_every).
#'    - **snapshot_dir**: Directory where .rds snapshots are saved.
#'    - **stop_file**: Path to a file that, if created, signals the
#'      worker to terminate early.
#'    - **progress_dir**: Directory where worker-specific progress
#'      logs are stored.
#'
#' @return Invisibly returns TRUE if the worker finishes successfully, or
#' FALSE if a scraping session could not be initialized.
#'
#' @keywords internal
#' @noRd
.worker_scrape <- function(urls, chunk_id, p, config) {
  # Verify if the current scraping session is responsive
  .check_session_active <- function(sid) {
    active <- tryCatch(
      expr = {
        sid$current_url()
        TRUE
      },
      error = function(e) {
        FALSE
      }
    )
    return(active)
  }

  # Initialize a Selenium session or prepare request headers
  .create_sid <- function(cfg, timeout = 300) {
    if (!isTRUE(cfg$selenium$use_selenium)) {
      return(c(user_agent = cfg$httr2$user_agent))
    }
    tryCatch(
      expr = {
        sel_cfg <- cfg$selenium
        caps <- list(
          browserName = sel_cfg$browser,
          pageLoadStrategy = sel_cfg$pageLoadStrategy,
          timeouts = list(
            implicit = 5000,
            pageLoad = 60000,
            script = 30000
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
      },
      error = function(e) NULL
    )
  }

  # Introduce random delays
  .random_sleep <- function(long = FALSE) {
    if (isTRUE(long)) {
      Sys.sleep(stats::runif(1, 3, 7))
    } else {
      Sys.sleep(stats::runif(1, 0.5, 2.5))
    }
  }

  # Log operation status and update the global progress bar
  .log_and_progress <- function(p, u_str, is_retry = FALSE, status = NULL, amount = 1) {
    if (!missing(p)) {
      prefix <- if (is_retry) "Retry " else ""
      if (amount > 0) {
        p(
          message = glue::glue("{prefix}W{chunk_id}: {basename(u_str)}"),
          amount = amount
        )
      }
    }

    # Write Logfile
    status_suffix <- if (!is.null(status)) glue::glue("\tRETRY_{status}") else ""
    cat(
      glue::glue("{format(Sys.time())}\t{chunk_id}\t{u_str}{status_suffix}"),
      file = progress_file,
      append = TRUE,
      sep = "\n"
    )
  }

  # Define file paths and configuration variables
  db_file <- config$db_file
  snapshot_every <- config$selenium$snapshot_every
  snapshot_dir <- config$snapshot_dir
  stop_file <- config$stop_file
  progress_file <- fs::path(config$progress_dir, chunk_id, "progress.log")
  fs::dir_create(fs::path_dir(progress_file), recurse = TRUE)
  fs::dir_create(snapshot_dir, recurse = TRUE)

  # Initialize the Selenium session
  sid <- .create_sid(cfg = config)
  if (is.null(sid) && isTRUE(config$selenium$use_selenium)) {
    return(FALSE)
  }

  # Ensure the session closes automatically upon completion or error
  on.exit(
    expr = {
      if ("SeleniumSession" %in% class(sid)) {
        try(sid$close(), silent = TRUE)
      }
    },
    add = TRUE
  )

  out <- NULL
  retry_queue <- character()
  consecutive_failures <- 0

  # Execute primary scraping loop
  # Strategy: Try every URL once and if failed, move to retry queue
  for (i in seq_len(length(urls))) {
    u <- as.character(urls[i])

    if (fs::file_exists(stop_file)) {
      break
    }

    # Periodically verify session health
    if (i %% 50 == 0) {
      if (!.check_session_active(sid)) {
        message(glue::glue("W{chunk_id}: Session unresponsive. Creating new session."))
        sid <- .create_sid(cfg = config)
      }
    }

    # Attempt to scrape the current URL
    rec <- .scrape_single_url(sid = sid, url = u)
    is_error <- is.na(rec$src) && isTRUE(config$selenium$use_selenium)

    # Manage failure state and retry queue
    if (is_error) {
      retry_queue <- c(retry_queue, u)
      consecutive_failures <- consecutive_failures + 1

      if (!.check_session_active(sid)) {
        message(glue::glue("W{chunk_id}: Session lost at URL: {u}."))
        try(sid$close(), silent = TRUE)
        sid <- .create_sid(cfg = config)
        consecutive_failures <- 0
      }
    } else {
      consecutive_failures <- 0
      .random_sleep()
    }

    # Force session reset after multiple consecutive failures
    if (consecutive_failures >= 5) {
      cat(
        glue::glue("W{chunk_id}: Forced session reset after 5 failures."),
        file = progress_file,
        append = TRUE,
        sep = "\n"
      )
      try(sid$close(), silent = TRUE)
      sid <- .create_sid(cfg = config)
      consecutive_failures <- 0
    }

    .log_and_progress(
      p = p,
      u_str = u,
      amount = if (is_error) 0 else 1
    )
    out <- data.table::rbindlist(list(out, rec), use.names = TRUE, fill = TRUE)

    # Write snapshotdata (rds) to disk
    if ((i %% snapshot_every) == 0L && !is.null(out)) {
      out <- .write_snapshot(
        dt = out,
        chunk_id = chunk_id,
        snapshot_dir = snapshot_dir
      )
    }
  }

  # Handle the retry queue for failed URLs
  if (length(retry_queue) > 0 && !fs::file_exists(stop_file)) {
    try(sid$close(), silent = TRUE)
    sid <- .create_sid(cfg = config)

    if (!is.null(sid)) {
      for (idx in seq_along(retry_queue)) {
        if (fs::file_exists(stop_file)) {
          break
        }
        u <- retry_queue[[idx]]

        .random_sleep(long = TRUE)

        success <- FALSE
        for (attempt in 1:2) {
          rec <- .scrape_single_url(sid = sid, url = u)
          if (!is.na(rec$src)) {
            success <- TRUE
            break
          }
          if (!.check_session_active(sid)) {
            sid <- .create_sid(cfg = config)
          }
          Sys.sleep(2)
        }

        .log_and_progress(
          p = p,
          u_str = u,
          is_retry = TRUE,
          status = if (success) "OK" else "FAIL",
          amount = 1
        )

        out <- data.table::rbindlist(
          l = list(out, rec),
          use.names = TRUE,
          fill = TRUE
        )

        # Snapshot check for retry queue progress
        if ((idx %% snapshot_every) == 0L && !is.null(out)) {
          out <- .write_snapshot(
            dt = out,
            chunk_id = chunk_id,
            snapshot_dir = snapshot_dir
          )
        }
      }
    }
  }

  # Save remaining data to disk
  if (!is.null(out) && nrow(out) > 0) {
    .write_snapshot(dt = out, chunk_id = chunk_id, snapshot_dir = snapshot_dir)
  }

  invisible(TRUE)
}
