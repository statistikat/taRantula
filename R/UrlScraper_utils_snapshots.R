#' Handle and Import Snapshot Files into the DuckDB Database
#'
#' Processes all snapshot .rds files in a directory, saves scraped content to
#' Parquet archives, and updates the DuckDB database with the associated metadata.
#'
#' This function integrates snapshot data into the primary storage workflow.
#' It reads individual snapshot files, consolidates them, and separates metadata
#' from raw content. While metadata is written to the results table in DuckDB,
#' the raw HTML and link information are persisted in compressed Parquet files.
#'
#' @param snapshot_dir Character path to the directory containing snapshot .rds files.
#' @param data_dir Character path to the directory for Parquet storage.
#' @param db_file Character path to the existing DuckDB database file.
#'
#' @return Invisible TRUE on success, or invisible NULL if no snapshots exist.
#'
#' @section Database Requirements:
#' The DuckDB database must contain a results table compatible with the
#' metadata structure. The function automatically triggers a view update upon
#' successful data insertion.
#'
#' @keywords internal
#' @noRd
.handle_snapshots <- function(snapshot_dir, data_dir, db_file) {
  . <- scraped_at <- src <- url_redirect <- status <- links <- url_actual <- NULL

  if (!fs::dir_exists(snapshot_dir)) {
    return(NULL)
  }

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
  conn <- DBI::dbConnect(duckdb::duckdb(db_file, read_only = FALSE))
  on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)

  # Process files in batches to manage memory consumption
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
          base::readRDS(f)
        })
        batch_content <- rbindlist(raw_data)

        batch_content[, status := ifelse(status == TRUE, "success", "failed_scraping")]
        batch_content$scraped_at <- as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), tz = "UTC")

        parquet_filename <- sprintf("batch_%s.parquet", format(Sys.time(), "%Y%m%d_%H%M%S_%s"))
        parquet_path <- fs::path(data_dir, parquet_filename)

        # Save raw content and link lists as compressed Parquet files
        arrow::write_parquet(
          x = batch_content[, .(url, scraped_at, src, links)],
          sink = parquet_path,
          compression = "zstd"
        )

        # Extract metadata for the results table (no src!)
        meta_content <- batch_content[, .(
          url,
          url_actual,
          url_redirect,
          status,
          file_path = parquet_path,
          scraped_at
        )]

        DBI::dbWithTransaction(conn, {
          # Remove outdated entries for processed URLs
          urls_in_batch <- paste0("'", unique(meta_content$url), "'", collapse = ",")
          DBI::dbExecute(
            conn = conn,
            statement = glue::glue(sql_queries$delete_results_by_url, urls_in_batch = urls_in_batch)
          )

          # Insert current batch metadata
          DBI::dbWriteTable(
            conn = conn,
            name = "results",
            value = meta_content,
            append = TRUE
          )

          # Refresh database views to include new data
          .setup_database_views(conn, data_dir)
        })

        # Remove processed snapshot files
        fs::file_delete(group)
        return(TRUE)
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
#'   Identifier of the current chunk. Used in output file names.
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
  f <- fs::path(snapshot_dir, glue::glue("snap_chunk{chunk_id}_{ts}.rds"))
  base::saveRDS(dt, file = f)
  return(dt[0])
}
