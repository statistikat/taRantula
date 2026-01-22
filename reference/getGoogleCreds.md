# Retrieve Google Search Credentials

Reads Google Custom Search API credentials from environment variables.
This allows secure decoupling of API keys from code.

## Usage

``` r
getGoogleCreds()
```

## Value

A named list with elements:

- `engine` – The Google Custom Search Engine ID

- `key` – The API key string

## Details

The following environment variables must be defined:

- `SCRAPING_APIKEY_GOOGLE` – Your Google Custom Search API key

- `SCRAPING_ENGINE_GOOGLE` – The Custom Search Engine (CSE) identifier

These values can be defined inside `~/.Renviron` or set at runtime using
[`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html).

## Examples

``` r
## Example:
Sys.setenv(SCRAPING_APIKEY_GOOGLE = "your_key")
Sys.setenv(SCRAPING_ENGINE_GOOGLE = "your_engine")
creds <- getGoogleCreds()
print(creds)
#> $engine
#> [1] "your_engine"
#> 
#> $key
#> [1] "your_key"
#> 
```
