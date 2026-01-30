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
│   └── 04_rdd/               # RDD estimation
├── output/                   # Tables and figures
├── old/                      # Legacy code (reference)
├── docs/                     # Notes and documentation
└── WORKFLOW.md               # Detailed task tracking
```

## Authors

- Barrios, Borghesan, Díaz, Rodríguez

## References

See `old/Barrios_Borghersan_Diaz_Rodriguez.pdf` for prior analysis conducted at RIS Investigación (Ministerio de Desarrollo Social).
