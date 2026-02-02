/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    02_build_running_var.do

                    Builds the running variable for RDD analysis.

                    Steps:
                    1. Load applications (with application scores from PUNTAJE)
                    2. Merge with PSU scores (individual test scores)
                    3. Merge with program weights
                    4. Compute weighted scores when PUNTAJE is missing/zero
                    5. Merge with cutoffs
                    6. Compute running variable: score_rd = application_score - cutoff
                    7. Create treatment indicator: above_cutoff = (score_rd >= 0)

                    Based on legacy code: 03_returns.do (Sections 5, 8)

                    Input:  $processed/applications.dta
                            $processed/psu_scores.dta
                            $processed/weights.dta
                            $processed/cutoffs.dta
                    Output: $processed/applications_rd.dta
------------------------------------------------------------------------------*/

do "code/config.do"

*-------------------------------------------------------------------------------
* Load applications data
*-------------------------------------------------------------------------------

use "$processed/applications.dta", clear

* Keep only applicants with admission status 24, 25, or 26
* (Following legacy code line 278)
keep if estado_preferencia == $admitted | ///
        estado_preferencia == $waiting_list | ///
        estado_preferencia == $rejected

*-------------------------------------------------------------------------------
* Merge with PSU scores
*-------------------------------------------------------------------------------

merge m:1 mrun ao_proceso using "$processed/psu_scores.dta", ///
    keepusing(ptje_nem ptje_ranking ///
              lyc_actual mate_actual hycs_actual ciencias_actual promlm_actual ///
              lyc_anterior mate_anterior hycs_anterior ciencias_anterior promlm_anterior ///
              first_year) ///
    keep(1 3) nogen

*-------------------------------------------------------------------------------
* Merge with program weights
*-------------------------------------------------------------------------------

merge m:1 codigo_carrera ao_proceso using "$processed/weights.dta", ///
    keep(1 3) nogen

*-------------------------------------------------------------------------------
* Compute weighted application scores
* (Following legacy code lines 291-302)
*
* The formula computes:
*   score = w_gpa*NEM + w_rank*ranking + w_reading*language + w_math*math + ...
*
* Two versions: using current year scores (_actual) or previous year (_anterior)
* Some programs let students choose between history and science (take max)
*-------------------------------------------------------------------------------

gen app_score_actual = .
gen app_score_anterior = .

* Compute score using current year test scores
* Only for valid test scores (150-850 range)
replace app_score_actual = w_gpa * ptje_nem + ///
                           w_rank * ptje_ranking + ///
                           w_reading * lyc_actual + ///
                           w_math * mate_actual + ///
                           w_history * hycs_actual + ///
                           w_science * ciencias_actual ///
    if choose_hist_science == "NO" & ///
       lyc_actual >= 150 & lyc_actual <= 850 & ///
       mate_actual >= 150 & mate_actual <= 850

* For programs allowing choice between history and science, take max
replace app_score_actual = w_gpa * ptje_nem + ///
                           w_rank * ptje_ranking + ///
                           w_reading * lyc_actual + ///
                           w_math * mate_actual + ///
                           w_history * max(hycs_actual, ciencias_actual) ///
    if choose_hist_science == "SI" & ///
       lyc_actual >= 150 & lyc_actual <= 850 & ///
       mate_actual >= 150 & mate_actual <= 850

* Compute score using previous year test scores (for repeat test-takers)
replace app_score_anterior = w_gpa * ptje_nem + ///
                             w_rank * ptje_ranking + ///
                             w_reading * lyc_anterior + ///
                             w_math * mate_anterior + ///
                             w_history * hycs_anterior + ///
                             w_science * ciencias_anterior ///
    if choose_hist_science == "NO" & ///
       lyc_anterior >= 150 & lyc_anterior <= 850 & ///
       mate_anterior >= 150 & mate_anterior <= 850

replace app_score_anterior = w_gpa * ptje_nem + ///
                             w_rank * ptje_ranking + ///
                             w_reading * lyc_anterior + ///
                             w_math * mate_anterior + ///
                             w_history * max(hycs_anterior, ciencias_anterior) ///
    if choose_hist_science == "SI" & ///
       lyc_anterior >= 150 & lyc_anterior <= 850 & ///
       mate_anterior >= 150 & mate_anterior <= 850

*-------------------------------------------------------------------------------
* Normalize computed scores
* Weights are in percentage form (summing to ~100), so divide by 100
* to get scores on the same scale as original PUNTAJE (150-850)
*-------------------------------------------------------------------------------

replace app_score_actual = app_score_actual / 100 if app_score_actual != .
replace app_score_anterior = app_score_anterior / 100 if app_score_anterior != .

*-------------------------------------------------------------------------------
* Create final application score
* Priority:
*   1. Use original PUNTAJE (application_score) if available and non-zero
*   2. Use computed score from current year if original is missing/zero
*   3. Use computed score from previous year as last resort
* (Following legacy code lines 299-301)
*-------------------------------------------------------------------------------

gen app_score = application_score if application_score != 0 & application_score != .

replace app_score = app_score_actual ///
    if (application_score == 0 | application_score == .) & ///
       app_score_actual != 0 & app_score_actual != .

replace app_score = app_score_anterior ///
    if (app_score == 0 | app_score == .) & ///
       app_score_anterior != 0 & app_score_anterior != .

* Replace original application_score with the final computed score
drop application_score
rename app_score application_score

label variable application_score "Application score (PUNTAJE or computed from weights)"

* Clean up intermediate variables
drop app_score_actual app_score_anterior

*-------------------------------------------------------------------------------
* Merge with cutoffs
*-------------------------------------------------------------------------------

merge m:1 codigo_carrera ao_proceso using "$processed/cutoffs.dta", ///
    keep(1 3) nogen

*-------------------------------------------------------------------------------
* Compute running variable and treatment indicator
* (Following legacy code line 599-600)
*-------------------------------------------------------------------------------

* Running variable: distance to cutoff
gen score_rd = application_score - cutoff_regular

* Treatment indicator: above cutoff
gen above_cutoff = (score_rd >= 0) if score_rd != .

label variable score_rd "Running variable (application_score - cutoff)"
label variable above_cutoff "Above cutoff indicator (1 if score_rd >= 0)"
label variable cutoff_regular "Admission cutoff for program-year"

*-------------------------------------------------------------------------------
* Basic validation and summary
*-------------------------------------------------------------------------------

* Check running variable distribution
di _n "=== Running Variable Summary ==="
summarize score_rd, detail

* Check treatment indicator
tab above_cutoff, missing

* Cross-tab with estado_preferencia (should align reasonably well)
tab estado_preferencia above_cutoff, missing

* Check for missing values
count if application_score == .
di "Missing application scores: " r(N)

count if cutoff_regular == .
di "Missing cutoffs: " r(N)

count if score_rd == .
di "Missing running variable: " r(N)

* Summary by year
table ao_proceso, stat(count score_rd) stat(mean score_rd) stat(mean above_cutoff)

*-------------------------------------------------------------------------------
* Save
*-------------------------------------------------------------------------------

compress
save "$processed/applications_rd.dta", replace

di _n "Applications with running variable saved to: $processed/applications_rd.dta"
