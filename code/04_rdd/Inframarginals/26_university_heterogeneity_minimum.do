/**********************************************************************
*  
*
* Objetivo:
*   Estimar first stage y 2SLS para seis universidades seleccionadas,
*   usando la definición Minimum Cohort de inframarginales.
*
* Universidades:
*   Más selectivas:
*       UC, UCH, USACH
*
*   Menos selectivas:
*       UPA, UCSC, UBB
*
* Outcome:
*   Graduación dentro de 8 años del programa en que el estudiante
*   se matriculó inicialmente.
*
* Outputs:
*   $processed/university_heterogeneity_minimum_cohort.dta
*   $processed/university_heterogeneity_minimum_cohort.csv
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local panel ///
    "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_min_enroll.dta"

local master_base ///
    "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta"

local output_dta ///
    "$processed/university_heterogeneity_minimum_cohort.dta"

local output_csv ///
    "$processed/university_heterogeneity_minimum_cohort.csv"


/**********************************************************************
* 0. Verificar archivos
**********************************************************************/

foreach f in "`panel'" "`master_base'" {

    capture confirm file "`f'"

    if _rc != 0 {
        di as error "No existe el archivo requerido:"
        di as error "`f'"
        exit 601
    }
}


/**********************************************************************
* 1. Construir PSU promedio por universidad
*
* PSU promedio Lenguaje-Matemática entre estudiantes que se
* matricularon efectivamente en su programa target, 2007--2016.
**********************************************************************/

use "`master_base'", clear

keep if inrange(ao_proceso, 2007, 2016)
keep if enrolls_target == 1

foreach v in sigla_universidad lyc_actual mate_actual {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable en master_base: `v'"
        exit 111
    }
}

replace sigla_universidad = upper(strtrim(sigla_universidad))

capture drop psu_lm

capture confirm variable promlm_actual

if _rc == 0 {

    capture drop promlm_num

    destring promlm_actual, gen(promlm_num) force

    gen double psu_lm = promlm_num

    replace psu_lm = (lyc_actual + mate_actual) / 2 ///
        if missing(psu_lm) ///
        & !missing(lyc_actual, mate_actual)

    drop promlm_num
}
else {

    gen double psu_lm = (lyc_actual + mate_actual) / 2 ///
        if !missing(lyc_actual, mate_actual)
}

drop if missing(psu_lm)

collapse (mean) mean_psu = psu_lm, ///
    by(sigla_universidad)

isid sigla_universidad

tempfile university_psu
save `university_psu', replace


/**********************************************************************
* 2. Abrir panel Minimum Cohort
**********************************************************************/

use "`panel'", clear

foreach v in ///
    program_id_rank_analysis ///
    sigla_universidad ///
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
        di as error "Falta variable en el panel Minimum Cohort: `v'"
        exit 111
    }
}

replace sigla_universidad = upper(strtrim(sigla_universidad))

merge m:1 sigla_universidad using `university_psu', ///
    keep(master match)

tab _merge, missing

count if _merge == 1
di as result "Observaciones sin PSU promedio: " r(N)

keep if _merge == 3
drop _merge


/**********************************************************************
* 3. Mantener las seis universidades seleccionadas
**********************************************************************/

keep if inlist(sigla_universidad, ///
    "UC", ///
    "UCH", ///
    "USACH", ///
    "UPA", ///
    "UCSC", ///
    "UBB")

count

if r(N) == 0 {
    di as error "No quedaron observaciones para las universidades seleccionadas."
    exit 2000
}


/**********************************************************************
* 4. Archivo para resultados
**********************************************************************/

capture postclose results

postfile results ///
    str8 university ///
    str45 university_name ///
    byte selectivity_group ///
    str25 selectivity_label ///
    double mean_psu ///
    double programs ///
    double fd_obs ///
    double fs_coef ///
    double fs_se ///
    double fs_p ///
    double fs_F ///
    double iv_coef ///
    double iv_se ///
    double iv_p ///
    using "`c(tmpdir)'/university_minimum_results_tmp.dta", ///
    replace


/**********************************************************************
* 5. Loop por universidad
**********************************************************************/

foreach u in UC UCH USACH UPA UCSC UBB {

    preserve

        keep if sigla_universidad == "`u'"

        local uname ""
        local group = .
        local grouplabel ""

        if "`u'" == "UC" {
            local uname "Pontificia Universidad Catolica"
            local group = 1
            local grouplabel "High selectivity"
        }

        if "`u'" == "UCH" {
            local uname "Universidad de Chile"
            local group = 1
            local grouplabel "High selectivity"
        }

        if "`u'" == "USACH" {
            local uname "Universidad de Santiago"
            local group = 1
            local grouplabel "High selectivity"
        }

        if "`u'" == "UPA" {
            local uname "Universidad de Playa Ancha"
            local group = 2
            local grouplabel "Lower selectivity"
        }

        if "`u'" == "UCSC" {
            local uname "Universidad Catolica de Concepcion"
            local group = 2
            local grouplabel "Lower selectivity"
        }

        if "`u'" == "UBB" {
            local uname "Universidad del Bio-Bio"
            local group = 2
            local grouplabel "Lower selectivity"
        }


        /**************************************************************
        * Descriptivos
        **************************************************************/

        summarize mean_psu, meanonly
        local university_mean_psu = r(mean)

        distinct program_id_rank_analysis if sample_iv == 1
        local programs = r(ndistinct)

        count if sample_iv == 1
        local fd_obs = r(N)

        di as text "=================================================="
        di as result "`uname' | Minimum Cohort"
        di as text "=================================================="

        di as result "Mean PSU: " %9.1f `university_mean_psu'
        di as result "Programs: " %9.0fc `programs'
        di as result "FD observations: " %9.0fc `fd_obs'

        if `programs' < 3 | `fd_obs' < 20 {

            di as error "Muy pocas observaciones para estimar `u'."

            restore
            continue
        }


        /**************************************************************
        * First stage
        *
        * Delta enrollment on delta vacancies.
        **************************************************************/

        quietly reg ///
            D_N_total_enter ///
            D_Z_total_cupos ///
            i.ao_proceso ///
            [aw = avg_N_total_enter] ///
            if sample_firststage == 1, ///
            vce(cluster program_id_rank_analysis)

        local fs_coef = _b[D_Z_total_cupos]
        local fs_se   = _se[D_Z_total_cupos]

        local fs_p = 2 * ttail( ///
            e(df_r), ///
            abs(`fs_coef' / `fs_se') ///
        )

        quietly test D_Z_total_cupos = 0
        local fs_F = r(F)


        /**************************************************************
        * 2SLS
        *
        * Delta total enrollment instrumented by delta vacancies.
        **************************************************************/

        quietly ivregress 2sls ///
            D_grad_enrolled_program_rate_8y ///
            i.ao_proceso ///
            (D_N_total_enter = D_Z_total_cupos) ///
            [aw = avg_N_infra_enter] ///
            if sample_iv == 1, ///
            vce(cluster program_id_rank_analysis)

        local iv_coef = _b[D_N_total_enter]
        local iv_se   = _se[D_N_total_enter]

        local iv_p = 2 * normal( ///
            -abs(`iv_coef' / `iv_se') ///
        )


        /**************************************************************
        * Mostrar resultados
        **************************************************************/

        di as result ///
            "First stage: " %9.5f `fs_coef' ///
            " (" %9.5f `fs_se' ")" ///
            " | F = " %9.1f `fs_F'

        di as result ///
            "2SLS: " %9.5f `iv_coef' ///
            " (" %9.5f `iv_se' ")" ///
            " | p = " %6.3f `iv_p'


        /**************************************************************
        * Guardar resultados
        **************************************************************/

        post results ///
            ("`u'") ///
            ("`uname'") ///
            (`group') ///
            ("`grouplabel'") ///
            (`university_mean_psu') ///
            (`programs') ///
            (`fd_obs') ///
            (`fs_coef') ///
            (`fs_se') ///
            (`fs_p') ///
            (`fs_F') ///
            (`iv_coef') ///
            (`iv_se') ///
            (`iv_p')

    restore
}

postclose results


/**********************************************************************
* 6. Abrir, ordenar y guardar resultados
**********************************************************************/

use "`c(tmpdir)'/university_minimum_results_tmp.dta", clear

gen university_order = .

replace university_order = 1 if university == "UC"
replace university_order = 2 if university == "UCH"
replace university_order = 3 if university == "USACH"
replace university_order = 4 if university == "UPA"
replace university_order = 5 if university == "UCSC"
replace university_order = 6 if university == "UBB"

sort selectivity_group university_order

format mean_psu %9.1f
format programs fd_obs %9.0fc

format ///
    fs_coef ///
    fs_se ///
    iv_coef ///
    iv_se ///
    %9.5f

format fs_F %9.1f
format fs_p iv_p %9.3f

order ///
    selectivity_group ///
    selectivity_label ///
    university_order ///
    university ///
    university_name ///
    mean_psu ///
    programs ///
    fd_obs ///
    fs_coef ///
    fs_se ///
    fs_F ///
    iv_coef ///
    iv_se ///
    iv_p

list, sepby(selectivity_group) noobs clean

save "`output_dta'", replace

export delimited using "`output_csv'", replace

di as text "=================================================="
di as result "Minimum Cohort university exercise completed."
di as result "DTA: `output_dta'"
di as result "CSV: `output_csv'"
di as text "=================================================="