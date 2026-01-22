# Run Google Search Workflow

Executes one or multiple Google Custom Search API queries derived from a
prepared dataset. Results are saved into the directory structure defined
in the provided
[`cfg_googlesearch()`](https://statistikat.github.io/taRantula/reference/paramsGoogleSearch.md)
configuration object.

## Usage

``` r
runGoogleSearch(cfg = cfg_googlesearch$new(), dat)
```

## Arguments

- cfg:

  A
  [`cfg_googlesearch()`](https://statistikat.github.io/taRantula/reference/paramsGoogleSearch.md)
  configuration object containing all required search, credential, and
  file‑handling settings.

- dat:

  A `data.table` containing variables referenced in `cfg$query_col`. All
  referenced columns must exist in `dat`.

## Value

Returns `TRUE` invisibly when all queries have completed successfully.
Result files are written to the directory specified in `cfg`.

## Examples

``` r
## Example use will be added in future releases
```
