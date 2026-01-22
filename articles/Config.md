# Configuration Management with \`params_manager\`

The `taRantula` package uses a robust, `R6`-based configuration system
for both scraping-jobs as well as Jobs based on Google Custom Search.
This ensures that parameters are validated before scraping begins,
reducing the risk of runtime errors in long-running parallel jobs.

## The Configuration Hierarchy

The `params_manager` class follows a specific priority when loading
settings:

1.  **Defaults:** Hardcoded values defined in the package.
2.  **YAML File:** Values loaded from an external file (overrides
    defaults).
3.  **Manual Overrides:** Values passed directly in R (overrides
    everything).

## Using the Configuration for a scraping job

The scraper configuration initialized using function
[`paramsScraper()`](https://statistikat.github.io/taRantula/reference/paramsScraper.md)
manages settings for Selenium, robots.txt, and directory paths.

### Initializing

You can initialize with defaults or override specific values
immediately.

``` r
library(taRantula)

# Basic initialization
cfg <- paramsScraper(project = "census_scrape")

# Advanced initialization with nested Selenium settings
cfg <- paramsScraper(
  project = "census_scrape",
  selenium = list(host = "192.168.1.xx", workers = 5)
)
```

### Getting and Setting Values

The class supports a convenient `$`-syntax and character vector syntax
for nested paths.

``` r
# Accessing nested values
cfg$get("selenium$host")
cfg$get(c("selenium", "port"))

# Updating values (automatically triggers validation)
cfg$set("selenium$port", 4445)
cfg$set("robots$check", FALSE)
```

------------------------------------------------------------------------

## Using the Configuration for a Google Custom Search

The Google Search configuration which can be initialized with function
`paramsGoogleSearch` is more streamlined, focusing on API limits and
result attributes.

``` r
# Set up a Google Search task
gcfg <- paramsGoogleSearch(
  path = "~/google_results",
  max_queries = 500,
  scrape_attributes = c("link", "snippet") # Only keep specific fields
)

# Current state
gcfg$show_config()
```

------------------------------------------------------------------------

## Portability: Exporting and Importing YAML

A key feature for reproducible research is the ability to save your
configuration to a file. This allows you to share the exact scraper
settings with colleagues or use them in a CI/CD pipeline.

### Exporting

``` r
# Save your current configuration
cfg$export("my_config.yaml")

# You can also save just the package defaults as a template
cfg$write_defaults("template.yaml")
```

### Importing

``` r
# Recreate a scraper state from a YAML file
new_cfg <- paramsScraper(config_file = "my_config.yaml")
```

------------------------------------------------------------------------

## Built-in Validation

The `params_manager` provides strict type and range checking. If you
attempt to set an invalid value, the package will throw an informative
error immediately.

``` r
# This will trigger an error (port must be an integerish number <= 65535)
try(cfg$set("selenium$port", 99999))

# This will trigger an error (scrape_attributes must be one of the allowed fields)
try(gcfg$set("scrape_attributes", "raw_html"))
```

------------------------------------------------------------------------

## Summary of Methods

| Method                  | Description                                      |
|:------------------------|:-------------------------------------------------|
| `$get(key)`             | Retrieves a value (supports nested `$`).         |
| `$set(key, val)`        | Updates a value and validates the top-level key. |
| `$update(list)`         | Merges a named list into the config.             |
| `$show_config()`        | Returns the full configuration list.             |
| `$export(file)`         | Saves the current state to a YAML file.          |
| `$write_defaults(file)` | Saves the default template to a YAML file.       |
