/**********************************************************************
* 25_program_selectivity_group_heterogeneity.do
*
* Objetivo:
*   Estimar first stage, reduced form y 2SLS por grupos de selectividad
*   del programa.
*
* Grupos:
*   1. Mean PSU < 550
*   2. Mean PSU 550--599.999
*   3. Mean PSU 600--649.999
*   4. Mean PSU >= 650
*
* Definiciones inframarginales:
*   - First Cohort
*   - Minimum Cohort
*
* Inputs:
*   $processed/program_selectivity_2007_2016.dta
*
*   $processed/
*   inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_
*   first_enroll.dta
*
*   $processed/
*   inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_
*   min_enroll.dta
*
* Outputs:
*   $processed/program_selectivity_group_results.dta
*   $processed/program_selectivity_group_results.csv
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local selectivity_file ///
    "$processed/program_selectivity_2007_2016.dta"

local panelprefix ///
    "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016"

local output_dta ///
    "$processed/program_selectivity_group_results.dta"

local output_csv ///
    "$processed/program_selectivity_group_results.csv"

**********************************************************************
* 0. Verificar archivos
**********************************************************************/

capture confirm file "`selectivity_file'"
if _rc != 0 {
    di as error "No existe: `selectivity_file'"
    exit 601
}

foreach def in first_enroll min_enroll {

    local panel "`panelprefix'_`def'.dta"

    capture confirm file "`panel'"
    if _rc != 0 {
        di as error "No existe: `panel'"
        exit 601
    }
}

**********************************************************************
* 1. Preparar clasificación fija de programas
**********************************************************************/

use "`selectivity_file'", clear

foreach v in ///
    program_id_rank_analysis ///
    sigla_universidad ///
    codigo_carrera_harmonized ///
    mean_psu_program {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable en selectivity_file: `v'"
        exit 111
    }
}

* Una fila por programa.
isid program_id_rank_analysis

capture drop selectivity_group

gen byte selectivity_group = .

replace selectivity_group = 1 ///
    if mean_psu_program < 550

replace selectivity_group = 2 ///
    if mean_psu_program >= 550 ///
    & mean_psu_program < 600

replace selectivity_group = 3 ///
    if mean_psu_program >= 600 ///
    & mean_psu_program < 650

replace selectivity_group = 4 ///
    if mean_psu_program >= 650 ///
    & !missing(mean_psu_program)

label define selectivity_group_lbl ///
    1 "PSU < 550" ///
    2 "PSU 550--600" ///
    3 "PSU 600--650" ///
    4 "PSU 650+"

label values selectivity_group selectivity_group_lbl

drop if missing(selectivity_group)

tab selectivity_group

keep ///
    program_id_rank_analysis ///
    sigla_universidad ///
    codigo_carrera_harmonized ///
    mean_psu_program ///
    selectivity_group

tempfile selectivity_groups
save `selectivity_groups', replace

**********************************************************************
* 2. Crear archivo para guardar resultados
**********************************************************************/

capture postclose results

postfile results ///
    str20 definition ///
    str35 definition_label ///
    byte selectivity_group ///
    str20 selectivity_label ///
    double mean_psu ///
    double programs ///
    double fd_obs ///
    double fs_coef ///
    double fs_se ///
    double fs_p ///
    double fs_F ///
    double rf_coef ///
    double rf_se ///
    double rf_p ///
    double iv_coef ///
    double iv_se ///
    double iv_p ///
    using "`c(tmpdir)'/program_selectivity_group_results_tmp.dta", ///
    replace

**********************************************************************
* 3. Loop por definición de inframarginales
**********************************************************************/

foreach def in first_enroll min_enroll {

    local panel "`panelprefix'_`def'.dta"

    if "`def'" == "first_enroll" {
        local deflabel "First Cohort"
    }

    if "`def'" == "min_enroll" {
        local deflabel "Minimum Cohort"
    }

    use "`panel'", clear

    foreach v in ///
        program_id_rank_analysis ///
        ao_proceso ///
        D_N_total_enter ///
        D_Z_total_cupos ///
        D_grad_enrolled_program_rate_8y ///
        avg_N_total_enter ///
        avg_N_infra_enter ///
        sample_firststage ///
        sample_iv {

        capture confirm variable `v'

        if _rc != 0 {
            di as error "Falta variable en `panel': `v'"
            exit 111
        }
    }

    merge m:1 program_id_rank_analysis ///
        using `selectivity_groups', ///
        keep(master match)

    tab _merge, missing

    count if _merge == 1
    di as result ///
        "Programas-año sin clasificación de selectividad: " r(N)

    keep if _merge == 3
    drop _merge

    ******************************************************************
    * 4. Loop por grupo de selectividad
    ******************************************************************

    foreach g in 1 2 3 4 {

        preserve

            keep if selectivity_group == `g'

            if `g' == 1 local glabel "PSU < 550"
            if `g' == 2 local glabel "PSU 550--600"
            if `g' == 3 local glabel "PSU 600--650"
            if `g' == 4 local glabel "PSU 650+"

            di as text "=================================================="
            di as result "`deflabel' | `glabel'"
            di as text "=================================================="

            **********************************************************
            * Descriptivos del grupo
            **********************************************************

            summarize mean_psu_program, meanonly
            local mean_psu = r(mean)

            distinct program_id_rank_analysis if sample_iv == 1
            local programs = r(ndistinct)

            count if sample_iv == 1
            local fd_obs = r(N)

            di as result "Mean PSU: " %9.2f `mean_psu'
            di as result "Programs: " %9.0fc `programs'
            di as result "FD observations: " %9.0fc `fd_obs'

            if `programs' < 10 | `fd_obs' < 30 {

                di as error ///
                    "Muy pocas observaciones para estimar este grupo."

                restore
                continue
            }

            **********************************************************
            * First stage
            *
            * Delta enrollment on delta vacancies.
            **********************************************************

            quietly reg ///
                D_N_total_enter ///
                D_Z_total_cupos ///
                i.ao_proceso ///
                [aw = avg_N_total_enter] ///
                if sample_firststage == 1, ///
                vce(cluster program_id_rank_analysis)

            local fs_coef = _b[D_Z_total_cupos]
            local fs_se   = _se[D_Z_total_cupos]
            local fs_p    = 2 * ttail(e(df_r), ///
                abs(`fs_coef' / `fs_se'))

            quietly test D_Z_total_cupos = 0
            local fs_F = r(F)

            **********************************************************
            * Reduced form
            *
            * Delta graduation rate on delta vacancies.
            **********************************************************

            quietly reg ///
                D_grad_enrolled_program_rate_8y ///
                D_Z_total_cupos ///
                i.ao_proceso ///
                [aw = avg_N_infra_enter] ///
                if sample_iv == 1, ///
                vce(cluster program_id_rank_analysis)

            local rf_coef = _b[D_Z_total_cupos]
            local rf_se   = _se[D_Z_total_cupos]
            local rf_p    = 2 * ttail(e(df_r), ///
                abs(`rf_coef' / `rf_se'))

            **********************************************************
            * 2SLS
            *
            * Delta total enrollment instrumented with delta vacancies.
            **********************************************************

            quietly ivregress 2sls ///
                D_grad_enrolled_program_rate_8y ///
                i.ao_proceso ///
                (D_N_total_enter = D_Z_total_cupos) ///
                [aw = avg_N_infra_enter] ///
                if sample_iv == 1, ///
                vce(cluster program_id_rank_analysis)

            local iv_coef = _b[D_N_total_enter]
            local iv_se   = _se[D_N_total_enter]
            local iv_p    = 2 * normal( ///
                -abs(`iv_coef' / `iv_se') ///
            )

            **********************************************************
            * Mostrar resultados
            **********************************************************

            di as result ///
                "First stage: " %9.5f `fs_coef' ///
                " (" %9.5f `fs_se' "), F = " %8.2f `fs_F'

            di as result ///
                "Reduced form: " %9.5f `rf_coef' ///
                " (" %9.5f `rf_se' ")"

            di as result ///
                "2SLS: " %9.5f `iv_coef' ///
                " (" %9.5f `iv_se' "), p = " %6.3f `iv_p'

            **********************************************************
            * Guardar fila
            **********************************************************

            post results ///
                ("`def'") ///
                ("`deflabel'") ///
                (`g') ///
                ("`glabel'") ///
                (`mean_psu') ///
                (`programs') ///
                (`fd_obs') ///
                (`fs_coef') ///
                (`fs_se') ///
                (`fs_p') ///
                (`fs_F') ///
                (`rf_coef') ///
                (`rf_se') ///
                (`rf_p') ///
                (`iv_coef') ///
                (`iv_se') ///
                (`iv_p')

        restore
    }
}

postclose results

**********************************************************************
* 5. Abrir y ordenar resultados
**********************************************************************/

use "`c(tmpdir)'/program_selectivity_group_results_tmp.dta", clear

sort definition selectivity_group

format mean_psu %9.1f
format programs fd_obs %9.0fc

format ///
    fs_coef ///
    fs_se ///
    rf_coef ///
    rf_se ///
    iv_coef ///
    iv_se ///
    %9.5f

format fs_F %9.1f

format ///
    fs_p ///
    rf_p ///
    iv_p ///
    %9.3f

order ///
    definition ///
    definition_label ///
    selectivity_group ///
    selectivity_label ///
    mean_psu ///
    programs ///
    fd_obs ///
    fs_coef ///
    fs_se ///
    fs_F ///
    rf_coef ///
    rf_se ///
    iv_coef ///
    iv_se ///
    iv_p

list, sepby(definition) noobs clean

**********************************************************************
* 6. Guardar resultados
**********************************************************************/

save "`output_dta'", replace

export delimited using "`output_csv'", replace

di as text "=================================================="
di as result "Finished program-selectivity heterogeneity."
di as result "Results saved:"
di as result "`output_dta'"
di as result "`output_csv'"
di as text "=================================================="