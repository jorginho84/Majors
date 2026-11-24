/**********************************************************************
* 20_build_program_year_controls.do
*
* Program-year characteristics for the Design V balance and results (issue
* #10, 2026-11-17 meeting): candidate controls that vary at the
* program-year level and could explain the residual imbalance of
* Z_pt (more NEM, BEA and municipal-school students at equal PSU).
* One file, built once, so every balance specification draws on the
* same variables.
*
*   unit : program (codigo_carrera_harmonized, 5-digit DEMRE code;
*          pre-2012 XXYY -> XX0YY) x admission year, 2007-2016
*   blocks (prefix):
*     w_   admission rules (Oferta Academica): weights of NEM, ranking
*          (from 2013; 0 before), language, math, history, science;
*          minimum weighted score and minimum language+math; regular
*          vacancies, sobrecupo and BEA seats; dw_* = change vs t-1
*     d_   demand (Formulario C applications): applicants (any
*          preference), first-preference applicants, waiting list
*          (status 25), mean application score of first-preference
*          applicants; logs and t-1 values (applications are made
*          after the seats are published, so t values may respond to
*          Z: the t-1 values are the predetermined version)
*     m_   MINEDUC enrollment of the program-year (first-year and
*          continuing students): share in an accredited program,
*          share in an accredited institution, institutional
*          accreditation years, median tuition and enrollment fee,
*          share in day programs, formal duration; modal cod_inst
*     x_   market and university (Vacancy_shocks panel): exposure to
*          other programs' shocks (broad market, cosine), CRUCH,
*          state, SUA entrant 2012, region, first year with entrants
*     f_   university finances (SES, 02_build/17), by cod_inst x year,
*          FY 2013-2016 only: log expenses, capital (non-current
*          assets), academic salaries and overhead per undergraduate,
*          and log total expenses (per student at all levels:
*          undergraduate, graduate, postitulo); same in t-1 (FY 2013-2015)
*   Missing values are left missing (the balance script adds missing
*   indicators). Gratuidad (2016) is not included: no source here,
*   and university x year FE absorb it.
*
* Inputs:  $processed/oferta_academica_2007_2016_appended.dta
*          $processed/applications.dta
*          $mat_raw/Matrícula_Ed_Superior_YYYY.csv (2007-2016)
*          $processed/vs_panel_exposure.dta (Vacancy_shocks/03)
*          $processed/university_finance_panel.dta (02_build/17)
* Output:  $processed/program_year_controls_2007_2016.dta
**********************************************************************/

clear all
set more off
do "code/config.do"

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
* 1. Admission rules (Oferta Academica)
**********************************************************************/

use "$processed/oferta_academica_2007_2016_appended.dta", clear
replace PORC_RANKINK = 0 if missing(PORC_RANKINK) & ao_proceso < 2013
harmonize_code CODIGO codigo_carrera_harmonized
collapse (max) w_nem = PORC_NOTAS w_rank = PORC_RANKINK ///
    w_leng = PORC_LENGUAJE w_mat = PORC_MATEMATICA ///
    w_hist = PORC_HISTORIA w_cien = PORC_CIEN ///
    w_min_pond = MINIMO_PONDERADO w_min_lm = MINIMO_LEN_MAT ///
    w_vac = VACANTES_1SEM w_sobrecupo = SOBRECUPO_1SEM w_bea = CUPOS_BEA, ///
    by(codigo_carrera_harmonized ao_proceso)
* NEM + ranking: the school-record weight
gen double w_nemrank = w_nem + w_rank
xtset codigo_carrera_harmonized ao_proceso
foreach v in w_nem w_rank w_nemrank w_leng w_mat w_min_pond w_bea w_sobrecupo {
    gen double d`v' = D.`v'
}
tempfile rules
save `rules'

/**********************************************************************
* 2. Demand (applications)
**********************************************************************/

use codigo_carrera ao_proceso preferencia estado_preferencia application_score ///
    using "$processed/applications.dta", clear
harmonize_code codigo_carrera codigo_carrera_harmonized
gen byte one   = 1
gen byte pref1 = preferencia == 1
gen byte wait  = estado_preferencia == 25
gen double score1 = application_score if pref1
* applications.dta keeps the raw weighted score; some years are on a
* 1/100 scale (02_build/01-02 known issue): put them on the PSU scale
replace score1 = score1 * 100 if score1 < 100
collapse (sum) d_apps = one d_apps1 = pref1 d_wait = wait ///
    (mean) d_score1 = score1, by(codigo_carrera_harmonized ao_proceso)
foreach v in d_apps d_apps1 d_wait {
    gen double l`v' = ln(`v') if `v' > 0
}
xtset codigo_carrera_harmonized ao_proceso
foreach v in d_apps d_apps1 d_wait d_score1 ld_apps ld_apps1 ld_wait {
    gen double `v'_l1 = L.`v'
}
tempfile demand
save `demand'

/**********************************************************************
* 3. MINEDUC enrollment: accreditation, tuition, schedule, duration
**********************************************************************/

tempfile mat
local first 1
forvalues y = 2007/2016 {
    import delimited "$mat_raw/Matrícula_Ed_Superior_`y'.csv", ///
        delimiter(";") varnames(1) clear encoding(utf-8) stringcols(_all)
    rename *, lower
    keep codigo_demre cod_inst jornada dur_estudio_carr valor_matricula ///
        valor_arancel acreditada_carr acreditada_inst acre_inst_anio
    destring codigo_demre, replace force
    drop if missing(codigo_demre) | codigo_demre <= 0
    foreach v in cod_inst dur_estudio_carr valor_matricula valor_arancel acre_inst_anio {
        destring `v', replace force
    }
    foreach v in acreditada_carr acreditada_inst {
        replace `v' = ustrupper(strtrim(`v'))
        gen byte b_`v' = .
        replace b_`v' = 1 if strpos(`v', "ACREDITAD") & !strpos(`v', "NO ACRED")
        replace b_`v' = 0 if strpos(`v', "NO ACRED")
    }
    gen byte diurno = ustrupper(strtrim(jornada)) == "DIURNO" if jornada != ""
    replace valor_arancel   = . if valor_arancel <= 0
    replace valor_matricula = . if valor_matricula <= 0
    replace dur_estudio_carr = . if dur_estudio_carr <= 0
    gen int ao_proceso = `y'
    keep codigo_demre ao_proceso cod_inst b_acreditada_carr b_acreditada_inst ///
        acre_inst_anio valor_arancel valor_matricula diurno dur_estudio_carr
    if !`first' append using `mat'
    save `mat', replace
    local first 0
}
harmonize_code codigo_demre codigo_carrera_harmonized
gen byte one = 1
* modal institution code of the program-year (for the finance merge)
bysort codigo_carrera_harmonized ao_proceso cod_inst: gen long n_ci = _N
bysort codigo_carrera_harmonized ao_proceso (n_ci): gen int m_cod_inst = cod_inst[_N]
collapse (mean) m_acred_carr = b_acreditada_carr m_acred_inst = b_acreditada_inst ///
    m_acred_inst_years = acre_inst_anio m_diurno = diurno ///
    (p50) m_tuition = valor_arancel m_fee = valor_matricula m_duration = dur_estudio_carr ///
    (first) m_cod_inst (sum) m_students = one, by(codigo_carrera_harmonized ao_proceso)
foreach v in m_acred_carr m_acred_inst m_diurno {
    replace `v' = 100 * `v'
}
gen double m_ltuition = ln(m_tuition)
tempfile mineduc
save `mineduc'

/**********************************************************************
* 4. Market and university (Vacancy_shocks panel)
**********************************************************************/

use code_h ao_proceso E_tot_broad cumE_tot_broad E_cos_psu cumE_cos_psu ///
    cruch state entrant_2012 sua_incumbent region first_year_S ///
    using "$processed/vs_panel_exposure.dta", clear
rename code_h codigo_carrera_harmonized
rename (E_tot_broad cumE_tot_broad E_cos_psu cumE_cos_psu cruch state ///
    entrant_2012 sua_incumbent region first_year_S) ///
    (x_exp_broad x_cumexp_broad x_exp_cos x_cumexp_cos x_cruch x_state ///
    x_entrant2012 x_sua_incumbent x_region x_first_year)
gen int x_age = ao_proceso - x_first_year
duplicates drop codigo_carrera_harmonized ao_proceso, force
tempfile market
save `market'

/**********************************************************************
* 5. University finances (FY 2013-2016)
**********************************************************************/

use "$processed/university_finance_panel.dta", clear
gen double overhead = rem_adm + rem_dir + g_adm
* per student at all levels (undergraduate, graduate, postitulo): the
* statements cover every level, not only undergraduates (2026-11-19)
gen double f_lpc_exp     = ln(gasto_total / enr_all)
gen double f_lpc_capital = ln(act_nc / enr_all)
gen double f_lpc_acad    = ln(rem_acad / enr_all)
gen double f_lpc_ovh     = ln(overhead / enr_all)
gen double f_lexp        = ln(gasto_total)
xtset cod_inst fy
foreach v in f_lpc_exp f_lpc_capital f_lpc_acad f_lpc_ovh f_lexp {
    gen double `v'_l1 = L.`v'
}
keep cod_inst fy f_*
rename (cod_inst fy) (m_cod_inst ao_proceso)
keep if inrange(ao_proceso, 2007, 2016)
tempfile fin
save `fin'

/**********************************************************************
* 6. Merge and save
**********************************************************************/

use `rules', clear
foreach b in demand mineduc market {
    merge 1:1 codigo_carrera_harmonized ao_proceso using ``b'', keep(master match) gen(_m_`b')
}
merge m:1 m_cod_inst ao_proceso using `fin', keep(master match) gen(_m_fin)
keep if inrange(ao_proceso, 2007, 2016)

label variable w_nem        "Admission weight: NEM (%)"
label variable w_rank       "Admission weight: ranking (%; 0 before 2013)"
label variable w_nemrank    "Admission weight: NEM + ranking (%)"
label variable w_leng       "Admission weight: language (%)"
label variable w_mat        "Admission weight: math (%)"
label variable w_hist       "Admission weight: history (%)"
label variable w_cien       "Admission weight: science (%)"
label variable w_min_pond   "Minimum weighted score"
label variable w_min_lm     "Minimum language+math score"
label variable w_vac        "Regular vacancies, 1st semester"
label variable w_sobrecupo  "Sobrecupo, 1st semester"
label variable w_bea        "BEA seats"
label variable d_apps       "Applicants, any preference"
label variable d_apps1      "Applicants, first preference"
label variable d_wait       "Applicants on the waiting list"
label variable d_score1     "Mean application score, first-preference applicants"
label variable m_acred_carr "Students in an accredited program (%)"
label variable m_acred_inst "Students in an accredited institution (%)"
label variable m_acred_inst_years "Institutional accreditation years"
label variable m_tuition    "Median annual tuition (CLP, nominal)"
label variable m_fee        "Median enrollment fee (CLP, nominal)"
label variable m_diurno     "Students in day programs (%)"
label variable m_duration   "Formal duration (semesters)"
label variable m_cod_inst   "MINEDUC institution code (modal)"
label variable m_students   "MINEDUC enrollment of the program-year"
label variable x_exp_broad  "Exposure to other programs' shocks, broad market"
label variable x_exp_cos    "Exposure to other programs' shocks, cosine"
label variable x_age        "Years since first year with entrants (from 2007)"
label variable f_lpc_exp    "University: log expenses per student (all levels)"
label variable f_lpc_capital "University: log non-current assets per student (all levels)"
label variable f_lpc_acad   "University: log academic salaries per student (all levels)"
label variable f_lpc_ovh    "University: log overhead per student (all levels)"
label variable f_lexp       "University: log total expenses"

* coverage by year
foreach v in w_nem d_apps m_acred_carr m_tuition x_exp_broad f_lpc_exp f_lpc_exp_l1 {
    quietly gen byte c_`v' = !missing(`v')
}
tabstat c_*, by(ao_proceso) stat(mean) format(%5.2f)
drop c_*
tabstat w_nem w_rank w_nemrank d_apps1 d_score1 m_acred_carr m_acred_inst ///
    m_tuition m_diurno m_duration x_exp_broad x_age f_lpc_exp, ///
    by(ao_proceso) stat(mean) format(%9.2f)

compress
save "$processed/program_year_controls_2007_2016.dta", replace
di as result "20_build_program_year_controls.do finished."
