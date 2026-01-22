# Google Search Configuration Class

`cfg_googlesearch` is an R6 class that inherits from
[`params_manager`](https://statistikat.github.io/taRantula/reference/params_manager.md)
and provides configuration management for performing Google Custom
Search API queries.

It handles:

- Definition of default parameters for Google search jobs

- YAML-based configuration overrides

- Programmatic overrides via `...`

- Validation of all relevant configuration fields

This utility function simplifies the creation of a cfg_googlesearch
object. It supports optional configuration file loading and programmatic
overrides.

## Usage

``` r
paramsGoogleSearch(config_file = NULL, path = tempdir(), ...)
```

## Format

An [`R6::R6Class`](https://r6.r-lib.org/reference/R6Class.html)
generator object.

## Arguments

- config_file:

  Optional path to a YAML configuration file.

- path:

  Path to a directory used for storing downloaded data. Defaults to
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html).

- ...:

  Additional named configuration overrides. These take precedence over
  defaults and YAML configuration.

## Value

A `cfg_googlesearch` object.

## Key Features

- Built-in defaults suitable for most scraping workflows

- Support for API credentials (key + engine ID)

- Control over query frequency and batching

- Control over which metadata fields to keep from API responses

- Optional saving of results to disk

## Super class

[`taRantula::params_manager`](https://statistikat.github.io/taRantula/reference/params_manager.md)
-\> `cfg_googlesearch`

## Methods

### Public methods

- [`cfg_googlesearch$new()`](#method-cfg_googlesearch-new)

- [`cfg_googlesearch$defaults()`](#method-cfg_googlesearch-defaults)

- [`cfg_googlesearch$clone()`](#method-cfg_googlesearch-clone)

Inherited methods

- [`taRantula::params_manager$export()`](https://statistikat.github.io/taRantula/reference/params_manager.html#method-export)
- [`taRantula::params_manager$get()`](https://statistikat.github.io/taRantula/reference/params_manager.html#method-get)
- [`taRantula::params_manager$load_config()`](https://statistikat.github.io/taRantula/reference/params_manager.html#method-load_config)
- [`taRantula::params_manager$print()`](https://statistikat.github.io/taRantula/reference/params_manager.html#method-print)
- [`taRantula::params_manager$set()`](https://statistikat.github.io/taRantula/reference/params_manager.html#method-set)
- [`taRantula::params_manager$show_config()`](https://statistikat.github.io/taRantula/reference/params_manager.html#method-show_config)
- [`taRantula::params_manager$update()`](https://statistikat.github.io/taRantula/reference/params_manager.html#method-update)
- [`taRantula::params_manager$write_defaults()`](https://statistikat.github.io/taRantula/reference/params_manager.html#method-write_defaults)

------------------------------------------------------------------------

### Method `new()`

Initialize a new `cfg_googlesearch` configuration object.

The load precedence is:

1.  Defaults

2.  YAML configuration file (if provided)

3.  Programmatic overrides via `...`

#### Usage

    cfg_googlesearch$new(config_file = NULL, path = tempdir(), ...)

#### Arguments

- `config_file`:

  (Optional) Path to a YAML configuration file. Supported settings
  include:

  - `path`: Directory where output data are stored.

  - `id_col`: Column name serving as a unique identifier for each entity
    (default: `"kz_z"`).

  - `query_col`: Column name containing the search queries. Must be
    created via
    [`buildQuery()`](https://statistikat.github.io/taRantula/reference/buildQuery.md)
    (default: `NULL`).

  - `print_every_n`: Positive integer. Interval for displaying progress
    messages (default: `100`).

  - `save_every_n`: Positive integer. Interval for saving intermediate
    results (default: `500`).

  - `scrape_attributes`: Character vector. Specifies which data to
    extract from results. One or more of: `"title"`, `"link"`,
    `"displayLink"`, `"snippet"` (default: `c("link", "displayLink")`).

  - `verbose`: Logical. Should progress updates be printed to the
    console? (default: `TRUE`).

  - `max_queries`: Maximum queries allowed per 24-hour period. If
    reached, the process will pause until the 24-hour window resets
    (default: `10000`).

  - `max_query_rate`: Numeric. Maximum number of queries allowed per 100
    seconds (default: `100`).

  - `file`: Filename (relative to `path`) for saving results. If `NULL`,
    results are not written to disk. Uses
    [`data.table::fwrite()`](https://rdatatable.gitlab.io/data.table/reference/fwrite.html)
    internally.

  - `overwrite`: Logical. If `TRUE`, existing files are overwritten. If
    `FALSE`, existing data are loaded via
    [`data.table::fread()`](https://rdatatable.gitlab.io/data.table/reference/fread.html)
    and new results are appended. Ensure column names match when
    appending (default: `FALSE`).

  - `credentials`: A named list containing Google API credentials. Use
    `"key"` or `"SCRAPING_APIKEY_GOOGLE"` for the API Key, and
    `"engine"` or `"SCRAPING_ENGINE_GOOGLE"` for the Search Engine ID.
    If omitted, environment variables are used. See also
    [`getGoogleCreds()`](https://statistikat.github.io/taRantula/reference/getGoogleCreds.md).

- `path`:

  Path to the directory where project data are stored. Overrides the
  `path` setting in `config_file`.

- `...`:

  Named arguments used to override specific configuration settings.
  These take precedence over both `config_file` and default values.

#### Returns

A configured object of class `cfg_googlesearch`.

------------------------------------------------------------------------

### Method `defaults()`

Return the default configuration settings for Google Custom Search.

#### Usage

    cfg_googlesearch$defaults()

#### Returns

A named list containing default values for:

- `path` – directory to store output

- `id_col` – identifier column

- `query_col` – column containing query strings

- `print_every_n` – progress message interval

- `save_every_n` – save interval

- `scrape_attributes` – which CSE fields to keep

- `verbose` – print progress messages

- `max_queries` – maximum queries per 24h

- `max_query_rate` – queries per 100 seconds

- `file` – output file (or `NULL`)

- `overwrite` – overwrite output file or append

- `credentials` – list with `key` and `engine`

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    cfg_googlesearch$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r
# Create with defaults
# in this case, Environment-Variables `SCRAPING_APIKEY_GOOGLE` and `SCRAPING_ENGINE_GOOGLE`
# need to be set beforehand
cfg <- paramsGoogleSearch()
#> ℹ No configuration file provided for 'cfg_googlesearch'. Using default configuration.

# Create with overrides
cfg <- paramsGoogleSearch(
  path = getwd(),
  credentials = list(
    key = "my_google_apikey",
    engine = "my-search-engine-id"
  ),
  verbose = FALSE
)
#> Set/Updated environment variables for SCRAPING_APIKEY_GOOGLE and SCRAPING_ENGINE_GOOGLE.
#> ℹ No configuration file provided for 'cfg_googlesearch'. Using default configuration.

# Return the current configuration
cfg$show_config()
#> $path
#> [1] "/tmp/RtmppVykHU/file1b7447f41c24/reference"
#> 
#> $id_col
#> [1] "ID"
#> 
#> $query_col
#> NULL
#> 
#> $print_every_n
#> [1] 100
#> 
#> $save_every_n
#> [1] 500
#> 
#> $scrape_attributes
#> [1] "link"        "displayLink"
#> 
#> $verbose
#> [1] FALSE
#> 
#> $max_queries
#> [1] 10000
#> 
#> $max_query_rate
#> [1] 100
#> 
#> $file
#> NULL
#> 
#> $overwrite
#> [1] FALSE
#> 
#> $credentials
#> $credentials$engine
#> [1] "my-search-engine-id"
#> 
#> $credentials$key
#> [1] "my_google_apikey"
#> 
#> 

# Write current configuration to file
f <- file.path(tempdir(), "config.yaml")
cfg$export(f)
#> ℹ Current configuration for 'cfg_googlesearch' written to '/tmp/RtmppVykHU/config.yaml'.

# Load from exported config-file and override
cfg <- paramsGoogleSearch(config_file = f, verbose = TRUE)
#> ℹ Configuration loaded from '/tmp/RtmppVykHU/config.yaml' for cfg_googlesearch
try(file.remove(f))
#> [1] TRUE

# Return the current configuration
cfg$show_config()
#> $path
#> [1] "/tmp/RtmppVykHU"
#> 
#> $id_col
#> [1] "ID"
#> 
#> $print_every_n
#> [1] 100
#> 
#> $save_every_n
#> [1] 500
#> 
#> $scrape_attributes
#> [1] "link"        "displayLink"
#> 
#> $verbose
#> [1] TRUE
#> 
#> $max_queries
#> [1] 10000
#> 
#> $max_query_rate
#> [1] 100
#> 
#> $overwrite
#> [1] FALSE
#> 
#> $credentials
#> $credentials$engine
#> [1] "my-search-engine-id"
#> 
#> $credentials$key
#> [1] "my_google_apikey"
#> 
#> 

# Or a specific setting
cfg$get("max_query_rate")
#> [1] 100

# Update the configuration
cfg$set("max_query_rate", 200)
cfg$get("max_query_rate")
#> [1] 200
```
