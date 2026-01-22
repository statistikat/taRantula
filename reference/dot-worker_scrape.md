# Worker Function for Batched URL Scraping

This internal function orchestrates the scraping of multiple URLs in
parallel processing contexts. It manages progress logging, snapshot
creation, robots.txt validation, and stopping conditions.

## Usage

``` r
.worker_scrape(inputs, sid)
```

## Arguments

- inputs:

  A named list containing:

  db_file

  :   Path to the DuckDB file used for robots.txt checks.

  urls

  :   Character vector of URLs to process in this worker.

  chunk_id

  :   Numeric identifier for this worker chunk.

  snapshot_every

  :   Integer: write snapshot files every N URLs.

  snapshot_dir

  :   Directory in which snapshot output is stored.

  stop_file

  :   Path to a file whose existence indicates that scraping should stop
      early.

  progress_dir

  :   Directory for storing progress logs.

  robots_check

  :   Logical indicating whether robots.txt rules should be evaluated.

  p

  :   A progress callback function accepting arguments `amount` and
      `message`.

- sid:

  A Selenium session object or a list of HTTP headers, passed along to
  [`.scrape_single_url()`](https://statistikat.github.io/taRantula/reference/dot-scrape_single_url.md).

## Value

Invisibly returns `TRUE` after completing all scraping tasks assigned to
this worker.

## Details

The function iterates over provided URLs, invoking
[`.scrape_single_url()`](https://statistikat.github.io/taRantula/reference/dot-scrape_single_url.md)
for each. Progress is logged to file, and optional snapshot files store
intermediate results to safeguard against worker interruptions. When the
stop file is detected, the worker terminates early. Any remaining
un-snapshotted results are written at the end of execution.

## Examples

``` r
if (FALSE) { # \dontrun{
# Inside a parallel worker
.worker_scrape(
  inputs = list(
    db_file = "mydb.duckdb",
    urls = c("https://example1.com", "https://example2.com"),
    chunk_id = 1,
    snapshot_every = 50,
    snapshot_dir = "snapshots/",
    stop_file = "stop.flag",
    progress_dir = "progress/",
    robots_check = TRUE,
    p = function(amount, message) cat(amount, message, "\n")
  ),
  sid = my_selenium_session
)
} # }
```
