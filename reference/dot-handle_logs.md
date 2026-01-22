# Import and Store Scraping Log Files

Reads individual progress log files generated during scraping, parses
their contents, and inserts the collected entries into the `logs` table
of the DuckDB results database. After successful insertion, processed
log files are removed from the filesystem.

## Usage

``` r
.handle_logs(progress_dir, db_file)
```

## Arguments

- progress_dir:

  Path to the directory containing log files produced during scraping.

- db_file:

  Path to the DuckDB database file where logs should be stored.

## Value

Invisibly returns `TRUE` after logs have been imported and (if possible)
the corresponding files removed.

## Details

The function performs the following actions:

- Scans the `progress_dir` for log files created by parallel scraper
  workers

- Parses each log file line‑by‑line, splitting entries into:

  - timestamp

  - chunk/work‑unit identifier

  - URL currently being processed

- Converts parsed entries into a data frame suitable for database
  storage

- Inserts all log entries into the DuckDB `logs` table using
  `"INSERT OR IGNORE"` to avoid duplicates

- Removes successfully processed log files

Log files are expected to contain tab‑separated entries created by
worker processes. Files that are empty or unreadable are automatically
discarded.

## See also

- The `logs` table created in the scraper database structure

- Worker‑level logging functions within the scraper implementation
