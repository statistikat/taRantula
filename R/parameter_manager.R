#' @title Parameter Manager Base Class
#'
#' @description
#' `params_manager` is an R6 base class for managing hierarchical
#' configuration parameters. It supports:
#'
#' * Built‑in default settings defined by subclasses
#' * Optional overrides via a YAML configuration file
#' * Programmatic overrides via named arguments
#' * Nested key access using `$` syntax or character vectors
#'
#' The class is designed to be inherited by specialized configuration
#' classes (e.g., for scrapers or API clients) and provides a consistent,
#' validated mechanism for reading, updating, and exporting configuration
#' settings.
#'
#' @section Features:
#' * YAML read/write support (via the **yaml** package)
#' * Path syntax support: `"a$b$c"` or `c("a","b","c")`
#' * Nested configuration updating with validation at the top-level key
#' * Export of defaults or current configuration to a YAML file
#'
#' @keywords internal
#' @docType class
#' @format An `R6::R6Class` generator object.

params_manager <- R6::R6Class(
  classname = "params_manager",
  private = list(
    .config = NULL,
    .yaml_available = function() {
      requireNamespace("yaml", quietly = TRUE)
    },
    .yaml_read = function(path) {
      if (!private$.yaml_available()) {
        rlang::abort("Reading YAML requires the 'yaml' package.")
      }
      yaml::read_yaml(path)
    },
    .yaml_write = function(obj, path) {
      if (!private$.yaml_available()) {
        rlang::abort("Writing YAML requires the 'yaml' package.")
      }
      yaml::write_yaml(obj, path)
    },

    # Default check, subclasses can override and validate *top-level* keys.
    .validate = function(key, value) {
      TRUE
    },
    .req_string = function(x, nm, null_allowed = FALSE, allowed = NULL) {
      stopifnot(rlang::is_scalar_logical(null_allowed))
      if (is.null(x) && null_allowed) {
        return(TRUE)
      }
      if (!rlang::is_scalar_character(x)) {
        rlang::abort(glue::glue("'{nm}' must be a non-empty string."))
      }
      if (!is.null(allowed)) {
        if (!rlang::is_character(allowed)) {
          rlang::abort("'allowed' must be a character vector.")
        }
        if (!x %in% allowed) {
          rlang::abort(glue::glue("'{nm}' must be one of {paste(shQuote(allowed), collapse = ', ')}."))
        }
      }
    },
    .req_bool = function(x, nm) {
      if (!rlang::is_scalar_logical(x)) {
        rlang::abort(glue::glue("'{nm}' must be TRUE/FALSE."))
      }
    },

    # FIXED: correct range checks (previous version used `!x >=` and `!x <=`)
    .req_int = function(x, nm, min_val = NULL, max_val = NULL) {
      if (!rlang::is_scalar_integerish(x)) {
        rlang::abort(glue::glue("'{nm}' must be an integerish number."))
      }
      if (!is.null(min_val)) {
        if (!rlang::is_scalar_integerish(min_val)) {
          rlang::abort("'min_val' must be an integerish number.")
        }
        if (x < min_val) {
          rlang::abort(glue::glue("'{nm}' must be >= {min_val}."))
        }
      }
      if (!is.null(max_val)) {
        if (!rlang::is_scalar_integerish(max_val)) {
          rlang::abort("'max_val' must be an integerish number.")
        }
        if (x > max_val) {
          rlang::abort(glue::glue("'{nm}' must be <= {max_val}."))
        }
      }
    },
    .req_named_list = function(x, nm) {
      if (!is.list(x)) {
        rlang::abort(glue::glue("'{nm}' must be a list."))
      }
      if (is.null(names(x)) || any(names(x) == "")) {
        rlang::abort(glue::glue("'{nm}' must be a named list (all elements named)."))
      }
    },
    .req_charv = function(x, nm, null_allowed = FALSE, allowed = NULL) {
      stopifnot(rlang::is_scalar_logical(null_allowed))
      if (is.null(x) && null_allowed) {
        return(TRUE)
      }

      if (!is.character(x)) {
        rlang::abort(glue::glue("'{nm}' must be a character vector."))
      }

      if (!is.null(allowed)) {
        if (!rlang::is_character(allowed)) {
          rlang::abort("'allowed' must be a character vector.")
        }
        bad <- setdiff(x, allowed)
        if (length(bad) > 0) {
          rlang::abort(glue::glue(
            "'{nm}' contains invalid values: {paste(shQuote(bad), collapse=', ')};
            allowed are {paste(shQuote(allowed), collapse=', ')}."
          ))
        }
      }
    },
    .req_path = function(x, nm) {
      private$.req_string(x = x, nm = nm)
      if (!fs::dir_exists(x)) {
        rlang::abort(glue::glue("'{nm}' ('{x}') is not an existing directory"))
      }
    },
    .validate_path_syntax = function(path) {
      if (rlang::is_string(path) && grepl("^[^$.]+(\\.[^$.]+)+$", path)) {
        rlang::abort("'path' must not use dot-syntax (e.g., 'a.b.c'). Use 'a$b$c' or c('a','b','c') instead.")
      }
    },

    # split path on '$' to allow for a$b$c syntax
    .split_path = function(path) {
      private$.validate_path_syntax(path)
      if (rlang::is_string(path)) {
        # Split only on dollar signs
        parts <- unlist(strsplit(path, "\\$", fixed = FALSE))
        parts <- trimws(parts)
        parts[nzchar(parts)]
      } else if (is.character(path)) {
        parts <- trimws(path)
        parts[nzchar(parts)]
      } else {
        rlang::abort("'path' must be a string with '$' separators or a character vector.")
      }
    },

    # Recursively set a value inside list `x` at `keys`.
    .set_in = function(x, keys, value) {
      if (length(keys) == 0L) {
        return(value)
      }
      k <- keys[1]
      rest <- keys[-1]
      if (is.null(x)) x <- list()
      if (!is.list(x)) {
        rlang::abort(glue::glue("Attempt to set '{paste(keys, collapse='.')}' inside a non-list value."))
      }
      x[[k]] <- private$.set_in(x = x[[k]], keys = rest, value = value)
      x
    }
  ),
  public = list(
    #' @description
    #' Initialize the parameter manager.
    #'
    #' This loads configuration using the following precedence:
    #' 1. **Defaults** defined by the subclass
    #' 2. **YAML configuration file** (if provided)
    #' 3. **Programmatic overrides** via `...`
    #'
    #' @param config_file Optional path to a YAML configuration file.
    #' @param ... Named overrides applied after defaults and YAML values.
    initialize = function(config_file = NULL, ...) {
      private$.config <- self$load_config(config_file, ...)
    },

    #' @description
    #' Print the current settings
    print = function() {
      print(self$show_config())
    },

    #' @description
    #' Loads configuration: defaults < YAML < args
    #'
    #' @param config_file (Optional) YAML file path.
    #' @param ... Named overrides to apply last.
    #'
    #' @return A list with the resulting configuration.
    load_config = function(config_file = NULL, ...) {
      default_config <- self$defaults()
      base_config <- default_config

      if (!is.null(config_file) && file.exists(config_file)) {
        tryCatch(
          expr = {
            file_config <- private$.yaml_read(config_file)
            cli::cli_alert_info(
              text = "Configuration loaded from '{config_file}' for {class(self)[1]}"
            )
            base_config <- utils::modifyList(base_config, file_config)
          },
          error = function(e) {
            rlang::warn(
              message = glue::glue(
                "Error reading config file '{config_file}' for '{class(self)[1]}':\nMsg: {e$message}; Using default configuration."
              )
            )
          }
        )
      } else if (!is.null(config_file)) {
        cli::cli_alert_info(
          text = "Configuration file '{config_file}' not found for '{class(self)[1]}'. Using default configuration."
        )
      } else {
        cli::cli_alert_info(
          text = "No configuration file provided for '{class(self)[1]}'. Using default configuration."
        )
      }

      # Overwrite with arguments passed to initialize()
      init_overrides <- list(...)
      allowed_params <- names(base_config)
      class_name <- class(self)[1]
      for (key in names(init_overrides)) {
        if (!key %in% allowed_params) {
          rlang::abort(
            message = glue::glue("'{key}' is not a valid parameter for class '{class_name}'")
          )
        }
        if (!private$.validate(key, init_overrides[[key]])) {
          rlang::abort(
            message = glue::glue("Invalid value for configuration setting '{key}' for class '{class_name}.'")
          )
        }
      }

      show_config <- utils::modifyList(base_config, init_overrides)
      return(show_config)
    },

    #' @description
    #' Retrieve a configuration value (supports nested paths).
    #'
    #' Nested syntax examples:
    #' * `"selenium$host"`
    #' * `"robots$check"`
    #' * `c("selenium", "port")`
    #'
    #' @param key A string using `$` or a character vector of nested keys.
    #' @return The configuration value or `NULL` if not found.
    get = function(key) {
      # nested paths are allowed
      path <- private$.split_path(key)
      if (length(path) == 1) {
        if (!path %in% names(private$.config)) {
          rlang::warn(glue::glue("Setting '{key}' not found in configuration for '{class(self)[1]}."))
          return(invisible(NULL))
        }
        return(private$.config[[path]])
      }

      res <- tryCatch(
        expr = Reduce(`[[`, path, init = private$.config),
        error = function(e) e
      )
      if (inherits(res, "error") || is.null(res)) {
        warning(paste0("Setting '", key, "' not found in configuration for ", class(self)[1], "."))
        return(invisible(NULL))
      }
      return(res)
    },

    #' @description
    #' Return the complete current configuration as a list.
    #'
    #' @return A named list representing the current configuration.
    show_config = function() {
      private$.config
    },

    #' @description
    #' Subclasses must override this method to define default settings.
    #'
    #' @return A named list containing default configuration values.
    defaults = function() {
      rlang::abort("Subclass must implement defaults()")
    },

    #' @description
    #' Write default configuration values to a YAML file.
    #'
    #' @param filename Output file ending in `.yaml`.
    write_defaults = function(filename) {
      stopifnot(tolower(tools::file_ext(filename)) == "yaml")
      default_config <- self$defaults()
      private$.yaml_write(default_config, filename)
      cli::cli_alert_info(
        text = "Default configuration for '{class(self)[1]}' written to '{filename}'."
      )
    },

    #' @description
    #' Export the *current* configuration (including overrides) to YAML.
    #'
    #' @param filename Output file ending in `.yaml`.
    export = function(filename) {
      stopifnot(tolower(tools::file_ext(filename)) == "yaml")
      private$.yaml_write(private$.config, filename)
      cli::cli_alert_info(
        text = "Current configuration for '{class(self)[1]}' written to '{filename}'."
      )
    },

    #' @description
    #' Updates configuration.
    #'
    #' * If `key` is a top-level name*, only the specific element is modified.
    #' * If `key` is a nested path* (e.g., "x.y" / "x$y" / c("x","y")),
    #'
    #' the method updates only that nested value. In both cases, the relevant
    #' top-level key is validated via `private$.validate()`.
    #'
    #' @param key A top-level key or nested path (`"a$b$c"` or `c("a","b","c")`)
    #' @param val New value to assign.
    #' @return The object itself (invisibly).
    set = function(key, val) {
      class_name <- class(self)[1]

      # nested paths are allowed
      path <- private$.split_path(key)
      root <- path[1]

      if (!root %in% names(private$.config)) {
        rlang::abort(paste0(shQuote(root), " is not a valid parameter for class ", shQuote(class_name), "."))
      }

      if (length(path) == 1L) {
        # If a list is provided, it needs to be merged into existing defaults
        if (is.list(val) && is.list(private$.config[[root]])) {
          val <- utils::modifyList(private$.config[[root]], val)
        }

        if (!private$.validate(root, val)) {
          rlang::abort("Error validating key")
        }
        private$.config[[root]] <- val
        return(invisible(self))
      }

      # Nested assignment: update subtree at `root`, then validate the merged top-level value
      merged_root <- private$.set_in(private$.config[[root]], path[-1], val)

      if (!private$.validate(root, merged_root)) {
        cli::cli_alert_danger(
          text = "Error validating nested configuration under '{root}' for class '{class_name}'"
        )
        print(merged_root)
        rlang::abort("Error validating nested key")
      }

      private$.config[[root]] <- merged_root
      invisible(self)
    },

    #' @description
    #' Recursively update configuration values from a (possibly nested) list.
    #'
    #' Only top-level keys contained in `values` are validated.
    #'
    #' @param values A named list merged into the current configuration.
    #'
    #' @return The object itself (invisibly).
    update = function(values) {
      stopifnot(is.list(values))
      bad <- setdiff(names(values), names(private$.config))
      if (length(bad)) {
        rlang::abort(glue::glue("Unknown top-level keys in update(): {paste(bad, collapse = ', ')}"))
      }

      merged <- utils::modifyList(private$.config, values)

      # Validate only affected top-level keys using their merged values
      for (key in names(values)) {
        private$.validate(key, merged[[key]])
      }

      private$.config <- merged
      invisible(self)
    }
  )
)

#' @title Google Search Configuration Class
#'
#' @description
#' `cfg_googlesearch` is an R6 class that inherits from
#' [`params_manager`] and provides configuration management for
#' performing Google Custom Search API queries.
#'
#' It handles:
#'
#' * Definition of default parameters for Google search jobs
#' * YAML-based configuration overrides
#' * Programmatic overrides via `...`
#' * Validation of all relevant configuration fields
#'
#' @section Key Features:
#' * Built-in defaults suitable for most scraping workflows
#' * Support for API credentials (key + engine ID)
#' * Control over query frequency and batching
#' * Control over which metadata fields to keep from API responses
#' * Optional saving of results to disk
#'
#' @docType class
#' @keywords internal
#' @format An `R6::R6Class` generator object.
#' @rdname paramsGoogleSearch
#' @export
cfg_googlesearch <- R6::R6Class(
  classname = "cfg_googlesearch",
  inherit = params_manager,
  public = list(
    #' @description
    #' Initialize a new `cfg_googlesearch` configuration object.
    #'
    #' The load precedence is:
    #' 1. Defaults
    #' 2. YAML configuration file (if provided)
    #' 3. Programmatic overrides via `...`
    #'
    #' @param config_file (Optional) Path to a YAML configuration file.
    #'   Supported settings include:
    #'   * `path`: Directory where output data are stored.
    #'   * `id_col`: Column name serving as a unique identifier for each entity (default: `"kz_z"`).
    #'   * `query_col`: Column name containing the search queries. Must be created
    #'     via [buildQuery()] (default: `NULL`).
    #'   * `print_every_n`: Positive integer. Interval for displaying progress
    #'     messages (default: `100`).
    #'   * `save_every_n`: Positive integer. Interval for saving intermediate
    #'     results (default: `500`).
    #'   * `scrape_attributes`: Character vector. Specifies which data to extract
    #'     from results. One or more of: `"title"`, `"link"`, `"displayLink"`,
    #'     `"snippet"` (default: `c("link", "displayLink")`).
    #'   * `verbose`: Logical. Should progress updates be printed to the
    #'     console? (default: `TRUE`).
    #'   * `max_queries`: Maximum queries allowed per 24-hour period. If reached,
    #'     the process will pause until the 24-hour window resets (default: `10000`).
    #'   * `max_query_rate`: Numeric. Maximum number of queries allowed per 100
    #'     seconds (default: `100`).
    #'   * `file`: Filename (relative to `path`) for saving results. If `NULL`,
    #'     results are not written to disk. Uses [data.table::fwrite()]
    #'     internally.
    #'   * `overwrite`: Logical. If `TRUE`, existing files are overwritten. If `FALSE`,
    #'     existing data are loaded via [data.table::fread()] and new results are
    #'     appended. Ensure column names match when appending (default: `FALSE`).
    #'   * `credentials`: A named list containing Google API credentials. Use
    #'     `"key"` or `"SCRAPING_APIKEY_GOOGLE"` for the API Key, and `"engine"`
    #'     or `"SCRAPING_ENGINE_GOOGLE"` for the Search Engine ID. If omitted,
    #'     environment variables are used. See also [getGoogleCreds()].
    #'
    #' @param path Path to the directory where project data are stored.
    #'   Overrides the `path` setting in `config_file`.
    #' @param ... Named arguments used to override specific configuration settings.
    #'   These take precedence over both `config_file` and default values.
    #'
    #' @return A configured object of class `cfg_googlesearch`.
    #' @export
    initialize = function(config_file = NULL, path = tempdir(), ...) {
      .update_google_envvars <- function(creds) {
        creds <- list(...)$credentials
        if (is.null(creds) || length(creds) == 0) {
          return(invisible(NULL))
        }
        mm <- c(
          "KEY"                    = "SCRAPING_APIKEY_GOOGLE",
          "SCRAPING_APIKEY_GOOGLE" = "SCRAPING_APIKEY_GOOGLE",
          "ENGINE"                 = "SCRAPING_ENGINE_GOOGLE",
          "SCRAPING_ENGINE_GOOGLE" = "SCRAPING_ENGINE_GOOGLE"
        )

        nn <- toupper(names(creds))

        # filter/remove non-valid inputs
        idx <- nn %in% names(mm)
        creds <- creds[idx]
        nn <- nn[idx]
        if (length(creds) == 0) {
          return(invisible(NULL))
        }

        # set envvars
        names(creds) <- mm[nn]
        do.call(Sys.setenv, creds)
        rlang::inform(glue::glue(
          "Set/Updated environment variables for {glue::glue_collapse(names(creds), sep = ', ', last = ' and ')}."
        ))
        return(invisible(NULL))
      }
      .update_google_envvars(creds = list(...)$credentials)
      super$initialize(config_file, ..., path = path)
    },
    #' @description
    #' Return the default configuration settings for Google Custom Search.
    #'
    #' @return A named list containing default values for:
    #' * `path` – directory to store output
    #' * `id_col` – identifier column
    #' * `query_col` – column containing query strings
    #' * `print_every_n` – progress message interval
    #' * `save_every_n` – save interval
    #' * `scrape_attributes` – which CSE fields to keep
    #' * `verbose` – print progress messages
    #' * `max_queries` – maximum queries per 24h
    #' * `max_query_rate` – queries per 100 seconds
    #' * `file` – output file (or `NULL`)
    #' * `overwrite` – overwrite output file or append
    #' * `credentials` – list with `key` and `engine`
    defaults = function() {
      list(
        path = NULL,
        id_col = "ID",
        query_col = NULL,
        print_every_n = 100,
        save_every_n = 500,
        scrape_attributes = c("link", "displayLink"),
        verbose = TRUE,
        max_queries = 10000,
        max_query_rate = 100,
        file = NULL,
        overwrite = FALSE,
        credentials = getGoogleCreds()
      )
    }
  ),
  private = list(
    .validate = function(key, value) {
      # Specific checks for google api queries
      if (key %in% c("id_col")) {
        super$.req_string(
          x = value,
          nm = key
        )
      } else if (key == "path") {
        super$.req_path(
          x = value,
          nm = key
        )
      } else if (key %in% c("verbose", "overwrite")) {
        super$.req_bool(
          x = value,
          nm = key
        )
      } else if (key %in% c("print_every_n", "save_every_n", "max_queries", "max_query_rate")) {
        super$.req_int(
          x = value,
          nm = key,
          min_val = 0
        )
      } else if (key %in% c("file", "query_col")) {
        super$.req_charv(
          x = value,
          nm = key,
          null_allowed = TRUE
        )
      } else if (key == "scrape_attributes") {
        super$.req_charv(
          x = value,
          nm = key,
          null_allowed = FALSE,
          allowed = c("title", "link", "displayLink", "snippet")
        )
      }
      return(invisible(TRUE))
    }
  )
)

#' Create a [cfg_googlesearch] configuration object
#'
#' This utility function simplifies the creation of a [cfg_googlesearch] object.
#' It supports optional configuration file loading and programmatic overrides.
#'
#' @param config_file Optional path to a YAML configuration file.
#' @param path Path to a directory used for storing downloaded data.
#'   Defaults to `tempdir()`.
#' @param ... Additional named configuration overrides.
#'   These take precedence over defaults and YAML configuration.
#'
#' @return A `cfg_googlesearch` object.
#' @export
#' @rdname paramsGoogleSearch
#' @examples
#' # Create with defaults
#' # in this case, Environment-Variables `SCRAPING_APIKEY_GOOGLE` and `SCRAPING_ENGINE_GOOGLE`
#' # need to be set beforehand
#' cfg <- paramsGoogleSearch()
#'
#' # Create with overrides
#' cfg <- paramsGoogleSearch(
#'   path = getwd(),
#'   credentials = list(
#'     key = "my_google_apikey",
#'     engine = "my-search-engine-id"
#'   ),
#'   verbose = FALSE
#' )
#'
#' # Return the current configuration
#' cfg$show_config()
#'
#' # Write current configuration to file
#' f <- file.path(tempdir(), "config.yaml")
#' cfg$export(f)
#'
#' # Load from exported config-file and override
#' cfg <- paramsGoogleSearch(config_file = f, verbose = TRUE)
#' try(file.remove(f))
#'
#' # Return the current configuration
#' cfg$show_config()
#'
#' # Or a specific setting
#' cfg$get("max_query_rate")
#'
#' # Update the configuration
#' cfg$set("max_query_rate", 200)
#' cfg$get("max_query_rate")
paramsGoogleSearch <- function(config_file = NULL, path = tempdir(), ...) {
  cfg_googlesearch$new(config_file = config_file, path = path, ...)
}

#' @title Scraper Configuration Class
#'
#' @description
#' `cfg_scraper` is an R6 configuration class that inherits from
#' [`params_manager`] and provides a structured way to manage configuration
#' parameters for a generic web scraper.
#'
#' It is designed for Selenium-based scraping workflows with integrated
#' `robots.txt` checks and also supports `httr::GET()`-based scraping.
#'
#' @section Main Responsibilities:
#' * Define and expose sensible **default settings** for scraping projects
#' * Optionally load overrides from a **YAML configuration file**
#' * Allow **programmatic overrides** via `...`
#' * Validate top-level and nested configuration entries (e.g. `robots`, `selenium`)
#' * Provide a convenient interface to access and update nested settings
#'
#' @section Top-level Configuration Structure:
#' The default configuration contains the following top-level entries:
#'
#' * `project` – Name of the scraping project (used for organizing outputs/logs)
#' * `base_dir` – Base directory where project-related data are stored
#' * `urls` – Character vector of URLs to be scraped
#' * `robots` – List with `robots.txt`-related settings
#' * `httr` – List of options for `httr::GET()` calls
#' * `selenium` – List with Selenium-related configuration
#'
#' See `defaults()` for the exact structure and default values.
#'
#' @docType class
#' @keywords internal
#' @format An `R6::R6Class` generator object.
#' @rdname paramsScraper
#' @export
cfg_scraper <- R6::R6Class(
  classname = "cfg_scraper",
  inherit = params_manager,
  public = list(
    #' @description
    #' Initialize a new `cfg_scraper` configuration object.
    #'
    #' Configuration is resolved in the following order:
    #' 1. Built-in defaults defined in `defaults()`
    #' 2. Optional YAML configuration file (`config_file`)
    #' 3. Programmatic overrides passed via `...`
    #'
    #' In addition, the Selenium configuration is post-processed so that
    #' the `selenium$ecaps$args` vector contains a `--user-agent=` entry
    #' matching the configured `selenium$user_agent`.
    #'
    #' @param config_file Optional path to a YAML configuration file.
    #'
    #' @param base_dir Character string specifying the base directory where
    #'   project-related data will be stored.
    #'   Defaults to `getwd()`.
    #'
    #' @param ... Named arguments that override specific configuration
    #'   settings. These values take precedence over defaults and YAML file
    #'   entries. Commonly used overrides include:
    #'
    #'   * `project` (character): Project name used for file and directory
    #'     structures; default `"my-project"`.
    #'   * `urls` (character vector): URLs to be scraped; default `character(0)`.
    #'   * `robots` (list): Settings related to `robots.txt` handling:
    #'     - `check` (logical): Respect `robots.txt`? Default `TRUE`.
    #'     - `snapshot_every` (integer): Snapshot interval for robots checks; default `10`.
    #'     - `workers` (integer): Number of parallel workers for robots checks; default `1`.
    #'     - `robots_user_agent` (character): User agent string for robots queries;
    #'       default `.default_useragent()`.
    #'   * `httr` (list): Configuration for `httr::GET()`-based requests:
    #'     - `user_agent` (character): User agent string; default `.default_useragent()`.
    #'   * `selenium` (list): Selenium-related configuration:
    #'     - `use_selenium` (logical): Use Selenium? Default `TRUE`.
    #'     - `host` (character): Selenium server host; default `"localhost"`.
    #'     - `port` (integer): Selenium server port; default `4444L`.
    #'     - `verbose` (logical): Verbose Selenium output; default `FALSE`.
    #'     - `browser` (character): Browser name (e.g. `"chrome"`); default `"chrome"`.
    #'     - `user_agent` (character): User agent for Selenium; default `.default_useragent()`.
    #'     - `ecaps` (list): Extra capabilities:
    #'       - `args` (character vector): Chrome command-line arguments.
    #'       - `prefs` (list): Browser preferences (e.g. popup settings).
    #'       - `excludeSwitches` (character vector): Chrome switches to exclude.
    #'     - `snapshot_every` (integer): Snapshot interval during Selenium scraping; default `10L`.
    #'     - `workers` (integer): Number of parallel Selenium workers; default `1L`.
    #'
    #' @return A new `cfg_scraper` object.
    initialize = function(config_file = NULL, base_dir = getwd(), ...) {
      super$initialize(config_file, ..., base_dir = base_dir)

      # set user_agent in ecaps for selenium
      sel <- self$get("selenium")
      if (!is.null(sel) && !is.null(sel$ecaps)) {
        sel$ecaps$args <- c(sel$ecaps$args, paste0("--user-agent=", sel$user_agent))
        self$set("selenium", sel)
      }
      invisible(self)
    },

    #' @description
    #' Return the default configuration values for the scraper.
    #'
    #' These defaults define a complete, valid configuration for both
    #' robots handling and Selenium-based scraping. Users can override any
    #' of these values via YAML or programmatic arguments.
    #'
    #' @return A named list with the default configuration values.
    defaults = function() {
      list(
        project = "my-project",
        base_dir = getwd(),
        urls = character(0),
        robots = list(
          check = TRUE,
          snapshot_every = 10L,
          workers = 1L,
          robots_user_agent = .default_useragent()
        ),
        httr = list(
          user_agent = .default_useragent() # default user agent
        ),
        selenium = list(
          use_selenium = TRUE,
          host = "localhost",
          port = 4444L,
          verbose = FALSE,
          browser = "chrome",
          user_agent = .default_useragent(),
          ecaps = list(
            args = c(
              "--headless",
              "--enable-automation",
              "--disable-gpu",
              "--no-sandbox",
              "--start-maximized",
              "--disable-infobars",
              "--disk-cache-size=400000000",
              "--disable-browser-side-navigation",
              "--disable-blink-features",
              "--window-size=1080,1920",
              "--disable-popup-blocking",
              "--disable-dev-shm-usage",
              "--lang=de"
            ),
            prefs = list(
              PageLoadStrategy = "eager",
              `profile.default_content_settings.popups` = 0L
            ),
            excludeSwitches = c("disable-popup-blocking")
          ),
          snapshot_every = 10L,
          workers = 1L
        )
      )
    }
  ),
  private = list(
    # Validation of top-level entries (including nested structure checks)
    .validate = function(key, value) {
      # --- top-level validation dispatch ---
      if (key == "project") {
        super$.req_string(value, "project")
      } else if (key == "base_dir") {
        super$.req_path(value, "base_dir")
      } else if (key == "urls") {
        super$.req_charv(value, "urls")
      } else if (key == "robots") {
        super$.req_named_list(value, "robots")
        # Provide defaults if user passes a partial list (for validation)
        def <- self$defaults()$robots
        rob <- utils::modifyList(def, value)

        super$.req_bool(
          x = rob$check,
          nm = "robots$check"
        )
        super$.req_int(
          x = rob$snapshot_every,
          nm = "robots$snapshot_every",
          min_val = 1L
        )

        super$.req_int(
          x = rob$workers,
          nm = "robots$workers",
          min_val = 1L
        )
        super$.req_string(
          x = rob$robots_user_agent,
          nm = "robots$robots_user_agent"
        )
      } else if (key == "httr") {
        super$.req_named_list(value, "httr")
        # Provide defaults if user passes a partial list (for validation)
        def <- self$defaults()$httr
        httr_get <- utils::modifyList(def, value)

        super$.req_string(
          x = httr_get$user_agent,
          nm = "httr$user_agent"
        )
      } else if (key == "selenium") {
        super$.req_named_list(value, "selenium")
        def <- self$defaults()$selenium
        sel <- utils::modifyList(def, value)

        super$.req_string(sel$host, "selenium$host")
        super$.req_int(
          x = sel$port,
          nm = "selenium$port",
          min_val = 1L,
          max_val = 65535L
        )

        super$.req_bool(
          x = sel$verbose,
          nm = "selenium$verbose"
        )
        super$.req_string(
          x = sel$browser,
          nm = "selenium$browser",
          null_allowed = FALSE,
          allowed = c("chrome")
        )
        super$.req_string(
          x = sel$user_agent,
          nm = "sel$user_agent"
        )
        # ecaps
        super$.req_named_list(sel$ecaps, "selenium$ecaps")

        # args
        if (!is.null(sel$ecaps$args)) {
          super$.req_charv(sel$ecaps$args, "selenium$ecaps$args")
        }

        # prefs (a list; keys can be arbitrary, values typically scalar)
        if (!is.null(sel$ecaps$prefs)) {
          if (!is.list(sel$ecaps$prefs)) {
            rlang::abort("'selenium$ecaps$prefs' must be a list.")
          }
        }

        # excludeSwitches as character vector
        if (!is.null(sel$ecaps$excludeSwitches)) {
          # Allow both list and character, coerce check to char
          if (is.list(sel$ecaps$excludeSwitches)) {
            tryCatch(
              {
                as.character(unlist(sel$ecaps$excludeSwitches, use.names = FALSE))
              },
              error = function(e) rlang::abort("'selenium$ecaps$excludeSwitches' must be a character vector or list of strings.")
            )
          } else {
            super$.req_charv(sel$ecaps$excludeSwitches, "selenium$ecaps$excludeSwitches")
          }
        }

        # scheduling
        super$.req_int(
          x = sel$snapshot_every,
          nm = "selenium$snapshot_every",
          min_val = 1
        )
        super$.req_int(
          x = sel$workers,
          nm = "selenium$workers",
          min_val = 1L
        )
      } else {
        # Unknown top-level key
        rlang::abort(glue::glue("'{key}' is not a valid parameter for class 'cfg_scraper'."))
      }
      invisible(TRUE)
    }
  )
)

#' @title Create a Scraper Configuration Object
#'
#' @description
#' Convenience constructor for creating a [`cfg_scraper`] object.
#' It supports optional YAML-based configuration and programmatic overrides.
#'
#' This is the recommended entry point for users who want to configure
#' scraping projects without interacting with the R6 class API directly.
#'
#' @param config_file Optional path to a YAML configuration file.
#' @param base_dir Path to the folder where project data are stored.
#'   Defaults to `getwd()`.
#' @param ... Named arguments to override specific configuration settings
#'   (see the `initialize()` method of [`cfg_scraper`] for details).
#'
#' @return A [`cfg_scraper`] object.
#'
#' @export
#' @rdname paramsScraper
#'
#' @examples
#' # Create with defaults
#' cfg <- paramsScraper()
#'
#' # Create with overrides
#' cfg <- paramsScraper(base_dir = tempdir(), project = "my-project")
#'
#' # Write current configuration to file
#' f <- tempfile(fileext = ".yaml")
#' cfg$export(f)
#'
#' # Load from exported config-file and override
#' cfg <- paramsScraper(config_file = f, project = "some-other-proj")
#' try(file.remove(f))
#'
#' # Return the current configuration
#' cfg$show_config()
#'
#' # Retrieve specific settings
#' cfg$get("project")
#' cfg$get("selenium$host")          # nested via $-syntax
#' cfg$get(c("selenium", "port"))    # nested via character vector
#'
#' # Update the configuration
#' cfg$set(c("selenium", "port"), 4445)
#' cfg$set("selenium$host", "127.0.0.1")
paramsScraper <- function(config_file = NULL, base_dir = getwd(), ...) {
  cfg_scraper$new(config_file = config_file, base_dir = base_dir, ...)
}
