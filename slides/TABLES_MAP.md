# Deck tables → producing scripts

Map of every hardcoded `tabular` in `RDDs-Inframarginal/main.tex` (31 tabulars in 25 frames,
as of 2026-09-28) to the Stata script that produces its numbers. This is the worklist for
replacing hardcoded tables with generated `.tex` fragments under `output/`.

Line numbers refer to the deck before the Design III frames were added.

**Design numbering (2026-10-05, issue #3):** the deck now runs I (inframarginal) → II (own
sudden expansions, new) → III (SUA, formerly II) → IV (competitor vacancy shocks, formerly III).
Rows below written before that date use the old names.

**Emission today:** no SUA, cosine or inframarginal script writes `.tex`. SUA and cosine
scripts only `list` results to the log; inframarginal scripts `postfile` to csv/dta in
`$processed`. The RDD-by-field scripts (`04_rdd/03`, `07`) already write `.tex`, and so do
the four orphan files in `output/tables/` (committed in a91f9e5 with no generating script).

| Deck line | Frame | Producer | Status |
|---|---|---|---|
| 61 | Data and sample | `04_rdd/23_data_sample_table.do` (2026-11-09) | `output/tables/data_sample_overview.tex` (`\input`) |
| 347 | Target enrollment by field | estimates `04_rdd/03_rdd_heterogeneity_field.do`; table `04_rdd/22_rdd_by_field_tables.do` (2026-11-09) | `output/tables/rdd_field_enroll_target.tex` (`\input`) |
| 386 | Univ & HE enrollment by field | same; baseline = mean below the cutoff within the bandwidth, computed in 22 | `output/tables/rdd_field_enroll_unihe.tex` (`\input`) |
| 447 | Target graduation by field | estimates `04_rdd/07_rdd_graduation_by_field.do`; table 22 | `output/tables/rdd_field_grad_target.tex` (`\input`) |
| 490 | Univ & HE graduation by field | same; baseline computed in 22 | `output/tables/rdd_field_grad_unihe.tex` (`\input`) |
| appendix (`nonharmonizedfields`) | RD observations without a harmonized field | `04_rdd/23_data_sample_table.do` | `output/tables/data_nonharmonized_fields.tex` (`\input`) |
| 621 | Delta selectivity definitions | static text | nothing to generate |
| Design I (2026-10-06) | Univ. selectivity, first cohort | — | **no producer** (script 23 reads a .dta nothing builds; script 26 could do it with the `_first_enroll` panel) |
| Design I (2026-10-06) | Univ. selectivity, minimum cohort | `Inframarginals/26_...:183-422` | csv/dta |
| `SUA exposure: samples and descriptive statistics` | SUA samples and exposure (panels A, B) | `Sua/03c_sua_exposure_enrollment_descriptives.do` (section 13, 2026-11-09) | `output/tables/sua_samples_panel{A,B}.tex` (`\input`) |
| `sua-first-stage` | SUA levels first stage | `Sua/04g_sua_first_stages_restricted_samples.do` (full sample, 2026-11-09; same estimates as `04_sua_levels_first_stages.do`) | `output/tables/sua_fs_lvl_full.tex` (`\input`) |
| appendix (`sua-fs-{lvl,log}-{entrant,positive}`) | SUA levels and log first stages, entrant regions only / positive exposure only | `Sua/04g_sua_first_stages_restricted_samples.do` | `output/tables/sua_fs_{lvl,log}_{entrant,positive}.tex` (`\input`) |
| Design V (2026-10-20, issue #8) | ROL sparsity; compact results (no ROL, top 1 + univ., program set, exact); balance; distributed lag; trends | `Inframarginals/36_design5_diagnostic.do` (`im_d5_rol_sparsity.tex`), `37_design5_main.do` (`im_d5_main.tex`, full ladder `im_d5_{program,uni,he}.tex`), `37b_design5_logs.do` (`im_d5_logs.tex`, logs version), `40_design5_placebo.do` (`im_d5_placebo_balance.tex`, replaces 38's `im_d5_balance.tex`; distributed-lag figures `im_d5_leadlag_{fs,grad}.pdf`; `im_d5_placebo_tplus1.tex` and `im_d5_placebo_leadlag.tex` are written but not in the deck), `39_design5_trends.do` (`im_d5_trends.tex`, trends only). Appendix: `42_design5_balance_rolgroups.do` (`im_d5_balance_rolgroups.tex`), `41_design5_rol_groupings.do` (`im_d5_rolgroups.tex`; with argument `trend`, run by `41b_design5_rol_groupings_trends.do`: `im_d5_rolgroups_trends.tex`) | writes .tex (`\input`) |
| appendix (`sua-es-{lvl,log}-{entrant,positive}`) | SUA levels and log event studies, same samples | `Sua/05_...do entrant\|positive`, `Sua/05a_...do entrant\|positive` | `output/sua_{event_study_exposure_comparison,log_event_study}_{baseline,regionyear}_{entrant,positive}.png`; pretrend p-values typed in the frame notes |
| `sua-kd-first-stage`, `sua-kd-log-first-stage` | SUA first stages with kernel-weighted denominator (levels, logs) | `Sua/Sua kernel weights/04i_sua_kernelden_first_stage_tables.do` (needs `03d`) | `output/tables/sua_fs_{lvl,log}_kd.tex` (`\input`) |
| appendix (`sua-kd-event-studies`, `sua-kd-log-event-studies`) | KD event studies | `Sua/05_...do kd`, `Sua/05a_...do kd` | `output/sua_{event_study_exposure_comparison,log_event_study}_{baseline,regionyear}_kd.png`; pretrend p-values typed in the frame notes |
| `sua-log-first-stage` | SUA log first stage | `Sua/04g_...` (full sample; same as `04b_sua_log_first_stages.do`) | `output/tables/sua_fs_log_full.tex` (`\input`) |
| `sua-similarity-first-stage` (appendix) | SUA similarity first stage, levels and logs | `Sua/04e_sua_similarity_log_test.do` (levels added in section 12b, 2026-11-09) | `output/tables/sua_similarity_fs.tex` (`\input`) |
| `sua-selectivity-heterogeneity`, `sua-q-heterogeneity` | SUA exposure and Q heterogeneity by selectivity | `Sua/04f_sua_Exposure_Q_Selectivity_FirstStages.do` (section 15, 2026-11-09) | `output/tables/sua_selectivity_{exposure,q}.tex` (`\input`) |
| `Cosine exposure: samples and descriptive statistics` | Cosine samples and exposure (panels A, B), full and N_2011>=10 | `Sua/Cosine/03_cosine_estimate_first_stages.do` (section 6b, 2026-11-09) | `output/tables/cosine_samples_panel{A,B}.tex` (`\input`) |
| `cosine-first-stage` | Cosine first stage | `Sua/Cosine/03_cosine_estimate_first_stages.do` (section 16) | `output/tables/cosine_fs.tex` (`\input`) |

| Design II frames | Own sudden expansions: thresholds, TWFE/CS, composition, threshold robustness | `Own_expansion/02_own_expansion.do` (needs `01`, `Vacancy_shocks/03`) | `output/own_expansion/tables/oe_{thresholds,twfe_enroll,twfe_comp,threshold_sens}.tex` (`\input`); figures `oe_dV_hist_sel`, `oe_es_*_sel` |
| Design IV, selective vs selective | Exposure moments, levels/log first stages, composition, event study | `Own_expansion/03_selective_competitors.do` (needs `02`) | `output/own_expansion/tables/oe_sel_{exposure_moments,fs_N_first,fs_lnN,composition}.tex` (`\input`); figure `oe_sel_es_N_first` |
| Composition frames inside Designs I, III, IV (the separate section was removed 2026-10-06) | Entrant composition outcomes | `Own_expansion/04_composition_designs.do` (needs `01`, `02`); Design I in `Inframarginals/32` | `output/own_expansion/tables/oe_comp_{sua,vs}.tex` (`\input`); figures `oe_comp_sua_es_c_psu_mean`, `oe_comp_vs_es_c_psu_mean` |

| Design I: data, results, placebo, threshold and horizon robustness, field (issue #5) | Pooled 2007--2016, First Cohort threshold; FS/RF/2SLS with year FE and with university-year FE; placebo leads/lags figure | `Inframarginals/31_design1_main.do` (needs `21b`, `21c`, `28b`, `27`) | `output/inframarginal/tables/im_d1_{desc,main,thresholds,horizon,field}.tex`; figure `output/inframarginal/figures/im_d1_placebo.pdf` |
| Design I: composition of the entering cohort | Pooled, year FE and university-year FE | `Inframarginals/32_design1_composition.do` | `output/own_expansion/tables/oe_comp_design1.tex` |
| Design I: heterogeneity by predetermined selectivity (2 frames) | FS/RF/2SLS by quartile of 2007--09 entrant PSU; university-year FE, continuous interaction (main table, `robust`); the placebo table is still produced but not shown | `Inframarginals/29_selectivity_heterogeneity_predetermined.do` (needs `21b`, `Vacancy_shocks/01`) | `output/inframarginal/tables/im_sel_{Q,Q_ufe,G,robust,placebo}_{first,min}.tex` (`\input`) |
| Design I: selectivity heterogeneity by inframarginal population | 2SLS by quartile for all ranked / enrolled / top half / near threshold | `Inframarginals/30_selectivity_heterogeneity_population.do` (needs `21b`) | `output/inframarginal/tables/im_pop_{first,min}.tex` (`\input`) |
| Reduced form: slot shocks and inframarginal graduation (4 frames) | Designs II-IV shocks on inframarginal graduation, 8y and 10y | `Own_expansion/05_reduced_form_infra.do` (needs `21b`, `28b`, `02`; titulados through 2024) | `output/own_expansion/tables/oe_rf_{design2,sua,vs}.tex`; figures `oe_rf_{d2,sua,vs}_es_g8p_f` |

## Blocking inputs

- ~~`admission_rank_inframarginal_2007_2016.dta`~~ — now built by `02_build/15_build_admission_rank.do`
  from the raw `LUGAR` column (issue #4).
- Titulados 2017--2024 must be in `data/MINEDUC/Base Titulados/` (named `titulados_ed_superior_YYYY_web.csv`);
  without them graduation is censored after cohort 2008 (issue #4).

- **Oferta Académica** Excel files (`$demre_raw/Postulacion/OfertaAcadémica_Admisión<year>.xlsx`)
  — feed `13_build_program_year_vacancies.do` → inframarginal design I (21b, 21c, 28b).
- `weights_2004_2016.csv` — `04_clean_weights.do` cannot rebuild `weights.dta`.
- `psu2011_student_geo_psu_cells.dta` — input to `Sua/Cosine/01`, no producer in the repo.
