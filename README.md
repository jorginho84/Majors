# Why Don't High-Return College Programs Expand?

Marginal benefits and marginal costs of higher-education capacity in Chile's centralized admission system.

## Motivation and research questions

**Motivating question.** Why don't we increase capacity in high-return programs?

Expanding a program's capacity has two sides, and the project estimates each one:

1. **Marginal benefit (at the margin).** What does one more seat do for the student who gets it? A regression discontinuity design (RDD) around program-year admission cutoffs compares applicants just above and just below the cutoff.
2. **Marginal cost (inframarginal students).** What happens to the students who would have been admitted anyway when capacity changes? A larger program changes class size and who the classmates are, which may affect students already in the program (congestion and peer composition). Five inframarginal designs study this.

The long-run goal is to put the two together: estimate marginal benefit and marginal cost as flexible functions of program characteristics (selectivity, returns), then simulate a reallocation of enrollment across programs that equates the two. The target is a simple reallocation exercise, not a full structural model. This needs **program-level** estimates, not only aggregate coefficients.

The framing under discussion starts from programs that are oversubscribed and high-return according to the RDD (they already have a queue, so demand is established by construction), and asks why they do not expand. Whether "selective" and "high-return" programs overlap is an empirical question; selectivity is observable now, returns need labor-market data that we do not have yet.

## Where the evidence stands

Preliminary results, from the deck [`slides/RDDs-Inframarginal/main.tex`](slides/RDDs-Inframarginal/main.tex). Numbers come from the deck as of the last commit and can change as designs are re-estimated.

**At the margin (RDD).** Crossing the admission cutoff raises enrollment in the target program by about 50.7 pp and graduation from the target program (8 years) by 18.0 pp. Graduation from *any* university rises only 2.9 pp and from any higher-education institution 2.4 pp, and PSU retaking falls 4.9 pp. The seat changes *where* the student studies much more than *whether* they study. Effects appear in every field and are larger when the target program is much more selective than the student's next-best option.

**Inframarginal students.**

| Design | Variation | Status |
|---|---|---|
| **I. Yearly vacancy changes** | Every year-to-year change in a program's vacancies instruments the size of its entering cohort (first differences, 2SLS). | Cleanest design. Strong first stage (about 0.74 entrants per added seat). Small effect on inframarginal graduation within university and year (−0.33 pp per 10 entrants); graduation from any university does not fall, which points to switching rather than dropping out. Selectivity heterogeneity is noisy. |
| **II. Own sudden expansion** | Binary event: a selective program's large positive vacancy shock (top 20% of positive changes). DiD / event study / Callaway–Sant'Anna, plus the shock as an instrument. | Adds about 23 entrants and lowers entrant PSU by 5–9 points. The graduation effect reflects a pre-existing decline and disappears with university × year FE. |
| **III. Entry of private universities (SUA, 2012)** | Incumbent programs more exposed to the 2012 entry of eight private universities (PSU-proximity-weighted exposure). | Weak: wrong-signed first stage, pre-trend rejected, not significant with region × year FE. |
| **IV. Close competitors' expansions** | A program is treated once a close competitor (same region × broad field, entrant PSU within 50 points) has a sudden expansion. | Enrollment of the affected program rises by about 3 and entrants are weaker, with flat pre-trends. Inframarginal graduation at 8 years does not change. |
| **V. Individual-level Design I (ROL FE)** | Design I's variation (yearly vacancy changes instrumenting cohort size) at the student level, with controls (PSU, NEM, sex, school type) and fixed effects for the student's application portfolio (ROL). 432,184 inframarginal students, SE clustered by program-year (issue #8). | Strong first stage (about 0.8–0.9 entrants per vacancy). Graduation from the program *rises* by 0.06–0.09 pp per entrant, which is Design I's result *in levels* (issue #7), not the first-difference −0.33 pp. ROL FE do not move the estimate on a common sample. Not identified as is: balance fails slightly and next year's vacancies predict this year's graduation as much as current vacancies, which points to within-program trends. A specification that absorbs trends is pending. |

So far the evidence does not show a large cost of expansion for the students already in a program, which means the question of why capacity is not expanded is not answered by costs to inframarginal students alone.

Open items include a specification for Design V that absorbs program trends, a geographic-distance kernel in the Design III exposure measure, program-level estimates for all designs, a waiting-list measure of queue length, and labor-market outcomes (a data request to the Ministry of Labor is pending).

## Data

Administrative records for admission cohorts **2007–2016**, linked at the applicant level:

- **DEMRE** (PSU scores, applications and admission status, enrollment, selection-list rank `LUGAR`, vacancies).
- **MINEDUC** (higher-education enrollment, graduates/*titulados* through 2024).

Main RDD sample: applicants within 25 points of the regular admission cutoff. Raw data and the processed `.dta` files are not in this repository; they live on the secure server and in Dropbox. There is no income variable; school dependency is the socioeconomic proxy.

## Methods in one paragraph

*RDD*: running variable is the application score minus the program-year cutoff, treatment is `score ≥ cutoff`, program-year fixed effects, standard errors clustered by program-year. *Inframarginal designs*: an applicant is inframarginal if their admission rank is within a fixed program threshold built from enrolled cohort sizes (first cohort in the main specification, minimum cohort as robustness); the outcome is the share of those applicants who graduate within 8 years from the program where they first enrolled. Designs use two-way fixed effects, event studies, Callaway–Sant'Anna estimators and 2SLS, with fixed effects for university × year or field × year as robustness.

## Repository structure

```
code/
  config.do                  # paths and parameters
  01_clean/                  # raw DEMRE/MINEDUC → .dta
  02_build/                  # cutoffs, running variable, outcomes, vacancies, admission rank, inframarginal samples
  04_rdd/                    # RDD estimation and figures
    Inframarginals/          # Design I (31–33, 35), Design V (36–38) and heterogeneity/graduation scripts
  Vacancy_shocks/            # vacancy-shock panel, similarity, exposure (inputs to Designs II–IV; Design V is built in 02_build/16)
  Own_expansion/             # Design II, selective-competitor Design IV, composition (see its README)
  Sua/                       # Design III, SUA entry (see its README); Sua/Cosine for the cosine exposure variant
  ado/                       # custom Stata programs (rd_plot)
slides/RDDs-Inframarginal/   # main.tex / main.pdf, the working deck
output/                      # tables and figures that the deck includes
docs/meetings/               # weekly meeting minutes and TODOS.md
old/                         # legacy code and the prior paper (reference only)
```

Run all scripts from the project root. The full RDD pipeline is `code/00_master.do`; the other folders have their own runners and READMEs. Make a local `code/config_user.do` from `config_user_template.do`.

## How we work

**One issue per research thread.** Every time we start exploring a new empirical question, we open a GitHub issue *before* writing code, using the [research-thread template](.github/ISSUE_TEMPLATE/research-thread.md). The structure follows [issue #1](https://github.com/jorginho84/Majors/issues/1).

**Progress is reported in that issue.** As work advances we comment on what ran, the estimates, what broke and what is still blocked. The issue is the running record of the thread.

**Slides trace to code.** Figures in the deck use paths into `output/`, so `grep` finds the script that produced each one (see [slides/README.md](slides/README.md)). Weekly minutes and the to-do list are in [docs/meetings/](docs/meetings/).

## Authors

Andrés Barrios, Emilio Borghesan, Agustín Díaz, Jorge Rodríguez.

## References

`old/Barrios_Borghersan_Diaz_Rodriguez.pdf`: prior analysis conducted at RIS Investigación (Ministerio de Desarrollo Social), which this project builds on and extends.
