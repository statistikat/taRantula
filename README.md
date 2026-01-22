# taRantula

**taRantula** is an `R` package designed for robust, large-scale web scraping. It combines the flexibility of Selenium with the speed of `httr`, backed by a persistent DuckDB storage engine to ensure data integrity.

---

## Key Features

* **Hybrid Scraping Engine**: Seamlessly switch between **Selenium 4** (for JS-heavy sites) and **httr** (for high-speed static content).
* **Persistent Storage**: All results are written directly to a **DuckDB** backend, allowing for SQL-based querying and zero data loss.
* **Selenium Grid Ready**: Optimized for containerized Hub/Node architectures and high-memory environments.
* **Fault Tolerance**: Features a snapshotting mechanism to resume interrupted jobs from the last stable state.
* **Parallel Processing**: Scales across multiple workers using the `future` framework.
* **Regex Data Mining**: High-performance extraction of emails, VAT/UID numbers, and custom patterns directly from your collected data.

## Configuration (`params_manager`)

The package uses a robust, `R6`-based configuration system with strict type validation:

* **`params_scraper()`**: General web crawling and JS rendering settings.
* **`params_googlesearch()`**: Specialized config for Google Search API and rate-limit handling.
* **YAML Support**: Easily export or import configurations for reproducible scraping pipelines.

## Compliance and Safety

* **Robots.txt Enforcement**: Automated checking with internal caching to respect site owner preferences.
* **Graceful Termination**: Signaling mechanisms ensure workers exit cleanly without corrupting the database.
* **Redirect Detection**: Logs and tracks URL changes from request to final browser state.

---

## Installation

```r
# Install from GitHub
remotes::install_github("statistikat/taRantula")
```

## Quick Start

Below is a basic example of how to initialize a scraping job using the Selenium engine and DuckDB storage. 

For advanced users looking to run this in a containerized environment, please refer to the **[Intro Vignette: Docker-based Selenium Setup](vignettes/Intro.Rmd)**.

```r
library(taRantula)

# 1. Setup Configuration
cfg <- params_scraper()
cfg$set("selenium$host", "localhost")
cfg$set("selenium$port", 4444L)
cfg$set("storage$path", "scraping_results.duckdb")

# 2. Initialize the Scraper
scraper <- UrlScraper$new(config = cfg)

# 3. Define URLs and Run
urls <- c("[https://example.com](https://example.com)", "[https://r-project.org](https://r-project.org)")
scraper$run(urls)

# 4. Extract Data (e.g., Email addresses)
emails <- scraper$regex_extract(pattern = "email")

# 5. Graceful Stop
scraper$stop()
```

## Production Deployment

For production environments, the package includes `docker-compose` templates to spin up a **Selenium Grid** alongside your R environment. Detailed instructions are available in the documentation vignettes.
