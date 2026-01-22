# Initialize Scraper Configuration

Internal utility that prepares and normalizes the configuration list
used by the `UrlScraper` class. This includes creating required
directories, setting file paths, determining pending URLs, and applying
global options needed during scraping.

## Usage

``` r
.initialize(config)
```

## Arguments

- config:

  A `cfg_scraper` configuration object.

## Value

A normalized configuration list ready for use by the scraping engine.

## Details

The function performs the following steps:

- Validates that the provided configuration object is a `cfg_scraper`
  instance

- Constructs the project directory under `base_dir`

- Creates required subfolders for snapshots, progress files, and the
  DuckDB database

- Initializes the URL queue (`urls_todo`) and marks none as scraped
  initially

- If an existing DuckDB file is found, previously scraped URLs are
  loaded and removed from the queue

- Stores the current global R options and applies scraper‑specific
  defaults

This function is called automatically inside the `UrlScraper`
constructor and should not be used directly.

## See also

[cfg_scraper](https://statistikat.github.io/taRantula/reference/paramsScraper.md),
[UrlScraper](https://statistikat.github.io/taRantula/reference/UrlScraper.md)
