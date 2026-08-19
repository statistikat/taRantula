test_that("runOwiSliceQuery builds the default OWI command", {
  old_path <- Sys.getenv("owilix_path", unset = NA)
  on.exit({
    if (is.na(old_path)) {
      Sys.unsetenv("owilix_path")
    } else {
      Sys.setenv(owilix_path = old_path)
    }
  })
  Sys.setenv(owilix_path = "/tmp/owilix-test-bin")

  cmd <- runOwiSliceQuery(dry_run = TRUE)

  expect_equal(cmd$command, "owi")
  expect_match(cmd$env, "^PATH=/tmp/owilix-test-bin:", perl = TRUE)
  expect_equal(
    cmd$args[1:4],
    c("query", "slice", "-R", "all:latest/collectionName=legal")
  )
  expect_true(is.na(cmd$parquet_path))
  expect_true("--where" %in% cmd$args)
  expect_true("--select" %in% cmd$args)
  expect_true("--collection" %in% cmd$args)
  expect_true("--no-ciff" %in% cmd$args)
  expect_true("--yes" %in% cmd$args)

  where <- cmd$args[match("--where", cmd$args) + 1]
  select <- cmd$args[match("--select", cmd$args) + 1]
  collection <- cmd$args[match("--collection", cmd$args) + 1]

  expect_equal(
    where,
    "url_suffix='at' AND valid=true AND (ows_index=true OR ows_index IS NULL)"
  )
  expect_match(select, "main_content", fixed = TRUE)
  expect_match(select, "warc_date", fixed = TRUE)
  expect_equal(collection, "austrian_legal_pages")
})

test_that("runOwiSliceQuery parameterizes OWI query slice options", {
  cmd <- runOwiSliceQuery(
    route = "all/collectionName=other",
    where = "valid=true",
    select = c("id", "url"),
    collection = "other_collection",
    no_ciff = FALSE,
    yes = FALSE,
    command = "/usr/local/bin/owi",
    dry_run = TRUE
  )

  expect_equal(cmd$command, "/usr/local/bin/owi")
  expect_equal(
    cmd$args[1:4],
    c("query", "slice", "-R", "all/collectionName=other")
  )
  expect_equal(cmd$args[match("--where", cmd$args) + 1], "valid=true")
  expect_equal(cmd$args[match("--select", cmd$args) + 1], "id,\nurl")
  expect_equal(
    cmd$args[match("--collection", cmd$args) + 1],
    "other_collection"
  )
  expect_false("--no-ciff" %in% cmd$args)
  expect_false("--yes" %in% cmd$args)
})

test_that("runOwiSliceQuery parameterizes url_suffix", {
  cmd <- runOwiSliceQuery(
    url_suffix = "de",
    dry_run = TRUE
  )

  expect_equal(
    cmd$args[match("--where", cmd$args) + 1],
    "url_suffix='de' AND valid=true AND (ows_index=true OR ows_index IS NULL)"
  )
})

test_that("runOwiSliceQuery quotes shell-sensitive system arguments", {
  output <- runOwiSliceQuery(
    command = "echo",
    stdout = TRUE,
    stderr = TRUE,
    dry_run = FALSE
  )

  expect_true(any(grepl(
    "ows_index=true OR ows_index IS NULL",
    output$result,
    fixed = TRUE
  )))
})

test_that("runOwiSliceQuery uses path_prepend to locate the command", {
  bin_dir <- tempfile("owi-bin-")
  dir.create(bin_dir)
  command <- file.path(bin_dir, "owi-test-command")
  writeLines(c("#!/bin/sh", "echo path-ok"), command)
  Sys.chmod(command, "0755")

  output <- runOwiSliceQuery(
    command = "owi-test-command",
    path_prepend = bin_dir,
    stdout = TRUE,
    stderr = TRUE,
    dry_run = FALSE
  )

  expect_equal(output$result, "path-ok")
})

test_that("runOwiSliceQuery returns the latest parquet glob for the collection", {
  local_base_path <- tempfile("owi-public-")
  collection <- "test_collection"
  old_dataset <- file.path(local_base_path, collection, "old-dataset")
  new_dataset <- file.path(local_base_path, collection, "new-dataset")
  unrelated_newer_dataset <- file.path(
    local_base_path,
    collection,
    "unrelated-newer-dataset"
  )
  dir.create(old_dataset, recursive = TRUE)
  dir.create(new_dataset, recursive = TRUE)
  dir.create(unrelated_newer_dataset, recursive = TRUE)
  file.create(file.path(old_dataset, "part-old.parquet"))
  file.create(file.path(new_dataset, "part-new.parquet"))
  file.create(file.path(unrelated_newer_dataset, "part-unrelated.parquet"))
  Sys.setFileTime(old_dataset, Sys.time() - 60)
  Sys.setFileTime(new_dataset, Sys.time() - 30)
  Sys.setFileTime(unrelated_newer_dataset, Sys.time())

  command <- tempfile("owi-touch-command-")
  writeLines(
    c(
      "#!/bin/sh",
      sprintf("touch %s", shQuote(new_dataset)),
      "echo path-ok"
    ),
    command
  )
  Sys.chmod(command, "0755")

  output <- runOwiSliceQuery(
    collection = collection,
    command = command,
    local_base_path = local_base_path,
    stdout = TRUE,
    stderr = TRUE,
    dry_run = FALSE
  )

  expect_equal(output$parquet_path, file.path(new_dataset, "*.parquet"))
})

test_that("runOwiSliceQuery validates inputs", {
  expect_error(runOwiSliceQuery(route = "", dry_run = TRUE), "`route`")
  expect_error(
    runOwiSliceQuery(url_suffix = "", dry_run = TRUE),
    "`url_suffix`"
  )
  expect_error(
    runOwiSliceQuery(select = character(), dry_run = TRUE),
    "`select`"
  )
  expect_error(runOwiSliceQuery(no_ciff = "yes", dry_run = TRUE), "`no_ciff`")
  expect_length(runOwiSliceQuery(path_prepend = "", dry_run = TRUE)$env, 0)
  expect_error(
    runOwiSliceQuery(local_base_path = "", dry_run = TRUE),
    "`local_base_path`"
  )
})

test_that("searchOwi searches main_content by default", {
  parquet_dir <- tempfile("owi-parquet-")
  dir.create(parquet_dir)
  arrow::write_parquet(
    data.frame(
      id = c("1", "2", "3"),
      url = c(
        "https://a.at/impressum",
        "https://b.at/privacy",
        "https://c.at/contact"
      ),
      title = c("Impressum", "Privacy", "Contact"),
      url_domain = c("a", "b", "c"),
      url_suffix = "at",
      language = c("deu", "eng", "deu"),
      warc_date = "2026-08-10T00:00:00Z",
      main_content = c("Firmenbuchnummer FN 123", "privacy text", NA_character_)
    ),
    file.path(parquet_dir, "part-1.parquet")
  )

  result <- searchOwi(
    parquet_path = file.path(parquet_dir, "*.parquet"),
    keyword = "firmenbuchnummer"
  )

  expect_s3_class(result, "data.table")
  expect_equal(nrow(result), 1)
  expect_equal(result$url, "https://a.at/impressum")
  expect_true("main_content" %in% names(result))
})

test_that("searchOwi supports a custom search field and limit", {
  parquet_dir <- tempfile("owi-parquet-")
  dir.create(parquet_dir)
  arrow::write_parquet(
    data.frame(
      id = c("1", "2"),
      url = c("https://a.at/impressum", "https://b.at/privacy"),
      title = c("Impressum", "Privacy Policy"),
      main_content = c("content a", "content b")
    ),
    file.path(parquet_dir, "part-1.parquet")
  )

  result <- searchOwi(
    parquet_path = parquet_dir,
    keyword = "Privacy",
    field = "title",
    select = c("url", "title"),
    limit = 1,
    as_data_table = FALSE
  )

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("url", "title"))
  expect_equal(result$url, "https://b.at/privacy")
})

test_that("searchOwi excludes supplied domains", {
  parquet_dir <- tempfile("owi-parquet-")
  dir.create(parquet_dir)
  arrow::write_parquet(
    data.frame(
      id = c("1", "2", "3"),
      url = c(
        "https://a.at/impressum",
        "https://b.at/impressum",
        "https://c.at/impressum"
      ),
      title = c("A", "B", "C"),
      url_domain = c("a.at", "www.b.at", "c.at"),
      main_content = c(
        "legal disclosure",
        "legal disclosure",
        "legal disclosure"
      )
    ),
    file.path(parquet_dir, "part-1.parquet")
  )

  result <- searchOwi(
    parquet_path = parquet_dir,
    keyword = "legal",
    select = c("url", "title"),
    exclude_domains = c("a.at", "b.at"),
    as_data_table = FALSE
  )

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("url", "title"))
  expect_equal(result$url, "https://c.at/impressum")
})

test_that("searchOwi excludes reconstructed OWI domains", {
  parquet_dir <- tempfile("owi-parquet-")
  dir.create(parquet_dir)
  arrow::write_parquet(
    data.frame(
      id = c("1", "2", "3"),
      url = c(
        "https://www.a.at/impressum",
        "https://www.wirtschaftsmediation.at/en/legal-disclosure/",
        "https://www.c.at/impressum"
      ),
      title = c("A", "B", "C"),
      url_domain = c("a", "wirtschaftsmediation", "c"),
      url_suffix = c("at", "at", "at"),
      main_content = c(
        "legal disclosure",
        "legal disclosure",
        "legal disclosure"
      )
    ),
    file.path(parquet_dir, "part-1.parquet")
  )

  result <- searchOwi(
    parquet_path = parquet_dir,
    keyword = "legal",
    select = c("url", "title"),
    exclude_domains = c("https://www.a.at/page", "www.wirtschaftsmediation.at"),
    as_data_table = FALSE
  )

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("url", "title"))
  expect_equal(result$url, "https://www.c.at/impressum")
})

test_that("searchOwi only uses the DuckDB backend", {
  parquet_dir <- tempfile("owi-parquet-")
  dir.create(parquet_dir)
  arrow::write_parquet(
    data.frame(
      id = c("1", "2"),
      url = c("https://a.at/impressum", "https://b.at/privacy"),
      title = c("Impressum", "Privacy"),
      main_content = c("legal disclosure", "privacy text")
    ),
    file.path(parquet_dir, "part-1.parquet")
  )

  result <- searchOwi(
    parquet_path = parquet_dir,
    keyword = "LEGAL"
  )

  expect_s3_class(result, "data.table")
  expect_equal(nrow(result), 1)
  expect_equal(result$url, "https://a.at/impressum")
})

test_that("searchOwi validates inputs and missing files", {
  expect_error(searchOwi("", keyword = "x"), "`parquet_path`")
  expect_error(searchOwi(tempfile(), keyword = "x"), "No parquet files")
  expect_error(
    searchOwi(tempfile(fileext = ".parquet"), keyword = ""),
    "`keyword`"
  )
  expect_error(
    searchOwi(tempfile(), keyword = "x", backend = "arrow"),
    "unused argument"
  )

  parquet_dir <- tempfile("owi-parquet-")
  dir.create(parquet_dir)
  arrow::write_parquet(
    data.frame(
      url = "https://a.at/impressum",
      main_content = "legal disclosure"
    ),
    file.path(parquet_dir, "part-1.parquet")
  )
  expect_error(
    searchOwi(parquet_dir, keyword = "legal", exclude_domains = "a.at"),
    "`exclude_domains` requires a `url_domain` column"
  )
  expect_error(
    searchOwi(parquet_dir, keyword = "legal", exclude_domains = 1),
    "`exclude_domains` must be a character vector"
  )
})
