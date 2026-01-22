test_that("cfg_scraper R6 configuration and validation works", {
  # Initialization and Defaults
  cfg <- paramsScraper()
  expect_true(inherits(cfg, "cfg_scraper"))

  expect_equal(cfg$get("project"), "my-project")
  expect_equal(cfg$get("selenium$port"), 4444L)
  expect_length(cfg$get("urls"), 0)

  # Programmatic Overrides via $set
  td <- tempdir()
  cfg$set("project", "test-proj")
  cfg$set("base_dir", td)

  expect_equal(cfg$get("project"), "test-proj")
  expect_equal(cfg$get("base_dir"), td)

  # Nested Updates (Testing your $path implementation)
  cfg$set("selenium$host", "remote-hub")
  cfg$set("selenium$port", 5555L)
  cfg$set("robots$check", FALSE)

  expect_equal(cfg$get("selenium$host"), "remote-hub")
  expect_equal(cfg$get("selenium$port"), 5555L)
  expect_false(cfg$get("robots$check"))

  # Validation: Top-level keys
  expect_error(cfg$set("invalid_key", 123), "is not a valid parameter")
  expect_error(cfg$set("project", 123), "must be a non-empty string")
  expect_error(cfg$set("base_dir", "non/existent/path/xyz"), "is not an existing directory")

  # Validation: Nested keys (Testing your .set_in logic)
  # This ensures that updating a nested value still triggers the parent's validation
  expect_error(cfg$set("selenium$port", 99999), "must be <= 65535")
  expect_error(cfg$set("selenium$browser", "firefox"), "must be one of 'chrome'")
  expect_error(cfg$set("robots$workers", -1), "must be >= 1")

  # Mass update via $update
  cfg$update(list(
    project = "mass-update",
    selenium = list(workers = 10L)
  ))
  expect_equal(cfg$get("project"), "mass-update")
  expect_equal(cfg$get("selenium$workers"), 10L)
  # Ensure other nested values weren't wiped by the update (modifyList check)
  expect_equal(cfg$get("selenium$host"), "remote-hub")
})

test_that("cfg_googlesearch specific validation works", {
  env1 <- Sys.getenv("SCRAPING_APIKEY_GOOGLE")
  env2 <- Sys.getenv("SCRAPING_ENGINE_GOOGLE")
  on.exit({
    Sys.setenv("SCRAPING_APIKEY_GOOGLE" = env1)
    Sys.setenv("SCRAPING_ENGINE_GOOGLE" = env2)
  })

  Sys.setenv("SCRAPING_APIKEY_GOOGLE" = "mygoogleAPIKey")
  Sys.setenv("SCRAPING_ENGINE_GOOGLE" = "mysearchEngineID")

  gcfg <- paramsGoogleSearch(path = tempdir())

  expect_equal(gcfg$get("max_queries"), 10000L)

  # Test enum-like validation for scrape_attributes
  expect_error(gcfg$set("scrape_attributes", "invalid_attr"))
  gcfg$set("scrape_attributes", c("title", "link"))
  expect_equal(gcfg$get("scrape_attributes"), c("title", "link"))

  # Test integer range
  expect_error(gcfg$set("max_query_rate", -5))
})

test_that("YAML export and round-trip loading works", {
  td <- tempdir()
  yaml_path <- file.path(td, "test_config.yaml")

  # 1. Setup a config with non-default nested values
  cfg <- paramsScraper(base_dir = td)
  cfg$set("selenium$port", 5555L)
  cfg$set("selenium$ecaps$args", c("--headless", "--no-sandbox", "--custom-flag"))

  # 2. Export to YAML
  cfg$export(yaml_path)
  expect_true(file.exists(yaml_path))

  # 3. Load into a new object and verify
  # Pass the file to initialize via the config_file argument
  cfg_new <- paramsScraper(config_file = yaml_path, base_dir = td)

  expect_equal(cfg_new$get("selenium$port"), 5555L)
  expect_contains(cfg_new$get("selenium$ecaps$args"), "--custom-flag")

  # 4. Check that defaults for other keys were preserved during YAML load
  # (Verifying modifyList behavior)
  expect_equal(cfg_new$get("selenium$browser"), "chrome")

  if (file.exists(yaml_path)) file.remove(yaml_path)
})

test_that("Complex nested list validation works", {
  cfg <- paramsScraper()

  # Test that providing a partial list to a top-level key works
  # because your .validate uses modifyList with defaults
  new_robots <- list(workers = 5L)
  cfg$set("robots", new_robots)

  expect_equal(cfg$get("robots$workers"), 5L)
  expect_equal(cfg$get("robots$check"), TRUE) # Should still be default

  # Test that invalid types inside a nested list are caught during top-level set
  expect_error(
    cfg$set("robots", list(check = "not_a_boolean")),
    "must be TRUE/FALSE"
  )
})

test_that("Path splitting and validation works", {
  cfg <- paramsScraper()

  # Test $ syntax
  cfg$set("selenium$host", "test-host")
  expect_equal(cfg$get("selenium$host"), "test-host")

  # Test character vector syntax
  cfg$set(c("selenium", "host"), "vector-host")
  expect_equal(cfg$get(c("selenium", "host")), "vector-host")

  # Test that dot-syntax is blocked per your .validate_path_syntax
  expect_error(cfg$get("selenium.host"), "must not use dot-syntax")
  expect_error(cfg$set("selenium.host", "error"), "must not use dot-syntax")
})
