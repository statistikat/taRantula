# taRantula 0.2.0

### Main Features
* **Storage Refactoring**: Moved raw scraping data (source code and link metadata) from the database into `parquet` files under `{project_dir}/data`.
* **Brave Search Support**: `searchURL()` now supports the Brave Search API via `paramsBraveSearch()` and `SCRAPING_APIKEY_BRAVE`, returning Google-compatible result columns for downstream workflows.
* **Brave Search URL Blacklists**: `paramsBraveSearch()` now accepts `blacklisted_urls`, writes them to a temporary `.goggle` file, and sends the generated Goggles rules to Brave Search.
* **Database Schema Changes**:
    * Added a `urls` table to store all target URLs.
    * Modified the `results` table to replace raw source code storage with a `file_path` reference to the `parquet` files.
    * Added a `status` column to track URL states (`"todo"`, `"success"`, `"failed_domain"`, `"failed_scraping"`, and `"blocked"`).
    * Replaced the static `links` table with a dynamic view aggregating link data from `parquet` files.
    * Added a `full_results` view that reconstructs the original `results` table structure by joining source code and link data.
* **Scraping Workflow**: Domain reachability and `robots.txt` validations are now executed during a pre-scraping phase. Workers only process pre-validated `"todo"` URLs, removing redundant checks within parallel processes.

### Interface changes (`UrlScraper`)
* **`$results()` Method**: Added a `with_src` parameter (defaults to `TRUE`) to choose between the basic `results` table and the `full_results` view. The method now queries the new view and computes hierarchy levels internally.
* **`$remove_urls()` Method**: Added a new method to delete pending, unscraped URLs from the queue.
* **Active Bindings**:
    * Added `$url_info` to return real-time counts of total, successful, pending, and failed URLs.
    * Added `$urls_todo` to return all pending URLs marked as `"todo"`.

### Internal Quality & Documentation
* **SQL Management**: Centralized SQL queries into a structured `sql_queries` list.
* **Documentation**: Simplified Roxygen documentation and internal utility functions.


# taRantula 0.1.0

### Main Features
* **Persistent Storage**: Implemented **DuckDB** backend for all scraping jobs. This ensures data is persisted to disk immediately, preventing data loss and allowing for standard SQL querying of results.
* **Selenium Grid Integration**: Full support for **Selenium 4** Hub/Node architectures. The system is optimized for containerized environments with high memory demands.
* **Redirect Detection**: Introduced logic to detect and log URL redirects by comparing initial request URLs with final browser state; results are stored in the `url_redirect` field.
* **Fault Tolerance**: Introduced a **snapshotting mechanism** that periodically saves worker progress. This allows the scraper to resume from the last stable state in the event of a system or network crash.
* **Parallel Processing**: Integrated `future` and `future.apply` for multi-worker scraping, enabling simultaneous browser sessions across the Selenium Grid.

### Configuration (`params_manager`)
* **R6-based Config System**: Introduced a robust, hierarchical configuration system with strict validation logic.
    * `paramsScraper()`: Dedicated configuration for generic web crawling and JS rendering.
    * `paramsGoogleSearch()`: Tailored configuration for Google Search API interactions including rate-limit management.
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
