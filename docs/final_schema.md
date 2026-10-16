# Final Dataset Schema

**Unit of observation:** One row per individual endorsement event, i.e., one endorser (individual
or group) endorsing one candidate in one contest.

**Scope:** Democratic and Republican presidential nomination contests. Rows for other parties'
contests are dropped during cleaning. Endorsements made after a nomination was settled
(including cross-party endorsements) are kept and flagged with `post_primary`.

This schema is designed to be the target structure that Sources 1, 2, and future sources
(2016-2024) are all transformed into. Core fields must be populated by every source; supplementary
fields will be populated only where the source data supports them.

---

## Core Fields (required from every source)

These are the minimum fields needed for any source — including manually collected data — to
be usable in the final dataset.

| Field | Type | Description | Notes |
| --- | --- | --- | --- |
| `endorsement_id` | integer | Unique ID for each row in the **final** dataset (generated during merge, not from raw sources) | New field — not copied from any source's own ID |
| `contest_id` | string | Standardized contest code, e.g. `"2004D"` | Source 1 & 2 already use this format; confirm new sources match. Only `D` and `R` contests are kept |
| `year` | integer | Election year | Derive from `contest_id` if not given directly |
| `party` | string | `"D"` or `"R"` | Derive from `contest_id` if not given directly. Rows for other parties (e.g. Ballotpedia's `2012L`, `2016L`) are dropped |
| `endorsee` | string | Candidate being endorsed | Standardize name format (e.g., full name, consistent capitalization) across sources |
| `endorser` | string | Name of the person or group making the endorsement | Standardize name format |
| `endorser_description` | string | Free-text description of the endorser's role, title, or basis for influence (e.g., "Governor", "Radio host", "Former Senator") | Maps directly from `description`. Not every endorser holds elected office. Categorized in `endorser_type` |
| `endorser_type` | string | Controlled category of endorser, derived from `endorser_description` and the source page | Allowed values: `"governor"`, `"us_senator"`, `"us_representative"`, `"other_official"`, `"organization"`, `"labor_union"`, `"newspaper"`, `"other"`. Allows comparison with Source 2's Governor/Senator/Representative scope |
| `endorser_state` | string | State associated with the endorser | Standardize to uppercase 2-letter postal code |
| `district` | numeric | District of the endorser | At-large districts coded as `0` |
| `date` | date | Date of the endorsement | Standardize to ISO format (`YYYY-MM-DD`). Month-only dates are coded as the first of the month; dates that cannot be determined are `NA`. See `date_precision` |
| `date_precision` | string | How exact `date` is | Allowed values: `"day"` (exact date), `"month"` (month known, day set to 1), `"source"` (no endorsement date; `date` is the publication date of the cited evidence, e.g. Ballotpedia's `source_date`), `"none"` (`date` is `NA`) |
| `post_primary` | boolean, nullable | Whether the endorsement was made after the contest's nomination was settled | `TRUE` if `date` is after the settlement date for the contest, or if the source labels it a general-election endorsement (e.g. Ballotpedia cross-party lists, `stage = "General"`). `NA` when neither the date nor the source settles it |
| `weight` | numeric | Endorsement weight, 0.1–0.9, using the Party Decides weighting system (Cohen et al. codebook, Appendix B) | Taken directly from Source 1's `Weight` column (not `Adjusted weight`). Assigned to rows from all other sources by the same rules: the category weight for the endorser's description, the "Former" weight for former officeholders, and the named-individual exceptions. Source 2's `points` are not used |
| `weight_category` | string | The Appendix B description used to assign `weight`, e.g. `"Governor"`, `"Senator (former)"`, `"Newspaper"` | Records how each weight was chosen, so assignments can be checked and corrected. Taken from Source 1's `Description` where it matches an Appendix B category |
| `record_type` | string | `"endorsement"` or `"retraction"` | Retraction removes a previously-counted endorsement. Retractions most often occur when a candidate drops out and the endorser's support is removed from that candidate's count; they may or may not be followed by a new `"endorsement"` row for a different candidate ("switch"). See `previous_endorsee` below for linking these. |
| `previous_endorsee` | string, nullable | For an `"endorsement"` row that follows a same-endorser retraction, the candidate this endorser previously supported | New, derived field populated during cleaning by matching an endorser's retraction to a subsequent endorsements (same endorser, same contest, nearby date). Left null for an endorser's first/only endorsement in a contest. Makes "switches" explicit and queryable without needing to infer them from paired rows at analysis time. |
| `source_dataset` | string | Which raw source this row originated from (e.g., `"Cohen et al. 2008"`, `"FiveThirtyEight 2024"`) | Essential for provenance. When an endorsement appears in several sources, this is the source of the row kept (see Source Precedence) |
| `also_in_sources` | string, nullable | Other sources that list the same endorsement, separated by `"; "` | Filled during de-duplication; `NA` if only one source lists it |
| `endorsement_evidence` | string (URL or citation) | Citation or link to the original public evidence of the endorsement — e.g., a news article or press release announcing it | Distinct from `source_dataset` |

---

## Supplementary Fields (populate where available; NA otherwise)

These carry extra detail that only some sources provide. Keeping them separate from the core spine
means the dataset doesn't force other sources to fabricate values they don't have.

| Field | Type | Description | Notes |
| --- | --- | --- | --- |
| `count` | numeric | Raw count measure | Source 1 (`Count`/`Adjusted count`), Source 2 (`count`) |
| `endorser_region` | string | Census region of endorser's state | Source 1 (`Region`) |
| `endorser_ideology` | numeric | Ideology score of endorser | Difficult to measure for non-elected officials |
| `ideological_distance` | numeric | Distance between endorser and endorsee ideology | |
| `home_state_endorsement` | boolean | Whether endorser is from endorsee's home state | |

---

## Source Precedence

When the same endorsement (same endorser, `endorsee` and `contest_id`) appears in more than one
source, one row is kept, chosen in this order:

1. The row with the most exact date (`date_precision`: `day` > `month` > `source` > `none`).
2. If tied, the row with more endorser detail (`endorser_state`, `district`, `endorser_description`
   filled).
3. If still tied, the source listed first: Source 1 (Cohen et al.), Source 2 (FiveThirtyEight),
   Source 3 (Democracy in Action), Source 4 (Ballotpedia).

The other sources are recorded in `also_in_sources`. This rule also applies to the 1980–2004
overlap between Sources 1 and 2.

---

## Open Harmonization Decisions

These need to be settled before/during the cleaning scripts, and are 
tracked here so they don't get lost:

- [x] **Weight/count comparability**: Source 1 and Source 2 use different 
      scales for endorsement "weight." Decide whether to (a) keep both as 
      raw, source-specific values and avoid direct comparison, or (b) 
      develop a normalized/standardized weight for cross-source analysis.
      - **Decision (2026-10-16):** Neither. The final dataset has one
        `weight` field using the Party Decides weighting system (codebook
        Appendix B), applied to every source. Source 1's `Weight` is used as
        given; Source 2's `points` are dropped, and Sources 2–4 are weighted
        by the Appendix B rules. `Adjusted weight` is not carried over;
        `count` is kept, so it can be recomputed if needed.
- [ ] **Applying Appendix B to Sources 2–4**: write the rules for assigning
      weights where Appendix B is silent or ambiguous, in a lookup table
      (e.g. `data/lookups/tpd_weights.csv`, transcribed from Appendix B).
      Cases to cover: endorser types not in Appendix B (e.g. online groups,
      super PACs); whether leadership weights (Senate leader 0.8, House
      leader 0.6) apply by position at the time of endorsement; how "Former"
      is detected from descriptions; and whether named exceptions are
      extended to comparable post-2004 figures or left at the category
      weight. Check the rules by re-deriving Source 1's own `Weight` values
      from its `Description` and comparing.
- [x] **1980-2004 merge policy**: Per prior documentation, Source 1 is 
      likely sufficient alone for 1980-2004; confirm this holds once 
      `endorser_description` is populated for Source 1, then decide whether 
      Source 2's overlapping rows are excluded entirely or retained as a 
      validation check.
      - **Decision (2026-10-16):** Neither. Overlapping rows are merged under
        the Source Precedence rule like any other overlap. Matching rows
        collapse into one, with the other source in `also_in_sources`; Source
        2 rows with no Source 1 match are kept.
- [x] **`endorser_description` categorization for cross-source comparability**: since this field is free text rather than structured, decide whether a derived categorical field (e.g., isolating Governors/Senators/Representatives) is needed to compare against Source 2's narrower scope, and if so, how to parse it out of Source 1's `Description` and Source 2's `description` text consistently.
      - **Decision (2026-10-16):** Add `endorser_type` with controlled values
        (see Core Fields). Parsing rules are written in the cleaning scripts.
- [ ] **Retraction-to-switch linking logic**: define the matching rule for populating `previous_endorsee` (e.g., same endorser + same contest + retraction and endorsement within N days of each other). Confirm this logic correctly distinguishes true switches (like Thurmond/Holt) from standalone withdrawals (like Snelling) rather than incorrectly pairing unrelated records.
- [ ] **Does Source 1 include retractions at all?** Confirm whether Source 1 has any analog to Source 2's negative-count retraction rows, or whether every Source 1 row represents a standing, uncontested endorsement.
- [x] **Coding at-large districts:** At-large districts are coded as `0`
- [x] **General-election endorsements**: keep or exclude endorsements made
      after the nomination was settled?
      - **Decision (2026-10-16):** Keep and flag with `post_primary`.
        Rationale: the choice can be reversed at analysis time by filtering.
- [ ] **Settlement date for each contest**: define the date after which an
      endorsement counts as `post_primary` (e.g. the date the nominee
      clinched a delegate majority, or the last rival's withdrawal), and
      record it per contest in a lookup table.
- [x] **Non-major-party contests**: keep or drop Ballotpedia's `2012L` and
      `2016L` rows (13 rows)?
      - **Decision (2026-10-16):** Drop. `party` stays `"D"` or `"R"`.
- [x] **Cross-party endorsements** (e.g. Republicans endorsing Biden in 2020):
      - **Decision (2026-10-16):** Treated like general-election endorsements:
        kept, flagged with `post_primary = TRUE`.
- [x] **Dates that are not exact days** (month-only, `?`, blank, text):
      - **Decision (2026-10-16):** Month-only dates become the first of the
        month; undeterminable dates become `NA`. Add `date_precision`.
- [x] **Ballotpedia list items with no endorsement date**: may the cited
      article's date (`source_date`) stand in?
      - **Decision (2026-10-16):** Yes, with `date_precision = "source"`.
- [x] **Overlapping sources**: which row is kept when several sources list
      the same endorsement?
      - **Decision (2026-10-16):** Most detailed row; see Source Precedence.
- [x] **Source 2 rows in the published dataset**: the FiveThirtyEight raw
      file cannot be redistributed.
      - **Decision (2026-10-16):** Include Source 2 rows in the final dataset.
        The README states that the raw file is available on request from
        FiveThirtyEight, so replicators know the cleaning step for Source 2
        cannot be re-run from the public repo alone.

---