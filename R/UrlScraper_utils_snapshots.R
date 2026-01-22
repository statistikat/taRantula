
#' Handle and Import Snapshot Files into the DuckDB Database
#'
#' Processes all snapshot `.rds` files found in a given directory, extracts both
#' scraped content and discovered hyperlinks, and writes them into the associated
#' DuckDB database.  
#'
#' This function is designed for use in a snapshot‑based web‑scraping workflow:
#' each snapshot contains scraped page data (`content`) and extracted hyperlinks
#' (`links`). The function:
#'
#' - Reads all pending snapshot files  
#' - Normalizes and merges the content and link tables  
#' - Inserts/updates records in the DuckDB tables `results` and `links`  
#' - Ensures hierarchical link levels are respected  
#' - Removes snapshot files after successful processing  
#'
#' The function is *side‑effect heavy*: it performs database writes, link‑level
#' conflict resolution, and deletes files once processed.
#'
#' @param snapshot_dir `character(1)`  
#'   Path to the directory containing snapshot `.rds` files.
#'   All files matching `snap_*.rds` (recursively) will be processed.
#'
#' @param db_file `character(1)`  
#'   Path to the DuckDB database file. Must already exist.
#'
#' @return  
#' `invisible(TRUE)` on success, or `invisible(NULL)` if no snapshots exist.
#'  
#' On errors during database insertion, the function prints a diagnostic message
#' and leaves the snapshot files untouched.
#'
#' @details  
#' Snapshot files are expected to contain a list with at least two elements:
#'
#' - `content`: A `data.table` holding scraped page data  
#' - `links`: A list of link records, each convertible to `data.table`  
#'
#' The `links` table must contain at least:
#'
#' - `href` — Discovered link  
#' - `label` — Link label  
#' - `source_url` — URL from which the link was extracted  
#' - `scraped_at` — The timestamp of scraping  
#'
#' Link levels are assigned as follows:
#'
#' - Level 1 for previously unseen base URLs  
#' - Otherwise, `max(existing level) + 1`  
#'
#' Updates use `INSERT ... ON CONFLICT (...) DO UPDATE`, but only when the
#' proposed new level is *lower* than the existing one (i.e., a "shorter path").
#'
#' @section Database Requirements:
#' The DuckDB database must contain the following tables:
#'
#' - `results` with compatible columns matching `batch_content`  
#' - `links` with columns `href`, `label`, `source_url`, `level`, `scraped_at`  
#'
#' @examples
#' \dontrun{
#' # Directory containing snapshot files
#' dir <- "snapshots/"
#'
#' # Existing DuckDB database file
#' db <- "scraper_results.duckdb"
#'
#' # Process and import all snapshots
#' .handle_snapshots(snapshot_dir = dir, db_file = db)
#' }
#'
#' @keywords internal

.handle_snapshots <- function(snapshot_dir, db_file) {
  url_redirect <- NULL
  snaps <- fs::dir_ls(
    path = snapshot_dir,
    regexp = "snap_.*\\.rds$",
    type = "file",
    recurse = TRUE
  )

  if (length(snaps) == 0) {
    return(invisible(NULL))
  }

  batch <- lapply(snaps, function(f) {
    tmp <- readRDS(f)
    links <- rbindlist(tmp$links)
    data.table::set(tmp, j = "links", value = NULL)
    list(content = data.table::setDT(tmp), links = data.table::setDT(links))
  })

  batch_content <- data.table::rbindlist(lapply(batch, function(x) {
    x$content
  }))

  if (nrow(batch_content) == 0) {
    fs::file_delete(snaps)
    return(invisible())
  }
  batch_links <- data.table::rbindlist(lapply(batch, function(x) {
    x$links
  }))

  stopifnot(fs::file_exists(db_file))
  con <- DBI::dbConnect(
    drv = duckdb::duckdb(db_file, read_only = FALSE)
  )
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  res <- tryCatch(
    expr = DBI::dbWithTransaction(con, {
      DBI::dbWriteTable(con, "tmp", batch_content, overwrite = TRUE)
      DBI::dbExecute(con, "INSERT OR REPLACE INTO results SELECT * FROM tmp")
      DBI::dbExecute(con, "DROP TABLE tmp")

      # Handle hrefs
      if (nrow(batch_links) > 0) {
        spl <- split(batch_links, batch_links$source_url)
        for (i in seq_len(length(spl))) {
          baseurl <- spl[[i]]$source_url[1]
          lev <- DBI::dbGetQuery(
            conn = con,
            statement = glue::glue(
              "SELECT max(level) AS lev FROM
              links WHERE href = {shQuote(baseurl)}"
            )
          )$lev

          if (is.na(lev)) {
            # we need to store also the initial link
            sql_statement <- "INSERT INTO
              links (href, label, source_url, level, scraped_at)
              VALUES (?, ?, ?, ?, ?)"

            ref_url <- batch_content[url_redirect == baseurl]$url[1]
            ref_url <- ifelse(length(ref_url), baseurl, ref_url)
            ll <- list(
              baseurl,
              paste(baseurl, "-", "Redirected_Baseurl"),
              ref_url,
              1,
              min(spl[[i]]$scraped_at)
            )
            DBI::dbExecute(
              conn = con,
              statement = sql_statement,
              params = ll
            )
            spl[[i]]$level <- 2
          } else {
            spl[[i]]$level <- lev + 1
          }

          DBI::dbWriteTable(con, "temp_new_links", spl[[i]], overwrite = TRUE)
          DBI::dbExecute(
            conn = con,
            statement = "INSERT INTO links (href, label, source_url, level, scraped_at)
            SELECT href, label, source_url, level, scraped_at
            FROM temp_new_links
            -- When a conflict on the PRIMARY KEY (href) occurs
            -- update only if level is lower than existing level
            ON CONFLICT (href, scraped_at)
            DO UPDATE SET
              level = EXCLUDED.level,
              source_url = EXCLUDED.source_url,
              scraped_at = EXCLUDED.scraped_at
            WHERE EXCLUDED.level < links.level;
          "
          )
          DBI::dbExecute(con, "DROP TABLE temp_new_links")
        }
      }
    }),
    error = function(e) e
  )

  if (!inherits(res, "error")) {
    # they are now successfully inserted
    # into the database
    try(fs::file_delete(snaps), silent = TRUE)
  } else {
    message("error occured")
    print(res)
  }
  return(invisible(TRUE))
}


#' Write Snapshot File to Disk
#'
#' Saves a data snapshot (`data.table`) to the specified snapshot directory,
#' naming it with the chunk ID and a timestamp. This is typically called during
#' batched scraping operations to persist intermediate results.
#'
#' @param dt A `data.table` containing scraped data and extracted links.
#' @param chunk_id `integer(1)`  
#'   Identifier of the current chunk. Used in file naming as `snap_chunkXX_*`.
#' @param snapshot_dir `character(1)`  
#'   Directory where the snapshot file will be written.
#'
#' @return  
#' `invisible(NULL)`. The function writes a `.rds` file as a side effect.
#'
#' @examples
#' \dontrun{
#' dt <- data.table::data.table(
#'   url = "https://example.com",
#'   scraped_at = Sys.time(),
#'   html = "<html></html>"
#' )
#'
#' .write_snapshot(dt, chunk_id = 1, snapshot_dir = "snapshots/")
#' }
#'
#' @keywords internal
.write_snapshot <- function(dt, chunk_id, snapshot_dir) {
  stopifnot(data.table::is.data.table(dt))
  ts <- format(Sys.time(), "%Y%m%dT%H%M%S")
  f <- fs::path(snapshot_dir, sprintf("snap_chunk%02d_%s.rds", chunk_id, ts))
  saveRDS(dt, file = f)
  return(invisible(NULL))
}
