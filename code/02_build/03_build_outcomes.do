/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    03_build_outcomes.do

                    Merges enrollment outcomes with application data.

                    Creates outcome variables:
                    - enrolls_he: enrolled in any higher education
                    - enrolls_uni: enrolled in university
                    - enrolls_target: enrolled in the target program applied to

                    Based on legacy code: 03_returns.do (lines 397-406)

                    Input:  $processed/applications_rd.dta
                            $processed/enrollment.dta
                    Output: $processed/analysis_sample.dta
------------------------------------------------------------------------------*/

do "$code/config.do"

*-------------------------------------------------------------------------------
* Load applications with running variable
*-------------------------------------------------------------------------------

use "$processed/applications_rd.dta", clear

* Rename target program code to distinguish from enrollment program code
rename codigo_carrera t_codigo_carrera

*-------------------------------------------------------------------------------
* Merge with enrollment data
*-------------------------------------------------------------------------------

merge m:1 mrun año_proceso using "$processed/enrollment.dta", ///
    keepusing(codigo_demre enrolls_he enrolls_uni nomb_inst nomb_carrera tipo_inst_1) ///
    keep(1 3) nogen

* Rename enrollment program code
rename codigo_demre codigo_carrera_enrolled

*-------------------------------------------------------------------------------
* Create outcome variables
*-------------------------------------------------------------------------------

* Fill missing enrollment indicators with zeros (not enrolled)
replace enrolls_he = 0 if enrolls_he == .
replace enrolls_uni = 0 if enrolls_uni == .

* Enrolled in target program
* Target = the program the student applied to (t_codigo_carrera)
gen enrolls_target = (t_codigo_carrera == codigo_carrera_enrolled) if codigo_carrera_enrolled != .
replace enrolls_target = 0 if enrolls_target == .

label variable enrolls_he "Enrolled in higher education"
label variable enrolls_uni "Enrolled in university"
label variable enrolls_target "Enrolled in target program"

*-------------------------------------------------------------------------------
* Label key variables
*-------------------------------------------------------------------------------

label variable t_codigo_carrera "Target program code (applied to)"
label variable codigo_carrera_enrolled "Program code enrolled in"

*-------------------------------------------------------------------------------
* Basic validation and summary
*-------------------------------------------------------------------------------

di _n "=== Outcome Summary ==="

* Overall enrollment rates
di _n "Overall enrollment rates:"
summarize enrolls_he enrolls_uni enrolls_target

* Enrollment rates by treatment status
di _n "Enrollment rates by treatment status (above_cutoff):"
table above_cutoff, stat(mean enrolls_he) stat(mean enrolls_uni) stat(mean enrolls_target) stat(count enrolls_he)

* Enrollment rates by admission status
di _n "Enrollment rates by admission status:"
table estado_preferencia, stat(mean enrolls_he) stat(mean enrolls_uni) stat(mean enrolls_target) stat(count enrolls_he)

* Enrollment rates by year
di _n "Enrollment rates by year:"
table año_proceso, stat(mean enrolls_he) stat(mean enrolls_uni) stat(mean enrolls_target)

* Cross-tab: admission status vs enrollment in target
di _n "Enrollment in target by admission status:"
tab estado_preferencia enrolls_target, row

*-------------------------------------------------------------------------------
* Save
*-------------------------------------------------------------------------------

compress
save "$processed/analysis_sample.dta", replace

di _n "Analysis sample saved to: $processed/analysis_sample.dta"
di "Observations: " _N
