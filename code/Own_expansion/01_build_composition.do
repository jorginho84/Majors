/**********************************************************************
* 01_build_composition.do
*
* Composition of the entering cohort, program x year, 2007-2016.
* Dependent variables for the composition exercises of Designs I-IV
* (issue #3).
*
* Entrants: first-year enrollees in Formulario D (vs_first_year_students
* keeps those with LM PSU; here all entrants are rebuilt so that the
* non-PSU characteristics use every entrant).
*
* Per program-year (code_h = harmonized DEMRE code, as in Vacancy_shocks):
*   c_psu_mean    mean LM PSU of entrants
*   c_psu_sd      SD of LM PSU of entrants
*   c_nem_mean    mean NEM score of entrants
*   c_female      share female (COD_SEXO, Formulario A)
*   c_priv        share from private-paid schools (GRUPO_DEPENDENCIA)
*   c_mun         share from municipal schools
*   c_psu_last    LM PSU of the last admitted (lowest application score
*                 among regular admits, status 24)
*   c_priv_last   private-paid school, last admitted
*
* Income is not available: Formulario A has no income and the DEMRE
* socioeconomic questionnaire is not in data/. School dependency is the
* SES proxy.
*
* Inputs:
*   $psu_raw/A_INSCRITOS_PUNTAJES_PSU_YYYY_PRIV_MRUN.csv
*   $demre_raw/D_MATRICULA_YYYY_PSU_MRUN.csv
*   $processed/psu_scores.dta, applications.dta
*
* Output:
*   $processed/oe_composition_program_year.dta
**********************************************************************/

do "code/config.do"

global oe_out "$output/own_expansion"
cap mkdir "$oe_out"
cap mkdir "$oe_out/tables"
cap mkdir "$oe_out/figures"

tempfile demo psu fd last

capture program drop harmonize_code
program define harmonize_code
    * 4-digit pre-2012 DEMRE code XXYY -> XX0YY
    syntax varname, Generate(name)
    tempvar s
    gen str12 `s' = strtrim(string(`varlist', "%12.0f"))
    gen long `generate' = `varlist'
    replace `generate' = real(substr(`s', 1, 2) + "0" + substr(`s', 3, 2)) ///
        if length(`s') == 4
end


/**********************************************************************
* 1. Sex and school dependency, Formulario A
**********************************************************************/

forvalues y = 2007/2016 {
    import delimited "$psu_raw/A_INSCRITOS_PUNTAJES_PSU_`y'_PRIV_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(windows-1252) ///
        stringcols(_all)
    rename *, lower
    keep mrun cod_sexo grupo_dependencia
    destring mrun cod_sexo grupo_dependencia, replace force
    gen ao_proceso = `y'
    if `y' > 2007 append using `demo'
    save `demo', replace
}
drop if missing(mrun)
duplicates drop mrun ao_proceso, force

di as text _n "Codes in Formulario A"
tab cod_sexo, missing
tab grupo_dependencia, missing

save `demo', replace


/**********************************************************************
* 2. PSU (LM average; current score, else previous) and NEM
**********************************************************************/

use mrun ao_proceso lyc_actual mate_actual lyc_anterior mate_anterior ptje_nem ///
    using "$processed/psu_scores.dta", clear
keep if inrange(ao_proceso, 2007, 2016)
gen double psu_lm = (lyc_actual + mate_actual) / 2 ///
    if inrange(lyc_actual, 150, 850) & inrange(mate_actual, 150, 850)
replace psu_lm = (lyc_anterior + mate_anterior) / 2 ///
    if missing(psu_lm) & inrange(lyc_anterior, 150, 850) & inrange(mate_anterior, 150, 850)
gen double nem = ptje_nem if inrange(ptje_nem, 150, 850)
keep mrun ao_proceso psu_lm nem
duplicates drop mrun ao_proceso, force
merge 1:1 mrun ao_proceso using `demo', keep(master match using) nogen

* Check the code mapping before using it: private-paid schools have the
* highest mean PSU, and the sex code should split roughly evenly
di as text _n "Mean LM PSU by school dependency and by sex code"
tabstat psu_lm, by(grupo_dependencia) statistics(n mean) format(%9.1f)
tabstat psu_lm, by(cod_sexo) statistics(n mean) format(%9.1f)

gen byte female = cod_sexo == 2 if inlist(cod_sexo, 1, 2)
* DEMRE GRUPO_DEPENDENCIA: 1 municipal corporation, 2 municipal (DAEM),
* 3 private subsidized, 4 private paid, 5 delegated administration.
* Verified in the log: code 4 has the highest mean PSU (~607) and ~10% of takers.
gen byte priv   = grupo_dependencia == 4 if inrange(grupo_dependencia, 1, 5)
gen byte mun    = inlist(grupo_dependencia, 1, 2) if inrange(grupo_dependencia, 1, 5)
keep mrun ao_proceso psu_lm nem female priv mun
save `psu'


/**********************************************************************
* 3. Entrants (Formulario D) -> program-year means
**********************************************************************/

forvalues y = 2007/2016 {
    import delimited "$demre_raw/D_MATRICULA_`y'_PSU_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(windows-1252)
    rename *, lower
    foreach v in mrun codigo_carrera {
        capture confirm numeric variable `v'
        if _rc destring `v', replace force
    }
    gen ao_proceso = `y'
    keep mrun ao_proceso codigo_carrera
    drop if missing(codigo_carrera)
    if `y' > 2007 append using `fd'
    save `fd', replace
}

merge m:1 mrun ao_proceso using `psu', keep(master match) nogen
harmonize_code codigo_carrera, generate(code_h)

collapse (mean) c_psu_mean = psu_lm (sd) c_psu_sd = psu_lm ///
         (mean) c_nem_mean = nem c_female = female c_priv = priv c_mun = mun ///
         (count) c_n_psu = psu_lm, ///
         by(code_h ao_proceso)
save `fd', replace


/**********************************************************************
* 4. Last admitted (regular admission, status 24)
**********************************************************************/

use mrun ao_proceso codigo_carrera estado_preferencia application_score ///
    using "$processed/applications.dta", clear
keep if estado_preferencia == $admitted & !missing(application_score)
keep if inrange(ao_proceso, 2007, 2016)
harmonize_code codigo_carrera, generate(code_h)
bys code_h ao_proceso: egen double min_score = min(application_score)
keep if application_score == min_score
merge m:1 mrun ao_proceso using `psu', keep(master match) nogen keepusing(psu_lm priv)
* ties at the last score: average over them
collapse (mean) c_psu_last = psu_lm c_priv_last = priv, by(code_h ao_proceso)
save `last'


/**********************************************************************
* 5. Assemble
**********************************************************************/

use `fd', clear
merge 1:1 code_h ao_proceso using `last', nogen

* shares in percentage points
foreach v in c_female c_priv c_mun c_priv_last {
    replace `v' = 100 * `v'
}

label var c_psu_mean  "Mean LM PSU, entrants"
label var c_psu_sd    "SD of LM PSU, entrants"
label var c_nem_mean  "Mean NEM, entrants"
label var c_female    "Female, entrants, pct."
label var c_priv      "Private-paid school, entrants, pct."
label var c_mun       "Municipal school, entrants, pct."
label var c_n_psu     "Entrants with LM PSU"
label var c_psu_last  "LM PSU of the last admitted"
label var c_priv_last "Private-paid school, last admitted, pct."

* SD needs at least 5 entrants with PSU to be meaningful
replace c_psu_sd = . if c_n_psu < 5

compress
sort code_h ao_proceso
isid code_h ao_proceso
save "$processed/oe_composition_program_year.dta", replace

di as text _n "Composition variables, all program-years"
summarize c_*

di as result "oe_composition_program_year.dta saved."
