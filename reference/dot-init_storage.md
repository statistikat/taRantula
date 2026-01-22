# Initialize DuckDB Storage Structure

Creates the internal DuckDB storage schema if it does not yet exist.
Required directories are created and tables for results, links, logs,
and robots‑permissions are initialized.

## Usage

``` r
.init_storage(db_file, snapshot_dir, progress_dir)
```

## Arguments

- db_file:

  Path to the DuckDB database file.

- snapshot_dir:

  Directory in which intermediate snapshots are stored.

- progress_dir:

  Directory for incremental progress logs.

## Value

Invisibly returns `TRUE` after ensuring that storage is ready.

## Details

When a DuckDB database already exists, this function performs no
destructive actions and simply returns. Otherwise, it:

- Connects to the DuckDB file

- Creates four tables (if not already present):

  - **results** – scraped pages with status, HTML, timestamps

  - **links** – extracted hyperlinks with labels and metadata

  - **logs** – progress tracking entries

  - **robots** – stored robots.txt permissions for visited domains

All table definitions include primary keys to ensure data integrity.

## See also

[UrlScraper](https://statistikat.github.io/taRantula/reference/UrlScraper.md)
