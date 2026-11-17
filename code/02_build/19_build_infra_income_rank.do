/**********************************************************************
* 19_build_infra_income_rank.do
*
* Issue #13: income rank of the program of graduation as an outcome for
* the inframarginal designs. Program-year panel for Design II.
*
* Outcome (Step 0, code/ProgramVA/01b_build_income_rank.do):
*   inc_rank   percentile (1-100), among sample graduates, of the Mi
*              Futuro income index of the program of the student's first
*              title within 8 years (any program, any institution;
*              switchers count); 0 if no title
*   grad_any   any title within 8 years (same definition)
*
* Inframarginal applicants as in Design I (21b): lugar <= T_p, First
* Cohort (infra_first_enroll) and Minimum Cohort (infra_min_enroll).
* Every inframarginal application counts, as in the 21b panels.
*
* Program-year means, keyed by harmonized code x year as in
* Own_expansion/05 (which collapses 21b to code x year weighting by the
* inframarginal count; collapsing the applications directly is the same):
*   ir_<d>   mean inc_rank (rank points)
*   ga_<d>   mean grad_any (pct.)
*   irg_<d>  mean inc_rank among graduates (rank points; selected sample)
*   d in {f, m}
*
* Inputs:  $processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta (21b)
*          $processed/pva_students_2007_2016.dta (ProgramVA/01b)
* Output:  $processed/oe_infra_income_rank.dta
**********************************************************************/

clear all
set more off
do "code/config.do"

use mrun ao_proceso inc_rank grad_any_8y ///
    using "$processed/pva_students_2007_2016.dta", clear
tempfile pva
save `pva'

use mrun ao_proceso codigo_carrera_harmonized infra_first_enroll infra_min_enroll ///
    using "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta", clear
keep if infra_first_enroll == 1 | infra_min_enroll == 1
merge m:1 mrun ao_proceso using `pva', keep(master match)
tab _merge
drop _merge

gen double ga  = 100 * grad_any_8y
gen double irg = inc_rank if grad_any_8y == 1

tempfile out
local first 1
foreach d in f m {
    local def = cond("`d'" == "f", "infra_first_enroll", "infra_min_enroll")
    preserve
        keep if `def' == 1
        collapse (mean) ir_`d' = inc_rank ga_`d' = ga irg_`d' = irg ///
            (count) nir_`d' = inc_rank, by(codigo_carrera_harmonized ao_proceso)
        if !`first' merge 1:1 codigo_carrera_harmonized ao_proceso using `out', nogen
        save `out', replace
    restore
    local first 0
}

use `out', clear
rename codigo_carrera_harmonized code_h
label var ir_f  "Income rank of program of graduation, First Cohort (0 if no title)"
label var ga_f  "Any title 8y, First Cohort (pct.)"
label var irg_f "Income rank among graduates, First Cohort"
label var ir_m  "Income rank of program of graduation, Minimum Cohort (0 if no title)"
label var ga_m  "Any title 8y, Minimum Cohort (pct.)"
label var irg_m "Income rank among graduates, Minimum Cohort"

tabstat ir_f ga_f irg_f ir_m ga_m irg_m, by(ao_proceso) stat(mean n) format(%6.1f)

compress
save "$processed/oe_infra_income_rank.dta", replace
di as result "oe_infra_income_rank.dta saved."
