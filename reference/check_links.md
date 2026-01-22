# Link Validation Helper

Evaluates extracted URLs and determines which of them should be retained
for further processing. The function filters out links that:

- Do not belong to the same domain as `baseurl`

- Point to files such as images, audio, video, archives, executables,
  etc.

- Refer to fragments or anchor points

- Refer back to the same path as the main page

## Usage

``` r
check_links(hrefs, baseurl)
```

## Arguments

- hrefs:

  Character vector of URLs to check.

- baseurl:

  Character string giving the original page URL for domain and path
  comparison.

## Value

A logical vector indicating which entries in `hrefs` should be retained.
