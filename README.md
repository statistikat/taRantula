# taRantula
[![check](https://github.com/statistikat/taRantula/actions/workflows/check.yaml/badge.svg)](https://github.com/statistikat/taRantula/actions/workflows/check.yaml)

**taRantula** is an `R` package for large-scale web scraping. It integrates Selenium for JavaScript-rendered pages and `httr2` for static content, using DuckDB and Parquet files for persistent storage.

---

## Key Features

* **Dual Engines**: Switches between **Selenium 4** (for dynamic JavaScript sites) and **httr2** (for fast static content extraction).
* **Persistent Storage**: Stores scraped data in **Parquet** format, managed via a **DuckDB** backend for SQL-based querying and crash resilience.
* **Selenium Grid Support**: Configured for containerized Hub/Node architectures and high-memory environments.
* **Fault Tolerance**: Includes a snapshotting mechanism to resume interrupted scraping jobs from the last saved state.
* **Parallel Processing**: Distributes workloads across multiple workers using the `future` framework.
* **Search API Integration**: Builds URL candidate lists with Google Custom Search or Brave Search.
* **Regex Extraction**: Extracts emails, VAT/UID numbers, and custom text patterns directly from collected data.

## Configuration (`params_manager`)

The package uses an `R6`-based configuration system with strict type validation:

* **`paramsScraper()`**: Configures general web crawling and browser rendering settings.
* **`paramsGoogleSearch()`**: Configures Google Search queries and rate-limit handling.
* **`paramsBraveSearch()`**: Configures Brave Search queries using `SCRAPING_APIKEY_BRAVE`, with optional URL blacklists via Brave Goggles.
* **YAML Support**: Imports and exports configuration files for reproducible pipelines.

## Compliance and Safety

* **Robots.txt Enforcement**: Automated parsing with internal caching to respect site permissions.
* **Graceful Termination**: Signaling mechanisms ensure workers exit cleanly without corrupting the database.
* **Redirect Tracking**: Logs and tracks URL changes from the initial request to the final browser state.

---

## Installation

```r
# Install from GitHub
remotes::install_github("statistikat/taRantula")
```

## Quick Start

For deployment in containerized environments, see the **[Intro Vignette: Docker-based Selenium Setup](https://statistikat.github.io/taRantula/articles/Intro.html)**.

```r
library(taRantula)

# Configure settings
cfg <- paramsScraper()
cfg$set("selenium$host", "localhost")
cfg$set("selenium$port", 4444L)
cfg$set("storage$path", "scraping_results.duckdb")

# Define target URLs
cfg$set("urls", c("https://www.statistik.at", "https://r-project.org"))

# Initialize the scraper
scraper <- UrlScraper$new(config = cfg)

# Execute job
scraper$scrape()

# Extract data using regex (e.g., emails)
emails <- scraper$regex_extract(pattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+")

# Retrieve full results
results <- scraper$results()

# Shut down cleanly
scraper$stop()
```

## Search URL Candidates

```r
library(taRantula)

Sys.setenv(SCRAPING_APIKEY_BRAVE = "your_brave_search_key")

queries <- data.frame(
  id = 1,
  term = "st-georgen-kreischberg"
)
queries$query <- buildQuery(queries, selectCols = "term")

cfg <- paramsBraveSearch(
  id_col = "id",
  query_col = "query",
  blacklisted_urls = "https://www.st-georgen-kreischberg.gv.at/",
  scrape_attributes = c("title", "link", "displayLink", "snippet"),
  verbose = FALSE
)

urls <- searchURL(
  cfg = cfg,
  dat = queries,
  file = NULL,
  query_col = "query"
)
```

## Production Deployment

The package includes `docker-compose` templates to deploy a **Selenium Grid** alongside the `R` environment. Detailed instructions are available in the documentation vignettes.
