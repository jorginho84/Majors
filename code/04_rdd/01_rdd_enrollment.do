/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    01_rdd_enrollment.do

                    Main RDD estimates for enrollment outcomes.

                    Specification:
                        Y = β₀ + β₁·above_cutoff + β₂·score_rd + β₃·above_cutoff×score_rd + FE + ε

                    Where:
                        - Y: outcome (enrolls_he, enrolls_uni, enrolls_target)
                        - above_cutoff: treatment indicator (1 if score ≥ cutoff)
                        - score_rd: running variable (application_score - cutoff)
                        - FE: year × program fixed effects

                    Based on legacy code: 04_a2_figures_enrollment.do

                    Input:  $processed/analysis_sample.dta
                    Output: $output/tables/rdd_enrollment.tex
------------------------------------------------------------------------------*/

do "code/config.do"

*-------------------------------------------------------------------------------
* Load analysis sample
*-------------------------------------------------------------------------------

use "$processed/analysis_sample.dta", clear

*-------------------------------------------------------------------------------
* Sample preparation
*-------------------------------------------------------------------------------

* Keep observations within bandwidth
keep if abs(score_rd) <= $bandwidth

* Check sample size
count
di "Observations within bandwidth: " r(N)

* Generate year dummies for display
tab ao_proceso, gen(yr_)

*-------------------------------------------------------------------------------
* Summary statistics before estimation
*-------------------------------------------------------------------------------

di _n "=== Pre-estimation Summary ==="

* Sample composition
tab above_cutoff, missing
tab ao_proceso above_cutoff

* Outcome means by treatment status
di _n "Mean outcomes by treatment status:"
table above_cutoff, stat(mean enrolls_he) stat(mean enrolls_uni) stat(mean enrolls_target) stat(count enrolls_he)

* Running variable distribution
di _n "Running variable distribution:"
summarize score_rd, detail

*-------------------------------------------------------------------------------
* RDD Estimation: Enrollment Outcomes
*-------------------------------------------------------------------------------

* Store estimates for table
estimates clear

* Local for fixed effects
local fe "i.ao_proceso#i.t_codigo_carrera"
local cluster_var "ao_proceso#t_codigo_carrera"

*--- Outcome 1: Enrolls in any higher education ---

di _n "=== Enrolls in Higher Education ==="

reghdfe enrolls_he above_cutoff score_rd 1.above_cutoff#c.score_rd, ///
    absorb(`fe') cluster(i.`cluster_var')

estimates store rdd_he

* Display key results
di "RD estimate (enrolls_he): " _b[above_cutoff]
di "SE: " _se[above_cutoff]
di "N: " e(N)

*--- Outcome 2: Enrolls in university ---

di _n "=== Enrolls in University ==="

reghdfe enrolls_uni above_cutoff score_rd 1.above_cutoff#c.score_rd, ///
    absorb(`fe') cluster(i.`cluster_var')

estimates store rdd_uni

* Display key results
di "RD estimate (enrolls_uni): " _b[above_cutoff]
di "SE: " _se[above_cutoff]
di "N: " e(N)

*--- Outcome 3: Enrolls in target program ---

di _n "=== Enrolls in Target Program ==="

reghdfe enrolls_target above_cutoff score_rd 1.above_cutoff#c.score_rd, ///
    absorb(`fe') cluster(i.`cluster_var')

estimates store rdd_target

* Display key results
di "RD estimate (enrolls_target): " _b[above_cutoff]
di "SE: " _se[above_cutoff]
di "N: " e(N)

*-------------------------------------------------------------------------------
* Export results table
*-------------------------------------------------------------------------------

* Create output directory if it doesn't exist
capture mkdir "$output"
capture mkdir "$output/tables"

* Export to LaTeX
esttab rdd_he rdd_uni rdd_target using "$output/tables/rdd_enrollment.tex", ///
    replace ///
    keep(above_cutoff) ///
    label ///
    se(3) b(3) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    title("RDD Estimates: Enrollment Outcomes") ///
    mtitles("Any HE" "University" "Target Program") ///
    note("Standard errors clustered at program-year level in parentheses.") ///
    addnote("Sample restricted to applicants within $bandwidth points of cutoff.") ///
    scalars("N Observations") ///
    substitute(\_ _)

* Also export to CSV for easy viewing
esttab rdd_he rdd_uni rdd_target using "$output/tables/rdd_enrollment.csv", ///
    replace ///
    keep(above_cutoff) ///
    se(3) b(3) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    csv

di _n "Results exported to: $output/tables/rdd_enrollment.tex"

*-------------------------------------------------------------------------------
* Quadratic specification (robustness)
*-------------------------------------------------------------------------------

di _n "=== Quadratic Specification (Robustness) ==="

estimates clear

* Enrolls in any HE
reghdfe enrolls_he above_cutoff score_rd 1.above_cutoff#c.score_rd ///
    c.score_rd#c.score_rd 1.above_cutoff#c.score_rd#c.score_rd, ///
    absorb(`fe') cluster(i.`cluster_var')
estimates store rdd_he_q

* Enrolls in university
reghdfe enrolls_uni above_cutoff score_rd 1.above_cutoff#c.score_rd ///
    c.score_rd#c.score_rd 1.above_cutoff#c.score_rd#c.score_rd, ///
    absorb(`fe') cluster(i.`cluster_var')
estimates store rdd_uni_q

* Enrolls in target
reghdfe enrolls_target above_cutoff score_rd 1.above_cutoff#c.score_rd ///
    c.score_rd#c.score_rd 1.above_cutoff#c.score_rd#c.score_rd, ///
    absorb(`fe') cluster(i.`cluster_var')
estimates store rdd_target_q

* Export quadratic results
esttab rdd_he_q rdd_uni_q rdd_target_q using "$output/tables/rdd_enrollment_quadratic.tex", ///
    replace ///
    keep(above_cutoff) ///
    label ///
    se(3) b(3) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    title("RDD Estimates: Enrollment Outcomes (Quadratic)") ///
    mtitles("Any HE" "University" "Target Program") ///
    note("Standard errors clustered at program-year level in parentheses.") ///
    addnote("Quadratic specification with different slopes above/below cutoff.") ///
    scalars("N Observations") ///
    substitute(\_ _)

*-------------------------------------------------------------------------------
* Display summary of main results
*-------------------------------------------------------------------------------

di _n _dup(70) "="
di "MAIN RDD RESULTS: ENROLLMENT OUTCOMES"
di _dup(70) "="
di _n "Linear specification (bandwidth = $bandwidth)"
di _dup(50) "-"

estimates restore rdd_he
local b_he = _b[above_cutoff]
local se_he = _se[above_cutoff]

estimates restore rdd_uni
local b_uni = _b[above_cutoff]
local se_uni = _se[above_cutoff]

estimates restore rdd_target
local b_target = _b[above_cutoff]
local se_target = _se[above_cutoff]

di "Enrolls in any HE:      " %6.3f `b_he' " (" %5.3f `se_he' ")"
di "Enrolls in university:  " %6.3f `b_uni' " (" %5.3f `se_uni' ")"
di "Enrolls in target:      " %6.3f `b_target' " (" %5.3f `se_target' ")"
di _dup(70) "="

di _n "RDD estimation complete."
