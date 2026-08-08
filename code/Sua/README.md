# `code/Sua/` — SUA entry design

Instrumental-variables design exploiting the entry of **eight private universities into the SUA in the 2012 admission process** (UNAB, UDP, UDD, U. Mayor, UAI, U. de los Andes, U. Finis Terrae, UAH).

The instrument moves realized enrollment through a **competition channel that no incumbent program controls**, which is what makes it useful: unlike cupos, it is not chosen by the program in response to demand expectations.

**First stage**

```
N_total_pt = π (E_p × Post2012_t) + μ_p + α_f(p),t + ν_pt
```

**Second stage**

```
ȳ_infra_pt = β N̂_total_pt + μ_p + α_f(p),t + ε_pt
```

with program fixed effects `μ_p` and field × year fixed effects `α_f(p),t`. The sample is **incumbent (pre-2012 CRUCH) programs only** — entrants have no DEMRE pre-period. Expected `π < 0`: entrant integration diverts marginal matriculants and pulls realized enrollment below cupos.

Full conceptual and econometric write-up: **[issue #1](https://github.com/jorginho84/Majors/issues/1)**.

---

## Two exposure measures

Both feed the same estimating equations. They differ only in how `E_p` is built.

| | **Design A — market share** | **Design B — cosine similarity** |
|---|---|---|
| Location | `code/Sua/*.do` | `code/Sua/Cosine/*.do` |
| Idea | Entrant share of pre-2012 first-year enrollment in program `p`'s market | Weighted average similarity between `p`'s student body and each entrant program's |
| Market definition | Discrete: field × geography (9 variants) | None — continuous in student-body overlap |
| Pre-period | 2009–2011 average | 2011 cross-section |
| Refinement | Selectivity-proximity kernels (triangular, gaussian; `h = 50` PSU) | Weights `w_j` = entrant program `j`'s share of 2011 entrant enrollment |
| Status | First stages, event study, heterogeneity done | First stage drafted |

Design B is the refinement proposed by Emilio Borghesan. It avoids arbitrary cell boundaries: two programs in different regions serving the same student type are correctly treated as competitors.

---

## Run order

Scripts must be run **from the project root**, not from this directory:

```bash
cd /home/jrodriguezo/majors
/usr/local/stata17/stata-mp -b do code/Sua/00_build_validate_sua_roster.do
```

### Shared foundation

| # | Script | Produces |
|---|---|---|
| `00` | `00_build_validate_sua_roster.do` | `sua_university_roster_manual.dta` — the 33-university roster (25 incumbents + 8 entrants), built in-script and validated against `applications_rd.dta` |
| `01` | `01_build_sua_program_year_base_revised.do` | `sies_program_year_raw_2007_2016.dta`, `sua_preperiod_program_year_2009_2011.dta` |

Upstream dependencies from the main pipeline: `psu_scores.dta`, `applications_rd.dta`, SIES Matrícula CSVs, DEMRE Formulario D.

### Design A — market-share exposure

| # | Script | Role | Produces |
|---|---|---|---|
| `02` | `02_build_sua_markets_exposure.do` | Attach official geography; build DEMRE↔market crosswalk; build unweighted exposure | `sies_program_year_geo_2007_2016.dta`, `sua_demre_market_crosswalk_2007_2016.dta`, `sua_market_exposure_2009_2011.dta` |
| `03` | `03_build_sua_incumbent_panels.do` | Incumbent panels for all 9 market definitions | `sua_incumbent_panel_<market>_<geo>_2007_2016.dta` (×9) |
| `03b` | `03b_build_sua_weighted_exposure.do` | Selectivity-proximity weighted exposure (triangular & gaussian, `h = 50`) | `sua_incumbent_panel_w_<market>_<geo>_2007_2016.dta` |
| `04` | `04_sua_first_stage.do` | **Main first stage**, 9 market definitions | `sua_first_stage_results.dta` / `.xlsx` |
| `04b` | `04b_sua_weighted_first_stages.do` | First stages on weighted exposure; outcomes = enrollment and mean PSU | — |
| `04c` | `04c_sua_event_study.do` | Event study, unweighted + weighted jointly; 2011 omitted | `sua_event_study_results.dta` / `.xlsx` |
| `04d` | `04d_selectivity_groups_diagnostics.do` | Diagnostics on selectivity cutoffs (terciles vs manual 550/600/645/650). No regressions | — |
| `04e` | `04e_sua_first_stage_by_selectivity.do` | First-stage heterogeneity by pre-treatment selectivity; also the monotonicity check | `sua_first_stage_by_selectivity.dta` / `.xlsx` |

**Market grid.** 3 field definitions (`broad_area`, `cine_subarea`, `generic_area`) × 3 geographic levels (`region`, `provincia`, `comuna`). Note `03` writes its main-spec copy using `cine_subarea × region`, while `04` labels `broad_area × region` as the main specification — worth reconciling.

### Design B — cosine-similarity exposure (`Cosine/`)

| # | Script | Role |
|---|---|---|
| `01` | `01_build_cosine_exposure_2011.do` | Build 2011 program vectors over demographic cells, compute pairwise cosine similarity, aggregate to `E_p` with entrant-size weights |
| `02` | `02_MERGE_COSINE_EXPOSURE_ANALYSIS_PANEL.do` | Bridge exposure from MINEDUC `codigo_unico` → `codigo_demre` → main analysis database, via the major-homologation files |
| `03` | `03_build_program_year_enrollment.do` | Program-year enrollment built directly from student destinations |
| `04` | `04_cosin_first_stage.do` | First stage on native SIES units (`codigo_unico × year`), no DEMRE crosswalk |

---

## Known blockers and open items

Tracked in [issue #1](https://github.com/jorginho84/Majors/issues/1).

**Missing inputs with no producer in this repo**

- `geographic_codebook.dta` → expected at `$raw/geographic_codebook.dta`. **Blocks `02` and all of Design A downstream.**
- `08_h_codigo_unico.dta`, `08_h_codigo_demre.dta` (Sofía Schuster's homologation files) → expected at `$data/`. **Blocks `Cosine/02`.**
- `sua_exposure/sies_program_year_with_demre_2007_2016.dta`, `sua_exposure/sua_university_sies_roster.dta` → required by `Cosine/04`, but nothing in this repo creates them or the `sua_exposure/` subdirectory.

**Specification gaps**

- `Cosine/01` builds cells as **región × PSU bin only** — the spec calls for geography × **SES** × PSU.
- `entrant_2012` assumes all eight universities entered in the same year; validated only indirectly. Should be checked against DEMRE *oferta* publications for 2012 and 2013.
- Second stage not yet implemented for either design.
- Exposure-robust (Adão–Kolesár–Morales / Borusyak–Hull–Jaravel) standard errors not yet implemented.

---

## Conventions and gotchas

- **Run from the project root.** Every script loads `do "code/config.do"`, which resolves paths relative to the root and auto-detects the user.
- **Stata's batch exit code lies.** `stata-mp -b do <script>` can return `0` even when the script aborted with `r(601)`. Always confirm by grepping the `.log` for `^r([0-9]+);` *and* checking that the expected `.dta` outputs exist.
- **`reghdfe` is required** by `04`, `04b`, `04c`, `04e` (`ssc install reghdfe, replace`).
- Logs are written to the **project root**, not next to the script.

### Naming inconsistencies worth cleaning up

Left as-is for now to avoid conflicting with in-flight work — rename in a dedicated commit if desired:

- `01_build_sua_program_year_base_revised.do` — the `_revised` suffix suggests a superseded version that no longer exists
- `Cosine/04_cosin_first_stage.do` — `cosin` → `cosine`
- `Cosine/02_MERGE_COSINE_EXPOSURE_ANALYSIS_PANEL.do` — all-caps is inconsistent with every other filename
