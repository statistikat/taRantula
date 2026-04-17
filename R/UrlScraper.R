#' @title UrlScraper R6 Class for Parallel Web Scraping with Selenium
#'
#' @description
#' The `UrlScraper` R6 class provides a high‑level framework for scraping
#' a list of URLs using multiple parallel Selenium (or non‑Selenium) workers.
#' It manages scraping state, progress, snapshots, logs, and respects
#' `robots.txt` rules. Results and logs are stored in an internal DuckDB
#' database.
#'
#' @section Overview:
#' The `UrlScraper` class is designed for robust, resumable web scraping
#' workflows. Its key features include:
#'
#' * Parallel scraping of URLs via multiple Selenium workers
#' * Persistent storage of results, logs, and extracted links in DuckDB
#' * Automatic snapshotting and recovery of partially processed chunks
#' * Respecting `robots.txt` rules via pre‑checks on domains
#' * Convenience helpers for querying results, logs, and extracted links
#' * Regex‑based extraction of text from previously scraped HTML
#'
#' @section Configuration:
#' A configuration object (typically created via [paramsScraper]) is
#' expected to contain at least the following entries:
#'
#' * `db_file` – path to the DuckDB database file
#' * `snapshot_dir` – directory for temporary snapshot files
#' * `progress_dir` – directory for progress/log files
#' * `stop_file` – path to a file used to signal workers to stop
#' * `urls` / `urls_todo` – vectors of URLs and URLs still to scrape
#' * `selenium` – list with Selenium‑related settings, such as:
#'   - `use_selenium` – logical, whether to use Selenium
#'   - `workers` – number of parallel Selenium workers
#'   - `host`, `port`, `browser`, `verbose` – Selenium connection settings
#'   - `ecaps` – list with Chrome options (`args`, `prefs`, `excludeSwitches`)
#'   - `snapshot_every` – number of URLs after which a snapshot is taken
#' * `robots` – list with `robots.txt` handling options, such as:
#'   - `check` – logical, whether to check `robots.txt`
#'   - `snapshot_every` – snapshot frequency for robots checks
#'   - `workers` – number of workers for `robots.txt` checks
#'   - `robots_user_agent` – user agent string used for robots queries
#' * `exclude_social_links` – logical, whether to exclude social media links
#'
#' The exact structure depends on [paramsScraper] and related helpers.
#'
#' @section Methods:
#' * `initialize(config)` – create a new `UrlScraper` instance
#' * `scrape()` – scrape all remaining URLs in parallel
#' * `update_urls(urls, force = FALSE)` – add new URLs to the queue
#' * `results(filter = NULL)` – extract scraping results
#' * `logs(filter = NULL)` – extract log entries
#' * `links(filter = NULL)` – extract discovered links
#' * `query(q)` – run custom SQL queries on the internal DuckDB database
#' * `regex_extract(pattern, group = NULL, filter_links = NULL,
#'   ignore_cases = TRUE)` – extract text via regex from scraped HTML
#' * `stop()` – create a stop‑file so workers can exit gracefully
#' * `close()` – clean up snapshots and close database connections
#'
#' @rdname UrlScraper
#' @usage NULL
#' @format An R6 class generator of class `UrlScraper`.
#' @export
#'
#' @examples
#' \dontrun{
#' # Create a default configuration object
#' cfg <- paramsScraper()
#'
#' # Example Selenium settings
#' cfg$set("selenium$host", "localhost")
#' cfg$set("selenium$workers", 2)
#' cfg$show_config()
#'
#' # Initialize the scraper
#' scraper <- UrlScraper$new(config = cfg)
#'
#' # Start scraping remaining URLs
#' scraper$scrape()
#'
#' # Retrieve results as a data.table
#' results_dt <- scraper$results()
#'
#' # Retrieve logs and links
#' logs_dt <- scraper$logs()
#' links_dt <- scraper$links()
#'
#' # Add new URLs to be scraped (only those not already in the DB)
#' scraper$update_urls(urls = c("https://example.com/"))
#'
#' # Force adding URLs (ignores duplicates against already scraped ones)
#' scraper$update_urls(urls = c("https://example.com/"), force = TRUE)
#'
#' # Regex extraction from scraped HTML
#' emails_dt <- scraper$regex_extract(
#'   pattern      = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
#'   filter_links = c("contact", "imprint")
#' )
#'
#' # Stop ongoing workers after they finish the current URL
#' scraper$stop()
#'
#' # Clean up resources
#' scraper$close()
#' }
UrlScraper <- R6::R6Class(
  classname = "UrlScraper",
  public = list(
    #' @description
    #' Create a new `UrlScraper` object.
    #'
    #' This constructor initializes the internal storage (DuckDB database,
    #' snapshot and progress directories), restores previous snapshots/logs
    #' if present, and configures progress handlers.
    #'
    #' @param config A list (or configuration object) of settings, typically
    #'   created by [paramsScraper()]. It should include:
    #'   * `db_file` – path to the DuckDB database file.
    #'   * `snapshot_dir` – directory for snapshot files.
    #'   * `progress_dir` – directory for progress/log files.
    #'   * `stop_file` – path to the stop signal file.
    #'   * `urls_todo` – character vector of URLs still to be scraped.
    #'   * `selenium` – list of Selenium settings (host, port, workers, etc.).
    #'   * `robots` – list of `robots.txt` handling options.
    #'   * any additional options required by helper functions.
    #'
    #' @return An initialized `UrlScraper` object (invisibly).
    initialize = function(config) {
      private$config <- .initialize(config = config)

      options(progressr.enable = TRUE)
      progressr::handlers(global = TRUE)
      progressr::handlers("cli") # or rstudio | progress | debug

      # Initialize results/log databases in duckdb
      # and create required dirs for snapshotting/logging purposes
      private$init_storage()

      # Handling Snapshots (if any) before Scraping
      private$handle_snapshots()

      # Handling Logs (if any) before Scraping
      private$handle_logs()

      len_urls <- length(private$config$urls_todo)
      urls_scraped <- private$get_scraped_urls()
      len_urls_scraped <- nrow(private$get_scraped_urls())
      cli::cli_alert_info(
        text = glue::glue(
          "Initialized. {len_urls} URLs provided - {len_urls_scraped} URLs already scraped"
        )
      )
      return(invisible(self))
    },

    #' @description
    #' Scrape all remaining URLs using parallel workers.
    #'
    #' @details
    #' This method orchestrates the parallel scraping process:
    #' * Re‑initializes storage and processes any existing snapshots or logs.
    #' * Computes the set of URLs still to scrape.
    #' * Optionally performs `robots.txt` checks on new domains.
    #' * Sets up a parallel plan via the `future` framework.
    #' * Starts multiple Selenium (or non‑Selenium) sessions.
    #' * Distributes URLs across workers and tracks global progress.
    #' * Cleans up snapshots/logs and updates internal URL state after scraping.
    #'
    #' If a stop‑file is detected (see [`stop()`]), scraping is aborted
    #' before starting. Workers themselves will also honor the stop‑file to
    #' terminate gracefully after finishing the current URL.
    #'
    #' @param batch_size (integerish) Maximum number of URLs to process per
    #' iteration before merging results.
    #' @return The `UrlScraper` object (invisibly), with internal state
    #'   updated to reflect newly scraped URLs.
    scrape = function(batch_size = 2000) {
      # check if dev-mode is required (envvar or package is not installed)
      is_dev <- private$is_dev()
      private$init_storage()

      # Handling Snapshots (if any) before scraping
      private$handle_snapshots()

      # Handling Logs (if any) before scraping
      private$handle_logs()

      urls_todo <- private$config$urls_todo
      urls_scraped <- private$get_scraped_urls()
      total_count <- length(urls_todo) + nrow(urls_scraped)
      done_initial <- nrow(urls_scraped)

      if (length(urls_todo) == 0) {
        cli::cli_alert_info("All URLs already scraped. Nothing to do.")
        return(invisible(self))
      }

      # Handling robots.txt on potentially new domains
      private$handle_robots(urls = urls_todo)

      cli::cli_alert_info(
        text = glue::glue(paste(
          "Resuming with {done_initial}/{total_count} already scraped ({.fmt(100 * done_initial / total_count)}%).",
          "{length(urls_todo)} remaining. Batch size: {batch_size}"
        ))
      )

      if (fs::file_exists(private$config$stop_file)) {
        cli::cli_alert_danger(
          text = glue::glue(
            "stop-file {private$config$stop_file} detected; please remove"
          )
        )
        return(invisible(self))
      }

      # Cleanup
      if (fs::dir_exists(private$config$progress_dir)) {
        fs::file_delete(fs::dir_ls(private$config$progress_dir))
      }

      # Parallelization Setup
      nr_workers <- private$config$selenium$workers
      oplan <- future::plan()
      on.exit(future::plan(oplan), add = TRUE)
      future::plan(
        strategy = future::multisession,
        workers = nr_workers
      )

      start_time <- Sys.time()

      # Wrap global progressbar
      progressr::with_progress({
        p <- progressr::progressor(steps = length(urls_todo))
        while (length(urls_todo) > 0) {
          if (fs::file_exists(private$config$stop_file)) {
            cli::cli_alert_warning(
              "Stop-file detected. Finishing current batch and exiting..."
            )
            break
          }

          # retrieve current batch of urls and split into chunks
          current_batch <- head(urls_todo, batch_size)
          current_nr_workers <- min(length(current_batch), nr_workers)
          chunks <- private$split_into_chunks(current_batch, current_nr_workers)
          conf_list <- as.list(private$config)

          if (is_dev) {
            # capture the required functions and packages
            f_pkgs <- c(
              "progressr",
              "data.table",
              "selenium",
              "fs",
              "jsonlite",
              "xml2",
              "rvest",
              "httr2",
              "robotstxt",
              "stats"
            )
            f_list <- list(
              ".worker_scrape" = .worker_scrape,
              ".scrape_single_url" = .scrape_single_url,
              ".write_snapshot" = .write_snapshot,
              "check_robotsdata" = check_robotsdata,
              "extractLinks" = extractLinks,
              "query_robotsdata" = query_robotsdata,
              "get_domain" = get_domain,
              "check_links" = check_links
            )

            # strip the 'taRantula' environment pointer
            # which should prevent the worker from trying to load a non-existent package
            f_globals <- lapply(f_list, function(fn) {
              environment(fn) <- .GlobalEnv
              return(fn)
            })
            f_globals$conf_list <- conf_list
            f_globals$p <- p
          } else {
            f_globals <- TRUE
            f_pkgs <- "taRantula"
          }

          # Scrape batch of urls
          future.apply::future_lapply(
            seq_along(chunks),
            function(x) {
              tryCatch(
                expr = {
                  .worker_scrape(
                    urls = chunks[[x]],
                    chunk_id = x,
                    p = p,
                    config = conf_list
                  )
                },
                error = function(e) {
                  message("FATAL WORKER ERROR: ", e$message)
                  return(FALSE)
                }
              )
            },
            future.seed = TRUE,
            future.globals = f_globals,
            future.packages = f_pkgs
          )

          # Handle Snaphots/Logs while workers pause
          private$handle_snapshots()
          private$handle_logs()

          # Check current scraping state
          scraped_now <- private$get_scraped_urls()
          urls_todo <- setdiff(private$config$urls_todo, scraped_now$url)

          gc() # Force Mem-Cleanup
        }
      })

      # Finalize
      scraped_final <- private$get_scraped_urls()
      private$config$urls <- scraped_final[["url"]]
      private$config$urls_todo <- setdiff(
        private$config$urls_todo,
        scraped_final$url
      )

      now_scraped_count <- nrow(scraped_final)
      elapsed <- difftime(Sys.time(), start_time, units = "secs")

      cli::cli_alert_info(
        text = glue::glue(paste(
          "Done. Scraped {now_scraped_count}/{total_count} URLs ({.fmt(100 * (now_scraped_count / total_count), digits = 1)}%).",
          "Elapsed: {.fmt(elapsed)}s"
        ))
      )

      invisible(self)
    },

    #' @description
    #' Update the list of URLs to be scraped.
    #'
    #' @details
    #' This method updates the internal URL queue based on the given input
    #' vector `urls`. Depending on `force`:
    #'
    #' * If `force = FALSE` (default), URLs that have already been scraped
    #'   (i.e. present in the results database) are removed, as well as
    #'   duplicates within the `urls` vector itself.
    #' * If `force = TRUE`, only duplicates within the given `urls` vector
    #'   are removed; URLs that are already present in the database are kept.
    #'
    #' Summary information about how many URLs were added, already known, or
    #' duplicates is printed via `cli`.
    #'
    #' @param urls A character vector of new URLs to add.
    #' @param force A logical flag. If `TRUE`, all given URLs are kept except
    #'   for duplicates within `urls` itself (no check against already
    #'   scraped URLs). If `FALSE` (default), URLs already in the database
    #'   and duplicates in `urls` are removed.
    #'
    #' @return The `UrlScraper` object (invisibly).
    update_urls = function(urls, force = FALSE) {
      stopifnot(rlang::is_character(urls))

      if (force == TRUE) {
        # only discard duplicted URLs in urls
        urls_scraped <- NULL
      } else {
        # discard duplicated URLs in urls
        # and already scraped URLs
        urls_scraped <- private$get_scraped_urls()
      }

      index_filter <- private$filter_new_urls(
        urls_scraped = urls_scraped,
        urls_new = urls,
        return_index = TRUE
      )
      index_drop <- unique(unlist(index_filter))
      index_keep <- setdiff(seq_along(urls), index_drop)
      remaining <- urls[index_keep]
      private$config$urls <- urls_scraped[["url"]]
      private$config$urls_todo <- remaining

      nr_new <- length(remaining)
      nr_removed <- length(urls) - nr_new
      cli::cli_alert_info(glue::glue("{nr_new} URLs were added"))
      if (nr_removed > 0) {
        nr_old <- length(index_filter$index_old)
        nr_dup <- length(index_filter$index_duplicate)
        if (nr_old > 0) {
          text_info <- paste0(
            "Number of URLs already in the database: {nr_old}"
          )
          cli::cli_alert_info(glue::glue(text_info))
        }
        if (nr_dup > 0) {
          text_info <- paste0(
            "Number of duplicated URLs in the input: {nr_dup}"
          )
          cli::cli_alert_info(glue::glue(text_info))
        }
      }
      invisible(self)
    },

    #' @description
    #' Extract scraping results from the internal database.
    #'
    #' @param filter Optional character string with a SQL‑like `WHERE`
    #'   condition (without the `WHERE` keyword), e.g.
    #'   `"url LIKE 'https://example.com/%'"`. If `NULL` (default), all rows
    #'   from the `results` table are returned.
    #'
    #' @return A `data.table` containing the scraping results.
    results = function(filter = NULL) {
      private$extract_results(tab = "results", filter = filter)
    },

    #' @description
    #' Extract log entries from the internal database.
    #'
    #' @param filter Optional character string with a SQL‑like `WHERE`
    #'   condition (without the `WHERE` keyword). If `NULL` (default), all
    #'   rows from the `logs` table are returned.
    #'
    #' @return A `data.table` containing the log entries.
    logs = function(filter = NULL) {
      private$extract_results(tab = "logs", filter = filter)
    },

    #' @description
    #' Extract scraped links from the internal database.
    #'
    #' @param filter Optional character string with a SQL‑like `WHERE`
    #'   condition (without the `WHERE` keyword). If `NULL` (default), all
    #'   rows from the `links` table are returned.
    #'
    #' @return A `data.table` containing the extracted links.
    links = function(filter = NULL) {
      private$extract_results(tab = "links", filter = filter)
    },

    #' @description
    #' Execute a custom SQL query against the internal DuckDB database.
    #'
    #' This is a low‑level helper for advanced use cases. It assumes that
    #' the user is familiar with the schema of the internal database
    #' (tables such as `results`, `logs`, `links`, and any others created
    #' by helper functions).
    #'
    #' @param q A character string containing a valid DuckDB SQL query.
    #'
    #' @return The result of the query, typically a `data.table`.
    query = function(q) {
      .extract_query(db_file = private$config$db_file, query = q)
    },

    #' @description
    #' Extract text from scraped HTML using a regular expression.
    #'
    #' @details
    #' This helper performs a post‑processing step on the stored HTML
    #' sources in the `results` table:
    #'
    #' 1. It first selects links from the `links` table whose `href` or
    #'    `label` match the provided `filter_links` terms.
    #' 2. It then identifies those documents (rows in `results`) whose
    #'    `url` is among the selected links and that have `status == TRUE`.
    #' 3. Finally, it applies a regular expression to the HTML source of
    #'    those documents and returns the extracted matches.
    #'
    #' This is particularly useful for extracting structured information
    #' such as email addresses, phone numbers, or IDs from a subset of
    #' pages (e.g. contact or imprint pages).
    #'
    #' @param pattern A character string containing a regular expression.
    #'   Named capture groups are supported.
    #' @param group Either:
    #'   * A character string naming a capture group (e.g.
    #'     `"name"` if the pattern contains `(?<name>...)`), or
    #'   * An integer specifying the index of the capture group to return.
    #'   If `NULL` (default), the behavior is delegated to `.extract_regex()`
    #'   and may return all groups depending on its implementation.
    #' @param filter_links A character vector containing keywords or partial
    #'   words used to filter the set of URLs from which `pattern` will be
    #'   extracted. For example, `filter_links = "imprint"` restricts the
    #'   extraction to URLs whose `href` or `label` contains "imprint".
    #' @param ignore_cases Logical. If `TRUE` (default), case is ignored
    #'   when matching `pattern`. If `FALSE`, the pattern is matched in a
    #'   case‑sensitive way.
    #'
    #' @return A `data.table` (or similar object) returned by
    #'   `.extract_regex()`, typically containing the matched text and the
    #'   corresponding URLs.
    regex_extract = function(pattern, group = NULL, filter_links = NULL, ignore_cases = TRUE) {
      private$extract_regex(
        pattern = pattern,
        group = group,
        filter_links = filter_links,
        ignore_cases = ignore_cases
      )
    },

    #' @description
    #' Create a stop‑file to signal running workers to terminate gracefully.
    #'
    #' @details
    #' Workers periodically check for the existence of the configured
    #' `stop_file`. When it is present, they will finish processing the
    #' current URL and then exit. This allows for a controlled shutdown
    #' of a long‑running scraping job without abruptly terminating the
    #' R session or Selenium instances.
    #'
    #' @return Invisible `NULL`.
    stop = function() {
      cat("stop", file = private$config$stop_file)
      cli::cli_alert_info(
        "Stop signal created. Workers will finish current URL and exit."
      )
    },

    #' @description
    #' Clean up resources, including snapshots and database connections.
    #'
    #' @details
    #' This method performs the following clean‑up steps:
    #' * Processes any remaining snapshots and logs.
    #' * Deletes the snapshot directory (if it exists).
    #' * Opens a DuckDB connection to the configured `db_file` and
    #'   disconnects it with `shutdown = TRUE`.
    #'
    #' It is good practice to call `close()` once you are done with a
    #' `UrlScraper` instance.
    #'
    #' @return Invisible `NULL`.
    close = function() {
      # Cleanup
      try(private$handle_snapshots(), silent = TRUE)
      try(private$handle_logs(), silent = TRUE)
      if (fs::dir_exists(private$config$snapshot_dir)) {
        fs::dir_delete(private$config$snapshot_dir)
      }

      if (fs::file_exists(private$config$db_file)) {
        con <- DBI::dbConnect(
          drv = duckdb::duckdb(private$config$db_file, read_only = FALSE)
        )
        on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
      }
    }
  ),
  private = list(
    config = list(),
    is_dev = function() {
      env_dev <- tolower(Sys.getenv("TARANTULA_DEV_MODE")) == "true"
      is_installed <- system.file(package = "taRantula") != ""
      return(env_dev || !is_installed)
    },
    finalize = function() {
      # Try to cleanup before GC cleanup
      try(private$handle_snapshots(), silent = TRUE)
      try(private$handle_logs(), silent = TRUE)
      try(
        expr = {
          if (fs::dir_exists(private$config$snapshot_dir)) {
            fs::dir_delete(private$config$snapshot_dir)
          }
        },
        silent = TRUE
      )
      con <- self$.__enclos_env__$private$config$conn
      if (!is.null(con)) {
        try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
        self$.__enclos_env__$private$config$conn <- NULL
      }

      # reset options
      try(options(private$config$saved_options), silent = TRUE)
    },
    init_storage = function() {
      .init_storage(
        db_file = private$config$db_file,
        snapshot_dir = private$config$snapshot_dir,
        progress_dir = private$config$progress_dir
      )
    },
    get_scraped_urls = function() {
      .get_scraped_urls(
        db_file = private$config$db_file
      )
    },
    filter_new_urls = function(urls_scraped, urls_new, return_index = FALSE) {
      .filter_new_urls(
        urls_scraped = urls_scraped,
        urls_new = urls_new,
        return_index = return_index
      )
    },
    split_into_chunks = function(x, k) {
      k <- max(1L, min(k, length(x)))
      idx <- ((seq_along(x) - 1L) %% k) + 1L
      split(x, idx)
    },
    write_snapshot = function(dt, chunk_id) {
      .write_snapshot(
        dt = dt,
        chunk_id = chunk_id,
        snapshot_dir = private$config$snapshot_dir
      )
    },
    handle_snapshots = function() {
      .handle_snapshots(
        snapshot_dir = private$config$snapshot_dir,
        db_file = private$config$db_file
      )
    },
    handle_logs = function() {
      .handle_logs(
        progress_dir = private$config$progress_dir,
        db_file = private$config$db_file
      )
    },
    handle_robots = function(urls) {
      .handle_robots(
        db_file = private$config$db_file,
        snapshot_every = private$config$robots$snapshot_every,
        workers = private$config$robots$workers,
        urls = private$config$urls_todo,
        user_agent = private$config$robots_user_agent
      )
    },
    extract_results = function(tab, filter = NULL) {
      .extract_results(
        db_file = private$config$db_file,
        tab = tab,
        filter = filter
      )
    },
    extract_regex = function(pattern,
                             group = NULL,
                             filter_links = NULL,
                             ignore_cases = TRUE) {
      results_links <- .extract_results(
        db_file = private$config$db_file,
        tab = "links",
        filter = NULL
      )
      filter_links <- paste(filter_links, collapse = "|")
      # query_filter_links <- glue::glue("regexp_matches(LOWER(COALESCE(HREF, '')), '({filter_links})') OR
      #                                   regexp_matches(LOWER(COALESCE(LABEL, '')), '({filter_links})')")

      results_links <- results_links[
        href %ilike% filter_links | label %ilike% filter_links
      ]

      results_docs <- .extract_results(
        db_file = private$config$db_file,
        tab = "results",
        filter = NULL
      )

      results_docs <- results_docs[url %in% results_links$href & status == TRUE]

      .extract_regex(
        docs = results_docs$src,
        urls = results_docs$url,
        pattern = pattern,
        group = group,
        ignore_cases = ignore_cases
      )
    }
  )
)
