# Handle and Import Snapshot Files into the DuckDB Database

Processes all snapshot `.rds` files found in a given directory, extracts
both scraped content and discovered hyperlinks, and writes them into the
associated DuckDB database.

## Usage

``` r
.handle_snapshots(snapshot_dir, db_file)
```

## Arguments

- snapshot_dir:

  `character(1)` Path to the directory containing snapshot `.rds` files.
  All files matching `snap_*.rds` (recursively) will be processed.

- db_file:

  `character(1)` Path to the DuckDB database file. Must already exist.

## Value

`invisible(TRUE)` on success, or `invisible(NULL)` if no snapshots
exist.

On errors during database insertion, the function prints a diagnostic
message and leaves the snapshot files untouched.

## Details

This function is designed for use in a snapshot‑based web‑scraping
workflow: each snapshot contains scraped page data (`content`) and
extracted hyperlinks (`links`). The function:

- Reads all pending snapshot files

- Normalizes and merges the content and link tables

- Inserts/updates records in the DuckDB tables `results` and `links`

- Ensures hierarchical link levels are respected

- Removes snapshot files after successful processing

The function is *side‑effect heavy*: it performs database writes,
link‑level conflict resolution, and deletes files once processed.

Snapshot files are expected to contain a list with at least two
elements:

- `content`: A `data.table` holding scraped page data

- `links`: A list of link records, each convertible to `data.table`

The `links` table must contain at least:

- `href` — Discovered link

- `label` — Link label

- `source_url` — URL from which the link was extracted

- `scraped_at` — The timestamp of scraping

Link levels are assigned as follows:

- Level 1 for previously unseen base URLs

- Otherwise, `max(existing level) + 1`

Updates use `INSERT ... ON CONFLICT (...) DO UPDATE`, but only when the
proposed new level is *lower* than the existing one (i.e., a "shorter
path").

## Database Requirements

The DuckDB database must contain the following tables:

- `results` with compatible columns matching `batch_content`

- `links` with columns `href`, `label`, `source_url`, `level`,
  `scraped_at`

## Examples

``` r
if (FALSE) { # \dontrun{
# Directory containing snapshot files
dir <- "snapshots/"

# Existing DuckDB database file
db <- "scraper_results.duckdb"

# Process and import all snapshots
.handle_snapshots(snapshot_dir = dir, db_file = db)
} # }
```
