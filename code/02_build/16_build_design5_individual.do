/**********************************************************************
* 16_build_design5_individual.do
*
* Design V (issue #8): individual-level base for the inframarginal
* design with application-portfolio (ROL) fixed effects.
*
* Unit: inframarginal application (i, p, t), same definition as Design I
* (04_rdd/Inframarginals/21b): lugar <= T_p, T_p = enrolled size of the
* program's first observed cohort (infra_first_enroll). All such rows are
* kept here, with flags, so the one-row-per-student rule is chosen in the
* analysis scripts, not baked in:
*   pick_admit   status 24 at p (the program the student was assigned to)
*   pick_toppref most preferred inframarginal application of i in year t
*   first_year_i first year in which i appears as inframarginal (retakers)
*
* Program-year variables (from the Design I panel, so the first stage is
* the same object): N_total_enter (entering cohort, n), Z_total_cupos (Z).
*
* ROL identifiers, built from the full application list in
* applications.dta with harmonized 5-digit program codes, so that the same
* list is the same ROL before and after 2012:
*   rol_exact   ordered list of programs
*   rol_set     unordered set of programs
*   rol_top1    first preference
*   rol_top2    first two preferences, ordered
*   rol_top3    first three preferences, ordered
*   rol_univ    unordered set of universities
*   rol_top1u   first preference + unordered set of universities
*
* Controls: PSU (mean language+math, current or previous), NEM, female,
* school dependency (private-paid, municipal), from Formulario A.
*
* Inputs:  $processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta
*          $processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_first_enroll.dta
*          $processed/applications.dta
*          $psu_raw/A_INSCRITOS_PUNTAJES_PSU_YYYY_PRIV_MRUN.csv
* Output:  $processed/design5_individual_2007_2016.dta
**********************************************************************/

clear all
set more off
do "code/config.do"

local master "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta"
local panel  "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_first_enroll.dta"

* 4-digit DEMRE codes (pre-2012) -> 5-digit format, as in 21b
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
* 1. Sex and school dependency, Formulario A
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
* GRUPO_DEPENDENCIA: 1 municipal corp., 2 municipal (DAEM),
* 3 private subsidized, 4 private paid, 5 delegated administration
gen byte female = cod_sexo == 2 if inlist(cod_sexo, 1, 2)
gen byte priv   = grupo_dependencia == 4 if inrange(grupo_dependencia, 1, 5)
gen byte mun    = inlist(grupo_dependencia, 1, 2) if inrange(grupo_dependencia, 1, 5)
gen byte dep    = grupo_dependencia if inrange(grupo_dependencia, 1, 5)
keep mrun ao_proceso female priv mun dep
save `demo', replace

/**********************************************************************
* 2. ROL identifiers from the full application list
**********************************************************************/

use mrun ao_proceso preferencia codigo_carrera sigla_universidad ///
    using "$processed/applications.dta", clear
keep if inrange(ao_proceso, 2007, 2016)
capture confirm numeric variable codigo_carrera
if _rc destring codigo_carrera, replace force
harmonize_code codigo_carrera code_h
replace sigla_universidad = upper(strtrim(sigla_universidad))
drop if missing(mrun, code_h, preferencia)
duplicates drop mrun ao_proceso code_h, force
bysort mrun ao_proceso (preferencia): gen byte k = _n
bysort mrun ao_proceso: gen byte n_apps = _N

gen str6 c = string(code_h, "%06.0f")

* ordered: running concatenation along preferences (max 10 x 7 chars)
gen str244 s_exact = ""
bysort mrun ao_proceso (k): replace s_exact = cond(_n == 1, c, s_exact[_n-1] + "-" + c)
gen str20 s_top1 = c if k == 1
gen str244 s_top2 = s_exact if k == min(2, n_apps)
gen str244 s_top3 = s_exact if k == min(3, n_apps)

* unordered set of programs: same, sorted by code
gen str244 s_set = ""
bysort mrun ao_proceso (code_h): replace s_set = cond(_n == 1, c, s_set[_n-1] + "-" + c)

* unordered set of universities: unique siglas, sorted
bysort mrun ao_proceso sigla_universidad: gen byte first_u = _n == 1
gen str244 s_univ = ""
bysort mrun ao_proceso (first_u sigla_universidad): replace s_univ = ///
    cond(!first_u, "", cond(s_univ[_n-1] == "", sigla_universidad, ///
    s_univ[_n-1] + "-" + sigla_universidad)) if _n > 1 | first_u
* rows with first_u == 0 sort first and stay empty; the chain starts at the
* first unique sigla

* spread the complete string to every row of i-t
foreach s in exact top1 top2 top3 set univ {
    bysort mrun ao_proceso (s_`s'): replace s_`s' = s_`s'[_N]
}
gen str244 s_top1u = s_top1 + "|" + s_univ

keep mrun ao_proceso n_apps s_exact s_set s_top1 s_top2 s_top3 s_univ s_top1u
bysort mrun ao_proceso: keep if _n == 1

foreach s in exact set top1 top2 top3 univ top1u {
    egen long rol_`s' = group(s_`s')
}
drop s_*
label var n_apps    "Number of applications in the ROL"
label var rol_exact "ROL: ordered list of programs"
label var rol_set   "ROL: unordered set of programs"
label var rol_top1  "ROL: first preference"
label var rol_top2  "ROL: first two preferences"
label var rol_top3  "ROL: first three preferences"
label var rol_univ  "ROL: set of universities"
label var rol_top1u "ROL: first preference + set of universities"
tempfile rol
save `rol'

/**********************************************************************
* 3. Inframarginal applications, Design I definition
**********************************************************************/

use mrun ao_proceso preferencia estado_preferencia sigla_universidad ///
    codigo_carrera_harmonized program_id_rank_analysis lugar ///
    threshold_first_enroll infra_first_enroll infra_min_enroll ///
    enrolls_target graduates_enrolled_program_8y graduates_uni_8y ///
    graduates_he_8y graduates_target_8y ///
    lyc_actual mate_actual lyc_anterior mate_anterior ptje_nem field ///
    using "`master'", clear
keep if infra_first_enroll == 1

* PSU language+math: best of current and previous, as DEMRE allows
gen double psu_lm = max((lyc_actual + mate_actual) / 2, ///
                        (lyc_anterior + mate_anterior) / 2)
replace psu_lm = . if psu_lm == 0
rename ptje_nem nem
replace nem = . if nem == 0
drop lyc_* mate_*

* one-row rules (applied later)
gen byte pick_admit = estado_preferencia == $admitted
bysort mrun ao_proceso (preferencia): gen byte pick_toppref = _n == 1
bysort mrun ao_proceso: gen byte n_infra_it = _N
bysort mrun: egen int first_year_i = min(ao_proceso)

merge m:1 mrun ao_proceso using `demo', keep(master match) nogen
merge m:1 mrun ao_proceso using `rol', keep(master match) gen(_m_rol)

* program-year n and Z, as in Design I
merge m:1 program_id_rank_analysis ao_proceso using "`panel'", ///
    keepusing(N_total_enter Z_total_cupos N_infra_enter) ///
    keep(master match) gen(_m_panel)

label var pick_admit   "Admitted (24) at p"
label var pick_toppref "Most preferred infra application of i in t"
label var n_infra_it   "Infra applications of i in t"
label var first_year_i "First year i is inframarginal"
label var psu_lm       "PSU language+math (best of current/previous)"

compress
save "$processed/design5_individual_2007_2016.dta", replace
di as result "design5_individual_2007_2016.dta saved."
