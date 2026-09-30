# Deck tables → producing scripts

Map of every hardcoded `tabular` in `RDDs-Inframarginal/main.tex` (31 tabulars in 25 frames,
as of 2026-09-28) to the Stata script that produces its numbers. This is the worklist for
replacing hardcoded tables with generated `.tex` fragments under `output/`.

Line numbers refer to the deck before the Design III frames were added.

**Emission today:** no SUA, cosine or inframarginal script writes `.tex`. SUA and cosine
scripts only `list` results to the log; inframarginal scripts `postfile` to csv/dta in
`$processed`. The RDD-by-field scripts (`04_rdd/03`, `07`) already write `.tex`, and so do
the four orphan files in `output/tables/` (committed in a91f9e5 with no generating script).

| Deck line | Frame | Producer | Status |
|---|---|---|---|
| 61 | Data and sample | mixed: `02_build/03_build_outcomes.do:56-58`, `04_rdd/01_rdd_enrollment.do:39-61`, orphan `output/tables/sample_overview_bw25.tex`, `descriptive_outcomes_bw25.tex` | partial; 786,071 students and 11,789 program-years have **no producer** |
| 347 | Target enrollment by field | `04_rdd/03_rdd_heterogeneity_field.do:56-150` | writes .tex |
| 386 | Univ & HE enrollment by field | same | Est/SE/N ok; **Baseline column: no producer** |
| 447 | Target graduation by field | `04_rdd/07_rdd_graduation_by_field.do:75-160` | writes .tex |
| 490 | Univ & HE graduation by field | same | **Baseline column: no producer** |
| 621 | Delta selectivity definitions | static text | nothing to generate |
| 875 | Corrected inframarginal IV | `04_rdd/21_compare_inframarginal_two_instruments_full.do:83-196` | inputs `inframarginal_program_year_panel_*.dta` have **no builder**; Univ and HE rows identical — check |
| 939 A | First-stage robustness | only "Differences + year FE" row from script 21:102 | **4 of 5 rows: no producer** |
| 957 B | Raw/residual SDs | — | **no producer** |
| 1015 | Results (four definitions) | `04_rdd/Inframarginals/21b_...:438-628` | csv/dta; needs Oferta Académica |
| 1066 | Alternative inframarginal | `04_rdd/Inframarginals/21c_...:430-597` | csv/dta; share 70.59 vs 72.90 at 1015 for the same definition — check |
| 1124 | Univ. selectivity, first cohort | — | **no producer** (script 23 reads a .dta nothing builds; script 26 could do it with the `_first_enroll` panel) |
| 1236 | Univ. selectivity, minimum cohort | `Inframarginals/26_...:183-422` | csv/dta |
| 1352, 1380 | Program selectivity A/B | `Inframarginals/25_...:142-417` | csv |
| 1420 | Field of study | `Inframarginals/27_...:371-778` | csv |
| 1489 | Graduation 8 vs 10 years | `Inframarginals/28b_...:488-1032` (needs 28a) | csv; needs Oferta Académica |
| 1542 | Inframarginal IV results | — | **no producer** (older definition) |
| 1604 | Heterogeneity by univ. selectivity | — | **no producer** (uses UNAB, not in any script) |
| 1922, 1971 | SUA samples and exposure | `Sua/03c_...:228-270, 486, 662` | log only |
| 2156 | SUA levels first stage | `Sua/04_sua_levels_first_stages.do:109-722` | log only |
| appendix (`sua-fs-{lvl,log}-{entrant,positive}`) | SUA levels and log first stages, entrant regions only / positive exposure only | `Sua/04g_sua_first_stages_restricted_samples.do` | `output/tables/sua_fs_{lvl,log}_{entrant,positive}.tex` (`\input`) |
| appendix (`sua-es-{lvl,log}-{entrant,positive}`) | SUA levels and log event studies, same samples | `Sua/05_...do entrant\|positive`, `Sua/05a_...do entrant\|positive` | `output/sua_{event_study_exposure_comparison,log_event_study}_{baseline,regionyear}_{entrant,positive}.png`; pretrend p-values typed in the frame notes |
| `sua-kd-first-stage`, `sua-kd-log-first-stage` | SUA first stages with kernel-weighted denominator (levels, logs) | `Sua/Sua kernel weights/04i_sua_kernelden_first_stage_tables.do` (needs `03d`) | `output/tables/sua_fs_{lvl,log}_kd.tex` (`\input`) |
| appendix (`sua-kd-event-studies`, `sua-kd-log-event-studies`) | KD event studies | `Sua/05_...do kd`, `Sua/05a_...do kd` | `output/sua_{event_study_exposure_comparison,log_event_study}_{baseline,regionyear}_kd.png`; pretrend p-values typed in the frame notes |
| appendix (`sua-q-selectivity-trends`, `sua-q-selectivity-es`) | Conditional similarity with selectivity-decile x year FE | `Sua/04j_sua_similarity_selectivity_trends.do` | `output/tables/sua_q_selectivity_trends.tex`, `output/sua_q_event_study_selectivity_trends.png`; decile/R2 facts typed in the frame |
| appendix (`sua-exposure-selectivity-trends`, `sua-exposure-selectivity-es`) | SUA exposure (incl. KD) with selectivity-decile x year FE | `Sua/04k_sua_exposure_selectivity_trends.do` (needs `03d`) | `output/tables/sua_fs_selectivity_trends.tex`, `output/sua_es_selectivity_trends.png`; pretrend p-values typed in the frame notes |
| 2393 | SUA log first stage | `Sua/04b_sua_log_first_stages.do` | log only |
| 2770 | SUA similarity first stage | logs: `Sua/04e_...:495-675` | **levels columns: no producer** |
| 2883 | SUA selectivity heterogeneity | `Sua/04f_...:310-732` | log only |
| 3169, 3208 | Cosine samples and exposure | `Sua/Cosine/Cosine_Exposure_Descriptive_Statistics.do` | log only; full-sample column needs a second run (`minimum_enrollment_2011 0`) |
| 3374 | Cosine first stage | `Sua/Cosine/03_cosine_estimate_first_stages.do:517-700` | log only |
| 3598 | Non-harmonized fields | `02_build/05_build_field.do:403-418` | log only; Years column and 0.095% done by hand |

## Blocking inputs

- **Oferta Académica** Excel files (`$demre_raw/Postulacion/OfertaAcadémica_Admisión<year>.xlsx`)
  — feed `13_build_program_year_vacancies.do` → inframarginal design I (21b, 21c, 28b).
- `weights_2004_2016.csv` — `04_clean_weights.do` cannot rebuild `weights.dta`.
- `psu2011_student_geo_psu_cells.dta` — input to `Sua/Cosine/01`, no producer in the repo.
