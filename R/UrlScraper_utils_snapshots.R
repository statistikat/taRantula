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
#' @keywords internal
#' @noRd
.handle_snapshots <- function(snapshot_dir, db_file) {
  snaps <- fs::dir_ls(
    path = snapshot_dir,
    regexp = "snap_.*\\.rds$",
    type = "file",
    recurse = TRUE
  )

  batch_size <- 100

  if (length(snaps) == 0) {
    return(invisible(NULL))
  }

  # Connect to DB
  con <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # Split files into batches
  snap_groups <- split(snaps, ceiling(seq_along(snaps) / batch_size))
  total_groups <- length(snap_groups)
  for (i in seq_along(snap_groups)) {
    group <- snap_groups[[i]]
    group_size <- length(group)
    cli::cli_alert_info(
      glue::glue(
        "Processing snapshot batch ({i}/{total_groups}) with {group_size} files..."
      )
    )

    res <- tryCatch(
      expr = {
        # Read data from current batch
        raw_data <- lapply(group, function(f) {
          tmp <- base::readRDS(f)
          links <- data.table::rbindlist(tmp$links)
          tmp$links <- NULL
          list(content = data.table::setDT(tmp), links = links)
        })

        batch_content <- data.table::rbindlist(lapply(
          raw_data, `[[`, "content"
        ))
        batch_links <- data.table::rbindlist(lapply(raw_data, `[[`, "links"))
        rm(raw_data)
        gc()

        DBI::dbWithTransaction(con, {
          # Write Content
          DBI::dbWriteTable(
            conn = con,
            name = "tmp_content",
            value = batch_content,
            overwrite = TRUE,
            temporary = TRUE
          )
          DBI::dbExecute(
            conn = con,
            statement = "INSERT OR REPLACE INTO results SELECT * FROM tmp_content"
          )

          if (nrow(batch_links) > 0) {
            # Add links to temporary table
            DBI::dbWriteTable(
              conn = con,
              name = "tmp_links_raw",
              value = batch_links,
              overwrite = TRUE,
              temporary = TRUE
            )

            # Compute level in SQL (faster than in R)
            DBI::dbExecute(
              conn = con,
              statement = "
              INSERT INTO links (href, label, source_url, level, scraped_at)
              SELECT
                  t.href,
                  t.label,
                  t.source_url,
                  COALESCE(l.level + 1, 2) as level,
                  t.scraped_at
              FROM tmp_links_raw t
              LEFT JOIN links l ON t.source_url = l.href
              ON CONFLICT (href, scraped_at) DO UPDATE SET
                  level = EXCLUDED.level,
                  source_url = EXCLUDED.source_url
              WHERE EXCLUDED.level < links.level
          "
            )
          }

          # Cleanup
          DBI::dbExecute(conn = con, statement = "DROP TABLE IF EXISTS tmp_content")
          DBI::dbExecute(conn = con, statement = "DROP TABLE IF EXISTS tmp_links_raw")
        })

        fs::file_delete(group)
        TRUE
      },
      error = function(e) {
        cli::cli_alert_danger(
          glue::glue("Error in snapshot batch {i}: {e$message}")
        )
        return(FALSE)
      }
    )

    if (!res) {
      break
    }
    gc()
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
#' @keywords internal
#' @noRd
.write_snapshot <- function(dt, chunk_id, snapshot_dir) {
  stopifnot(data.table::is.data.table(dt))
  ts <- format(Sys.time(), "%Y%m%dT%H%M%S")
  f <- fs::path(snapshot_dir, sprintf("snap_chunk%02d_%s.rds", chunk_id, ts))
  base::saveRDS(dt, file = f)
  return(dt[0])
}
