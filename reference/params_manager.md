# Parameter Manager Base Class

`params_manager` is an R6 base class for managing hierarchical
configuration parameters. It supports:

- Built‑in default settings defined by subclasses

- Optional overrides via a YAML configuration file

- Programmatic overrides via named arguments

- Nested key access using `$` syntax or character vectors

The class is designed to be inherited by specialized configuration
classes (e.g., for scrapers or API clients) and provides a consistent,
validated mechanism for reading, updating, and exporting configuration
settings.

## Format

An [`R6::R6Class`](https://r6.r-lib.org/reference/R6Class.html)
generator object.

## Features

- YAML read/write support (via the **yaml** package)

- Path syntax support: `"a$b$c"` or `c("a","b","c")`

- Nested configuration updating with validation at the top-level key

- Export of defaults or current configuration to a YAML file

## Methods

### Public methods

- [`params_manager$new()`](#method-params_manager-initialize)

- [`params_manager$print()`](#method-params_manager-print)

- [`params_manager$load_config()`](#method-params_manager-load_config)

- [`params_manager$get()`](#method-params_manager-get)

- [`params_manager$show_config()`](#method-params_manager-show_config)

- [`params_manager$defaults()`](#method-params_manager-defaults)

- [`params_manager$write_defaults()`](#method-params_manager-write_defaults)

- [`params_manager$export()`](#method-params_manager-export)

- [`params_manager$set()`](#method-params_manager-set)

- [`params_manager$update()`](#method-params_manager-update)

- [`params_manager$clone()`](#method-params_manager-clone)

------------------------------------------------------------------------

### `params_manager$new()`

Initialize the parameter manager.

This loads configuration using the following precedence:

1.  **Defaults** defined by the subclass

2.  **YAML configuration file** (if provided)

3.  **Programmatic overrides** via `...`

#### Usage

    params_manager$new(config_file = NULL, ...)

#### Arguments

- `config_file`:

  Optional path to a YAML configuration file.

- `...`:

  Named overrides applied after defaults and YAML values.

------------------------------------------------------------------------

### `params_manager$print()`

Print the current settings

#### Usage

    params_manager$print()

------------------------------------------------------------------------

### `params_manager$load_config()`

Loads configuration: defaults \< YAML \< args

#### Usage

    params_manager$load_config(config_file = NULL, ...)

#### Arguments

- `config_file`:

  (Optional) YAML file path.

- `...`:

  Named overrides to apply last.

#### Returns

A list with the resulting configuration.

------------------------------------------------------------------------

### `params_manager$get()`

Retrieve a configuration value (supports nested paths).

Nested syntax examples:

- `"selenium$host"`

- `"robots$check"`

- `c("selenium", "port")`

#### Usage

    params_manager$get(key)

#### Arguments

- `key`:

  A string using `$` or a character vector of nested keys.

#### Returns

The configuration value or `NULL` if not found.

------------------------------------------------------------------------

### `params_manager$show_config()`

Return the complete current configuration as a list.

#### Usage

    params_manager$show_config()

#### Returns

A named list representing the current configuration.

------------------------------------------------------------------------

### `params_manager$defaults()`

Subclasses must override this method to define default settings.

#### Usage

    params_manager$defaults()

#### Returns

A named list containing default configuration values.

------------------------------------------------------------------------

### `params_manager$write_defaults()`

Write default configuration values to a YAML file.

#### Usage

    params_manager$write_defaults(filename)

#### Arguments

- `filename`:

  Output file ending in `.yaml`.

------------------------------------------------------------------------

### `params_manager$export()`

Export the *current* configuration (including overrides) to YAML.

#### Usage

    params_manager$export(filename)

#### Arguments

- `filename`:

  Output file ending in `.yaml`.

------------------------------------------------------------------------

### `params_manager$set()`

Updates configuration.

- If `key` is a top-level name\*, only the specific element is modified.

- If `key` is a nested path\* (e.g., "x.y" / "x\$y" / c("x","y")),

the method updates only that nested value. In both cases, the relevant
top-level key is validated via `private$.validate()`.

#### Usage

    params_manager$set(key, val)

#### Arguments

- `key`:

  A top-level key or nested path (`"a$b$c"` or `c("a","b","c")`)

- `val`:

  New value to assign.

#### Returns

The object itself (invisibly).

------------------------------------------------------------------------

### `params_manager$update()`

Recursively update configuration values from a (possibly nested) list.

Only top-level keys contained in `values` are validated.

#### Usage

    params_manager$update(values)

#### Arguments

- `values`:

  A named list merged into the current configuration.

#### Returns

The object itself (invisibly).

------------------------------------------------------------------------

### `params_manager$clone()`

The objects of this class are cloneable with this method.

#### Usage

    params_manager$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
