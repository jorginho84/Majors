/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    01_build_cutoffs.do

                    Computes admission cutoffs from application data.
                    Cutoff = minimum score among admitted applicants (estado_preferencia == 24)
                    for each program-year.

                    Note: application_score (PUNTAJE) is often missing in the raw data.
                    This script computes weighted scores from PSU + weights when missing,
                    then derives cutoffs from those scores.

                    Based on legacy code: 03_returns.do (Section 4: Regular cutoff)

                    Input:  $processed/applications.dta
                            $processed/psu_scores.dta
                            $processed/weights.dta
                    Output: $processed/cutoffs.dta
------------------------------------------------------------------------------*/

do "code/config.do"

*-------------------------------------------------------------------------------
* Load applications data
*-------------------------------------------------------------------------------

use "$processed/applications.dta", clear

* Keep only admitted applicants
keep if estado_preferencia == $admitted

* Check we have data
count
if r(N) == 0 {
    di as error "ERROR: No admitted applicants found (estado_preferencia == $admitted)"
    exit 1
}

di "Admitted applicants: " r(N)

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
*-------------------------------------------------------------------------------

gen app_score = application_score if application_score != 0 & application_score != .

replace app_score = app_score_actual ///
    if (application_score == 0 | application_score == .) & ///
       app_score_actual != 0 & app_score_actual != .

replace app_score = app_score_anterior ///
    if (app_score == 0 | app_score == .) & ///
       app_score_anterior != 0 & app_score_anterior != .

* Report coverage
count if application_score != . & application_score != 0
di "With original PUNTAJE: " r(N)

count if app_score != .
di "With final score (any source): " r(N)

* Clean up
drop app_score_actual app_score_anterior application_score
rename app_score application_score

*-------------------------------------------------------------------------------
* Compute cutoffs
* Cutoff = min(application_score) among admitted by program-year
*-------------------------------------------------------------------------------

* Compute cutoff as minimum score among admitted by program-year
bysort codigo_carrera ao_proceso: egen cutoff_regular = min(application_score)

* Keep only cutoff information (one row per program-year)
keep codigo_carrera ao_proceso cutoff_regular
duplicates drop

* Check for missing cutoffs
count if cutoff_regular == .
if r(N) > 0 {
    di as text "Warning: " r(N) " program-years have missing cutoffs"
}

*-------------------------------------------------------------------------------
* Label variables
*-------------------------------------------------------------------------------

label variable codigo_carrera "Program code"
label variable ao_proceso "Application year"
label variable cutoff_regular "Admission cutoff (min score among admitted)"

*-------------------------------------------------------------------------------
* Basic validation and summary
*-------------------------------------------------------------------------------

* Summary statistics
di _n "=== Cutoffs Summary ==="
di "Years: $year_start - $year_end"

count
di "Total program-years: " r(N)

distinct codigo_carrera
di "Unique programs: " r(ndistinct)

tab ao_proceso

summarize cutoff_regular, detail

* Distribution of cutoffs
histogram cutoff_regular, ///
    title("Distribution of Admission Cutoffs") ///
    xtitle("Cutoff Score") ///
    name(cutoff_dist, replace)

*-------------------------------------------------------------------------------
* Save
*-------------------------------------------------------------------------------

compress
save "$processed/cutoffs.dta", replace

di _n "Cutoffs data saved to: $processed/cutoffs.dta"

* Also export summary table
table ao_proceso, stat(count cutoff_regular) stat(mean cutoff_regular) ///
    stat(sd cutoff_regular) stat(min cutoff_regular) stat(max cutoff_regular)
