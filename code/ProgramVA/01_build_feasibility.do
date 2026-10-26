/**********************************************************************
* 01_build_feasibility.do
*
* Program value-added (issue #9): student-level base with admission
* portfolios built from the DA feasibility of each ROL entry.
*
* Feasible at j (student i, cohort t):
*   - status in {24, 25, 26} (other DEMRE codes = ineligible), and
*   - j oversubscribed (has a waiting list): weighted score >= cutoff_j
*     j not oversubscribed: any eligible applicant
* The weighted score is recomputed for every ROL entry, since DEMRE's
* PUNTAJE is 0 below the assigned preference. Best of current and
* previous-year PSU, as DEMRE allows; official PUNTAJE when > 0.
*
* Portfolios (cohort-specific):
*   port_bin   unordered set of feasible ROL programs   (main)
*   port_ter   port_bin + unordered set of applied-not-feasible programs
*   port_enr   port_bin + enrolled program if on the ROL (waitlist calls)
*
* Treatments:
*   S_itt   program assigned by DEMRE (status 24)
*   S_enr   program of enrollment in t (Formulario D)
*
* Inputs:  $processed/applications.dta, psu_scores.dta, weights.dta,
*          cutoffs.dta, waiting_list.dta, enrollment_demre.dta,
*          check_06b_grad_general.dta (titulados through 2024),
*          $psu_raw/A_INSCRITOS_PUNTAJES_PSU_YYYY_PRIV_MRUN.csv
* Output:  $processed/pva_students_2007_2016.dta     (one row per i-t)
*          $processed/pva_applications_2007_2016.dta (one row per i-t-j)
*          output/tables/pva_feasibility_validation.csv
**********************************************************************/

clear all
set more off
do "code/config.do"

capture log close
log using "$logs/pva_01_build_feasibility.log", replace text

* 4-digit DEMRE codes (pre-2012) -> 5-digit format, as in 02_build/16
capture program drop harmonize_code
program define harmonize_code
    args in out
    tempvar s
    gen `s' = strtrim(string(`in', "%12.0f"))
    gen long `out' = `in'
    replace `out' = real(substr(`s', 1, length(`s')-2) + "0" + ///
        substr(`s', length(`s')-1, 2)) if length(`s') == 4
end

/**********************************************************************
* 1. Sex and school dependency, Formulario A (as in 02_build/16)
**********************************************************************/

tempfile demo
forvalues y = 2007/2016 {
    import delimited "$psu_raw/A_INSCRITOS_PUNTAJES_PSU_`y'_PRIV_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(windows-1252) ///
        stringcols(_all)
    rename *, lower
    keep mrun cod_sexo grupo_dependencia
    destring mrun cod_sexo grupo_dependencia, replace force
    gen int ao_proceso = `y'
    if `y' > 2007 append using `demo'
    save `demo', replace
}
drop if missing(mrun)
duplicates drop mrun ao_proceso, force
gen byte female = cod_sexo == 2 if inlist(cod_sexo, 1, 2)
gen byte priv   = grupo_dependencia == 4 if inrange(grupo_dependencia, 1, 5)
gen byte mun    = inlist(grupo_dependencia, 1, 2) if inrange(grupo_dependencia, 1, 5)
gen byte dep    = grupo_dependencia if inrange(grupo_dependencia, 1, 5)
keep mrun ao_proceso female priv mun dep
save `demo', replace

/**********************************************************************
* 2. Applications with weighted scores, cutoffs and feasibility
**********************************************************************/

use mrun ao_proceso preferencia codigo_carrera sigla_universidad ///
    estado_preferencia application_score using "$processed/applications.dta", clear
keep if inrange(ao_proceso, $year_start, $year_end)
drop if missing(mrun, codigo_carrera, preferencia)

merge m:1 mrun ao_proceso using "$processed/psu_scores.dta", ///
    keepusing(ptje_nem ptje_ranking lyc_actual mate_actual hycs_actual ///
              ciencias_actual lyc_anterior mate_anterior hycs_anterior ///
              ciencias_anterior) keep(1 3) nogen

merge m:1 codigo_carrera ao_proceso using "$processed/weights.dta", ///
    keepusing(w_gpa w_rank w_reading w_math w_history w_science ///
              choose_hist_science) keep(1 3) gen(_m_w)

merge m:1 codigo_carrera ao_proceso using "$processed/cutoffs.dta", ///
    keep(1 3) nogen

rename codigo_carrera t_codigo_carrera
merge m:1 t_codigo_carrera ao_proceso using "$processed/waiting_list.dta", ///
    keepusing(has_waiting_list) keep(1 3) nogen
rename t_codigo_carrera codigo_carrera
replace has_waiting_list = 0 if missing(has_waiting_list)

* weighted score, current and previous year. weights.dta stores weights
* as fractions (sum ~1) in every year (w_scale below is 1 for all rows;
* 02_build/01 and 02 divide by 100 and get scores of ~6). The scale is
* still detected from the weights, so the code is safe either way;
* the scale is read from the weights themselves
gen double w_scale = cond(w_gpa + w_rank + w_reading + w_math > 1.5, 100, 1)
tab ao_proceso w_scale
foreach v in actual anterior {
    gen double s_`v' = (w_gpa * ptje_nem + w_rank * ptje_ranking + ///
        w_reading * lyc_`v' + w_math * mate_`v' + ///
        cond(choose_hist_science == "SI", ///
             w_history * max(hycs_`v', ciencias_`v'), ///
             w_history * hycs_`v' + w_science * ciencias_`v')) / w_scale ///
        if inrange(lyc_`v', 150, 850) & inrange(mate_`v', 150, 850)
}
* agreement with the official score where both exist
gen double d_off = application_score - max(s_actual, s_anterior) ///
    if application_score > 0 & !missing(application_score)
summarize d_off, detail
gen byte agree_off = abs(d_off) < 1 if !missing(d_off)
tab ao_proceso agree_off, row nofreq
gen double score = application_score if application_score > 0 & !missing(application_score)
replace score = max(s_actual, s_anterior) if missing(score)
gen byte score_official = application_score > 0 & !missing(application_score)

gen byte eligible = inlist(estado_preferencia, 24, 25, 26)
gen byte feasible = estado_preferencia == $admitted
replace feasible = 1 if eligible & has_waiting_list == 0
replace feasible = 1 if eligible & has_waiting_list == 1 & ///
    !missing(score, cutoff_regular) & score >= cutoff_regular - 0.001

harmonize_code codigo_carrera code_h
replace sigla_universidad = upper(strtrim(sigla_universidad))
duplicates drop mrun ao_proceso code_h, force

/**********************************************************************
* 3. Validation of the feasibility reconstruction
*    DA implies: assigned program = top-ranked feasible program, and
*    every program ranked above the assigned one is infeasible.
**********************************************************************/

gen byte adm = estado_preferencia == $admitted
bysort mrun ao_proceso: egen byte n_adm = total(adm)
gen pref_adm_aux = preferencia if adm
bysort mrun ao_proceso: egen pref_adm = min(pref_adm_aux)
gen pref_feas_aux = preferencia if feasible
bysort mrun ao_proceso: egen pref_feas = min(pref_feas_aux)
drop pref_adm_aux pref_feas_aux

gen byte above_adm = preferencia < pref_adm if !missing(pref_adm)
gen byte viol_above = feasible & above_adm == 1

preserve
    bysort mrun ao_proceso: keep if _n == 1
    gen byte assigned   = n_adm >= 1
    gen byte top_match  = pref_feas == pref_adm if assigned
    gen byte unasg_feas = !missing(pref_feas) if !assigned
    collapse (mean) top_match unasg_feas assigned (count) n = mrun, by(ao_proceso)
    tempfile v1
    save `v1'
restore
preserve
    keep if above_adm == 1
    collapse (mean) viol_above (count) n_above = mrun, by(ao_proceso)
    merge 1:1 ao_proceso using `v1', nogen
    order ao_proceso n assigned top_match viol_above n_above unasg_feas
    di as result _n "=== Feasibility validation by cohort ==="
    di as text "top_match:  share of assigned students whose top feasible = assigned"
    di as text "viol_above: share of entries ranked above the assigned one flagged feasible"
    di as text "unasg_feas: share of unassigned students with some feasible entry"
    list, noobs abbrev(12)
    export delimited using "$output/tables/pva_feasibility_validation.csv", replace
restore

/**********************************************************************
* 4. Enrollment (Formulario D) and portfolio sets
**********************************************************************/

preserve
    use "$processed/enrollment_demre.dta", clear
    keep if inrange(ao_proceso, $year_start, $year_end)
    duplicates drop mrun ao_proceso, force
    harmonize_code codigo_carrera S_enr
    keep mrun ao_proceso S_enr
    tempfile enr
    save `enr'
restore
merge m:1 mrun ao_proceso using `enr', keep(1 3) nogen

gen byte enr_row  = code_h == S_enr
gen byte in_feas   = feasible
gen byte in_infeas = !feasible
gen byte in_enr    = feasible | enr_row

* unordered sets as sorted code chains: within i-t, rows with in_s == 0
* sort first, so the chain grows along the rows with in_s == 1 and its
* complete value sits in the last row
gen str6 c = string(code_h, "%06.0f")
foreach s in feas infeas enr {
    gen str244 set_`s' = ""
    bysort mrun ao_proceso (in_`s' code_h): replace set_`s' = ///
        cond(in_`s', cond(_n > 1 & in_`s'[_n-1] == 1, set_`s'[_n-1] + "-" + c, c), "")
    bysort mrun ao_proceso (in_`s' code_h): replace set_`s' = set_`s'[_N]
}
bysort mrun ao_proceso: egen byte n_feas     = total(in_feas)
bysort mrun ao_proceso: egen byte n_feas_enr = total(in_enr)
bysort mrun ao_proceso: egen byte enr_on_rol = max(enr_row)
gen byte enr_feas_row = enr_row & feasible
bysort mrun ao_proceso: egen byte enr_feasible = max(enr_feas_row)
bysort mrun ao_proceso: gen byte n_apps = _N

compress
save "$processed/pva_applications_2007_2016.dta", replace

/**********************************************************************
* 5. Student level
**********************************************************************/

gen long S_itt_aux = code_h if adm
bysort mrun ao_proceso: egen long S_itt = min(S_itt_aux)
gen sig_a = sigla_universidad if adm
gen sig_e = sigla_universidad if enr_row
bysort mrun ao_proceso (sig_a): gen str5 univ_itt = sig_a[_N]
bysort mrun ao_proceso (sig_e): gen str5 univ_enr = sig_e[_N]

bysort mrun ao_proceso: keep if _n == 1
keep mrun ao_proceso S_itt S_enr univ_itt univ_enr n_feas n_feas_enr n_apps ///
     n_adm enr_on_rol enr_feasible set_feas set_infeas set_enr ///
     ptje_nem ptje_ranking lyc_* mate_*
replace enr_on_rol = 0 if missing(S_enr)
gen byte enrolled = !missing(S_enr)

egen long port_bin = group(ao_proceso set_feas) if n_feas >= 1
egen long port_ter = group(ao_proceso set_feas set_infeas) if n_feas >= 1, missing
egen long port_enr = group(ao_proceso set_enr) if n_feas_enr >= 1

* controls
gen double psu_lm = max((lyc_actual + mate_actual) / 2, ///
                        (lyc_anterior + mate_anterior) / 2)
replace psu_lm = . if psu_lm == 0
gen double nem = ptje_nem if ptje_nem > 0
gen double rank = ptje_ranking if ptje_ranking > 0
drop lyc_* mate_* ptje_nem ptje_ranking

merge 1:1 mrun ao_proceso using `demo', keep(1 3) nogen

* outcomes: graduation within 8 years (titulados through 2024)
tostring mrun, gen(mrun_str) format(%12.0f) force
replace mrun_str = trim(mrun_str)
merge 1:1 mrun_str ao_proceso using "$processed/check_06b_grad_general.dta", ///
    keepusing(graduates_he_8y graduates_uni_8y) keep(1 3) nogen
replace graduates_he_8y  = 0 if missing(graduates_he_8y)
replace graduates_uni_8y = 0 if missing(graduates_uni_8y)
drop mrun_str

label var S_itt        "Program assigned by DEMRE (harmonized code)"
label var S_enr        "Program of enrollment in t, Formulario D (harmonized code)"
label var univ_itt     "University of the assigned program"
label var univ_enr     "University of the enrolled program (if on the ROL)"
label var n_feas       "Number of feasible ROL programs"
label var n_feas_enr   "Feasible ROL programs incl. enrolled program"
label var enr_on_rol   "Enrolled program is on the ROL"
label var enr_feasible "Enrolled program is feasible (first round)"
label var set_feas     "Unordered set of feasible ROL programs"
label var set_infeas   "Unordered set of applied-not-feasible programs"
label var port_bin     "Portfolio: cohort x feasible set"
label var port_ter     "Portfolio: cohort x feasible set x infeasible set"
label var port_enr     "Portfolio: cohort x feasible set incl. enrolled program"
label var psu_lm       "PSU language+math (best of current/previous)"
label var graduates_he_8y  "Graduated from HE within 8 years"
label var graduates_uni_8y "Graduated from university within 8 years"

/**********************************************************************
* 6. Diagnostics
**********************************************************************/

di as result _n "=== Students per cohort, assigned, enrolled ==="
gen byte assigned = !missing(S_itt)
tab ao_proceso assigned
tab ao_proceso enrolled
tab enr_on_rol enr_feasible if enrolled

di as result _n "=== Number of feasible ROL programs (assigned students) ==="
tab n_feas if assigned

foreach p in port_bin port_ter port_enr {
    bysort `p': gen long size_`p' = _N if !missing(`p')
    di as result _n "=== `p': portfolios and students in portfolios with >= 2 members ==="
    distinct `p'
    count if size_`p' >= 2 & !missing(`p')
    drop size_`p'
}

compress
save "$processed/pva_students_2007_2016.dta", replace

log close
