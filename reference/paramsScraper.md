# Scraper Configuration Class

`cfg_scraper` is an R6 configuration class that inherits from
[`params_manager`](https://statistikat.github.io/taRantula/reference/params_manager.md)
and provides a structured way to manage configuration parameters for a
generic web scraper.

It is designed for Selenium-based scraping workflows with integrated
`robots.txt` checks and also supports
[`httr::GET()`](https://httr.r-lib.org/reference/GET.html)-based
scraping.

Convenience constructor for creating a `cfg_scraper` object. It supports
optional YAML-based configuration and programmatic overrides.

This is the recommended entry point for users who want to configure
scraping projects without interacting with the R6 class API directly.

## Usage

``` r
paramsScraper(config_file = NULL, base_dir = getwd(), ...)
```

## Format

An [`R6::R6Class`](https://r6.r-lib.org/reference/R6Class.html)
generator object.

## Arguments

- config_file:

  Optional path to a YAML configuration file.

- base_dir:

  Path to the folder where project data are stored. Defaults to
  [`getwd()`](https://rdrr.io/r/base/getwd.html).

- ...:

  Named arguments to override specific configuration settings (see the
  `initialize()` method of `cfg_scraper` for details).

## Value

A `cfg_scraper` object.

## Main Responsibilities

- Define and expose sensible **default settings** for scraping projects

- Optionally load overrides from a **YAML configuration file**

- Allow **programmatic overrides** via `...`

- Validate top-level and nested configuration entries (e.g. `robots`,
  `selenium`)

- Provide a convenient interface to access and update nested settings

## Top-level Configuration Structure

The default configuration contains the following top-level entries:

- `project` – Name of the scraping project (used for organizing
  outputs/logs)

- `base_dir` – Base directory where project-related data are stored

- `urls` – Character vector of URLs to be scraped

- `robots` – List with `robots.txt`-related settings

- `httr` – List of options for
  [`httr::GET()`](https://httr.r-lib.org/reference/GET.html) calls

- `selenium` – List with Selenium-related configuration

See `defaults()` for the exact structure and default values.

## Super class

[`taRantula::params_manager`](https://statistikat.github.io/taRantula/reference/params_manager.md)
-\> `cfg_scraper`

## Methods

### Public methods

- [`cfg_scraper$new()`](#method-cfg_scraper-new)

- [`cfg_scraper$defaults()`](#method-cfg_scraper-defaults)

- [`cfg_scraper$clone()`](#method-cfg_scraper-clone)

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

Initialize a new `cfg_scraper` configuration object.

Configuration is resolved in the following order:

1.  Built-in defaults defined in `defaults()`

2.  Optional YAML configuration file (`config_file`)

3.  Programmatic overrides passed via `...`

In addition, the Selenium configuration is post-processed so that the
`selenium$ecaps$args` vector contains a `--user-agent=` entry matching
the configured `selenium$user_agent`.

#### Usage

    cfg_scraper$new(config_file = NULL, base_dir = getwd(), ...)

#### Arguments

- `config_file`:

  Optional path to a YAML configuration file.

- `base_dir`:

  Character string specifying the base directory where project-related
  data will be stored. Defaults to
  [`getwd()`](https://rdrr.io/r/base/getwd.html).

- `...`:

  Named arguments that override specific configuration settings. These
  values take precedence over defaults and YAML file entries. Commonly
  used overrides include:

  - `project` (character): Project name used for file and directory
    structures; default `"my-project"`.

  - `urls` (character vector): URLs to be scraped; default
    `character(0)`.

  - `robots` (list): Settings related to `robots.txt` handling:

    - `check` (logical): Respect `robots.txt`? Default `TRUE`.

    - `snapshot_every` (integer): Snapshot interval for robots checks;
      default `10`.

    - `workers` (integer): Number of parallel workers for robots checks;
      default `1`.

    - `robots_user_agent` (character): User agent string for robots
      queries; default
      [`.default_useragent()`](https://statistikat.github.io/taRantula/reference/dot-default_useragent.md).

  - `httr` (list): Configuration for
    [`httr::GET()`](https://httr.r-lib.org/reference/GET.html)-based
    requests:

    - `user_agent` (character): User agent string; default
      [`.default_useragent()`](https://statistikat.github.io/taRantula/reference/dot-default_useragent.md).

  - `selenium` (list): Selenium-related configuration:

    - `use_selenium` (logical): Use Selenium? Default `TRUE`.

    - `host` (character): Selenium server host; default `"localhost"`.

    - `port` (integer): Selenium server port; default `4444L`.

    - `verbose` (logical): Verbose Selenium output; default `FALSE`.

    - `browser` (character): Browser name (e.g. `"chrome"`); default
      `"chrome"`.

    - `user_agent` (character): User agent for Selenium; default
      [`.default_useragent()`](https://statistikat.github.io/taRantula/reference/dot-default_useragent.md).

    - `ecaps` (list): Extra capabilities:

      - `args` (character vector): Chrome command-line arguments.

      - `prefs` (list): Browser preferences (e.g. popup settings).

      - `excludeSwitches` (character vector): Chrome switches to
        exclude.

    - `snapshot_every` (integer): Snapshot interval during Selenium
      scraping; default `10L`.

    - `workers` (integer): Number of parallel Selenium workers; default
      `1L`.

#### Returns

A new `cfg_scraper` object.

------------------------------------------------------------------------

### Method `defaults()`

Return the default configuration values for the scraper.

These defaults define a complete, valid configuration for both robots
handling and Selenium-based scraping. Users can override any of these
values via YAML or programmatic arguments.

#### Usage

    cfg_scraper$defaults()

#### Returns

A named list with the default configuration values.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    cfg_scraper$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r
# Create with defaults
cfg <- paramsScraper()
#> ℹ No configuration file provided for 'cfg_scraper'. Using default configuration.

# Create with overrides
cfg <- paramsScraper(base_dir = tempdir(), project = "my-project")
#> ℹ No configuration file provided for 'cfg_scraper'. Using default configuration.

# Write current configuration to file
f <- tempfile(fileext = ".yaml")
cfg$export(f)
#> ℹ Current configuration for 'cfg_scraper' written to '/tmp/RtmppVykHU/file1b746f3bec68.yaml'.

# Load from exported config-file and override
cfg <- paramsScraper(config_file = f, project = "some-other-proj")
#> ℹ Configuration loaded from '/tmp/RtmppVykHU/file1b746f3bec68.yaml' for cfg_scraper
try(file.remove(f))
#> [1] TRUE

# Return the current configuration
cfg$show_config()
#> $project
#> [1] "some-other-proj"
#> 
#> $base_dir
#> [1] "/tmp/RtmppVykHU/file1b7447f41c24/reference"
#> 
#> $urls
#> list()
#> 
#> $robots
#> $robots$check
#> [1] TRUE
#> 
#> $robots$snapshot_every
#> [1] 10
#> 
#> $robots$workers
#> [1] 1
#> 
#> $robots$robots_user_agent
#> [1] "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5_2) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
#> 
#> 
#> $httr
#> $httr$user_agent
#> [1] "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5_2) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
#> 
#> 
#> $selenium
#> $selenium$use_selenium
#> [1] TRUE
#> 
#> $selenium$host
#> [1] "localhost"
#> 
#> $selenium$port
#> [1] 4444
#> 
#> $selenium$verbose
#> [1] FALSE
#> 
#> $selenium$browser
#> [1] "chrome"
#> 
#> $selenium$user_agent
#> [1] "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5_2) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
#> 
#> $selenium$ecaps
#> $selenium$ecaps$args
#>  [1] "--headless"                                                                                                                       
#>  [2] "--enable-automation"                                                                                                              
#>  [3] "--disable-gpu"                                                                                                                    
#>  [4] "--no-sandbox"                                                                                                                     
#>  [5] "--start-maximized"                                                                                                                
#>  [6] "--disable-infobars"                                                                                                               
#>  [7] "--disk-cache-size=400000000"                                                                                                      
#>  [8] "--disable-browser-side-navigation"                                                                                                
#>  [9] "--disable-blink-features"                                                                                                         
#> [10] "--window-size=1080,1920"                                                                                                          
#> [11] "--disable-popup-blocking"                                                                                                         
#> [12] "--disable-dev-shm-usage"                                                                                                          
#> [13] "--lang=de"                                                                                                                        
#> [14] "--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5_2) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
#> [15] "--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5_2) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
#> 
#> $selenium$ecaps$prefs
#> $selenium$ecaps$prefs$PageLoadStrategy
#> [1] "eager"
#> 
#> $selenium$ecaps$prefs$profile.default_content_settings.popups
#> [1] 0
#> 
#> 
#> $selenium$ecaps$excludeSwitches
#> [1] "disable-popup-blocking"
#> 
#> 
#> $selenium$snapshot_every
#> [1] 10
#> 
#> $selenium$workers
#> [1] 1
#> 
#> 

# Retrieve specific settings
cfg$get("project")
#> [1] "some-other-proj"
cfg$get("selenium$host")          # nested via $-syntax
#> [1] "localhost"
cfg$get(c("selenium", "port"))    # nested via character vector
#> [1] 4444

# Update the configuration
cfg$set(c("selenium", "port"), 4445)
cfg$set("selenium$host", "127.0.0.1")
```
