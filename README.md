# Threshold-Crossing Effects in Higher Education

This project estimates the causal effects of being eligible to certain college majors using Chile's Centralized Admission System. We implement a regression discontinuity design (RDD) exploiting admission cutoffs.

## Research Question

What are the returns to being admitted to a preferred college major? We compare outcomes of applicants who score marginally above vs. marginally below the admission cutoff for each program-year.

## Data

- **PSU Scores**: College admission test scores (2004–2023)
- **Applications**: Ranked-order lists submitted by applicants (2004–2023)
- **Enrollment**: Higher education enrollment records (2007–2022)

Data is accessed on a secure server.

## Methodology

- **Design**: Sharp regression discontinuity
- **Running variable**: Distance to admission cutoff (application score - cutoff)
- **Treatment**: Eligibility for admission (score ≥ cutoff)
- **Outcomes**: Enrollment in higher education, enrollment in target program

## Project Structure

```
majors/
├── code/
│   ├── config.do             # Path globals and parameters
│   ├── 01_clean/             # Data cleaning scripts
│   ├── 02_build/             # Sample construction
│   ├── 03_descriptive/       # Descriptive statistics
│   ├── 04_rdd/               # RDD estimation
│   └── Sua/                  # SUA entry IV design (see its README)
├── output/                   # Tables and figures
├── old/                      # Legacy code (reference)
├── docs/                     # Notes and documentation
└── WORKFLOW.md               # Detailed task tracking
```

## How we work

**One issue per research thread.** Every time we start exploring a new empirical question, we
open a GitHub issue *before* writing code, using the
[research-thread template](.github/ISSUE_TEMPLATE/research-thread.md) — the structure follows
[issue #1](https://github.com/jorginho84/Majors/issues/1), our reference example.

**Progress is reported in that issue.** As the work advances we add comments recording what ran,
the estimates, what broke, and what is still blocked. The issue is the running record of the
thread, not just its kickoff.

## Authors

- Barrios, Borghesan, Díaz, Rodríguez

## References

See `old/Barrios_Borghersan_Diaz_Rodriguez.pdf` for prior analysis conducted at RIS Investigación (Ministerio de Desarrollo Social).
