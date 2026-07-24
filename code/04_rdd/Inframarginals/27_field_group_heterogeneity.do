/**********************************************************************
* 27_field_group_heterogeneity.do
*
* Objetivo:
*   Estimar heterogeneidad por campo de estudios en el modelo de
*   estudiantes inframarginales.
*
* Grupos amplios:
*   1. Business and Law
*   2. Health
*   3. STEM
*   4. Education and Humanities
*   5. Arts, Agriculture and Other
*
* Definiciones de inframarginales:
*   - First Cohort
*   - Minimum Cohort
*
* Outcome principal:
*   Graduación dentro de 8 años del programa en que el estudiante
*   se matriculó inicialmente.
*
* Inputs:
*   $processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta
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
*   $processed/program_field_group_mapping.dta
*   $processed/program_field_group_mapping.csv
*
*   $processed/field_group_heterogeneity_results.dta
*   $processed/field_group_heterogeneity_results.csv
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local master_base ///
    "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta"

local panelprefix ///
    "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016"

local mapping_dta ///
    "$processed/program_field_group_mapping.dta"

local mapping_csv ///
    "$processed/program_field_group_mapping.csv"

local output_dta ///
    "$processed/field_group_heterogeneity_results.dta"

local output_csv ///
    "$processed/field_group_heterogeneity_results.csv"


/**********************************************************************
* 0. Verificar archivos requeridos
**********************************************************************/

capture confirm file "`master_base'"

if _rc != 0 {
    di as error "No existe la base principal:"
    di as error "`master_base'"
    exit 601
}

foreach def in first_enroll min_enroll {

    local panel "`panelprefix'_`def'.dta"

    capture confirm file "`panel'"

    if _rc != 0 {
        di as error "No existe el panel:"
        di as error "`panel'"
        exit 601
    }
}


/**********************************************************************
* 1. Construir clasificación fija del campo de cada programa
**********************************************************************/

use "`master_base'", clear

keep if inrange(ao_proceso, 2007, 2016)

foreach v in ///
    sigla_universidad ///
    codigo_carrera_harmonized {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable en master_base: `v'"
        exit 111
    }
}


**********************************************************************
* 1.1. Verificar identificador de programa
**********************************************************************/

capture confirm variable program_id_rank_analysis

if _rc != 0 {

    di as text ///
        "program_id_rank_analysis no existe. Se reconstruye."

    egen program_id_rank_analysis = ///
        group(sigla_universidad codigo_carrera_harmonized)
}


**********************************************************************
* 1.2. Detectar variable de campo
*
* Prioridad:
*   1. field
*   2. target_field
*   3. area_conocimiento
**********************************************************************/

local fieldvar ""

capture confirm variable field

if _rc == 0 {
    local fieldvar "field"
}

if "`fieldvar'" == "" {

    capture confirm variable target_field

    if _rc == 0 {
        local fieldvar "target_field"
    }
}

if "`fieldvar'" == "" {

    capture confirm variable area_conocimiento

    if _rc == 0 {
        local fieldvar "area_conocimiento"
    }
}

if "`fieldvar'" == "" {

    di as error ///
        "No se encontró field, target_field ni area_conocimiento."

    exit 111
}

di as result "Variable de campo utilizada: `fieldvar'"


/**********************************************************************
* 1.3. Crear cinco grupos amplios usando las categorías observadas
**********************************************************************/

capture drop field_raw field_group

gen str100 field_raw = strtrim(field)

gen byte field_group = .

* 1. Business and Law
replace field_group = 1 if ///
    inlist(field_raw, ///
        "Business", ///
        "Law")

* 2. Health
replace field_group = 2 if ///
    field_raw == "Health"

* 3. STEM
replace field_group = 3 if ///
    inlist(field_raw, ///
        "Basic Sciences", ///
        "Technology")

* 4. Education and Humanities
replace field_group = 4 if ///
    inlist(field_raw, ///
        "Education", ///
        "Humanities", ///
        "Social Sciences")

* 5. Arts, Agriculture and Other
replace field_group = 5 if ///
    inlist(field_raw, ///
        "Agriculture", ///
        "Arts and Architecture")


label define field_group_lbl ///
    1 "Business and Law" ///
    2 "Health" ///
    3 "STEM" ///
    4 "Education and Humanities" ///
    5 "Arts, Agriculture and Other", ///
    replace

label values field_group field_group_lbl


/**********************************************************************
* 2. Diagnósticos de la clasificación
**********************************************************************/

di as text "=================================================="
di as result "DISTRIBUCIÓN INDIVIDUAL DE CAMPOS"
di as text "=================================================="

tab field_group, missing


di as text "=================================================="
di as result "CATEGORÍAS ORIGINALES Y GRUPOS AMPLIOS"
di as text "=================================================="

tab field_raw field_group, missing


/**********************************************************************
* 2.1. Revisar valores que quedaron sin clasificación
**********************************************************************/

count if missing(field_group)

local n_unclassified = r(N)

di as result ///
    "Observaciones sin campo clasificable: " ///
    %12.0fc `n_unclassified'


if `n_unclassified' > 0 {

    di as error ///
        "Las siguientes categorías no fueron clasificadas:"

    preserve

        keep if missing(field_group)

        keep field_raw

        duplicates drop

        sort field_raw

        list field_raw, noobs clean

    restore
}
else {

    di as result ///
        "Todas las observaciones fueron clasificadas correctamente."
}
/**********************************************************************
* 3. Asignar un único campo fijo a cada programa
*
* Si un programa aparece asociado a más de un campo en distintos
* registros o años, se utiliza el grupo observado con mayor frecuencia.
**********************************************************************/

keep if !missing( ///
    program_id_rank_analysis, ///
    field_group ///
)

keep ///
    program_id_rank_analysis ///
    sigla_universidad ///
    codigo_carrera_harmonized ///
    field_group

contract ///
    program_id_rank_analysis ///
    sigla_universidad ///
    codigo_carrera_harmonized ///
    field_group, ///
    freq(n_field_observations)


* Ordenar para dejar primero el campo más frecuente.
gsort ///
    program_id_rank_analysis ///
    -n_field_observations ///
    field_group

by program_id_rank_analysis: ///
    gen byte n_field_groups_program = _N

egen byte tag_field_conflict = ///
    tag(program_id_rank_analysis) ///
    if n_field_groups_program > 1

count if tag_field_conflict == 1

di as result ///
    "Programas asociados a más de un grupo de campo: " r(N)

drop tag_field_conflict


* Mantener el grupo modal de cada programa.
by program_id_rank_analysis: ///
    keep if _n == 1

isid program_id_rank_analysis


/**********************************************************************
* 3.1. Diagnóstico a nivel de programa
**********************************************************************/

di as text "=================================================="
di as result "DISTRIBUCIÓN DE PROGRAMAS POR GRUPO DE CAMPO"
di as text "=================================================="

tab field_group, missing


/**********************************************************************
* 3.2. Guardar clasificación fija
**********************************************************************/

sort field_group program_id_rank_analysis

compress

save "`mapping_dta'", replace

export delimited using "`mapping_csv'", replace

tempfile field_mapping

save `field_mapping', replace


/**********************************************************************
* 4. Preparar archivo para almacenar resultados
**********************************************************************/

tempfile results_tmp

capture postclose results

postfile results ///
    str20 definition ///
    str35 definition_label ///
    byte field_group ///
    str50 field_label ///
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
* 5. Loop por definición de inframarginales
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


    /******************************************************************
    * 5.1. Verificar variables del panel
    ******************************************************************/

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


    /******************************************************************
    * 5.2. Agregar campo fijo del programa
    ******************************************************************/

    merge m:1 program_id_rank_analysis ///
        using `field_mapping', ///
        keep(master match)

    tab _merge, missing

    count if _merge == 1

    di as result ///
        "Programa-año sin grupo de campo (`deflabel'): " r(N)

    keep if _merge == 3

    drop _merge


    /******************************************************************
    * 5.3. Distribución de la muestra IV
    ******************************************************************/

    di as text "=================================================="
    di as result "`deflabel': FIELD DISTRIBUTION"
    di as text "=================================================="

    tab field_group if sample_iv == 1


    /******************************************************************
    * 6. Loop por grupo de campo
    ******************************************************************/

    foreach g in 1 2 3 4 5 {

        preserve

            keep if field_group == `g'

            if `g' == 1 {
                local glabel "Business and Law"
            }

            if `g' == 2 {
                local glabel "Health"
            }

            if `g' == 3 {
                local glabel "STEM"
            }

            if `g' == 4 {
                local glabel "Education and Humanities"
            }

            if `g' == 5 {
                local glabel "Arts, Agriculture and Other"
            }


            di as text "=================================================="
            di as result "`deflabel' | `glabel'"
            di as text "=================================================="


            /**********************************************************
            * 6.1. Número de programas y observaciones FD
            **********************************************************/

            egen byte tag_program_iv = ///
                tag(program_id_rank_analysis) ///
                if sample_iv == 1

            count if tag_program_iv == 1

            local programs = r(N)

            drop tag_program_iv

            count if sample_iv == 1

            local fd_obs = r(N)

            di as result ///
                "Programs: " %9.0fc `programs'

            di as result ///
                "FD observations: " %9.0fc `fd_obs'


            /**********************************************************
            * Evitar regresiones con grupos demasiado pequeños
            **********************************************************/

            if `programs' < 10 | `fd_obs' < 30 {

                di as error ///
                    "Muy pocas observaciones para estimar `glabel'."

                restore

                continue
            }


            /**********************************************************
            * 6.2. First stage
            *
            * Cambio en matrícula total sobre cambio en vacantes.
            **********************************************************/

            quietly reg ///
                D_N_total_enter ///
                D_Z_total_cupos ///
                i.ao_proceso ///
                [aw = avg_N_total_enter] ///
                if sample_firststage == 1, ///
                vce(cluster program_id_rank_analysis)

            local fs_coef = ///
                _b[D_Z_total_cupos]

            local fs_se = ///
                _se[D_Z_total_cupos]

            local fs_p = ///
                2 * ttail( ///
                    e(df_r), ///
                    abs(`fs_coef' / `fs_se') ///
                )

            quietly test ///
                D_Z_total_cupos = 0

            local fs_F = r(F)


            /**********************************************************
            * 6.3. Reduced form
            *
            * Cambio en graduación sobre cambio en vacantes.
            **********************************************************/

            quietly reg ///
                D_grad_enrolled_program_rate_8y ///
                D_Z_total_cupos ///
                i.ao_proceso ///
                [aw = avg_N_infra_enter] ///
                if sample_iv == 1, ///
                vce(cluster program_id_rank_analysis)

            local rf_coef = ///
                _b[D_Z_total_cupos]

            local rf_se = ///
                _se[D_Z_total_cupos]

            local rf_p = ///
                2 * ttail( ///
                    e(df_r), ///
                    abs(`rf_coef' / `rf_se') ///
                )


            /**********************************************************
            * 6.4. 2SLS
            *
            * Cambio en matrícula total instrumentado con cambios
            * en vacantes.
            **********************************************************/

            quietly ivregress 2sls ///
                D_grad_enrolled_program_rate_8y ///
                i.ao_proceso ///
                (D_N_total_enter = D_Z_total_cupos) ///
                [aw = avg_N_infra_enter] ///
                if sample_iv == 1, ///
                vce(cluster program_id_rank_analysis)

            local iv_coef = ///
                _b[D_N_total_enter]

            local iv_se = ///
                _se[D_N_total_enter]

            local iv_p = ///
                2 * normal( ///
                    -abs(`iv_coef' / `iv_se') ///
                )


            /**********************************************************
            * 6.5. Mostrar resultados
            **********************************************************/

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


            /**********************************************************
            * 6.6. Guardar resultados
            **********************************************************/

            post results ///
                ("`def'") ///
                ("`deflabel'") ///
                (`g') ///
                ("`glabel'") ///
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


/**********************************************************************
* 7. Abrir y ordenar resultados
**********************************************************************/

use `results_tmp', clear

gen byte definition_order = .

replace definition_order = 1 ///
    if definition == "first_enroll"

replace definition_order = 2 ///
    if definition == "min_enroll"

sort definition_order field_group


/**********************************************************************
* 7.1. Formatos
**********************************************************************/

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


/**********************************************************************
* 7.2. Ordenar columnas
**********************************************************************/

order ///
    definition_order ///
    definition ///
    definition_label ///
    field_group ///
    field_label ///
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
    iv_p


/**********************************************************************
* 7.3. Mostrar tabla final
**********************************************************************/

di as text "=================================================="
di as result "FIELD HETEROGENEITY RESULTS"
di as text "=================================================="

list ///
    definition_label ///
    field_label ///
    programs ///
    fd_obs ///
    fs_coef ///
    fs_se ///
    fs_F ///
    rf_coef ///
    rf_se ///
    iv_coef ///
    iv_se ///
    iv_p, ///
    sepby(definition_label) ///
    noobs ///
    clean


/**********************************************************************
* 8. Guardar resultados
**********************************************************************/

compress

save "`output_dta'", replace

export delimited using "`output_csv'", replace

di as text "=================================================="
di as result "Field heterogeneity exercise completed."
di as result "Program mapping:"
di as result "`mapping_dta'"
di as result "`mapping_csv'"
di as result "Regression results:"
di as result "`output_dta'"
di as result "`output_csv'"
di as text "=================================================="