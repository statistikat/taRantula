#' Scrape a Single URL
#'
#' This function retrieves and processes the content of a single URL using either
#' a Selenium session or an HTTP request. It extracts the HTML source, identifies
#' potential redirects, parses links on the page, and returns a structured
#' `data.table` containing the scraping results.
#'
#' @param db_file Character string specifying the path to the DuckDB database file
#'   used for robots.txt rule evaluation.
#' @param sid Either a Selenium session object (`SeleniumSession`) or a named list of
#'   HTTP headers to be used with `httr::GET()`.
#' @param url Character string containing the URL to be scraped.
#' @param robots_check Logical indicating whether robots.txt rules should be validated
#'   before scraping.
#'
#' @return A `data.table` with the following columns:
#'   \describe{
#'     \item{url}{Final URL after potential redirection.}
#'     \item{url_redirect}{Original URL, if a redirect occurred; otherwise `NA`.}
#'     \item{status}{Logical indicating whether scraping succeeded.}
#'     \item{src}{HTML source (or `NA` if scraping failed or disallowed).}
#'     \item{links}{A list-column containing extracted link information as a `data.table`.}
#'     \item{scraped_at}{POSIXct timestamp indicating when the scrape occurred.}
#'   }
#'
#' @details
#' The function first checks robots.txt rules using `check_robotsdata()`.
#' If scraping is disallowed, a standardized record is returned.
#' When using Selenium, the browser is navigated to the URL and the potentially
#' redirected final URL is captured. For non-Selenium inputs, an HTTP GET request
#' is performed.
#' Errors during scraping are caught and converted into structured output.
#'
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

  if (isFALSE(check_robotsdata(db_file = db_file, url = url))) {
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
      print(e)
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
#' processing contexts. It manages progress logging, snapshot creation, robots.txt
#' validation, and stopping conditions.
#'
#' @param inputs A named list containing:
#'   \describe{
#'     \item{db_file}{Path to the DuckDB file used for robots.txt checks.}
#'     \item{urls}{Character vector of URLs to process in this worker.}
#'     \item{chunk_id}{Numeric identifier for this worker chunk.}
#'     \item{snapshot_every}{Integer: write snapshot files every N URLs.}
#'     \item{snapshot_dir}{Directory in which snapshot output is stored.}
#'     \item{stop_file}{Path to a file whose existence indicates that scraping
#'       should stop early.}
#'     \item{progress_dir}{Directory for storing progress logs.}
#'     \item{robots_check}{Logical indicating whether robots.txt rules should be evaluated.}
#'     \item{p}{A progress callback function accepting arguments `amount` and `message`.}
#'   }
#' @param sid A Selenium session object or a list of HTTP headers, passed along to
#'   `.scrape_single_url()`.
#'
#' @return Invisibly returns `TRUE` after completing all scraping tasks assigned to
#'   this worker.
#'
#' @details
#' The function iterates over provided URLs, invoking `.scrape_single_url()` for each.
#' Progress is logged to file, and optional snapshot files store intermediate results to
#' safeguard against worker interruptions.
#' When the stop file is detected, the worker terminates early.
#' Any remaining un-snapshotted results are written at the end of execution.
#'
#' @examples
#' \dontrun{
#' # Inside a parallel worker
#' .worker_scrape(
#'   inputs = list(
#'     db_file = "mydb.duckdb",
#'     urls = c("https://example1.com", "https://example2.com"),
#'     chunk_id = 1,
#'     snapshot_every = 50,
#'     snapshot_dir = "snapshots/",
#'     stop_file = "stop.flag",
#'     progress_dir = "progress/",
#'     robots_check = TRUE,
#'     p = function(amount, message) cat(amount, message, "\n")
#'   ),
#'   sid = my_selenium_session
#' )
#' }
#'
#' @keywords internal
.worker_scrape <- function(inputs, sid) {
  db_file <- inputs$db_file
  urls <- inputs$urls
  chunk_id <- inputs$chunk_id
  snapshot_every <- inputs$snapshot_every
  snapshot_dir <- fs::path(inputs$snapshot_dir, chunk_id)
  fs::dir_create(snapshot_dir, recurse = TRUE)
  stop_file <- inputs$stop_file
  progress_dir <- inputs$progress_dir
  progress_file <- fs::path(progress_dir, chunk_id, "progress.log")
  robots_check <- inputs$robots_check
  p <- inputs$p
  db_file <- inputs$db_file

  fs::dir_create(fs::path_dir(progress_file), recurse = TRUE)
  out <- NULL
  for (i in seq_along(urls)) {
    if (fs::file_exists(stop_file)) {
      break
    }
    u <- urls[[i]]
    rec <- .scrape_single_url(
      db_file = db_file,
      sid = sid,
      url = u,
      robots_check = robots_check
    )
    if (is.null(out)) {
      out <- data.table::copy(rec)
    } else {
      out <- data.table::rbindlist(list(out, rec), use.names = TRUE, fill = TRUE)
    }

    cat(sprintf("%s\t%d\t%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), chunk_id, u),
      file = progress_file, append = TRUE
    )

    if ((i %% snapshot_every) == 0L) {
      .write_snapshot(dt = out, chunk_id = chunk_id, snapshot_dir = snapshot_dir)
      p(amount = nrow(out), message = sprintf("Adding %d chunks", nrow(out)))
      out <- out[0]
    }
  }

  if (nrow(out) > 0) {
    .write_snapshot(dt = out, chunk_id = chunk_id, snapshot_dir = snapshot_dir)
  }
  invisible(TRUE)
}
