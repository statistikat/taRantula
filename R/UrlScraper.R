#' @title UrlScraper R6 Class for Parallel Web Scraping with Selenium
#'
#' @description
#' The `UrlScraper` R6 class provides a framework for scraping lists of URLs
#' using multiple parallel Selenium (or httr2-Fallback) workers. It manages the scraping state,
#' progress, snapshots, and logs, while ensuring `robots.txt` rules are followed.
#' Metadata and logs are stored in an internal DuckDB database, while
#' the scraped HTML sources are saved in compressed `parquet` files.
#'
#' @section Overview:
#' The `UrlScraper` class is designed for robust and resumable web scraping.
#' Its key features include:
#'
#' * Parallel scraping of URLs via multiple Selenium workers
#' * Persistent storage of results and links in DuckDB
#' * Efficient storage of HTML sources in compressed `parquet` files
#' * Automatic snapshotting and recovery of processed chunks
#' * Respecting `robots.txt` rules per domain
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
#' * `results(filter = NULL, with_src = TRUE)` – extract scraping results with/without sources
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
#' results_dt <- scraper$results() # per default with sources
#' scraper$results(with_src = FALSE) # only metadata and path to result-files
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
    #'    created by [paramsScraper()]. It should include:
    #'    * `db_file` – path to the DuckDB database file.
    #'    * `snapshot_dir` – directory for snapshot files.
    #'    * `progress_dir` – directory for progress/log files.
    #'    * `stop_file` – path to the stop signal file.
    #'    * `urls` – character vector of URLs still to be scraped.
    #'    * `selenium` – list of Selenium settings (host, port, workers, etc.).
    #'    * `robots` – list of `robots.txt` handling options.
    #'    * any additional options required by helper functions.
    #'
    #' @return An initialized `UrlScraper` object (invisibly).
    initialize = function(config) {
      # Normalize and apply the configuration
      private$config <- .initialize(config = config)

      # Enable and configure progress reporting handlers
      options(progressr.enable = TRUE)
      progressr::handlers(global = TRUE)
      progressr::handlers("cli") # or rstudio | progress | debug

      # Initialize DB and required directories
      private$init_storage()

      # Restore pending snapshots / logs
      private$handle_snapshots()
      private$handle_logs()

      # Register pending URLs in the database
      self$update_urls(config$get("urls"), force = FALSE)

      return(invisible(self))
    },

    #' @description
    #' Scrape all remaining URLs using parallel workers.
    #'
    #' @details
    #' This method orchestrates the parallel scraping process:
    #' * Re-initializes storage and processes any existing snapshots or logs.
    #' * Computes the set of URLs still to scrape.
    #' * Optionally performs `robots.txt` checks on new domains.
    #' * Sets up a parallel plan via the `future` framework.
    #' * Starts multiple Selenium (or non-Selenium) sessions.
    #' * Distributes URLs across workers and tracks global progress.
    #' * Cleans up snapshots/logs and updates internal URL state after scraping.
    #'
    #' If a stop-file is detected (see `stop()`), scraping is aborted
    #' before starting. Workers themselves will also honor the stop-file to
    #' terminate gracefully after finishing the current URL.
    #'
    #' @param batch_size (integerish) Maximum number of URLs to process per
    #' iteration before merging results.
    #' @return The `UrlScraper` object (invisibly), with internal state
    #'    updated to reflect newly scraped URLs.
    scrape = function(batch_size = 2000) {
      is_dev <- private$is_dev()
      private$init_storage()

      # Import existing snapshots and logs before initiating the crawl
      private$handle_snapshots()
      private$handle_logs()

      info <- self$url_info
      total_count <- info$nr_todo + info$nr_scraped
      done_count  <- info$nr_scraped
      urls_todo <- self$urls_todo

      if (length(urls_todo) == 0) {
        cli::cli_alert_info("All URLs already processed. Nothing to do.")
        return(invisible(self))
      }

      cli::cli_alert_info(
        text = glue::glue(
          "Resuming: {done_count}/{total_count} URLs processed ({.fmt(100 * done_count / total_count, digits = 1)}%). ",
          "{info$nr_todo} remaining. Batch size: {batch_size}"
        )
      )

      # Abort if a termination signal file exists
      if (fs::file_exists(private$config$stop_file)) {
        cli::cli_alert_danger(
          text = glue::glue(
            "stop-file {private$config$stop_file} detected; please remove"
          )
        )
        return(invisible(self))
      }

      # Clear progress directory before starting
      if (fs::dir_exists(private$config$progress_dir)) {
        fs::file_delete(fs::dir_ls(private$config$progress_dir))
      }

      # Configure parallel execution
      nr_workers <- private$config$selenium$workers
      oplan <- future::plan()
      on.exit(future::plan(oplan), add = TRUE)
      future::plan(
        strategy = future::multisession,
        workers = nr_workers
      )

      start_time <- Sys.time()

      # Execute scraping within a progress tracking wrapper
      progressr::with_progress({
        p <- progressr::progressor(steps = length(urls_todo))
        while (length(urls_todo) > 0) {
          # Termination check
          if (fs::file_exists(private$config$stop_file)) {
            cli::cli_alert_warning(
              "Stop-file detected. Finishing current batch and exiting..."
            )
            break
          }

          # Batch and chunk URL distribution for parallel workers
          current_batch <- head(urls_todo, batch_size)
          current_nr_workers <- min(length(current_batch), nr_workers)
          chunks <- private$split_into_chunks(current_batch, current_nr_workers)
          conf_list <- as.list(private$config)

          # Prepare environment for development mode or package deployment
          if (is_dev) {
            f_pkgs <- c(
              "progressr", "data.table", "selenium", "fs", "jsonlite",
              "xml2", "rvest", "httr2", "stats", "cli", "glue"
            )
            f_list <- list(
              ".worker_scrape" = .worker_scrape,
              ".scrape_single_url" = .scrape_single_url,
              ".write_snapshot" = .write_snapshot,
              "extractLinks" = extractLinks,
              "get_domain" = get_domain,
              "clean_url" = clean_url,
              "check_links" = check_links
            )

            # Re-map function environments for isolated worker processes
            f_globals <- lapply(f_list, function(fn) {
              environment(fn) <- .GlobalEnv
              return(fn)
            })
            f_globals$chunks <- chunks
            f_globals$conf_list <- conf_list
            f_globals$p <- p
          } else {
            f_globals <- TRUE
            f_pkgs <- "taRantula"
          }

          # Parallel batch processing
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
                  cli::cli_alert_danger("FATAL WORKER ERROR [chunk {x}]: {e$message}")
                  return(FALSE)
                }
              )
            },
            future.seed = TRUE,
            future.globals = f_globals,
            future.packages = f_pkgs
          )

          # Post-batch maintenance / cleanup
          private$handle_snapshots()
          private$handle_logs()
          urls_todo <- self$urls_todo
          gc()
        }
      })

      # Summarize performance metrics
      ii <- self$url_info
      elapsed <- difftime(Sys.time(), start_time, units = "secs")
      total_count <- ii$nr_urls - ii$nr_failed_domaincheck - ii$nr_blocked

      cli::cli_alert_info(
        text = glue::glue(paste(
          "Done. Scraped {ii$nr_scraped}/{total_count} URLs ({.fmt(100 * (ii$nr_scraped / total_count), digits = 1)}%).",
          "Elapsed: {.fmt(elapsed)}s"
        ))
      )

      return(invisible(self))
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
      if (length(urls) == 0) {
        return(invisible(self))
      }

      # Normalize URLs
      urls_clean <- unique(vapply(urls, clean_url, FUN.VALUE = character(1)))
      dup_idx <- duplicated(urls_clean)
      urls_clean <- urls_clean[!dup_idx]

      conn <- DBI::dbConnect(duckdb::duckdb(private$config$db_file, read_only = FALSE))
      on.exit(DBI::dbDisconnect(conn, shutdown = TRUE))

      # Capture state for summary reporting
      stats_before <- self$url_info

      # Synchronize new URLs with the database storage
      DBI::dbWithTransaction(conn, {
        DBI::dbExecute(conn, sql_queries$tmp_urls_create)
        DBI::dbAppendTable(conn, "tmp_urls", data.frame(url = urls_clean))
        DBI::dbExecute(conn, sql_queries$import_urls_tmp)

        # Apply conditional synchronization logic
        if (isTRUE(force)) {
          DBI::dbExecute(conn, sql_queries$results_force_up)
        } else {
          DBI::dbExecute(conn, sql_queries$results_sync_new_todo_insert)
        }
        DBI::dbExecute(conn, sql_queries$drop_tmp_urls)
      })

      # Perform domain availability and robots.txt validation
      private$handle_domaincheck()
      private$handle_robots()

      # Summarize changes
      stats_after <- self$url_info
      added_queue <- stats_after$nr_todo - stats_before$nr_todo
      blocked_domain <- stats_after$nr_failed_domaincheck - stats_before$nr_failed_domaincheck
      blocked_robots <- stats_after$nr_blocked - stats_before$nr_blocked
      scraped_new <- stats_after$nr_scraped - stats_before$nr_scraped

      cli::cli_h3("taRantula URL Summary")
      cli::cli_dl(c(
        "Provided" = glue::glue("{length(urls_clean)} URLs"),
        "Added to scrape" = glue::glue("{added_queue} new URLs"),
        "Already done" = glue::glue("{scraped_new} URLs already scraped"),
        "Issues found" = glue::glue("{blocked_domain} domain failures, {blocked_robots} robots-blocked")
      ))
      cli::cli_alert_info(glue::glue(
        "Status: {stats_after$nr_todo} URLs pending | Total: {stats_after$nr_urls} entries in DB"
      ))

      return(invisible(self))
    },

    #' @description
    #' Extract scraping results from the internal database.
    #'
    #' @param filter Optional character string with a SQL‑like `WHERE`
    #'   condition (without the `WHERE` keyword), e.g.
    #'   `"url LIKE 'https://example.com/%'"`. If `NULL` (default), all rows
    #'   from the `results` table are returned.
    #' @param with_src (Logical); if `TRUE` (default), the result also contains
    #' the scraped sources (column `src`) of the scraped websites; else in column `file_path` the
    #' path to the local `parquet` Files, in which results are returned.
    #' @return A `data.table` containing the scraping results.
    results = function(filter = NULL, with_src = TRUE) {
      tab <- ifelse(with_src, "full_results", "results")
      private$extract_results(tab = tab, filter = filter)
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
    #' @details
    #' This method retrieves links from the database view, which is populated
    #' based on the underlying parquet data. Once the raw link data is
    #' retrieved, the function iteratively computes and appends the hierarchical
    #' depth (level) for each URL relative to the root pages.
    #'
    #' @param filter Optional character string with a SQL‑like `WHERE`
    #'   condition (without the `WHERE` keyword). If `NULL` (default), all
    #'   rows from the `links` table are returned.
    #'
    #' @return A `data.table` containing the extracted links with associated
    #' depth levels.
    links = function(filter = NULL) {
      # Fetch link data from the database view
      res <- private$extract_results(tab = "links", filter = filter)
      if (nrow(res) == 0) {
        return(NULL)
      }

      # Identify child pages and determine root URLs
      children <- unique(res$target_url)
      all_urls <- private$extract_results(tab = "urls", filter = NULL)$url
      roots <- setdiff(all_urls, children)

      # Initialize root URLs as level 1
      dt_levels <- data.table(target_url = roots, level = 1)

      # Iteratively compute levels based on link hierarchy
      current_level <- 1
      while (TRUE) {
        new_links <- res[source_url %in% dt_levels[level == current_level, target_url]]
        new_links <- new_links[!target_url %in% dt_levels$target_url]

        if (nrow(new_links) == 0) {
          break
        }

        new_rows <- data.table(
          target_url = unique(new_links$target_url),
          level = current_level + 1
        )
        dt_levels <- rbind(dt_levels, new_rows)
        current_level <- current_level + 1
      }

      # Merge computed levels back into the results table
      res <- merge(res, dt_levels, by = "target_url", all.x = TRUE)

      return(res[])
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
    #' * Deletes the snapshot directory if it exists.
    #' * Opens a DuckDB connection to the configured `db_file` and
    #'   disconnects it with `shutdown = TRUE`.
    #'
    #' It is good practice to call `close()` once you are done with a
    #' `UrlScraper` instance, or rely on the automatic `finalize()` method.
    #'
    #' @return Invisible `NULL`.
    close = function() {
      private$cleanup()
    }
  ),
  #' @field url_info A list containing aggregated statistics of the crawl process.
  #'   Provides the total count of URLs, as well as counts for successful scrapes,
  #'   failed domain checks, failed scraping attempts, and pending URLs.
  #'
  #' @field urls_todo A character vector of unique URLs currently marked with
  #'   the 'todo' status in the database. These are URLs that need to be scraped.
  active = list(
    url_info = function() {
      conn <- DBI::dbConnect(duckdb::duckdb(private$config$db_file, read_only = TRUE))
      on.exit(DBI::dbDisconnect(conn, shutdown = TRUE))
      res <- DBI::dbGetQuery(conn, sql_queries$get_url_statistics)
      as.list(res)
    },
    urls_todo = function() {
      conn <- DBI::dbConnect(duckdb::duckdb(private$config$db_file, read_only = TRUE))
      on.exit(DBI::dbDisconnect(conn, shutdown = TRUE))
      res <- DBI::dbGetQuery(conn, sql_queries$get_todo_urls)
      return(res$url)
    }
  ),
  private = list(
    config = list(),
    is_dev = function() {
      pkgload::is_dev_package("taRantula")
    },
    cleanup = function() {
      # Handy Snapshots and Logs
      try(private$handle_snapshots(), silent = TRUE)
      try(private$handle_logs(), silent = TRUE)

      # Remove Snapshot/Folder Directories
      try(
        {
          if (fs::dir_exists(private$config$snapshot_dir)) {
            fs::dir_delete(private$config$snapshot_dir)
          }
          if (fs::dir_exists(private$config$progress_dir)) {
            fs::dir_delete(private$config$progress_dir)
          }
        },
        silent = TRUE)

      # Close DB Conection
      con <- private$config$conn
      if (!is.null(con)) {
        try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
        private$config$conn <- NULL
      }

      # Optionen zurücksetzen
      try(options(private$config$saved_options), silent = TRUE)
    },
    finalize = function() {
      private$cleanup()
    },
    init_storage = function() {
      .init_storage(
        db_file = private$config$db_file,
        snapshot_dir = private$config$snapshot_dir,
        progress_dir = private$config$progress_dir,
        data_dir = private$config$data_dir
      )
    },
    get_scraped_urls = function() {
      .get_scraped_urls(
        db_file = private$config$db_file
      )
    },
    split_into_chunks = function(x, k) {
      if (inherits(x, "data.frame")) {
        n <- nrow(x)
      } else {
        n <- length(x)
      }

      # Ensure k is within a valid range
      k <- max(1L, min(k, n))

      # Create block IDs by repeating chunk indices up to length n
      idx <- sort(rep(seq_len(k), length.out = n))

      # Split based on the detected structure
      return(split(x, idx))
    },
    handle_snapshots = function() {
      .handle_snapshots(
        snapshot_dir = private$config$snapshot_dir,
        data_dir = private$config$data_dir,
        db_file = private$config$db_file
      )
    },
    handle_domaincheck = function() {
      .handle_domaincheck(
        db_file = private$config$db_file
      )
    },
    handle_logs = function() {
      .handle_logs(
        progress_dir = private$config$progress_dir,
        db_file = private$config$db_file
      )
    },
    handle_robots = function() {
      .handle_robots(
        db_file = private$config$db_file,
        robots_config = private$config$robots
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
      # Retrieve and filter links based on provided patterns
      results_links <- .extract_results(
        db_file = private$config$db_file,
        tab = "links",
        filter = NULL
      )

      if (!is.null(filter_links)) {
        filter_links <- paste(filter_links, collapse = "|")
        results_links <- results_links[
          href %ilike% filter_links | label %ilike% filter_links
        ]
      }

      # Extract relevant document content
      results_docs <- .extract_results(
        db_file = private$config$db_file,
        tab = "full_results",
        filter = NULL
      )

      # Filter documents to match processed links with successful scrape status
      results_docs <- results_docs[url %in% results_links$href & status == TRUE]

      # Apply regex extraction to the filtered document set
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
