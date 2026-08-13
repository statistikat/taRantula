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
