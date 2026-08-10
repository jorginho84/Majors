/**********************************************************************
* 28b_inframarginal_panel_grad8y10y.do
*
* Objetivo:
*
*   Replicar la arquitectura del panel inframarginal de 8 años,
*   pero comparar graduación a 8 y 10 años en las cohortes 2007--2014.
*
* Definiciones:
*
*   - First Cohort
*   - Minimum Cohort
*
* Merge de vacantes:
*
*   ao_proceso + codigo_carrera_harmonized
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


/**********************************************************************
* 0. Rutas
**********************************************************************/

local master ///
    "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2014_grad8y10y.dta"

local vacancies_file ///
    "$processed/program_year_vacancies_2007_2016.dta"

local results_dta ///
    "$processed/inframarginal_grad8y_vs_10y_2007_2014_results.dta"

local results_csv ///
    "$processed/inframarginal_grad8y_vs_10y_2007_2014_results.csv"


/**********************************************************************
* 0.1. Verificar archivos
**********************************************************************/

foreach f in "`master'" "`vacancies_file'" {

    capture confirm file "`f'"

    if _rc != 0 {
        di as error "No existe el archivo:"
        di as error "`f'"
        exit 601
    }
}


/**********************************************************************
***********************************************************************
* PARTE A
* PREPARAR BASE DE VACANTES
***********************************************************************
**********************************************************************/

use "`vacancies_file'", clear

keep if inrange(ao_proceso, 2007, 2014)


/**********************************************************************
* A.1. Detectar código de carrera
**********************************************************************/

local vacancy_code ""

foreach candidate in ///
    t_codigo_carrera ///
    codigo_carrera ///
    codigo_carrera_harmonized {

    capture confirm variable `candidate'

    if _rc == 0 & "`vacancy_code'" == "" {
        local vacancy_code "`candidate'"
    }
}


if "`vacancy_code'" == "" {

    di as error ///
        "No se encontró código de carrera en la base de vacantes."

    describe

    exit 111
}


di as result ///
    "Código de carrera utilizado en vacantes: `vacancy_code'"


/**********************************************************************
* A.2. Convertir código a formato numérico auxiliar
**********************************************************************/

capture confirm numeric variable `vacancy_code'

if _rc == 0 {

    gen double code_original = ///
        `vacancy_code'
}
else {

    destring `vacancy_code', ///
        gen(code_original) ///
        force
}


/**********************************************************************
* A.3. Armonizar códigos de cuatro a cinco dígitos
**********************************************************************/

gen str12 code_string = ///
    strtrim(string(code_original, "%12.0f"))


gen long codigo_carrera_harmonized = ///
    code_original


replace codigo_carrera_harmonized = ///
    real( ///
        substr(code_string, 1, length(code_string) - 2) + ///
        "0" + ///
        substr(code_string, length(code_string) - 1, 2) ///
    ) ///
    if length(code_string) == 4


drop code_string code_original


/**********************************************************************
* A.4. Detectar variable de cupos
**********************************************************************/

local vacancyvar ""

foreach candidate in ///
    Z_total_cupos ///
    total_cupos ///
    vacantes_1sem ///
    vacantes ///
    cupos {

    capture confirm variable `candidate'

    if _rc == 0 & "`vacancyvar'" == "" {
        local vacancyvar "`candidate'"
    }
}


if "`vacancyvar'" == "" {

    di as error ///
        "No se encontró variable de cupos en la base de vacantes."

    describe

    exit 111
}


di as result ///
    "Variable de vacantes utilizada: `vacancyvar'"


/**********************************************************************
* A.5. Estandarizar cupos
**********************************************************************/

capture confirm numeric variable `vacancyvar'

if _rc == 0 {

    gen double Z_total_cupos_clean = ///
        `vacancyvar'
}
else {

    destring `vacancyvar', ///
        gen(Z_total_cupos_clean) ///
        force
}


/**********************************************************************
* A.6. Verificar consistencia dentro de carrera-año
**********************************************************************/

bysort ///
    ao_proceso ///
    codigo_carrera_harmonized: ///
    egen double min_cupos = ///
        min(Z_total_cupos_clean)

bysort ///
    ao_proceso ///
    codigo_carrera_harmonized: ///
    egen double max_cupos = ///
        max(Z_total_cupos_clean)


count if ///
    min_cupos != max_cupos ///
    & !missing(min_cupos, max_cupos)

local inconsistent_cupos = r(N)

di as result ///
    "Filas en carrera-año con valores de cupos distintos: " ///
    %12.0fc `inconsistent_cupos'


if `inconsistent_cupos' > 0 {

    preserve

        keep if ///
            min_cupos != max_cupos ///
            & !missing(min_cupos, max_cupos)

        keep ///
            ao_proceso ///
            codigo_carrera_harmonized ///
            Z_total_cupos_clean ///
            min_cupos ///
            max_cupos

        duplicates drop

        export delimited using ///
            "$processed/vacancy_code_year_conflicts.csv", ///
            replace

    restore


    di as error ///
        "Hay conflictos de cupos dentro de código-año."

    di as error ///
        "Se guardó el diagnóstico en:"

    di as error ///
        "$processed/vacancy_code_year_conflicts.csv"

    exit 459
}


drop min_cupos max_cupos


/**********************************************************************
* A.7. Dejar una observación por código-año
**********************************************************************/

keep ///
    ao_proceso ///
    codigo_carrera_harmonized ///
    Z_total_cupos_clean


bysort ///
    ao_proceso ///
    codigo_carrera_harmonized: ///
    keep if _n == 1


rename ///
    Z_total_cupos_clean ///
    Z_total_cupos


isid ///
    ao_proceso ///
    codigo_carrera_harmonized


count if missing(Z_total_cupos)

di as result ///
    "Código-año con cupos missing: " ///
    %12.0fc r(N)


tempfile vacancies_clean

save `vacancies_clean', replace


/**********************************************************************
***********************************************************************
* PARTE B
* PREPARAR MASTER Y DETECTAR DEFINICIONES
***********************************************************************
**********************************************************************/

use "`master'", clear


/**********************************************************************
* B.1. Verificar variables generales
**********************************************************************/

foreach v in ///
    mrun ///
    ao_proceso ///
    enrolls_target ///
    codigo_carrera_harmonized ///
    sigla_universidad ///
    graduates_enrolled_program_8y ///
    graduates_enrolled_program_10y {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable en master: `v'"
        exit 111
    }
}


/**********************************************************************
* B.2. Construir ID de programa si no existe
**********************************************************************/

capture confirm variable program_id_rank_analysis

if _rc != 0 {

    egen long program_id_rank_analysis = ///
        group( ///
            sigla_universidad ///
            codigo_carrera_harmonized ///
        )
}


/**********************************************************************
* B.3. Detectar variables First y Minimum Cohort
**********************************************************************/

local infra_first ""
local infra_min ""


foreach candidate in ///
    infra_rank_initial ///
    infra_first_enroll ///
    infra_rank_first ///
    infra_first {

    capture confirm variable `candidate'

    if _rc == 0 & "`infra_first'" == "" {
        local infra_first "`candidate'"
    }
}


foreach candidate in ///
    infra_rank_min ///
    infra_min_enroll ///
    infra_rank_minimum ///
    infra_minimum {

    capture confirm variable `candidate'

    if _rc == 0 & "`infra_min'" == "" {
        local infra_min "`candidate'"
    }
}


if "`infra_first'" == "" {

    di as error ///
        "No se encontró variable First Cohort."

    describe infra*

    exit 111
}


if "`infra_min'" == "" {

    di as error ///
        "No se encontró variable Minimum Cohort."

    describe infra*

    exit 111
}


di as result ///
    "First Cohort variable: `infra_first'"

di as result ///
    "Minimum Cohort variable: `infra_min'"


/**********************************************************************
* B.4. Guardar master temporal con ID de programa
**********************************************************************/

tempfile master_ready

save `master_ready', replace


/**********************************************************************
***********************************************************************
* PARTE C
* CONSTRUIR PANEL DE MATRÍCULA TOTAL
***********************************************************************
**********************************************************************/

use `master_ready', clear

keep if enrolls_target == 1


/*
Una observación por estudiante, programa y año.
*/

bysort ///
    mrun ///
    program_id_rank_analysis ///
    ao_proceso: ///
    keep if _n == 1


gen byte one_total = 1


collapse ///
    (sum) N_total_enter = one_total, ///
    by( ///
        program_id_rank_analysis ///
        codigo_carrera_harmonized ///
        sigla_universidad ///
        ao_proceso ///
    )


isid ///
    program_id_rank_analysis ///
    ao_proceso


tempfile total_panel

save `total_panel', replace


/**********************************************************************
***********************************************************************
* PARTE D
* ARCHIVO PARA RESULTADOS
***********************************************************************
**********************************************************************/

tempfile results_tmp

capture postclose results


postfile results ///
    str12 definition ///
    str20 definition_label ///
    byte horizon ///
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
    using `results_tmp', ///
    replace


/**********************************************************************
***********************************************************************
* PARTE E
* LOOP FIRST COHORT Y MINIMUM COHORT
***********************************************************************
**********************************************************************/

foreach def in first min {


    /******************************************************************
    * E.1. Definición correspondiente
    ******************************************************************/

    if "`def'" == "first" {

        local infravar "`infra_first'"
        local deflabel "First Cohort"

        local panelout ///
            "$processed/inframarginal_rank_panel_2007_2014_first_enroll_grad8y10y.dta"
    }


    if "`def'" == "min" {

        local infravar "`infra_min'"
        local deflabel "Minimum Cohort"

        local panelout ///
            "$processed/inframarginal_rank_panel_2007_2014_min_enroll_grad8y10y.dta"
    }


    /******************************************************************
    * E.2. Construir panel de outcomes inframarginales
    ******************************************************************/

    use `master_ready', clear

    keep if ///
        `infravar' == 1 ///
        & enrolls_target == 1


    /*
    Una observación por estudiante, programa y año.
    */

    bysort ///
        mrun ///
        program_id_rank_analysis ///
        ao_proceso: ///
        keep if _n == 1


    gen byte one_infra = 1


    /*
    Muestra individual común para los outcomes 8y y 10y.
    */

    gen byte common_outcome = ///
        !missing( ///
            graduates_enrolled_program_8y, ///
            graduates_enrolled_program_10y ///
        )


    gen byte one_common = ///
        common_outcome == 1


    gen double grad8_common = ///
        graduates_enrolled_program_8y ///
        if common_outcome == 1


    gen double grad10_common = ///
        graduates_enrolled_program_10y ///
        if common_outcome == 1


    count if common_outcome == 0

    di as result ///
        "`deflabel': inframarginales excluidos por missing 8y/10y = " ///
        %12.0fc r(N)


    collapse ///
        (sum) ///
            N_infra_enter = one_infra ///
            N_infra_common = one_common ///
        (mean) ///
            grad_enrolled_program_rate_8y = grad8_common ///
            grad_enrolled_program_rate_10y = grad10_common, ///
        by( ///
            program_id_rank_analysis ///
            codigo_carrera_harmonized ///
            sigla_universidad ///
            ao_proceso ///
        )


    isid ///
        program_id_rank_analysis ///
        ao_proceso


    /******************************************************************
    * E.3. Incorporar matrícula total
    ******************************************************************/

    merge 1:1 ///
        program_id_rank_analysis ///
        codigo_carrera_harmonized ///
        sigla_universidad ///
        ao_proceso ///
        using `total_panel'


    tab _merge, missing


    count if _merge == 1

    di as result ///
        "`deflabel': infra panel sin matrícula total = " ///
        %12.0fc r(N)


    keep if _merge == 3

    drop _merge


    /******************************************************************
    * E.4. Incorporar vacantes como en el ejercicio original
    ******************************************************************/

    merge m:1 ///
        ao_proceso ///
        codigo_carrera_harmonized ///
        using `vacancies_clean'


    tab _merge, missing


    count if _merge == 1

    local without_vacancies = r(N)

    di as result ///
        "`deflabel': programa-año sin vacantes = " ///
        %12.0fc `without_vacancies'


    count if _merge == 2

    di as result ///
        "`deflabel': vacantes sin programa en panel = " ///
        %12.0fc r(N)


    keep if _merge == 3

    drop _merge


    /******************************************************************
    * E.5. Mantener programas con al menos dos años
    ******************************************************************/

    bysort program_id_rank_analysis: ///
        egen int n_years_panel = ///
            count(ao_proceso)


    keep if n_years_panel >= 2


    /******************************************************************
    * E.6. Construir primeras diferencias
    ******************************************************************/

    isid ///
        program_id_rank_analysis ///
        ao_proceso


    xtset ///
        program_id_rank_analysis ///
        ao_proceso


    foreach v in ///
        N_total_enter ///
        N_infra_enter ///
        N_infra_common ///
        grad_enrolled_program_rate_8y ///
        grad_enrolled_program_rate_10y ///
        Z_total_cupos {

        gen double D_`v' = ///
            D.`v'
    }


    /******************************************************************
    * E.7. Ponderadores promedio
    ******************************************************************/

    gen double avg_N_total_enter = ///
        (N_total_enter + L.N_total_enter) / 2


    gen double avg_N_infra_common = ///
        (N_infra_common + L.N_infra_common) / 2


    /******************************************************************
    * E.8. Muestra común de estimación
    ******************************************************************/

    gen byte sample_iv_common = ///
        !missing( ///
            D_N_total_enter, ///
            D_Z_total_cupos, ///
            D_grad_enrolled_program_rate_8y, ///
            D_grad_enrolled_program_rate_10y, ///
            avg_N_total_enter, ///
            avg_N_infra_common ///
        ) ///
        & avg_N_total_enter > 0 ///
        & avg_N_infra_common > 0


    /******************************************************************
    * E.9. Diagnósticos
    ******************************************************************/

    count if sample_iv_common == 1

    local fd_obs = r(N)


    egen byte tag_program = ///
        tag(program_id_rank_analysis) ///
        if sample_iv_common == 1


    count if tag_program == 1

    local programs = r(N)

    drop tag_program


    di as text "=================================================="
    di as result "`deflabel' | COMMON SAMPLE 2007--2014"
    di as result "Programs: " %12.0fc `programs'
    di as result "FD observations: " %12.0fc `fd_obs'
    di as text "=================================================="


    /******************************************************************
    * E.10. Guardar panel
    ******************************************************************/

    compress

    save "`panelout'", replace


    /******************************************************************
    * E.11. Loop por horizonte
    ******************************************************************/

    foreach h in 8 10 {


        if `h' == 8 {

            local outcome ///
                "D_grad_enrolled_program_rate_8y"
        }


        if `h' == 10 {

            local outcome ///
                "D_grad_enrolled_program_rate_10y"
        }


        /**************************************************************
        * First stage
        **************************************************************/

        quietly reg ///
            D_N_total_enter ///
            D_Z_total_cupos ///
            i.ao_proceso ///
            [aw = avg_N_total_enter] ///
            if sample_iv_common == 1, ///
            vce(cluster program_id_rank_analysis)


        local fs_coef = ///
            _b[D_Z_total_cupos]

        local fs_se = ///
            _se[D_Z_total_cupos]


        quietly test ///
            D_Z_total_cupos = 0

        local fs_F = r(F)
        local fs_p = r(p)


        /**************************************************************
        * Reduced form
        **************************************************************/

        quietly reg ///
            `outcome' ///
            D_Z_total_cupos ///
            i.ao_proceso ///
            [aw = avg_N_infra_common] ///
            if sample_iv_common == 1, ///
            vce(cluster program_id_rank_analysis)


        local rf_coef = ///
            _b[D_Z_total_cupos]

        local rf_se = ///
            _se[D_Z_total_cupos]


        quietly test ///
            D_Z_total_cupos = 0

        local rf_p = r(p)


        /**************************************************************
        * 2SLS
        **************************************************************/

        quietly ivregress 2sls ///
            `outcome' ///
            i.ao_proceso ///
            (D_N_total_enter = D_Z_total_cupos) ///
            [aw = avg_N_infra_common] ///
            if sample_iv_common == 1, ///
            vce(cluster program_id_rank_analysis)


        local iv_coef = ///
            _b[D_N_total_enter]

        local iv_se = ///
            _se[D_N_total_enter]


        quietly test ///
            D_N_total_enter = 0

        local iv_p = r(p)


        /**************************************************************
        * Mostrar resultados
        **************************************************************/

        di as text "--------------------------------------------------"
        di as result "`deflabel' | Graduation within `h' years"
        di as text "--------------------------------------------------"


        di as result ///
            "First stage: " ///
            %9.5f `fs_coef' ///
            " (" %9.5f `fs_se' ")" ///
            " | F = " %9.1f `fs_F'


        di as result ///
            "Reduced form: " ///
            %9.5f `rf_coef' ///
            " (" %9.5f `rf_se' ")" ///
            " | p = " %6.3f `rf_p'


        di as result ///
            "2SLS: " ///
            %9.5f `iv_coef' ///
            " (" %9.5f `iv_se' ")" ///
            " | p = " %6.3f `iv_p'


        /**************************************************************
        * Guardar resultados
        **************************************************************/

        post results ///
            ("`def'") ///
            ("`deflabel'") ///
            (`h') ///
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
    }
}

postclose results


/**********************************************************************
***********************************************************************
* PARTE F
* GUARDAR TABLA FINAL
***********************************************************************
**********************************************************************/

use `results_tmp', clear


gen byte definition_order = .

replace definition_order = 1 ///
    if definition == "first"

replace definition_order = 2 ///
    if definition == "min"


sort ///
    definition_order ///
    horizon


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
    definition_order ///
    definition ///
    definition_label ///
    horizon ///
    programs ///
    fd_obs ///
    fs_coef ///
    fs_se ///
    fs_F ///
    fs_p ///
    rf_coef ///
    rf_se ///
    rf_p ///
    iv_coef ///
    iv_se ///
    iv_p


di as text "=================================================="
di as result "GRADUATION 8Y VS 10Y — COMMON SAMPLE 2007--2014"
di as text "=================================================="


list ///
    definition_label ///
    horizon ///
    programs ///
    fd_obs ///
    fs_coef ///
    fs_se ///
    fs_F ///
    rf_coef ///
    rf_se ///
    rf_p ///
    iv_coef ///
    iv_se ///
    iv_p, ///
    sepby(definition_label) ///
    noobs ///
    clean


compress

save "`results_dta'", replace

export delimited using "`results_csv'", replace


di as text "=================================================="
di as result "Exercise completed."
di as result "Results DTA:"
di as result "`results_dta'"
di as result "Results CSV:"
di as result "`results_csv'" 
di as text "=================================================="