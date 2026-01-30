# Threshold-Crossing Effects in Higher Education

## Project Overview

**Research Question:** Estimate the returns to being eligible to certain college majors using Chile's Centralized Admission System, implementing a regression discontinuity design (RDD).

**Background:** Previous analysis was conducted at RIS Investigación (Ministerio de Desarrollo Social), with results documented in Barrios, Borghesan, Díaz & Rodríguez (Section 3). That analysis shows effects on enrollment, graduation, and labor market outcomes. We are replicating and verifying these results using locally available data, which currently allows us to estimate effects on **enrollment**.

---

## Existing Resources

### Legacy Code (in `old/` folder)
- `03_a_waiting_list.do` - Identifies program-years with waiting lists
- `03_d_merge_cod_carrera.do` - Appends application data across years
- `03_returns.do` - Main data construction (~710 lines)
- `04_a2_figures_enrollment.do` - RD plots for enrollment
- `04_a3_figures_graduation.do` - RD plots for graduation
- `Barrios_Borghersan_Diaz_Rodriguez.pdf` - Reference paper

### Legacy Code Structure (from `03_returns.do`)

| Step | Description | Output |
|------|-------------|--------|
| 1 | Load program weights | `weights_2004_2016.dta` |
| 2 | Load/append PSU scores (2007-2016) | `scores.dta` |
| 3 | Load enrollment (DEMRE + MINEDUC) | `enrolls_mineduc.dta` |
| 4 | Load applications, construct cutoffs | `applications.dta`, `cutoff_regular.dta` |
| 5 | Compute application scores using weights | Updated `applications.dta` |
| 6 | Compute next-best option | `all_applicants_nb.dta` |
| 7 | Compute selectivity measures | `selectivity_app.dta` |
| 8 | Merge all + create running variable | `base_returns_actualizada.dta` |

**Key variables:**
- `score_rd = application_score - cutoff_regular` (running variable)
- `above_cutoff = 1 if score_rd >= 0` (treatment indicator)
- `cutoff_regular` = min score among admitted (estado_preferencia == 24)
- `estado_preferencia`: 24=admitted, 25=waiting list, 26=not admitted

---

## Data Inventory

**Location:** Server only (CSV raw files)
**Base path:** `/home/jrodriguezo/majors/data/`

| Dataset | Files | Years | Delimiter |
|---------|-------|-------|-----------|
| PSU Scores | `A_INSCRITOS_PUNTAJES_PSU_YYYY_PRIV_MRUN.csv` | 2004–2023 | `;` |
| Applications | `C_POSTULACIONES_SELECCION_PSU_YYYY_PRIV_MRUN.csv` | 2004–2023 | `;` |
| Matrícula | `Matrícula_Ed_Superior_YYYY.csv` | 2007–2022 | `;` |
| Titulados | TBD | TBD | `;` |

### Key Variables

**Applications:**
- `MRUN` — Student ID
- `AÑO_PROCESO` — Application year
- `PREFERENCIA` — Preference rank (1–10)
- `CODIGO_CARRERA` — Program code
- `ESTADO_PREFERENCIA` — 24=admitted, 25=waiting list, 26=rejected
- `PUNTAJE` — Application score (divide by 100)

**PSU Scores:**
- `MRUN`, `AÑO_PROCESO`
- `PTJE_NEM`, `PTJE_RANKING` — GPA and ranking scores
- `LYC_ACTUAL`, `MATE_ACTUAL`, `HYCS_ACTUAL`, `CIENCIAS_ACTUAL` — Test scores
- `PROMLM_ACTUAL` — Average language + math

**Matrícula:**
- `mrun`, `codigo_demre`, `cod_inst`, `nomb_inst`, `nomb_carrera`, `tipo_inst_1`

**Note:**
- Raw data stays on server. Processed `.dta` files will also be stored on server.
- **Cutoffs** = min(PUNTAJE) among admitted (ESTADO_PREFERENCIA == 24) by program-year.

---

## Workflow Constraint

**Local-Server Setup:**
- All code is edited locally in this repository
- Code is executed on the server where data resides
- Server project path: `/home/jrodriguezo/majors/`
- **SSH:** `ssh jrodriguezo@192.168.20.25`
- **File transfer:** SSH login, copy/paste files manually
- **Output:** Generated on server, sync back to local `output/`

---

## Multi-User Setup

Each coauthor may have data in different locations. To accommodate this:

1. **Copy the template:**
   ```
   cp code/config_user_template.do code/config_user.do
   ```

2. **Edit `config_user.do`** with your paths:
   ```stata
   global root "/your/path/to/majors"
   ```

3. **`config_user.do` is gitignored** — your paths won't affect others

**Example paths by user:**
| User | Root Path |
|------|-----------|
| jrodriguezo (server) | `/home/jrodriguezo/majors` |
| Local Mac | `/Users/yourname/Research/Majors` |
| Local Windows | `C:/Users/yourname/Research/Majors` |

The default in `config.do` is the server path. If no `config_user.do` exists, it uses the default.

---

## Folder Structure

**Local Repository**
```
majors/
├── code/
│   ├── 00_master.do          # Runs everything in order
│   ├── config.do             # Paths, globals (local vs server toggle)
│   ├── 01_clean/             # Data cleaning scripts
│   ├── 02_build/             # Sample construction, merge, cutoffs
│   ├── 03_descriptive/       # Descriptive statistics, balance tables
│   └── 04_rdd/               # RDD estimation
├── output/                   # Tables, figures
├── old/                      # Legacy code (reference)
├── docs/                     # Notes, paper drafts
└── WORKFLOW.md
```

**Server (`/home/jrodriguezo/majors/`)**
```
majors/
├── code/                     # Synced from local
│   ├── 01_clean/
│   ├── 02_build/
│   ├── 03_descriptive/
│   └── 04_rdd/
├── data/
│   ├── MINEDUC/              # Applications, Matrícula, Titulados
│   ├── PSU_scores/
│   └── processed/            # Cleaned .dta files
├── output/                   # Generated tables, figures
└── logs/                     # Stata log files
```

---

## Tasks

### 1. Repository Organization
- [x] Define folder structure following best practices for empirical research
- [x] Create folder structure on server
- [x] Set up `config.do` with path globals
- [x] Create `00_master.do` to run everything in order
- [x] Set up multi-user configuration (`config_user_template.do`)

### 2. Data Cleaning (`01_clean/`)
Scripts to clean each raw data source:

| Script | Input | Output | Status |
|--------|-------|--------|--------|
| `01_clean_psu.do` | PSU_scores/*.csv | `psu_scores.dta` | [x] |
| `02_clean_applications.do` | MINEDUC/Applications/*.csv | `applications.dta` | [x] |
| `03_clean_enrollment.do` | MINEDUC/Matricula.../*.csv | `enrollment.dta` | [x] |
| `04_clean_weights.do` | weights_2004_2016.csv | `weights.dta` | [x] |

### 3. Data Construction (`02_build/`)
Scripts to build analysis datasets:

| Script | Description | Output | Status |
|--------|-------------|--------|--------|
| `01_build_cutoffs.do` | Compute cutoffs from admitted applicants | `cutoffs.dta` | [x] |
| `02_build_running_var.do` | Merge scores + applications, compute score_rd | `applications_rd.dta` | [x] |
| `03_build_outcomes.do` | Merge enrollment outcomes | `analysis_sample.dta` | [x] |
| `04_build_waiting_list.do` | Identify program-years with waiting lists | `waiting_list.dta` | [x] |

### 4. Descriptive Statistics (`03_descriptive/`)
| Script | Description | Status |
|--------|-------------|--------|
| `01_summary_stats.do` | Sample summary statistics | [ ] |
| `02_mccrary.do` | McCrary density test | [ ] |
| `03_covariate_balance.do` | Balance at cutoff | [ ] |

### 5. RDD Estimation (`04_rdd/`)
| Script | Description | Status |
|--------|-------------|--------|
| `01_rdd_enrollment.do` | Main RDD estimates for enrollment | [x] |
| `02_rdd_figures.do` | RD plots | [x] |
| `03_rdd_robustness.do` | Bandwidth sensitivity, polynomial order | [ ] |

### 6. Custom Commands (`code/ado/`)
| File | Description | Status |
|------|-------------|--------|
| `rd_plot.ado` | Reusable RD plot command | [x] |

---

## To Discuss

- [x] What data files are available locally vs. on server?
- [x] Year coverage for Applications, Matrícula, and Titulados? → 2004–2024
- [x] Where exactly are the raw CSVs stored on the server? → `/home/jrodriguezo/majors/data/`
- [x] Folder structure preferences? → See structure above
- [x] Review legacy code structure → See above
- [ ] Stata version compatibility considerations? → Check when running first script on server
- [x] Which outcomes to prioritize? → Enrollment first, then graduation, then labor market

---

## Next Steps

1. ~~**Explore server data** — Check exact file names and variable names in CSVs~~
2. ~~**Create `config.do`** — Set up paths for server execution~~
3. ~~**Data cleaning scripts** — PSU, applications, enrollment, weights~~
4. ~~**Data construction scripts** — cutoffs, running variable, outcomes~~
5. ~~**RDD estimation and figures** — enrollment outcomes~~
6. **Run pipeline on server** — Test full pipeline with actual data
7. **Descriptive statistics** — Summary stats, McCrary test, balance
8. **Robustness checks** — Bandwidth sensitivity, polynomial order

---

*This document will evolve as we build out the repository.*
