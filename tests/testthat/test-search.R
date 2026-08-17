search_companies <- function() {
  dat <- data.table::data.table(
    company_id = 1:3,
    company_name = c(
      "Österreichische Bundesforste AG",
      "Burghauptmannschaft Österreich",
      "Bundesanstalt Statistik Österreich"
    ),
    company_address = c(
      "3002 Purkersdorf, Pummergasse 10-12",
      "1010 Wien, Hofburg, Schweizerhof",
      "1110 Wien, Guglgasse 13"
    )
  )
  dat[,
    query := buildQuery(.SD),
    .SDcols = c("company_name", "company_address")
  ]
  dat
}

expect_search_output <- function(result) {
  expect_s3_class(result, "data.table")
  expect_gt(nrow(result), 0)
  expect_true(all(
    c("company_id", "title", "link", "displayLink", "snippet", "position") %in%
      names(result)
  ))
  expect_true(any(nzchar(result$link)))
  expect_true(all(result$position >= 1))
}

test_that("buildQuery creates encoded search queries for company data", {
  dat <- search_companies()

  expect_equal(attr(dat$query, "query_attr"), "built_encoded_query")
  expect_equal(length(dat$query), 3)
  expect_true(any(grepl("%c3%96sterreich", dat$query, fixed = TRUE)))
})

test_that("Google search returns business URL candidates", {
  skip_if_not(
    nzchar(Sys.getenv("SCRAPING_APIKEY_GOOGLE")) &&
      nzchar(Sys.getenv("SCRAPING_ENGINE_GOOGLE")),
    "Google Search API credentials are not configured"
  )

  cfg <- paramsGoogleSearch(
    provider = "google",
    path = tempdir(),
    id_col = "company_id",
    query_col = "query",
    scrape_attributes = c("title", "link", "displayLink", "snippet"),
    verbose = FALSE
  )

  result <- searchURL(
    cfg = cfg,
    dat = search_companies(),
    file = NULL,
    query_col = "query"
  )

  expect_search_output(result)
})

test_that("Brave search returns business URL candidates with Google-compatible columns", {
  skip_if_not(
    nzchar(Sys.getenv("SCRAPING_APIKEY_BRAVE")),
    "Brave Search API credentials are not configured"
  )

  cfg <- paramsBraveSearch(
    path = tempdir(),
    id_col = "company_id",
    query_col = "query",
    scrape_attributes = c("title", "link", "displayLink", "snippet"),
    verbose = FALSE
  )

  result <- searchURL(
    cfg = cfg,
    dat = search_companies(),
    file = NULL,
    query_col = "query"
  )

  expect_search_output(result)
})

test_that("Brave URL blacklists are converted to Goggles requests", {
  goggle_file <- write_brave_blacklist_goggle(
    c(
      "https://www.example.com/path",
      "spam.test",
      "example.com/duplicate"
    ),
    path = tempdir()
  )

  expect_true(file.exists(goggle_file))
  expect_equal(tools::file_ext(goggle_file), "goggle")

  goggle_lines <- readLines(goggle_file, warn = FALSE)
  expect_true("! name: URL Blacklist" %in% goggle_lines)
  expect_true("$discard,site=example.com" %in% goggle_lines)
  expect_true("$discard,site=spam.test" %in% goggle_lines)
  expect_equal(sum(goggle_lines == "$discard,site=example.com"), 1L)

  goggles <- read_brave_goggle_file(goggle_file)
  params <- brave_search_params("Acme%20GmbH", goggles = goggles)
  expect_equal(params$q, "Acme GmbH")
  expect_equal(params$goggles, goggles)

  url <- brave_search_url(brave_search_params("Acme%20GmbH"))
  expect_true(grepl("q=Acme%20GmbH", url, fixed = TRUE))
  expect_false(grepl("%2520", url, fixed = TRUE))
  expect_false(grepl("goggles=", url, fixed = TRUE))
})
