# Data Sources

This document tracks each raw data source feeding into the final compiled 
dataset: what it looks like, known issues, and the cleaning/transformation steps
required before it can be merged. This file is updated as sources are collected, 
inspected, and cleaned.

---

## Source 1: The Party Decides — Endorsement Data

**Acquisition Status:** File acquired (direct download)
**Processing Status:** Not yet inspected

**Format:** .xls (Excel 97-2003 format)
**File name(s):** 
- `data/raw/Endorsement data.xls` (5.4MB)
- `data/raw/Codebook for endorsement data.doc` (165KB)
**Author(s):** Marty Cohen, David Karol, Hans Noel, and John Zaller
**Provider/origin:** Direct download from Marty Cohen's personal website (http://www.martycohen.net/)
**Date acquired:** 12/09/25
**Date range covered:** 1979-01-06 to 2004-01-19 (endorsement report dates); covers
10 nomination contests from 1980 to 2004.
**Unit of observation:** Endorsement event-level

### Structure

**Sheet 1: 1980-2004 (main data)**
- 39 documented variables (A-AM), matching codebook exactly
- 7,325 real data rows (endorsements)
- Contests covered: 1980D, 1980R, 1984D, 1988D, 1988R, 1992D, 1996R, 2000D, 
 2000R, 2004D
- Row counts by contest range from 226 (1980D) to 1,974 (2004D)
- 5,928 distinct endorsers; 7,325 distinct endorsement events (primary key)
 
 **Sheet 2: Extra Variables (undocumented — not in codebook)**
- 16 additional variables: National, Intense policy demander, In-group (1) 
  & (2), Out-group (1) & (2), David's ideology, Wes/Mark's ideology, 
  Nominate, Discrete, Mainstream, Weighted mainstream, Distance from median 
  good/bad, Weighted good distance from median
- 7,325 distinct rows
- Joins to main sheet 1:1 via `Endorsement number`

### Known Issues

1. **Undocumented sheet:** "Extra Variables" is not described anywhere in the
codebook. Variable meanings are inferable from names but not authoritative.
2. **Referenced but missing data:** The codebook file's internal metadata title 
is "Two data sets: 1980-2004 and 1972-1976," but only the 1980-2004 data is present 
in this download. The 1972-1976 data is recovered from a second data set provided by FiveThirtyEight.
3. **Inconsistent missing-value coding:** Several nominally-numeric columns (e.g, `Home state endorsement`,
`Geography`, `Endorser's ideology`, `Weighted ideological distance`, `Weighted breadth`)
mix real numeric values with literal space-character strings (`' '`, `'  '`) as
missing-value placeholders, causing these columns to be read as text rather than numeric.
`Count` similarly mixes numbers with the literal string `"unknown"`.
4. **DATE column mixes real dates and text placeholders:** 9 rows contain text like
`"NO DATE"`, `"pre-May 27th"`, or `"post-October 6th"` instead of a parseable date.
5. **Substantial missingness in ideological variables:**  `Breadth`, `Breadth dummy`,
`Endorser's ideology`, and related weighted columns are missing for ~61–62% of 
rows (4,486–4,512 of 7,325). Per the codebook, this reflects real limitations in 
ideology coding (see Appendix C), not a data error. It substantially limits the 
usable sample for any ideology-based analysis.
6. **Gap in Endorser number sequence**: `Endorser number` spans 1–5,929 (5,929 
possible IDs, matching the codebook's stated range), but only 5,928 distinct values 
actually appear in the data — **endorser number 5105 never occurs**. Likely an ID 
left over from the original researchers' own data cleaning (e.g., a removed duplicate), 
but worth confirming rather than assuming if endorser-level analysis is planned.

### Cleaning / Transformation Steps Needed

- [ ] Convert `.xls` to `.csv` or `.xlsx` for long-term compatibility 
      (note: legacy `.xls` requires `xlrd` engine in pandas, or a 
      LibreOffice-based conversion if `xlrd` isn't available)
- [ ] Trim trailing blank rows (keep only first 7,325 
      data rows in each)
- [ ] Standardize missing-value encoding: convert literal space strings 
      and `"unknown"`/`"NO DATE"` text placeholders to proper `NA`, 
      consistently across all columns
- [ ] Parse `DATE` column to a proper date type; decide how to handle the 
      9 rows with text placeholders instead of dates (drop, impute 
      approximate date, or flag as a separate missingness category)
- [ ] Rename columns to a consistent, script-friendly naming convention 
      (e.g., snake_case) matching the rest of the final schema
- [ ] Join `Extra variables` sheet to main sheet on `Endorsement number`
- [ ] Document/infer meanings of the 16 undocumented "Extra variables" 
      columns before using them in analysis
- [ ] Decide on treatment of the ~61-62% missingness in ideology-related 
      columns (e.g., separate ideology-subsample analysis vs. imputation)
      
### Join Key(s)

- `Endorsement number` — joins main sheet to "Extra variables" sheet, 
  1:1 relationship (both trimmed to 7,325 rows)
- `Endorser number` — links endorsers who appear across multiple contests 
  (5,928 distinct endorsers across 7,325 endorsements, so this is not 
  unique per row)
  
### Notes

- Primary/foundational data source for this project.
- This dataset supported the research underlying Cohen, Karol, Noel, and Zaller's 
2008 book *The Party Decides: Presidential Nominations Before and After Reform* 
(University of Chicago Press). The book's appendix to Chapter 6, "A Closer Look 
at the Endorsement Data," provides a more reference for understanding data construction
and coding decisions.
- Codebook (`Codebook for endorsement data.doc`) should be reviewed alongside the
raw data file before/during inspection.
- Citation for this data source:
  > Cohen, Marty, David Karol, Hans Noel, and John Zaller. 2008. *The Party 
  > Decides: Presidential Nominations Before and After Reform.* Chicago: 
  > Univeristy of Chicago Press.

--- 

## Source 2: FiveThirtyEight Presidential Primary Endorsements Data

**Acquisition Status:** File acquired (shared directly by source)
**Processing Status:** Inspected; merge and weight decisions recorded (2026-10-16)

**Format:** .xlsx
**File name(s):** `data/raw/Prez primary endorsements 1972-2012.xlsx`
(2 sheets: "Pivot table", "Raw data")
**Provider/origin:** Shared via email by Nathaniel Rakich (FiveThirtyEight) in 
response to inquiry about the data underlying FiveThirtyEight's endorsement trackers
**Date acquired:** November 27, 2024
**Date range covered:** 1971-02-07 to 2012-08-26 (endorsement dates); covers 16 nomination
contests from 1972 to 2012
**Unit of observation:** Endorsement event-level

### Structure

**Sheet 1: "Raw data"**
- 10 columns: `contest`, `endorsee`, `endorser`, `description`, `date`, `state`,
`count`, `points`, `source`, `url`
- 3,422 rows, no blank padding rows, no exact duplicates
- Contests: 1972D, 1976D, 1976R, 1980D, 1980R, 1984D, 1988D, 1988R, 1992D, 1996R,
2000D, 2000R, 2004D, 2008D, 2008R, 2012R
- `url` column is entirely empty— appears to be a vestigial column
- `source` column is missing for 48 rows (all within 2008D/2008R contests)

**Sheet 2: "Pivot table"**
- A pre-built Excel pivot table (75 rows × 8 columns) summarizing points by 
  candidate for a single contest (2012R in the visible view). Not a 
  distinct data source. This is a derived summary view Excel retains 
  alongside the raw data, not something to import for cleaning.

### Known Issues

1. **Substantial contest overlap with Source 1, much of it same-provenance**: 2,097
of 3,422 rows (61%) fall within Source 1's contest range (1980-2004). Of those
overlapping rows, 1,408 (67%) explicitly cite "Marty Cohen (The Party Decides)"
as their source. Critically, **Source 2 only includes endorsements from Governors, U.S. Senators, and U.S. Representatives**,
which is a narrower scope than Source 1. This means that for the 1980-2004 overlap period,
Source 2 is primarily a subset of Source 1, rather than independent or additive data. Under
the merge decision (see Notes), overlapping rows are merged with Source 1 by the Source
Precedence rule in `docs/final_schema.md`: rows that match Source 1 collapse into one row,
and Source 2 rows with no Source 1 match are kept.
2. **Contests unique to Source 2:** 1972D, 1976D, 1976R, 2008D, 2008R, and 2012R
do not appear in Source 1. Notable, **1972D, 1976D, and 1976R may fill the gap** left
by the "missing" 1972-1976 dataset referenced in Source 1's codebook.
3. **Inconsistent state code casing:** `state` mixes uppercase (`CA`, `NY`) and lowercase
(`ca`, `ny`) postal abbreviations for the same states, plus one full-text outlier,
`"Northern Marina Islands"` (also likely misspelled), alongside the standard abbreviation
`CNMI` used elsewhere. Needs standardization to a single consistent format.
4. **Negative `points`/`count` values:** Values of -1, -5, -10 (points) and -1 (count)
represent endorsement retractions, not opposition. They are coded as rows with
`record_type = "retraction"` in the final schema. Whether Source 1 has any equivalent is
still an open question in `docs/final_schema.md`.
5. **`url` column is entirely empty** and likely safe to drop.
6. **48 rows missing `source`** (all in 2008D/2008R)— need to find alternative means of
verifying provenance of specific endorsements.
7. **`points` uses a different weighting scale from Source 1's `Weight`.** No codebook
documents how `points` were assigned, so they are not comparable with Source 1. Per the
weight decision in `docs/final_schema.md`, `points` are not carried into the final dataset;
Source 2 rows are weighted with the Party Decides system instead (see Notes).

### Cleaning / Transformation Steps Needed

- [ ] Import only the "Raw data" sheet; discard/ignore "Pivot table"
- [ ] Standardize `state` to consistent uppercase postal codes; recode "Northern
    Marina Islands" and `CNMI` to `MP` (the postal code for the Northern Mariana Islands)
- [ ] Code rows with negative `points` or `count` as `record_type = "retraction"`
- [ ] Drop `points` after coding retractions (not carried into the final dataset)
- [ ] Assign `weight` and `weight_category` from the Party Decides weighting system
    (codebook Appendix B, via `data/lookups/tpd_weights.csv`), using `description`
- [ ] Drop empty `url` column
- [ ] Rename columns to match final schema naming convention
- [ ] **Merge with Source 1 for 1980-2004** using the Source Precedence rule in
    `docs/final_schema.md`: match on a composite key (see Join Keys); for matched pairs keep
    the more detailed row and list the other source in `also_in_sources`; keep Source 2 rows
    with no Source 1 match, after checking them by hand for name-matching misses

### Join Key(s)
- No pre-built numeric ID (unlike Source 1's `Endorsement number`/`Endorser number`).
Matching to Source 1 will likely require a composite key — candidate/contest/endorser name/date —
with attention to name-formatting differences between sources.

### Notes

- This source directly overlaps in provenance with Source 1 for a majority 
  of shared-period rows, since FiveThirtyEight's own dataset cites Marty 
  Cohen's "The Party Decides" data as a source. However, since Source 2 is 
  scoped only to Governor/Senator/Representative endorsers, it is best 
  understood as **a subset of Source 1 for 1980-2004**, not an independent 
  or additive source for that period. Its unique contribution is the
  1972-1976 and 2008-2012 contests Source 1 lacks.
- **Merge decision (2026-10-16):** Source 2's 1980-2004 rows are merged with
  Source 1 under the Source Precedence rule in `docs/final_schema.md`, the same
  rule used for every overlap, rather than excluded or used only as a check.
  Because Source 2 is mostly a subset, most of its overlapping rows are expected
  to match Source 1 and collapse into Source 1's row, with Source 2 recorded in
  `also_in_sources`. Any Source 2 row with no Source 1 match is kept, so the
  merge also reveals where the two datasets disagree.
- No codebook was provided with this file; column meanings were inferred 
  from header names and data inspection. `points` appears to be a weighted 
  measure similar in spirit to Source 1's `Weight`/`Adjusted weight`.
- **Weight decision (2026-10-16):** `points` are dropped. The final dataset has
  a single `weight` field using the Party Decides weighting system (Cohen et al.
  codebook, Appendix B) for every source. Source 2 rows receive the Appendix B
  weight for their `description`, and `weight_category` records the category
  used. `points` are still used during cleaning to identify retractions.
- The raw data file (Prez_primary_endorsements_1972-2012.xlsx) is intentionally 
  excluded from this public repository, since it was shared directly by Nathaniel 
  Rakich via personal correspondence and its terms for redistribution were not specified.
  Per the decision in `docs/final_schema.md`, Source 2 rows are still included in the
  final dataset; the README states that the raw file is available on request from
  FiveThirtyEight, so replicators know the Source 2 cleaning step cannot be re-run from
  the public repo alone.
  
---
 
## Source 3: Democracy in Action — Endorsement Pages
 
**Acquisition Status:** File acquired (HTML pages saved directly from the website)
**Processing Status:** Extracted — manual review in progress (see per-file table below)
 
**Format:** .html (one saved web page per election cycle and endorser type)
**File name(s):** `data/raw/Democracy in Action/dia_<year>_<type>.html` (11 files;
see table below). Extracted output: `data/raw/Democracy in Action/extracted/*_extracted.csv`.
Text-safe review copies: `data/raw/Democracy in Action/review/*_review.xlsx`.
**Author(s):** Eric M. Appleman
**Provider/origin:** Democracy in Action (p2004.org, p2008.org, p2012.org, p2016.org,
democracyinaction.us), a site documenting U.S. presidential campaigns
**Date acquired:** September–October 2026 (first committed 2026-09-10 to 2026-10-14;
see per-file table)
**Date range covered:** the 2004–2020 nomination cycles: 2004D, 2008D, 2008R,
2012D (organizations page only; Obama was unopposed), 2012R, 2016D, 2016R and
2020D (see per-file table for each page's cut-off date)
**Unit of observation:** Endorsement event-level after extraction (one row per
endorser–candidate pair). The raw pages are curated lists, not datasets.
 
### Files
 
| Raw file | Page title | Page dated | Extraction script | Extracted rows | First committed | Review status |
| --- | --- | --- | --- | --- | --- | --- |
| `dia_2004_labor.html` | Labor Endorsements in the Race for the 2004 Dem. Nomination | through Feb. 19, 2004 (AFL-CIO endorsement of Kerry) | `extract_dia_2004_labor.R` | 78 | 2026-10-14 | not started |
| `dia_2008_labor.html` | Labor Endorsements in the 2008 Primary Campaigns | not stated (latest entry May 21, 2008) | `extract_dia_2008_labor.R` | 73 | 2026-10-12 | not started |
| `dia_2008_newspapers.html` | Endorsements by Newspapers and Magazines in the 2008 Primary Campaign | updated May 5, 2008 | `extract_dia_2008_newspapers.R` | 350 | 2026-09-17 | [confirm] |
| `dia_2008_officials.html` | Endorsements by Congressmen Senators and Governors--Feb. 5 Edition | last revised Feb. 27, 2008 | `extract_dia_2008_officials.R` | 386 | 2026-09-10 | [confirm] |
| `dia_2008_organizations.html` | Endorsements by National Organizations | not stated | `extract_dia_2008_organizations.R` | 15 | 2026-09-17 | [confirm] |
| `dia_2012_newspapers.html` | Endorsements by Newspapers and Magazines the 2012 Presidential Primary Campaign | updated March 31, 2012 | `extract_dia_2012_newspapers.R` | 58 | 2026-09-17 | [confirm] |
| `dia_2012_officials.html` | National Endorsements 2012 Republican Presidential Candidates | not stated | `extract_dia_2012_officials.R` | 157 | 2026-09-10 | [confirm] |
| `dia_2012_organizations.html` | Endorsements by National Organizations in the 2012 Presidential Campaign | updated April 7, 2013 | `extract_dia_2012_organizations.R` | 42 | 2026-09-17 | [confirm] |
| `dia_2016_officials.html` | Endorsements by Federal and Statewide Elected Officials in the 2016 Republican Presidential Primary | updated January 13, 2016 | `extract_dia_2016_officials.R` | 143 | 2026-10-14 | not started |
| `dia_2016_organizations.html` | Endorsements by National Organizations in the 2016 Presidential Campaign | updated September 26, 2016 | `extract_dia_2016_organizations.R` | 77 | 2026-10-14 | not started |
| `dia_2020_officials.html` | Endorsements by Federal and Statewide Elected Officials in the 2020 Democratic Presidential Primary | updated January 31, 2020 | `extract_dia_2020_officials.R` | 156 | 2026-10-14 | not started |
 
Extracted row counts include rows flagged for review (`parsed_ok = FALSE`, e.g.
`[PAGE NOTE]` and `[UNMATCHED]` rows), so they are not final endorsement counts.
 
### Structure
 
- **No common structure across pages.** Each page has its own HTML layout, so each
  file has its own extraction script in `scripts/extraction/`. The layouts fall
  into four types:
  - **Line lists** (organizations, newspapers): one endorsement per `<br>`-separated
    line under a candidate heading.
  - **Column-aligned tables** (2016 and 2020 officials): names, dates and links are
    in separate table cells, lined up line by line; blank lines are spacers that
    keep the columns aligned.
  - **Narrative blocks** (2004 and 2008 labor): one table cell or paragraph per
    union, with the endorsement date written inside prose.
  - **Free text between tables** (2020 statewide officials, page notes).
- **Extracted output columns.** All 11 CSVs share 16 core columns: `contest_id`,
  `year`, `party`, `endorsee`, `endorser_name`, `endorser_description`,
  `endorser_party_note`, `state`, `district`, `date_raw`, `note`,
  `switch_direction`, `switch_candidate`, `evidence_url`, `parsed_ok`, `raw_text`.
  The five files extracted in Oct. 2026 also have `record_type`, plus
  page-specific columns at the end (e.g. `section`, `all_dates`, `table_column`,
  `line_in_cell`, `date_ditto`, `endorsee_raw`). Each script's header comment
  documents its extra columns.
- **`raw_text`** keeps the source line (or, for column-aligned tables,
  `name | date | link`) so every row can be checked against the page.
- **Cross-reference grids** at the bottom of the 2012, 2016 and 2020 officials
  pages (all governors / senators / House members by state) have no dates or
  links and are not extracted. They could serve as a completeness check later.
- **Encoding:** 2004 and 2008 pages are ISO-8859-1; 2012 onward are UTF-8. Each
  script reads its page with the matching encoding and writes UTF-8.
### Known Issues
 
1. **Pages are snapshots, not complete records.** Each page stops at its own
   cut-off date (see table). Endorsements made after that date are missing, e.g.
   the 2016 officials page covers only endorsements through Jan. 13, 2016, and the
   2020 page only through Jan. 31, 2020.
2. **Republican-only and Democratic-only officials pages.** 2012 and 2016 officials
   cover only the Republican primary; 2020 officials only the Democratic primary.
   There is no 2016D or 2020R officials page, and labor pages exist only for 2004
   and 2008.
3. **General-election endorsements are mixed in.** The 2016 organizations page lists
   endorsements for the nominees (Clinton, Trump) dated after the primaries were
   settled. Kept as-is; a post-primary indicator is to be added later.
4. **Inconsistent date formats:** `MM/DD/YY` (2012 onward), `Month D, YYYY` and
   `Mon. D, YYYY` (2004, 2008), month-only dates (`May 2007`, `April 2007`), ditto
   marks (`"`), `?`, and text such as `from beg.`. Typos in the source include
   `12/13.19` and a 2008 Notes entry dated `Mar. 17, 2007` for a 2008 event.
   `date_raw` is kept as written; parsing to ISO dates happens at cleaning.
5. **Several dates per entry (labor pages).** Narratives mention founding dates,
   earlier endorsements and forum dates. The scripts choose the date nearest the
   candidate's name and keep every date found in `all_dates`.
6. **Misaligned columns (2016 officials).** In Bush's statewide column, one date
   line is missing a line break, shifting every date below it. Corrected by a
   hand-coded table in the script (`date_hand_corrected = TRUE` on 4 rows).
7. **Dates shared by a group.** Some groups are listed under one date (Kasich's Ohio
   statewide officials, 2016; Booker's New Jersey House delegation, 2020;
   comma-separated statewide lists, 2020). The scripts copy the date to each
   member and say so in `note`.
8. **Rows covering several endorsers** (e.g. "Ten SEIU State Councils", "SEIU Locals
   1199 and 32BJ", TCU inside the IAM cell, three UFCW locals in one line) are
   split into one row per endorser in the 2004 and 2008 labor extractions.
9. **Switches and retractions are written in prose** ("Originally endorsed Sen.
   Edwards", "Withdrew endorsement on February 7, 2004", a "second endorsements"
   legend on the 2020 page). Captured in `switch_direction` / `switch_candidate`
   and, for AFSCME 2004, a separate `record_type = "retraction"` row.
10. **Non-endorsements are listed alongside endorsements** ("No National
    Endorsement", "No Endorsement, At Least for Now", the 2008 labor Notes,
    "favorite son" resolutions). Excluded by the 2008 labor and 2016 organizations
    scripts.
11. **Source errors kept as written**, e.g. "Rep. Marco Rubio (UT-3)" (2016; UT-3 was
    Jason Chaffetz), California House seats written as `CD-41` (2012), several
    organization homepage links on the 2008 labor page pointing to the wrong
    union, and press-release file names whose dates don't match the displayed date
    (2016 organizations).
12. **Inconsistent conventions between older and newer extractions.** The six files
    extracted in Sept. 2026 keep candidate names as written on the page
    (`CLINTON`, `Clinton`, `Mitt Romney`) and at-large districts as written (`AL`),
    and have no `record_type` column. The five files extracted in Oct. 2026 use
    standardized full names (page heading kept in `endorsee_raw` /
    `section_heading`), code at-large districts as `0`, and include `record_type`.
### Cleaning / Transformation Steps Needed
 
- [ ] Finish manual review of each `*_review.xlsx` file in Excel (resolve
      `parsed_ok = FALSE` rows; delete or recode `[PAGE NOTE]` rows)
- [ ] Bring the six Sept. 2026 extractions in line with the Oct. 2026 conventions:
      standardized candidate names, at-large districts as `0`, `record_type`
- [ ] Parse `date_raw` to ISO dates (`YYYY-MM-DD`); decide how to code month-only,
      `?` and other non-date values
- [ ] Map `switch_direction` / `switch_candidate` to the final schema's
      `previous_endorsee` and retraction logic
- [ ] Rename columns to the final schema (`endorser_name` → `endorser`,
      `state` → `endorser_state`, `date_raw` → `date`, `evidence_url` →
      `endorsement_evidence`); set `source_dataset`
- [ ] Resolve relative `evidence_url` links (e.g. `usw060816pr.html`) to full URLs
      using each page's base address
- [ ] Add a post-primary indicator (e.g. for 2016 nominee endorsements)
- [ ] Combine the 11 reviewed files into one Source 3 dataset
### Join Key(s)
 
- No IDs in the source. Matching to Sources 1 and 2 (2004D, 2008D/R, 2012R) will
  need a composite key — `contest_id` + standardized `endorsee` + standardized
  endorser name (+ `state`/`district` for officials) — with attention to name
  formats (e.g. "Rep. Mike Rogers (AL-3)" vs. Source 1/2 formats).
### Notes
 
- Source 3's main contribution is **coverage beyond officeholders and beyond 2012**:
  newspapers, national organizations and labor unions (2004–2016), and officials
  for 2016R and 2020D, which Sources 1 and 2 do not cover.
- For 2008 and 2012 officials, Source 3 overlaps with Source 2's Governor / Senator /
  Representative scope and can serve as a cross-check.
- Decisions applied in the Oct. 2026 extractions (non-endorsements excluded,
  retractions coded, multi-endorser rows split, names standardized, at-large
  districts as `0`) are recorded in each script's header comment and in the
  commit history (`d0da47d`, `acae0bc`, `f72b9bc`).
- Citation for this data source:
  > Appleman, Eric M. Democracy in Action. "[page title]." [p2008.org / p2012.org /
  > etc.]. Accessed [date].

---
 
## Source 4: Ballotpedia — Presidential Election Endorsements
 
**Acquisition Status:** File acquired (HTML pages saved directly from the website)
**Processing Status:** Extracted — manual review not started (see per-file table below)
 
**Format:** .html (one saved web page per Ballotpedia endorsements page)
**File name(s):** `data/raw/Ballotpedia/bp_<cycle>_<page>.html` (3 files; see table below).
Extracted output: `data/raw/Ballotpedia/extracted/*_extracted.csv`. Text-safe review
copies: `data/raw/Ballotpedia/review/*_review.xlsx`.
**Author(s):** Ballotpedia staff
**Provider/origin:** Ballotpedia (ballotpedia.org), an encyclopedia of U.S. politics and
elections published by the Lucy Burns Institute
**Date acquired:** October 16, 2026 (pages saved and first committed 2026-10-16, commit
`fbe281f`)
**Date range covered:** the 2012–2024 cycles. The 2020 and 2024 pages have endorsement
dates from 2017-07-28 to 2024-10-08; the master table (2012, 2016, 2020, 2024) has no
dates.
**Unit of observation:** Endorsement event-level after extraction (one row per
endorser–candidate pair). The raw pages are curated lists and tables, not datasets.
 
### Files
 
| Raw file | Page title | URL | Extraction script | Extracted rows | First committed | Review status |
| --- | --- | --- | --- | --- | --- | --- |
| `bp_2020_crossparty.html` | Presidential election endorsements, 2020 | https://ballotpedia.org/Presidential_election_endorsements,_2020 | `extract_bp_2020_crossparty.R` | 283 | 2026-10-16 | not started |
| `bp_2024_endorsements.html` | Presidential election endorsements, 2024 | https://ballotpedia.org/Presidential_election_endorsements,_2024 | `extract_bp_2024_endorsements.R` | 958 | 2026-10-16 | not started |
| `bp_master_endorsements.html` | Presidential election endorsements | https://ballotpedia.org/Presidential_election_endorsements | `extract_bp_master_endorsements.R` | 2,823 | 2026-10-16 | postponed until cross-file matching (see Cleaning steps) |
 
All three pages are UTF-8. No rows are flagged `parsed_ok = FALSE`.
 
### Structure
 
- **`bp_2020_crossparty.html`** (despite the file name, two parts, recorded in
  `page_section`):
  - "Noteworthy cross-party endorsements": two bulleted lists, Republicans endorsing
    Joe Biden (32) and Democrats endorsing Donald Trump (8). General-election
    endorsements; no endorsement dates.
  - "Democratic primary endorsements": three tables, governors (10), U.S. senators
    (22) and U.S. representatives (211), with columns Name | State | Party |
    Candidate | Date (+ source link).
- **`bp_2024_endorsements.html`** (three parts):
  - "Noteworthy cross-party endorsements": five bulleted lists (75 items);
    no endorsement dates.
  - "General endorsements from noteworthy officeholders": Harris table (291 rows)
    and Trump table (322 rows). Despite the section name, many Trump rows are dated
    during the primary (from Nov. 2022).
  - "Republican primary endorsements": tables by office (governors 21, U.S. senators
    38, U.S. representatives 171) and one table per withdrawn candidate (DeSantis 17,
    Burgum 3, Haley 13, Pence 4, Ramaswamy 1, Scott 2).
- **`bp_master_endorsements.html`**: Ballotpedia's master table of every presidential
  endorsement it tracks, one sortable table with columns Endorser | Endorsee (+ source
  link and the candidate's party labels) | Election | Stage | Outcome. 2,823 rows:
  2012 (853), 2016 (673), 2020 (495), 2024 (802).
- **Extracted output columns.** All three CSVs share the 16 core columns used for
  Democracy in Action (`contest_id`, `year`, `party`, `endorsee`, `endorser_name`,
  `endorser_description`, `endorser_party_note`, `state`, `district`, `date_raw`,
  `note`, `switch_direction`, `switch_candidate`, `evidence_url`, `parsed_ok`,
  `raw_text`) plus `record_type` and `endorsee_raw`. Page-specific columns:
  - 2020 and 2024 pages: `page_section`, `source_table`, `endorser_url`, `citation`,
    `source_date`; 2024 also has `duplicate_in_page`.
  - Master table: `endorsee_party_label`, `endorser_url`, `election_raw`, `stage`,
    `outcome`, `multiple_endorsees_same_cycle`.
- **Conventions** follow the Oct. 2026 Democracy in Action extractions: `party` and
  `contest_id` are the candidate's party; the endorser's party is in
  `endorser_party_note`; candidate names are standardized (page form kept in
  `endorsee_raw`); `record_type = "endorsement"` on every row.
### Known Issues
 
1. **The master table has no dates, offices, states or endorser party.**
   `date_raw`, `endorser_description`, `state` and `endorser_party_note` are blank for
   all 2,823 rows. Without dates, a switch cannot be told apart from a dual
   endorsement; 362 rows are flagged `multiple_endorsees_same_cycle = TRUE`.
2. **Heavy overlap between pages and with other sources.** The master table's 2020
   and 2024 rows largely repeat the two cycle pages, which have dates and offices. Its
   2012 and 2016 rows overlap Democracy in Action. `endorser_url` (the endorser's
   Ballotpedia page) is the best join key between Ballotpedia files; it is blank for
   19 rows (2020), 36 (2024) and 22 (master).
3. **Duplicates within the 2024 page.** The same endorsement often appears in more
   than one table (e.g. in both the Trump table and the senators table): 460 rows are
   flagged `duplicate_in_page = TRUE`.
4. **General-election and cross-party endorsements are mixed in.** Cross-party lists
   (40 rows in 2020, 75 in 2024), the 2024 general tables (613 rows) and master rows
   with `stage = "General"` (241). Per `docs/final_schema.md`, these are kept and
   flagged with `post_primary`.
5. **Non-major-party contests.** The master table has Gary Johnson (Libertarian)
   rows: `2012L` (3) and `2016L` (10). Per `docs/final_schema.md`, these are dropped.
6. **Placeholder dates in the 2024 page.** Nine rows (7 Harris, 2 Trump, all in the
   general tables) show "October 16, 2026", the date the page was saved, in the Date
   column. Ballotpedia appears to show the current date where no endorsement date was
   entered. These are not endorsement dates and must be treated as missing.
7. **No endorsement dates for list items.** The cross-party list items (115 rows)
   have only a footnote citation. The citation is kept in `citation` and its first
   date in `source_date`; `date_raw` is blank. Per `docs/final_schema.md`,
   `source_date` may stand in, with `date_precision = "source"`.
8. **Missing endorser detail.**
   - The 2024 general tables (613 rows) give name, state and party only, with no
     office or title, so `endorser_description` is blank. These rows cannot be
     assigned an `endorser_type` or Appendix B `weight` until a description is added.
   - `state` is blank for 92 rows in 2024 (91 in the Harris table) and 12 in 2020.
   - No table gives district numbers; `district` is blank throughout.
9. **Switches are inferred, not stated.** Ballotpedia lists an endorser once per
   candidate endorsed. Within each table, rows after an endorser's first are coded as
   switches (`switch_direction = "from"`): 50 rows in 2020, 8 in 2024. These need
   confirming in review.
10. **Evidence links need cleaning.** `evidence_url` holds "source not available"
    (21 rows in 2024, 34 in master), "N/A" (2 in master), and in a few rows a URL
    wrapped in HTML paragraph markup (3 in 2020, 9 in master).
11. **Source errors kept as written**, e.g. "Harbors Mayor Chris Swanson" (the town
    is Two Harbors, MN; no state given), blank State cells for delegates (e.g. Stacey
    Plaskett, USVI) and for Kamala Harris as a senator. List-item states written as
    "Ill.", "Penn.", "Texas" are converted to postal codes, with the original kept in
    `raw_text`.
12. **`stage` and `outcome` describe the candidate, not the endorser.** `outcome` is
    the candidate's result (e.g. "Won General", "Withdrew in Convention"); `stage` is
    "Primary", "General", "Primary, General" or blank.
### Cleaning / Transformation Steps Needed
 
- [ ] Review `bp_2020_crossparty_review.xlsx` and `bp_2024_endorsements_review.xlsx`
      in Excel: confirm inferred switches; fill blank states where the page allows
- [ ] Review `bp_master_endorsements_review.xlsx` only after cross-file matching,
      limited to rows with no match in another file
- [ ] Drop `2012L` and `2016L` rows
- [ ] Keep one copy of each `duplicate_in_page` group (2024)
- [ ] Treat the nine "October 16, 2026" dates as missing
- [ ] Parse `date_raw` (`Month D, YYYY`) to ISO dates; use `source_date` for list items
      with `date_precision = "source"`
- [ ] Set `post_primary` from `page_section`, `stage` and `date`
- [ ] Add endorser descriptions for the 613 rows in the 2024 general tables (from
      matching rows in other tables or files, or the endorser's Ballotpedia page), so
      `endorser_type` and `weight` can be assigned
- [ ] Clean `evidence_url`: strip HTML markup; recode "source not available" and
      "N/A" to `NA`
- [ ] Rename columns to the final schema (`endorser_name` → `endorser`, `state` →
      `endorser_state`, `evidence_url` → `endorsement_evidence`); set `source_dataset`
      (e.g. `"Ballotpedia 2024"`)
- [ ] Match master-table rows to the 2020 and 2024 pages, then to other sources, using
      the Source Precedence rule in `docs/final_schema.md`
### Join Key(s)
 
- Between Ballotpedia files: `endorser_url` + `endorsee` + `contest_id`.
- With other sources: a composite key of `contest_id` + standardized `endorsee` +
  standardized endorser name (+ `state` for officials). No district numbers are
  available to help match House members.
### Notes
 
- Source 4's main contribution is **coverage after Democracy in Action's cut-off
  dates and for 2024**: the full 2020 Democratic primary for governors, senators and
  representatives (DiA's 2020 page stops at Jan. 31, 2020), the 2024 Republican
  primary, and 2024 general-election endorsements.
- The master table adds 2012 and 2016 endorsements, but without dates or offices, so
  its main use for those cycles is as a cross-check on Democracy in Action.
- Extraction decisions (sections kept, inferred switches, standardized candidate
  names, flags for duplicates and multiple endorsees) are recorded in each script's
  header comment.
- Citation for this data source:
  > Ballotpedia. "[page title]." https://ballotpedia.org/[page]. Accessed
  > October 16, 2026.
 