# taRantula 0.1.0

### Main Features
* **Persistent Storage**: Implemented **DuckDB** backend for all scraping jobs. This ensures data is persisted to disk immediately, preventing data loss and allowing for standard SQL querying of results.
* **Selenium Grid Integration**: Full support for **Selenium 4** Hub/Node architectures. The system is optimized for containerized environments with high memory demands.
* **Redirect Detection**: Introduced logic to detect and log URL redirects by comparing initial request URLs with final browser state; results are stored in the `url_redirect` field.
* **Fault Tolerance**: Introduced a **snapshotting mechanism** that periodically saves worker progress. This allows the scraper to resume from the last stable state in the event of a system or network crash.
* **Parallel Processing**: Integrated `future` and `future.apply` for multi-worker scraping, enabling simultaneous browser sessions across the Selenium Grid.

### Configuration (`params_manager`)
* **R6-based Config System**: Introduced a robust, hierarchical configuration system with strict validation logic.
    * `params_scraper()`: Dedicated configuration for generic web crawling and JS rendering.
    * `params_googlesearch()`: Tailored configuration for Google Search API interactions including rate-limit management.
* **Deep Merging**: Configuration methods now support nested path updates (e.g., `cfg$set("selenium$host", ...)`). 
* **Validation**: Built-in defensive programming with type-checking for integers, booleans, character vectors, and directory paths.
* **Export/Import functionality**: Added `$export()` and `$write_defaults()` methods to support YAML-based configuration round-trips.

### Scraping Implementation (`UrlScraper`)
* **Hybrid Engine Support**: Implemented a polymorphic scraping logic that switches between **Selenium** and **httr** (for high-speed static scraping) based on configuration.
* **Regex Extraction**: Added the `$regex_extract()` method for high-performance data mining (e.g., extracting VAT/UID numbers or Email addresses) directly from the persistent database.
* **Compliance**: Automated **robots.txt** enforcement with an internal cache to reduce overhead when hitting the same domain multiple times.
* **Graceful Termination**: Implemented a `$stop()` signaling mechanism that allows parallel workers to finish their current URL and exit cleanly without corrupting the DuckDB file.

### Documentation & Testing
* **Vignettes**: Created a "Getting Started" guide covering dual-engine setup and production-ready `docker-compose` templates.
* **Unit Tests**: Implemented `testthat` suite containing unit-tests, mainly for the configuration part.
