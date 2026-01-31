/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    01_build_cutoffs.do

                    Computes admission cutoffs from application data.
                    Cutoff = minimum score among admitted applicants (estado_preferencia == 24)
                    for each program-year.

                    Based on legacy code: 03_returns.do (Section 4: Regular cutoff)

                    Input:  $processed/applications.dta
                    Output: $processed/cutoffs.dta
------------------------------------------------------------------------------*/

do "code/config.do"

*-------------------------------------------------------------------------------
* Load applications data
*-------------------------------------------------------------------------------

use "$processed/applications.dta", clear

*-------------------------------------------------------------------------------
* Compute cutoffs
* Cutoff = min(application_score) among admitted (estado_preferencia == 24)
* by program-year
*-------------------------------------------------------------------------------

* Keep only admitted applicants
keep if estado_preferencia == $admitted

* Check we have data
count
if r(N) == 0 {
    di as error "ERROR: No admitted applicants found (estado_preferencia == $admitted)"
    exit 1
}

* Compute cutoff as minimum score among admitted by program-year
bysort codigo_carrera año_proceso: egen cutoff_regular = min(application_score)

* Keep only cutoff information (one row per program-year)
keep codigo_carrera año_proceso cutoff_regular
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
label variable año_proceso "Application year"
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

tab año_proceso

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
table año_proceso, stat(count cutoff_regular) stat(mean cutoff_regular) ///
    stat(sd cutoff_regular) stat(min cutoff_regular) stat(max cutoff_regular)
