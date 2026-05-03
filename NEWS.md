# taRantula next

* **Storage Refactoring:** Migrated raw scraping data (source code and link metadata) from the database to highly efficient `parquet` files located in `{project_dir}/data`.

* **Database Schema Evolution:**
    * **New `urls` Table:** Dedicated storage for all URLs provided to the project.
    * **Revised `results` Table:** Streamlined for performance; removed raw source code storage in favor of a `file_path` reference (pointing to the corresponding `parquet` file).
        * **New `status` column:** Tracks URL state:
            * `"todo"`: URL is awaiting scraping.
            * `"success"`: Scraping completed; source code is available.
            * `"failed_domain"`: Domain is unreachable; scraping not possible.
            * `"failed_scraping"`: Scraping attempt failed.
            * `"blocked"`: Access denied by `robots.txt`.
    * **Dynamic Views:**
        * Replaced the static `links` table with a dynamic view that aggregates link data directly from `parquet` files.
        * Added a `full_results` view that mimics the previous `results` table structure while including sources and link data.

* **Optimized Scraping Workflow:** 
  * Moved domain reachability and `robots.txt` validation to a pre-scraping phase. 
  * Workers now process only pre-validated `status = "todo"` URLs which allows for the removal of redundant availability checks within parallel worker processes.

* **R6-Methods Improvements:**
    * Updated the `$results()` method with a `with_src` parameter (default = `TRUE`) to switch between retrieving simple `results` table or the comprehensive `full_results` view.
    * Updated the `$results()` method by querying the new view and internally computing the hierarchy levels.
    * Added new active bindings:
        * `$url_info`: Real-time counts of total, successfully scraped, pending, and failed URLs.
        * `$urls_todo`: Returns all pending URLs currently set to `"todo"`.

* **Maintainability & Code Quality:**
    * Centralized all SQL queries into a structured `sql_queries` list for improved maintainability.
    * Unified the cleanup process: `close()` and `finalize()` methods now share a single underlying private `cleanup()` method.
    * Refinement and simplification of Roxygen documentation and various utility/helper functions.

- [todo] Implement `$vacuum()` method to remove old/expired results from `parquet` Files; 

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
