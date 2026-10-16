# ============================================================================
# Extract officials' endorsements from Democracy in Action (2020)
#
# Source page: "Endorsements by Federal and Statewide Elected Officials in
# the 2020 Democratic Presidential Primary" (updated January 31, 2020).
# This is a snapshot: endorsements after Jan. 31, 2020 are not on it.
# Input: data/raw/Democracy in Action/dia_2020_officials.html
# Output: data/raw/Democracy in Action/extracted/dia_2020_officials_extracted.csv
#
# Layout: same idea as the 2016 officials page, with one <table> per
# candidate (15 tables: BIDEN ... WARREN). Row 1 holds the candidate name
# (and, for some, a "+" link to the candidate's own endorsement page, kept
# as candidate_page_url); row 2 holds nine cells in three column groups:
#   td[1] names | td[2] dates | td[3] links   -> "Governors"
#   td[4] names | td[5] dates | td[6] links   -> "U.S. Senators"
#   td[7] names | td[8] dates | td[9] links   -> "U.S. Representatives"
# Within a group the cells line up LINE BY LINE (5th name <-> 5th date <->
# 5th link); blank lines are alignment spacers, kept while splitting and
# only skipped once all three cells are blank on that line. line_in_cell
# records the position. BULLOCK's table has a single row: the name sits in
# td[1] above his (empty) governor list, so that header line is skipped.
#
# Second endorsements: names marked "*" switched after their first choice
# dropped out. The page's own legend ("*Second endorsements after first
# choice dropped out: Ruben Gallego (AZ-7): Swalwell > Harris ...") is
# parsed and joined back on district + endorsee to fill
# switch_direction = "from" and switch_candidate (e.g. "Swalwell"; "self"
# for Ryan and Moulton, who first ran themselves).
#
# Statewide officials are NOT in the tables: they are printed as free text
# after each table ("More Statewide Officials - DE: Attorney General Kathy
# Jennings 04/25/19. IA: ..."). The text is split by state ("XX: "), then
# split again at each office title, giving one row per official (21 in all).
# In a comma-separated list sharing one date at the end (CA under Harris;
# VT Donovan/Pearce/Hoffer under Sanders), each official gets that date.
# Any state text with no recognised title would be kept as a
# "[STATEWIDE - UNSPLIT]" row (Step 6 checks there are none).
# Other text between tables becomes "[PAGE NOTE]" rows.
#
# Decisions applied in this script (Oct. 2026):
#   - Statewide officials are split automatically (above).
#   - Booker, U.S. Representatives: one date (02/01/19) on the first line
#     for the whole NJ delegation; it is copied to all 11 members (Step 2b).
#   - endorsee and switch_candidate use standardized full names ("Joe
#     Biden"); the page heading is kept in endorsee_raw. For Ryan and
#     Moulton, whose first choice was "self", switch_candidate is their own
#     name.
#   - At-large House districts are coded 0, including Representatives listed
#     with a state only (Lisa Blunt Rochester, DE).
#   - record_type = "endorsement" for every endorsement row (no retractions
#     on this page); blank for [PAGE NOTE] rows.
#
# The cross-reference grids further down the page (Democratic Governors,
# Senators, House members by state) have no dates -- not extracted, same
# decision as the 2012 and 2016 officials scripts.
#
# NOTE on source quirks (kept in output rather than silently "corrected"):
#   - Biden, U.S. Senators: a sentence about Feinstein ("Feinstein reported
#     by the Washington Examiner on May 8, 2019 ..., official announcement on
#     Oct. 8, 2019") sits in the names column -- kept as an [UNMATCHED] row.
#   - "New Jersey" (Booker), "Calif." (Harris) and "Texas" (Castro) are
#     delegation labels in the names column, each with a link to a joint
#     announcement -- kept as [UNMATCHED] rows (the link is in evidence_url).
#   - "Ben McAdams (UT-4)" (Bloomberg) has no "Rep." title; it is parsed as
#     a Representative with note "no 'Rep.' title on page".
#   - "Rep. Katie Hill (CA-25) resigned" -> note "resigned".
#   - Date oddities kept in note: "from beg." (Joaquin Castro for Castro),
#     "?" (Trone), "12/13.19" and "02/19" are kept as date_raw as written.
#   - Vicente González (TX-15)* is starred but missing from the legend (a
#     footnote says he "switched from Castro to Biden"); note keeps "*".
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ----------------------------------------------------------------
input_path  <- "data/raw/Democracy in Action/dia_2020_officials.html"
output_path <- "data/raw/Democracy in Action/extracted/dia_2020_officials_extracted.csv"

# ---- Helper functions (same as the 2016 officials script) -------------------

link_token_re <- regex('<a\\s+[^>]*?href="([^"]*)"[^>]*>(.*?)</a>',
                       dotall = TRUE, ignore_case = TRUE)
url_token_re  <- regex("@@URL\\[([^\\]]*)\\]@@")
block_tag_re  <- regex("</?(?:p|div|tr|td|th|table|tbody|li|ul|center|blockquote|h1|h2|h3)\\b[^>]*>",
                       ignore_case = TRUE)

# Links become "@@URL[href]@@text" -- URL token BEFORE the text, so a link
# that wraps a <br> keeps its "+" and URL on the same line.
markup_to_text <- function(html_str, block_tags) {
  html_str <- str_remove_all(html_str, regex("<script\\b.*?</script>", dotall = TRUE, ignore_case = TRUE))
  # An empty link may serialize as self-closing <a href="..."/>; drop it so
  # the link pattern cannot run on to the next </a>.
  html_str <- str_remove_all(html_str, regex("<a\\b[^>]*/>", ignore_case = TRUE))
  html_str <- str_replace_all(html_str, link_token_re, "@@URL[\\1]@@\\2")
  html_str <- str_replace_all(html_str, regex("<br\\b[^>]*>", ignore_case = TRUE), "@@BR@@")
  if (block_tags) html_str <- str_replace_all(html_str, block_tag_re, "@@BR@@")
  frag <- read_html(paste0("<html><body><div>", html_str, "</div></body></html>"),
                    encoding = "UTF-8")
  txt <- xml_text(frag)
  txt <- str_replace_all(txt, "\u00a0", " ")
  str_replace_all(txt, "\\s+", " ")
}

# One <td> -> its <br>-separated lines, KEEPING blank alignment lines.
cell_slots <- function(td) {
  html_str <- as.character(td)
  html_str <- str_remove(html_str, "^\\s*<td\\b[^>]*>")
  html_str <- str_remove(html_str, "</td>\\s*$")
  slots <- str_trim(str_split(markup_to_text(html_str, block_tags = FALSE), fixed("@@BR@@"))[[1]])
  while (length(slots) > 0 && slots[length(slots)] == "") slots <- slots[-length(slots)]
  slots
}

flatten_html <- function(html_str) {
  lines <- str_trim(str_split(markup_to_text(html_str, block_tags = TRUE), fixed("@@BR@@"))[[1]])
  lines[lines != ""]
}

strip_urls <- function(x) str_squish(str_remove_all(x, url_token_re))

collect_urls <- function(x) {
  urls <- unlist(map(x, ~ str_match_all(.x, url_token_re)[[1]][, 2]))
  urls <- unique(urls[!is.na(urls) & urls != ""])
  if (length(urls) == 0) NA_character_ else paste(urls, collapse = "; ")
}

# ---- Name / title parsing ---------------------------------------------------

titles <- c("Lt. Gov.", "Gov.", "Sen.", "Rep.")
title_alt    <- paste(str_replace_all(titles, "\\.", "\\\\."), collapse = "|")
name_loc_re  <- regex(paste0("^(", title_alt, ")\\s+(.+?)\\s*\\(([A-Z]{2,4}(?:-[A-Z0-9]+)?)\\)\\s*(.*)$"))
name_only_re <- regex(paste0("^(", title_alt, ")\\s+(.+)$"))

title_description <- c(
  "Gov." = "Governor", "Lt. Gov." = "Lieutenant Governor",
  "Sen." = "U.S. Senator", "Rep." = "U.S. Representative"
)

# A Representative listed without "Rep." ("Ben McAdams (UT-4)"); only
# accepted in the U.S. Representatives column.
untitled_rep_re <- regex("^([A-Z][^()]+?)\\s*\\(([A-Z]{2}-[A-Z0-9]+)\\)\\s*(.*)$")

# Page headings (and legend surnames) -> standardized full candidate names.
# stopifnot() in Step 5 catches any heading not listed.
candidate_names <- c(
  "BIDEN" = "Joe Biden", "BLOOMBERG" = "Michael Bloomberg", "BOOKER" = "Cory Booker",
  "BULLOCK" = "Steve Bullock", "BUTTIGIEG" = "Pete Buttigieg", "CASTRO" = "Julian Castro",
  "DELANEY" = "John Delaney", "GILLIBRAND" = "Kirsten Gillibrand", "HARRIS" = "Kamala Harris",
  "INSLEE" = "Jay Inslee", "KLOBUCHAR" = "Amy Klobuchar", "O'ROURKE" = "Beto O'Rourke",
  "SANDERS" = "Bernie Sanders", "SWALWELL" = "Eric Swalwell", "WARREN" = "Elizabeth Warren"
)
standardize_name <- function(x) {
  key <- toupper(x)
  unname(ifelse(!is.na(key) & key %in% names(candidate_names), candidate_names[key], x))
}

valid_date_re <- regex("^\\d{1,2}/\\d{1,2}[/.]\\d{2}$|^\\d{1,2}/\\d{2}$")
ditto_marks   <- c('"', "\u201c", "\u201d", "''")

# ---- Parse one column group (names / dates / links cells) -------------------

parse_group <- function(name_td, date_td, link_td, endorsee, column_label, skip_line = NULL) {
  N <- cell_slots(name_td)
  D <- cell_slots(date_td)
  L <- cell_slots(link_td)
  if (!is.null(skip_line)) N[strip_urls(N) == skip_line] <- ""   # single-row table header
  n <- max(length(N), length(D), length(L))
  if (n == 0) return(NULL)
  pad <- function(x) c(x, rep("", n - length(x)))
  N <- pad(N); D <- pad(D); L <- pad(L)
  
  last_date <- NA_character_
  out <- list()
  
  for (k in seq_len(n)) {
    name_txt <- strip_urls(N[k])
    date_txt <- strip_urls(D[k])
    link_txt <- strip_urls(L[k])
    if (name_txt == "" && date_txt == "" && link_txt == "") next   # spacer line
    
    date_ditto <- date_txt %in% ditto_marks
    if (date_ditto) {
      date_val <- last_date
    } else if (str_detect(date_txt, valid_date_re)) {
      date_val  <- date_txt
      last_date <- date_txt
    } else {
      date_val <- NA_character_
    }
    
    m1 <- str_match(name_txt, name_loc_re)
    m2 <- str_match(name_txt, name_only_re)
    m3 <- str_match(name_txt, untitled_rep_re)
    untitled <- FALSE
    if (!is.na(m1[1, 1])) {
      title <- m1[1, 2]; endorser <- m1[1, 3]; loc <- m1[1, 4]; post <- str_squish(m1[1, 5])
    } else if (!is.na(m2[1, 1])) {
      title <- m2[1, 2]; endorser <- m2[1, 3]; loc <- NA_character_; post <- ""
    } else if (column_label == "U.S. Representatives" && !is.na(m3[1, 1])) {
      title <- "Rep."; endorser <- str_squish(m3[1, 2]); loc <- m3[1, 3]; post <- str_squish(m3[1, 4])
      untitled <- TRUE
    } else {
      title <- NA_character_; endorser <- NA_character_; loc <- NA_character_; post <- ""
    }
    parsed <- !is.na(title)
    
    description <- if (!parsed) {
      NA_character_
    } else if (title %in% names(title_description)) {
      title_description[[title]]
    } else {
      title
    }
    
    note_parts <- c(
      if (post != "") post,                       # "*", "resigned"
      if (untitled) "no 'Rep.' title on page",
      if (date_txt == "?") "date shown as '?'",
      if (date_txt != "" && !date_ditto && is.na(date_val) && date_txt != "?") paste0("date cell reads: ", date_txt)
    )
    
    raw <- paste(name_txt, date_txt, link_txt, sep = " | ")
    raw <- if (name_txt == "") paste0("[ORPHAN LINE] ", raw) else if (!parsed) paste0("[UNMATCHED] ", raw) else raw
    
    out[[length(out) + 1]] <- tibble(
      endorsee             = endorsee,
      endorser_name        = endorser,
      endorser_description = description,
      loc                  = loc,
      state                = if (!is.na(loc)) str_remove(loc, "-[A-Z0-9]+$") else NA_character_,
      district             = if (!is.na(loc)) str_extract(loc, "(?<=-)[A-Z0-9]+$") else NA_character_,
      date_raw             = date_val,
      note                 = if (length(note_parts) > 0) paste(note_parts, collapse = "; ") else NA_character_,
      second_endorsement   = str_detect(post, fixed("*")),
      evidence_url         = collect_urls(c(L[k], if (!parsed) N[k])),
      parsed_ok            = parsed,
      raw_text             = raw,
      table_column         = column_label,
      line_in_cell         = k,
      date_ditto           = date_ditto
    )
  }
  bind_rows(out)
}

# ---- Step 1: Read HTML and find the candidate tables ------------------------

doc <- read_html(input_path, encoding = "UTF-8")
cand_tables <- xml_find_all(doc, "//table[./tbody/tr[1]/td[9] and not(./tbody/tr[1]/td[10]) and .//big]")
stopifnot(length(cand_tables) == 15)
cand_paths <- xml_path(cand_tables)

group_cells <- list(
  list(cols = 1:3, label = "Governors"),
  list(cols = 4:6, label = "U.S. Senators"),
  list(cols = 7:9, label = "U.S. Representatives")
)

# ---- Step 2: Parse each candidate table --------------------------------------

endorse_df <- map_dfr(cand_tables, function(tbl) {
  endorsee <- str_squish(xml_text(xml_find_first(tbl, ".//big")))
  trs   <- xml_find_all(tbl, "./tbody/tr")
  cells <- xml_find_all(trs[[length(trs)]], "./td")
  stopifnot(length(cells) == 9)
  
  single_row <- length(trs) == 1
  page_url <- if (!single_row) collect_urls(cell_slots(xml_find_all(trs[[1]], "./td")[[9]])) else NA_character_
  
  map_dfr(group_cells, function(g) {
    parse_group(cells[[g$cols[1]]], cells[[g$cols[2]]], cells[[g$cols[3]]],
                endorsee, g$label,
                skip_line = if (single_row && g$cols[1] == 1) endorsee else NULL)
  }) %>% mutate(candidate_page_url = page_url)
})
cat("Rows extracted from candidate tables:", nrow(endorse_df), "\n")

# ---- Step 2b: Groups listed under ONE date ------------------------------------
# The date on the first member's line applies to every member below it. On
# this page: Booker's New Jersey House delegation (02/01/19 on the first
# line only).

shared_date_groups <- tribble(
  ~endorsee, ~table_column,
  "BOOKER",  "U.S. Representatives"
)

fill_shared_dates <- function(df, groups) {
  for (g in seq_len(nrow(groups))) {
    idx <- which(df$endorsee == groups$endorsee[g] &
                   df$table_column == groups$table_column[g] & df$parsed_ok)
    idx <- idx[order(df$line_in_cell[idx])]
    last_date <- NA_character_
    for (i in idx) {
      if (!is.na(df$date_raw[i])) {
        last_date <- df$date_raw[i]
      } else if (!is.na(last_date)) {
        df$date_raw[i] <- last_date
        df$note[i] <- paste(na.omit(c(df$note[i], "date copied from the group's first listed member")),
                            collapse = "; ")
      }
    }
  }
  df
}
endorse_df <- fill_shared_dates(endorse_df, shared_date_groups)

# ---- Step 3: Join the "second endorsements" legend --------------------------

page_lines <- strip_urls(flatten_html(as.character(xml_find_first(doc, "//body"))))
legend_start <- which(str_starts(page_lines, fixed("*Second endorsements")))
stopifnot(length(legend_start) == 1)

legend_re <- regex("^(.+?) \\(([A-Z]{2}-[A-Z0-9]+)\\): (.+?) > (.+)$")
legend <- list()
for (ln in page_lines[(legend_start + 1):length(page_lines)]) {
  m <- str_match(ln, legend_re)
  if (is.na(m[1, 1])) break                 # legend ends at the first non-matching line
  legend[[length(legend) + 1]] <- tibble(
    loc = m[1, 3], legend_from = m[1, 4], endorsee_upper = toupper(m[1, 5])
  )
}
legend_df <- bind_rows(legend)
cat("Legend entries found:", nrow(legend_df), "\n")
stopifnot(nrow(legend_df) == 12)

endorse_df <- endorse_df %>%
  mutate(endorsee_upper = toupper(endorsee)) %>%
  left_join(legend_df, by = c("loc", "endorsee_upper")) %>%
  mutate(
    switch_direction = if_else(!is.na(legend_from), "from", NA_character_),
    # "self" (Ryan, Moulton) means their first choice was their own campaign
    switch_candidate = if_else(legend_from == "self", endorser_name, standardize_name(legend_from)),
    note = case_when(
      is.na(legend_from) | legend_from != "self" ~ note,
      is.na(note) ~ "first choice was own presidential campaign",
      TRUE ~ paste0(note, "; first choice was own presidential campaign")
    )
  ) %>%
  select(-endorsee_upper, -legend_from, -loc)

stopifnot(sum(!is.na(endorse_df$switch_direction)) == 12)

# ---- Step 4: Text between candidate tables ----------------------------------
# "More Statewide Officials - XX: ..." blocks and other notes. Collected from
# the sibling nodes after each candidate table, up to the next candidate
# table or the "_____" rule that starts the cross-reference grids.

# Within one state's text, split at each statewide title:
#   "Lt. Gov. Eleni Kounalakis, Secretary of State Alex Padilla, ..., 02/26/19."
# -> one row per official. An official with no date of their own takes the
# date (and link) of the next official in the list that has one, since a
# comma-separated list shares the date written at its end.
statewide_titles <- c(
  "Lt. Gov.", "Attorney General", "Secretary of State", "State Treasurer", "Treasurer",
  "State Auditor", "Auditor", "Sup. of Public Instruction", "Insurance Commissioner"
)
statewide_title_re <- regex(paste0(
  "(?<![A-Za-z])(?:", paste(str_replace_all(statewide_titles, "\\.", "\\\\."), collapse = "|"), ")(?= )"
))
statewide_description <- c(
  "Lt. Gov." = "Lieutenant Governor",
  "Sup. of Public Instruction" = "Superintendent of Public Instruction"
)
segment_date_re <- regex("\\b\\d{1,2}/\\d{1,2}/\\d{2}\\b|\\b\\d{1,2}/\\d{2}\\b")

split_officials <- function(seg) {          # seg still holds @@URL[...]@@ tokens
  locs <- str_locate_all(seg, statewide_title_re)[[1]]
  if (nrow(locs) == 0) return(NULL)
  starts <- locs[, "start"]
  chunks <- str_sub(seg, starts, c(starts[-1] - 1, str_length(seg)))
  out <- tibble(
    title        = str_sub(seg, locs[, "start"], locs[, "end"]),
    plain        = strip_urls(chunks),
    date_raw     = str_extract(plain, segment_date_re),
    evidence_url = map_chr(chunks, collect_urls),
    note         = "split from 'More Statewide Officials' text"
  )
  name <- str_trim(str_sub(out$plain, str_length(out$title) + 1))
  name <- str_remove(name, "\\s*\\d{1,2}/\\d{1,2}(?:/\\d{2})?.*$")   # drop date and anything after
  out$endorser_name <- str_remove(name, "[\\s,.>(+)]+$")
  for (i in rev(seq_len(nrow(out) - 1))) {
    if (is.na(out$date_raw[i]) && !is.na(out$date_raw[i + 1])) {
      out$date_raw[i] <- out$date_raw[i + 1]
      if (is.na(out$evidence_url[i])) out$evidence_url[i] <- out$evidence_url[i + 1]
      out$note[i] <- paste0(out$note[i], "; date shared with the officials listed after")
    }
  }
  out$endorser_description <- ifelse(out$title %in% names(statewide_description),
                                     statewide_description[out$title], out$title)
  out %>% select(endorser_name, endorser_description, date_raw, evidence_url, note)
}

split_states <- function(x) {
  locs <- str_locate_all(x, "(?<![A-Za-z])[A-Z]{2}: ")[[1]]
  if (nrow(locs) == 0) return(tibble(state = NA_character_, text = x))
  pieces <- tibble(
    state = str_sub(x, locs[, "start"], locs[, "start"] + 1),
    text  = str_sub(x, locs[, "end"] + 1, c(locs[-1, "start"] - 1, str_length(x)))
  )
  pre <- str_trim(str_sub(x, 1, locs[1, "start"] - 1))
  if (pre != "") pieces <- bind_rows(tibble(state = NA_character_, text = pre), pieces)
  pieces
}

between_df <- map_dfr(cand_tables, function(tbl) {
  endorsee <- str_squish(xml_text(xml_find_first(tbl, ".//big")))
  sibs <- xml_find_all(tbl, "following-sibling::node()")
  html_parts <- character(0)
  for (s in sibs) {
    if (xml_path(s) %in% cand_paths) break
    if (str_starts(str_remove_all(xml_text(s), "\\s"), "____")) break
    html_parts <- c(html_parts, as.character(s))
  }
  if (length(html_parts) == 0) return(NULL)
  lines <- flatten_html(paste(html_parts, collapse = ""))
  
  out <- list()
  statewide_mode <- FALSE
  last_state <- NA_character_
  for (ln in lines) {
    txt <- strip_urls(ln)
    if (txt == "") next
    if (str_starts(txt, fixed("More Statewide Officials"))) {
      statewide_mode <- TRUE
      ln <- str_remove(ln, "^.*?More Statewide Officials\\s*-?\\s*")
    }
    if (!statewide_mode) {
      out[[length(out) + 1]] <- tibble(
        endorsee = endorsee, evidence_url = collect_urls(ln), parsed_ok = FALSE,
        raw_text = paste0("[PAGE NOTE] ", txt), table_column = "Between tables"
      )
      next
    }
    pieces <- split_states(ln)
    for (i in seq_len(nrow(pieces))) {
      st <- if (!is.na(pieces$state[i])) pieces$state[i] else last_state   # continuation line
      last_state <- st
      seg_txt <- strip_urls(pieces$text[i])
      if (seg_txt == "") next
      officials <- split_officials(pieces$text[i])
      if (is.null(officials)) {
        # No recognised title: keep the text for manual review
        out[[length(out) + 1]] <- tibble(
          endorsee = endorsee, state = st, evidence_url = collect_urls(pieces$text[i]),
          endorser_description = "Statewide official(s)", parsed_ok = FALSE,
          raw_text = paste0("[STATEWIDE - UNSPLIT] ", st, ": ", seg_txt),
          table_column = "More Statewide Officials"
        )
      } else {
        out[[length(out) + 1]] <- officials %>% mutate(
          endorsee = endorsee, state = st, parsed_ok = TRUE,
          raw_text = paste0(st, ": ", seg_txt),
          table_column = "More Statewide Officials"
        )
      }
    }
  }
  bind_rows(out)
})
cat("Between-table rows (statewide + notes):", nrow(between_df), "\n")

# ---- Step 5: Combine, add constant fields, order columns -------------------

stopifnot(all(unique(endorse_df$endorsee) %in% names(candidate_names)))

df <- bind_rows(endorse_df, between_df) %>%
  mutate(
    endorsee_raw = endorsee,                       # heading as on the page
    endorsee = standardize_name(endorsee),
    # At-large House seats are coded 0 (docs/final_schema.md): "XX-AL", and
    # any Representative listed with a state but no district number
    # (e.g. "Rep. Lisa Blunt Rochester (DE)").
    district = case_when(
      district == "AL" ~ "0",
      endorser_description == "U.S. Representative" & is.na(district) & !is.na(state) ~ "0",
      TRUE ~ district
    ),
    record_type = if_else(str_starts(raw_text, fixed("[PAGE NOTE]")), NA_character_, "endorsement"),
    contest_id = "2020D",
    year = 2020,
    party = "D",
    endorser_party_note = NA_character_
  ) %>%
  select(
    contest_id, year, party, endorsee,
    endorser_name, endorser_description, endorser_party_note,
    state, district,
    date_raw, note, record_type, switch_direction, switch_candidate,
    evidence_url,
    parsed_ok, raw_text,
    # 2020-officials-specific columns (see header comments)
    endorsee_raw, table_column, line_in_cell, date_ditto, second_endorsement, candidate_page_url
  )

# ---- Step 6: Validation checkpoints, report, and write out -----------------
# Expected from manual inspection: 134 table rows, 130 parsed (the other 4
# are the Feinstein sentence and the New Jersey / Calif. / Texas delegation
# labels); 21 statewide officials split out of the between-table text.

cat("\nEndorsements per candidate and column (parsed rows):\n")
print(count(df %>% filter(parsed_ok), endorsee, table_column))

stopifnot(
  nrow(endorse_df) == 134,
  sum(endorse_df$parsed_ok) == 130,
  sum(df$table_column == "More Statewide Officials" & df$parsed_ok) == 21,
  !any(str_starts(df$raw_text, fixed("[STATEWIDE - UNSPLIT]")))
)

n_failed <- sum(!df$parsed_ok)
cat("\nSuccessfully parsed:", sum(df$parsed_ok), "/", nrow(df), "\n")
cat(n_failed, "row(s) need manual review:\n")
print(df %>% filter(!parsed_ok) %>% pull(raw_text) %>% str_trunc(110))

cat("\nParsed rows with no date:\n")
print(df %>% filter(parsed_ok, is.na(date_raw)) %>% select(endorsee, endorser_name, table_column, line_in_cell, note))

cat("\nSecond endorsements (from the page legend):\n")
print(df %>% filter(!is.na(switch_direction)) %>% select(endorsee, endorser_name, state, district, switch_candidate))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")

cat("Written to:", output_path, "\n")