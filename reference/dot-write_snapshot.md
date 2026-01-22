# Write Snapshot File to Disk

Saves a data snapshot (`data.table`) to the specified snapshot
directory, naming it with the chunk ID and a timestamp. This is
typically called during batched scraping operations to persist
intermediate results.

## Usage

``` r
.write_snapshot(dt, chunk_id, snapshot_dir)
```

## Arguments

- dt:

  A `data.table` containing scraped data and extracted links.

- chunk_id:

  `integer(1)` Identifier of the current chunk. Used in file naming as
  `snap_chunkXX_*`.

- snapshot_dir:

  `character(1)` Directory where the snapshot file will be written.

## Value

`invisible(NULL)`. The function writes a `.rds` file as a side effect.

## Examples

``` r
if (FALSE) { # \dontrun{
dt <- data.table::data.table(
  url = "https://example.com",
  scraped_at = Sys.time(),
  html = "<html></html>"
)

.write_snapshot(dt, chunk_id = 1, snapshot_dir = "snapshots/")
} # }
```
