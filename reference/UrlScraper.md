# UrlScraper R6 Class for Parallel Web Scraping with Selenium

The `UrlScraper` R6 class provides a high‑level framework for scraping a
list of URLs using multiple parallel Selenium (or non‑Selenium) workers.
It manages scraping state, progress, snapshots, logs, and respects
`robots.txt` rules. Results and logs are stored in an internal DuckDB
database.

## Format

An R6 class generator of class `UrlScraper`.

## Overview

The `UrlScraper` class is designed for robust, resumable web scraping
workflows. Its key features include:

- Parallel scraping of URLs via multiple Selenium workers

- Persistent storage of results, logs, and extracted links in DuckDB

- Automatic snapshotting and recovery of partially processed chunks

- Respecting `robots.txt` rules via pre‑checks on domains

- Convenience helpers for querying results, logs, and extracted links

- Regex‑based extraction of text from previously scraped HTML

## Configuration

A configuration object (typically created via
[paramsScraper](https://statistikat.github.io/taRantula/reference/paramsScraper.md))
is expected to contain at least the following entries:

- `db_file` – path to the DuckDB database file

- `snapshot_dir` – directory for temporary snapshot files

- `progress_dir` – directory for progress/log files

- `stop_file` – path to a file used to signal workers to stop

- `urls` / `urls_todo` – vectors of URLs and URLs still to scrape

- `selenium` – list with Selenium‑related settings, such as:

  - `use_selenium` – logical, whether to use Selenium

  - `workers` – number of parallel Selenium workers

  - `host`, `port`, `browser`, `verbose` – Selenium connection settings

  - `ecaps` – list with Chrome options (`args`, `prefs`,
    `excludeSwitches`)

  - `snapshot_every` – number of URLs after which a snapshot is taken

- `robots` – list with `robots.txt` handling options, such as:

  - `check` – logical, whether to check `robots.txt`

  - `snapshot_every` – snapshot frequency for robots checks

  - `workers` – number of workers for `robots.txt` checks

  - `robots_user_agent` – user agent string used for robots queries

- `exclude_social_links` – logical, whether to exclude social media
  links

The exact structure depends on
[paramsScraper](https://statistikat.github.io/taRantula/reference/paramsScraper.md)
and related helpers.

## Methods

- `initialize(config)` – create a new `UrlScraper` instance

- `scrape()` – scrape all remaining URLs in parallel

- `update_urls(urls, force = FALSE)` – add new URLs to the queue

- `results(filter = NULL)` – extract scraping results

- `logs(filter = NULL)` – extract log entries

- `links(filter = NULL)` – extract discovered links

- `query(q)` – run custom SQL queries on the internal DuckDB database

- `regex_extract(pattern, group = NULL, filter_links = NULL, ignore_cases = TRUE)`
  – extract text via regex from scraped HTML

- [`stop()`](https://rdrr.io/r/base/stop.html) – create a stop‑file so
  workers can exit gracefully

- [`close()`](https://rdrr.io/r/base/connections.html) – clean up
  snapshots and close database connections

## Methods

### Public methods

- [`UrlScraper$new()`](#method-UrlScraper-new)

- [`UrlScraper$scrape()`](#method-UrlScraper-scrape)

- [`UrlScraper$update_urls()`](#method-UrlScraper-update_urls)

- [`UrlScraper$results()`](#method-UrlScraper-results)

- [`UrlScraper$logs()`](#method-UrlScraper-logs)

- [`UrlScraper$links()`](#method-UrlScraper-links)

- [`UrlScraper$query()`](#method-UrlScraper-query)

- [`UrlScraper$regex_extract()`](#method-UrlScraper-regex_extract)

- [`UrlScraper$stop()`](#method-UrlScraper-stop)

- [`UrlScraper$close()`](#method-UrlScraper-close)

- [`UrlScraper$clone()`](#method-UrlScraper-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new `UrlScraper` object.

This constructor initializes the internal storage (DuckDB database,
snapshot and progress directories), restores previous snapshots/logs if
present, and configures progress handlers.

#### Usage

    UrlScraper$new(config)

#### Arguments

- `config`:

  A list (or configuration object) of settings, typically created by
  [`paramsScraper()`](https://statistikat.github.io/taRantula/reference/paramsScraper.md).
  It should include:

  - `db_file` – path to the DuckDB database file.

  - `snapshot_dir` – directory for snapshot files.

  - `progress_dir` – directory for progress/log files.

  - `stop_file` – path to the stop signal file.

  - `urls_todo` – character vector of URLs still to be scraped.

  - `selenium` – list of Selenium settings (host, port, workers, etc.).

  - `robots` – list of `robots.txt` handling options.

  - any additional options required by helper functions.

#### Returns

An initialized `UrlScraper` object (invisibly).

------------------------------------------------------------------------

### Method `scrape()`

Scrape all remaining URLs using parallel workers.

#### Usage

    UrlScraper$scrape()

#### Details

This method orchestrates the parallel scraping process:

- Re‑initializes storage and processes any existing snapshots or logs.

- Computes the set of URLs still to scrape.

- Optionally performs `robots.txt` checks on new domains.

- Sets up a parallel plan via the `future` framework.

- Starts multiple Selenium (or non‑Selenium) sessions.

- Distributes URLs across workers and tracks global progress.

- Cleans up snapshots/logs and updates internal URL state after
  scraping.

If a stop‑file is detected (see
[`stop()`](https://rdrr.io/r/base/stop.html)), scraping is aborted
before starting. Workers themselves will also honor the stop‑file to
terminate gracefully after finishing the current URL.

#### Returns

The `UrlScraper` object (invisibly), with internal state updated to
reflect newly scraped URLs.

------------------------------------------------------------------------

### Method `update_urls()`

Update the list of URLs to be scraped.

#### Usage

    UrlScraper$update_urls(urls, force = FALSE)

#### Arguments

- `urls`:

  A character vector of new URLs to add.

- `force`:

  A logical flag. If `TRUE`, all given URLs are kept except for
  duplicates within `urls` itself (no check against already scraped
  URLs). If `FALSE` (default), URLs already in the database and
  duplicates in `urls` are removed.

#### Details

This method updates the internal URL queue based on the given input
vector `urls`. Depending on `force`:

- If `force = FALSE` (default), URLs that have already been scraped
  (i.e. present in the results database) are removed, as well as
  duplicates within the `urls` vector itself.

- If `force = TRUE`, only duplicates within the given `urls` vector are
  removed; URLs that are already present in the database are kept.

Summary information about how many URLs were added, already known, or
duplicates is printed via `cli`.

#### Returns

The `UrlScraper` object (invisibly).

------------------------------------------------------------------------

### Method `results()`

Extract scraping results from the internal database.

#### Usage

    UrlScraper$results(filter = NULL)

#### Arguments

- `filter`:

  Optional character string with a SQL‑like `WHERE` condition (without
  the `WHERE` keyword), e.g. `"url LIKE 'https://example.com/%'"`. If
  `NULL` (default), all rows from the `results` table are returned.

#### Returns

A `data.table` containing the scraping results.

------------------------------------------------------------------------

### Method `logs()`

Extract log entries from the internal database.

#### Usage

    UrlScraper$logs(filter = NULL)

#### Arguments

- `filter`:

  Optional character string with a SQL‑like `WHERE` condition (without
  the `WHERE` keyword). If `NULL` (default), all rows from the `logs`
  table are returned.

#### Returns

A `data.table` containing the log entries.

------------------------------------------------------------------------

### Method `links()`

Extract scraped links from the internal database.

#### Usage

    UrlScraper$links(filter = NULL)

#### Arguments

- `filter`:

  Optional character string with a SQL‑like `WHERE` condition (without
  the `WHERE` keyword). If `NULL` (default), all rows from the `links`
  table are returned.

#### Returns

A `data.table` containing the extracted links.

------------------------------------------------------------------------

### Method `query()`

Execute a custom SQL query against the internal DuckDB database.

This is a low‑level helper for advanced use cases. It assumes that the
user is familiar with the schema of the internal database (tables such
as `results`, `logs`, `links`, and any others created by helper
functions).

#### Usage

    UrlScraper$query(q)

#### Arguments

- `q`:

  A character string containing a valid DuckDB SQL query.

#### Returns

The result of the query, typically a `data.table`.

------------------------------------------------------------------------

### Method `regex_extract()`

Extract text from scraped HTML using a regular expression.

#### Usage

    UrlScraper$regex_extract(
      pattern,
      group = NULL,
      filter_links = NULL,
      ignore_cases = TRUE
    )

#### Arguments

- `pattern`:

  A character string containing a regular expression. Named capture
  groups are supported.

- `group`:

  Either:

  - A character string naming a capture group (e.g. `"name"` if the
    pattern contains `(?<name>...)`), or

  - An integer specifying the index of the capture group to return. If
    `NULL` (default), the behavior is delegated to
    [`.extract_regex()`](https://statistikat.github.io/taRantula/reference/dot-extract_regex.md)
    and may return all groups depending on its implementation.

- `filter_links`:

  A character vector containing keywords or partial words used to filter
  the set of URLs from which `pattern` will be extracted. For example,
  `filter_links = "imprint"` restricts the extraction to URLs whose
  `href` or `label` contains "imprint".

- `ignore_cases`:

  Logical. If `TRUE` (default), case is ignored when matching `pattern`.
  If `FALSE`, the pattern is matched in a case‑sensitive way.

#### Details

This helper performs a post‑processing step on the stored HTML sources
in the `results` table:

1.  It first selects links from the `links` table whose `href` or
    `label` match the provided `filter_links` terms.

2.  It then identifies those documents (rows in `results`) whose `url`
    is among the selected links and that have `status == TRUE`.

3.  Finally, it applies a regular expression to the HTML source of those
    documents and returns the extracted matches.

This is particularly useful for extracting structured information such
as email addresses, phone numbers, or IDs from a subset of pages (e.g.
contact or imprint pages).

#### Returns

A `data.table` (or similar object) returned by
[`.extract_regex()`](https://statistikat.github.io/taRantula/reference/dot-extract_regex.md),
typically containing the matched text and the corresponding URLs.

------------------------------------------------------------------------

### Method [`stop()`](https://rdrr.io/r/base/stop.html)

Create a stop‑file to signal running workers to terminate gracefully.

#### Usage

    UrlScraper$stop()

#### Details

Workers periodically check for the existence of the configured
`stop_file`. When it is present, they will finish processing the current
URL and then exit. This allows for a controlled shutdown of a
long‑running scraping job without abruptly terminating the R session or
Selenium instances.

#### Returns

Invisible `NULL`.

------------------------------------------------------------------------

### Method [`close()`](https://rdrr.io/r/base/connections.html)

Clean up resources, including snapshots and database connections.

#### Usage

    UrlScraper$close()

#### Details

This method performs the following clean‑up steps:

- Processes any remaining snapshots and logs.

- Deletes the snapshot directory (if it exists).

- Opens a DuckDB connection to the configured `db_file` and disconnects
  it with `shutdown = TRUE`.

It is good practice to call
[`close()`](https://rdrr.io/r/base/connections.html) once you are done
with a `UrlScraper` instance.

#### Returns

Invisible `NULL`.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    UrlScraper$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r
if (FALSE) { # \dontrun{
# Create a default configuration object
cfg <- paramsScraper()

# Example Selenium settings
cfg$set("selenium$host", "localhost")
cfg$set("selenium$workers", 2)
cfg$show_config()

# Initialize the scraper
scraper <- UrlScraper$new(config = cfg)

# Start scraping remaining URLs
scraper$scrape()

# Retrieve results as a data.table
results_dt <- scraper$results()

# Retrieve logs and links
logs_dt  <- scraper$logs()
links_dt <- scraper$links()

# Add new URLs to be scraped (only those not already in the DB)
scraper$update_urls(urls = c("https://example.com/"))

# Force adding URLs (ignores duplicates against already scraped ones)
scraper$update_urls(urls = c("https://example.com/"), force = TRUE)

# Regex extraction from scraped HTML
emails_dt <- scraper$regex_extract(
  pattern      = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
  filter_links = c("contact", "imprint")
)

# Stop ongoing workers after they finish the current URL
scraper$stop()

# Clean up resources
scraper$close()
} # }
```
