# scripts/01_get_dia_html.R
# Download raw HTML snapshots for Democracy in Action endorsement pages

out_dir <- "data/raw/Democracy in Action"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Define pages to snapshot
pages <- data.frame(
  year = c(2008, 2012),
  source_site = c("p2008.org", "p2012.org"),
  url = c(
    "https://p2008.org/cands08/endorse08el2.html",
    "https://p2012.org/candidates/natendorse.html"
  ),
  stringsAsFactors = FALSE
)

download_one <- function(year, source_site, url) {
  out_file <- file.path(
    out_dir,
    sprintf("dia_%s_%s.html", year, gsub("\\.","_", source_site))
  )
  
  ok <- tryCatch({
    utils::download.file(url, destfile = out_file, mode = "wb", quiet = TRUE)
    TRUE
  }, error = function(e) {
    message("download.file failed for ", url, " : ", conditionMessage(e))
    FALSE
  })
  
  # Validate and fall back
  if (!ok || !file.exists(out_file) || is.na(file.info(out_file)$size) || file.info(out_file)$size == 0) {
    message("Falling back to curl for ", url)
    cmd <- sprintf(
      "curl -L -A %s -o %s %s",
      shQuote("Mozilla/5.0"),
      shQuote(out_file),
      shQuote(url)
    )
    system(cmd)
  }
  
  if (!file.exists(out_file) || is.na(file.info(out_file)$size) || file.info(out_file)$size == 0) {
    stop("Download failed or produced an empty file:", url)
  }
  
  message("Saved:", out_file)
  invisible(out_file)
}

mapply(download_one, pages$year, pages$source_site, pages$url)