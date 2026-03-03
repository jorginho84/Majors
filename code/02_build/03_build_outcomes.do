/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    03_build_outcomes.do

                    Merges enrollment outcomes with application data.

                    Creates outcome variables:
                    - enrolls_he: enrolled in any higher education
                    - enrolls_uni: enrolled in university
                    - enrolls_target: enrolled in the target program applied to

                    enrolls_target uses two code-based sources:
                    1. MINEDUC Matricula: codigo_demre (may be 0/missing)
                    2. DEMRE Formulario D: codigo_carrera (always present)
                    Both are matched against t_codigo_carrera (applied program).

                    Based on legacy code: 03_returns.do (lines 397-406, 458-460)

                    Input:  $processed/applications_rd.dta
                            $processed/enrollment.dta
                            $processed/enrollment_demre.dta
                    Output: $processed/analysis_sample.dta
------------------------------------------------------------------------------*/

do "code/config.do"

*-------------------------------------------------------------------------------
* Load applications with running variable
*-------------------------------------------------------------------------------

use "$processed/applications_rd.dta", clear

* Rename target program code to distinguish from enrollment program code
rename codigo_carrera t_codigo_carrera

*-------------------------------------------------------------------------------
* Drop non-binding status 26 observations
*
* In the DEMRE mechanism, estado_preferencia == 26 at program j means the
* student was assigned to a higher-ranked (more preferred) program k.
* Crossing j's cutoff would not change their assignment — j is non-binding.
*
* We identify these as: status 26 at j AND status 24 at some k with
* preferencia_k < preferencia_j (k is ranked higher = smaller number).
*
* Note: this must run BEFORE the oversubscribed restriction, since the
* higher-ranked admission k may be at a non-oversubscribed program.
*-------------------------------------------------------------------------------

* Find the most preferred program each student was admitted to (status 24)
gen     admitted_pref = preferencia if estado_preferencia == 24
bysort mrun ao_proceso: egen min_admitted_pref = min(admitted_pref)

* Count before
local n_before = _N
di _n "=== Binding Cutoff Filter ==="
di "Observations before filter: " `n_before'

count if estado_preferencia == 26 & ///
        min_admitted_pref < preferencia & min_admitted_pref != .
di "Non-binding status 26 observations dropped: " r(N)

* Drop: status 26 at j AND admitted to a higher-ranked program (lower pref number)
drop if estado_preferencia == 26 & ///
        min_admitted_pref < preferencia & min_admitted_pref != .

di "Observations after filter: " _N

drop admitted_pref min_admitted_pref

*-------------------------------------------------------------------------------
* Restrict to oversubscribed programs (with waiting lists)
* Only these have binding cutoffs for valid RDD identification
*-------------------------------------------------------------------------------

merge m:1 t_codigo_carrera ao_proceso using "$processed/waiting_list.dta", ///
    keep(3) nogen

di "Observations after restricting to oversubscribed programs: " _N

*-------------------------------------------------------------------------------
* Merge with MINEDUC enrollment data
*-------------------------------------------------------------------------------

merge m:1 mrun ao_proceso using "$processed/enrollment.dta", ///
    keepusing(codigo_demre enrolls_he enrolls_uni nomb_inst nomb_carrera tipo_inst_1) ///
    keep(1 3) nogen

rename codigo_demre codigo_carrera_mineduc

* Treat codigo_demre == 0 as missing (many records have 0 instead of missing)
replace codigo_carrera_mineduc = . if codigo_carrera_mineduc == 0

*-------------------------------------------------------------------------------
* Merge with DEMRE Formulario D enrollment data
*-------------------------------------------------------------------------------

merge m:1 mrun ao_proceso using "$processed/enrollment_demre.dta", ///
    keepusing(codigo_carrera) keep(1 3) nogen

rename codigo_carrera codigo_carrera_demre

*-------------------------------------------------------------------------------
* Create outcome variables
*-------------------------------------------------------------------------------

* Fill missing enrollment indicators with zeros (not enrolled)
replace enrolls_he  = 0 if enrolls_he  == .
replace enrolls_uni = 0 if enrolls_uni == .

*-------------------------------------------------------------------------------
* Enrolled in target program
* Match t_codigo_carrera against MINEDUC code OR Formulario D code
* (Following legacy code lines 458-460: code match is primary method)
*-------------------------------------------------------------------------------

gen enrolls_target_mineduc = (t_codigo_carrera == codigo_carrera_mineduc) ///
    if codigo_carrera_mineduc != .
replace enrolls_target_mineduc = 0 if enrolls_target_mineduc == .

gen enrolls_target_demre = (t_codigo_carrera == codigo_carrera_demre) ///
    if codigo_carrera_demre != .
replace enrolls_target_demre = 0 if enrolls_target_demre == .

gen enrolls_target = (enrolls_target_mineduc == 1 | enrolls_target_demre == 1)

* Diagnostics
di _n "=== Enrollment Target Matching Diagnostics ==="
di "MINEDUC code matches: "
count if enrolls_target_mineduc == 1
di "Formulario D code matches (additional): "
count if enrolls_target_demre == 1 & enrolls_target_mineduc == 0
di "Total target matches: "
count if enrolls_target == 1

drop enrolls_target_mineduc enrolls_target_demre

*-------------------------------------------------------------------------------
* Label variables
*-------------------------------------------------------------------------------

label variable enrolls_he     "Enrolled in higher education"
label variable enrolls_uni    "Enrolled in university"
label variable enrolls_target "Enrolled in target program"

label variable t_codigo_carrera      "Target program code (applied to)"
label variable codigo_carrera_mineduc "Program code enrolled in (MINEDUC)"
label variable codigo_carrera_demre   "Program code enrolled in (Formulario D)"

*-------------------------------------------------------------------------------
* Basic validation and summary
*-------------------------------------------------------------------------------

di _n "=== Outcome Summary ==="

di _n "Overall enrollment rates:"
summarize enrolls_he enrolls_uni enrolls_target

di _n "Enrollment rates by treatment status (above_cutoff):"
table above_cutoff, stat(mean enrolls_he) stat(mean enrolls_uni) stat(mean enrolls_target) stat(count enrolls_he)

di _n "Enrollment rates by admission status:"
table estado_preferencia, stat(mean enrolls_he) stat(mean enrolls_uni) stat(mean enrolls_target) stat(count enrolls_he)

di _n "Enrollment rates by year:"
table ao_proceso, stat(mean enrolls_he) stat(mean enrolls_uni) stat(mean enrolls_target)

di _n "Enrollment in target by admission status:"
tab estado_preferencia enrolls_target, row

*-------------------------------------------------------------------------------
* Save
*-------------------------------------------------------------------------------

compress
save "$processed/analysis_sample.dta", replace

di _n "Analysis sample saved to: $processed/analysis_sample.dta"
di "Observations: " _N
