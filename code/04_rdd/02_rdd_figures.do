/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    02_rdd_figures.do

                    Creates RD plots for enrollment outcomes using custom rd_plot command.

                    The rd_plot command creates publication-ready figures with:
                    - Binned scatter points
                    - Fitted polynomial lines (linear)
                    - Histogram of running variable
                    - RD coefficient displayed on graph

                    Based on legacy code: 04_a2_figures_enrollment.do

                    Input:  $processed/analysis_sample.dta
                    Output: $output/figures/rd_*.pdf
------------------------------------------------------------------------------*/

do "code/config.do"

*-------------------------------------------------------------------------------
* Setup
*-------------------------------------------------------------------------------

* Create output directories
capture mkdir "$output"
capture mkdir "$output/figures"

* Load analysis sample
use "$processed/analysis_sample.dta", clear

* Label variables for nice axis titles
label variable enrolls_he "Enrolls in Higher Education"
label variable enrolls_uni "Enrolls in University"
label variable enrolls_target "Enrolls in Target Program"
label variable score_rd "Distance to Admission Cutoff"
label variable above_cutoff "Above Cutoff"

*-------------------------------------------------------------------------------
* Figure 0: Histogram of running variable
*-------------------------------------------------------------------------------

di _n "=== Creating Histogram of Running Variable ==="

* Full sample histogram (within display range)
preserve
keep if abs(score_rd) <= 50

twoway (histogram score_rd, width(2) fcolor(gs12) lcolor(gs10) lwidth(vthin)), ///
    xline(0, lpattern(dash) lcolor(black) lwidth(medium)) ///
    xtitle("Distance to Admission Cutoff", size(medium)) ///
    ytitle("Density", size(medium)) ///
    xlabel(-50(10)50, labsize(small)) ///
    title("Distribution of Running Variable", size(medium)) ///
    graphregion(color(white)) ///
    plotregion(color(white))

graph export "$output/figures/histogram_running_var.pdf", replace as(pdf)
di "Histogram saved to: $output/figures/histogram_running_var.pdf"

restore

*-------------------------------------------------------------------------------
* Figure 1: Enrollment in any higher education
*-------------------------------------------------------------------------------

di _n "=== Creating RD Plot: Enrolls in Higher Education ==="

rd_plot enrolls_he, ///
    running(score_rd) ///
    treatment(above_cutoff) ///
    bandwidth($bandwidth) ///
    binwidth(5) ///
    degree(1) ///
    xsupport(50) ///
    absorb(ao_proceso t_codigo_carrera) ///
    cluster(ao_proceso#t_codigo_carrera) ///
    saving("$output/figures/rd_enrolls_he") ///
    title("Effect on Higher Education Enrollment") ///
    yrange(0 1)

*-------------------------------------------------------------------------------
* Figure 2: Enrollment in university
*-------------------------------------------------------------------------------

di _n "=== Creating RD Plot: Enrolls in University ==="

rd_plot enrolls_uni, ///
    running(score_rd) ///
    treatment(above_cutoff) ///
    bandwidth($bandwidth) ///
    binwidth(5) ///
    degree(1) ///
    xsupport(50) ///
    absorb(ao_proceso t_codigo_carrera) ///
    cluster(ao_proceso#t_codigo_carrera) ///
    saving("$output/figures/rd_enrolls_uni") ///
    title("Effect on University Enrollment") ///
    yrange(0 1)

*-------------------------------------------------------------------------------
* Figure 3: Enrollment in target program
*-------------------------------------------------------------------------------

di _n "=== Creating RD Plot: Enrolls in Target Program ==="

rd_plot enrolls_target, ///
    running(score_rd) ///
    treatment(above_cutoff) ///
    bandwidth($bandwidth) ///
    binwidth(5) ///
    degree(1) ///
    xsupport(50) ///
    absorb(ao_proceso t_codigo_carrera) ///
    cluster(ao_proceso#t_codigo_carrera) ///
    saving("$output/figures/rd_enrolls_target") ///
    title("Enroll in the Target University") ///
    yrange(0 .5)

*-------------------------------------------------------------------------------
* Summary
*-------------------------------------------------------------------------------

di _n _dup(70) "="
di "RD FIGURES COMPLETE"
di _dup(70) "="
di _n "Figures saved to: $output/figures/"
di _n "Files created:"
di "  - histogram_running_var.pdf"
di "  - rd_enrolls_he.pdf"
di "  - rd_enrolls_uni.pdf"
di "  - rd_enrolls_target.pdf"
di _dup(70) "="
