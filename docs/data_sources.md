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
**Processing Status:** Inspected

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

1. **Substantial contest overlap with Source, much of it same-provenance**: 2,097
of 3,422 rows (61%) fall within Source 1's contest range (1980-2004). Of those
overlapping rows, 1,408 (67%) explicitly cite "Marty Cohen (The Party Decides)"
as their source. Critically, **Source 2 only includes endorsements from Governors, U.S. Senators, and U.S. Representatives**,
which is a narrower scope than Source 1. This means that for the 1980-2004 overlap period,
Source 2 is primarily a subset of Source 1, rather than independent or additive data. Practically,
this simplifies the merge decision (see Notes) but means Source 2 should not be treated
as adding new endorsement coverage for those years. Its main value there is as a cross-check,
not a supplement.
2. **Contests unique to Source 2:** 1972D, 1976D, 1976R, 2008D, 2008R, and 2012R
do not appear in Source 1. Notable, **1972D, 1976D, and 1976R may fill the gap** left
by the "missing" 1972-1976 dataset referenced in Source 1's codebook.
3. **Inconsistent state code casing:** `state` mixes uppercase (`CA`, `NY`) and lowercase
(`ca`, `ny`) postal abbreviations for the same states, plus one full-text outlier,
`"Northern Marina Islands"` (also likely misspelled), alongside the standard abbreviation
`CNMI` used elsewhere. Needs standardization to a single consistent format.
4. **Negative `points`/`count` values:** Values of -1, -5, -10 (points) and -1 (count)
appear to represent a withdrawal of endorsement or opposition of a candidate. This is
a substantively important distinction from Source 1, which does not negative code 
opposition or withdrawn endorsements the same way. Needs clarification on how withdrawals
should be treated relative to Source 1's schema.
5. **`url` column is entirely empty** and likely safe to drop.
6. **48 rows missing `source`** (all in 2008D/2008R)— need to find alternative mean so f
verifying provenance of specific endorsements.

### Cleaning / Transformation Steps Needed

- [ ] Import only the "Raw data" sheet; discard/ignore "Pivot table"
- [ ] Standardize `state` to consistent uppercase postal codes; resolve the "Northern
    Marina Islands" / CNMI inconsistency
- [ ] Decide how to treat negative `points`/`count` rows relative to Source 1's schema
- [ ] Drop empty `url` column
- [ ] Rename columns to match final schema naming convention
- [ ] **Merge with Source 1 for 1980-2004:** since Source 2 is scoped to Governors/Senators/Reps
    only, decide whether to (a) use Source 1 exclusively for 1980-2004 endorser types it already covers
    and ignore Source 2's overlapping rows entirely, or (b) use Source 2 as a validation cross-check
    against Source 1's Governor/Senator/Rep subset before finalizing data for that period.

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
  or additive source for that period. This meaningfully simplifies the 
  merge decision: for 1980-2004, Source 1 can likely serve as the sole 
  authoritative source (since it already includes what Source 2 covers, 
  plus more endorser types), with Source 2 reserved for its unique 
  contribution — the 1972-1976 and 2008-2012 contests Source 1 lacks. 
  Source 2's overlapping rows may still be useful as a validation check 
  on Source 1's Governor/Senator/Representative records, but shouldn't be 
  merged in as new data for that period.
- No codebook was provided with this file; column meanings were inferred 
  from header names and data inspection. `points` appears to be a weighted 
  measure similar in spirit to Source 1's `Weight`/`Adjusted weight`.
- The raw data file (Prez_primary_endorsements_1972-2012.xlsx) is intentionally 
  excluded from this public repository, since it was shared directly by Nathaniel 
  Rakich via personal correspondence and its terms for redistribution were not specified.
  
---

## Source 3: 

**Acquisition Status:** 
**Processing Status:** 

**Format:**
**File name(s):**
**Provider/origin:**
**Date acquired:**
**Date range covered:**
**Unit of observation:**

### Structure

- Number of rows / columns
- Key variables
- Any header/footer rows, merged cells, or multiple sheets to be aware of

### Known Issues

- Missing values
- Inconsistent formatting
- Duplicates
- Anything requiring manual review in Excel before scripting

### Cleaning / Transformation Steps Needed

### Join Key(s)

### Notes



