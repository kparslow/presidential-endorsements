# Final Dataset Schema

**Unit of observation:** One row per individual endorsement event, i.e., one endorser (individual
or group) endorsing one candidate in one contest.

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
| `contest_id` | string | Standardized contest code, e.g. `"2004D"` | Source 1 & 2 already use this format; confirm new sources match |
| `year` | integer | Election year | Derive from `contest_id` if not given directly |
| `party` | string | `"D"` or `"R"` | Derive from `contest_id` if not given directly |
| `endorsee` | string | Candidate being endorsed | Standardize name format (e.g., full name, consistent capitalization) across sources |
| `endorser` | string | Name of the person or group making the endorsement | Standardize name format |
| `endorser_description` | string | Free-text description of the endorser's role, title, or basis for influence (e.g., "Governor", "Radio host", "Former Senator") | Maps directly from `description`. Not every endorser holds elected office. |
| `endorser_state` | string | State associated with the endorser | Standardize to uppercase 2-letter postal code |
| `date` | date | Date of the endorsement | Standardize to ISO format (`YYYY-MM-DD`) |
| `record_type` | string | `"endorsement"` or `"retraction"` | Retraction removes a previously-counted endorsement. Retractions most often occur when a candidate drops out and the endorser's support is removed from that candidate's count; they may or may not be followed by a new `"endorsement"` row for a different candidate ("switch"). See `previous_endorsee` below for linking these. |
| `previous_endorsee` | string, nullable | For an `"endorsement"` row that follows a same-endorser retraction, the candidate this endorser previously supported | New, derived field populated during cleaning by matching an endorser's retraction to a subsequent endorsements (same endorser, same contest, nearby date). Left null for an endorser's first/only endorsement in a contest. Makes "switches" explicit and queryable without needing to infer them from paired rows at analysis time. |
| `source_dataset` | string | Which raw source this row originated from (e.g., `"Cohen et al. 2008"`, `"FiveThirtyEight 2024"`) | Essential for provenance |
| `endorsement_evidence` | string (URL or citation) | Citation or link to the original public evidence of the endorsement— e.g., a news article or press release announcing it | Distinct from `source_dataset`. 

---

## Supplementary Fields (populate where available; NA otherwise)

These carry extra detail that only some sources provide. Keeping them separate from the core spine
means the dataset doesn't force other sources to fabricate values they don't have.

| Field | Type | Description | Notes |
| --- | --- | --- | --- |
| `weight` | numeric | Endorsement weight/importance score | Derived from Source 1's weighting schema |
| `count` | numeric | Raw count measure | Source 1 (`Count`/`Adjusted count`), Source 2 (`count`) |
| `endorser_region` | string | Census region of endorser's state | Source 1 (`Region`) |
| `endorser_ideology` | numeric | Ideology score of endorser | Difficult to measure for non-elected officials |
| `ideological_distance` | numeric | Distance between endorser and endorsee ideology | |
| `home_state_endorsement` | boolean | Whether endorser is from endorsee's home state | |

---

## Open Harmonization Decisions
 
These need to be settled before/during the cleaning scripts, and are 
tracked here so they don't get lost:
 
- [ ] **Weight/count comparability**: Source 1 and Source 2 use different 
      scales for endorsement "weight." Decide whether to (a) keep both as 
      raw, source-specific values and avoid direct comparison, or (b) 
      develop a normalized/standardized weight for cross-source analysis.
- [ ] **1980-2004 merge policy**: Per prior documentation, Source 1 is 
      likely sufficient alone for 1980-2004; confirm this holds once 
      `endorser_position` is populated for Source 1, then decide whether 
      Source 2's overlapping rows are excluded entirely or retained as a 
      validation check.
- [ ] **`endorser_description` categorization for cross-source comparability**: since this field is free text rather than structured, decide whether a derived categorical field (e.g., isolating Governors/Senators/Representatives) is needed to compare against Source 2's narrower scope, and if so, how to parse it out of Source 1's `Description` and Source 2's `description` text consistently.
- [ ] **Retraction-to-switch linking logic**: define the matching rule for populating `previous_endorsee` (e.g., same endorser + same contest + retraction and endorsement within N days of each other). Confirm this logic correctly distinguishes true switches (like Thurmond/Holt) from standalone withdrawals (like Snelling) rather than incorrectly pairing unrelated records.
- [ ] **Does Source 1 include retractions at all?** Confirm whether Source 1 has any analog to Source 2's negative-count retraction rows, or whether every Source 1 row represents a standing, uncontested endorsement.

---
