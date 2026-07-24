/**********************************************************************
* 28a_graduation_10y_to_inframarginal_master.do
*
* Objetivo:
*
*   1. Construir graduates_enrolled_program_10y a partir de
*      graduates_target_10y para estudiantes matriculados en target.
*
*   2. Incorporar el outcome a la base inframarginal.
*
* Período:
*   2007--2014, con seguimiento de graduación hasta 2024.
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


/**********************************************************************
* 0. Rutas
**********************************************************************/

local base10 ///
    "$processed/analysis_sample_with_fields_graduation_10y.dta"

local masterinfra ///
    "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta"

local crosswalk10 ///
    "$processed/graduation_enrolled_program_10y_crosswalk.dta"

local masterout ///
    "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2014_grad8y10y.dta"


/**********************************************************************
* 0.1. Verificar archivos
**********************************************************************/

foreach f in "`base10'" "`masterinfra'" {

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
* CONSTRUIR CROSSWALK DE GRADUACIÓN A 10 AÑOS
***********************************************************************
**********************************************************************/

use "`base10'", clear

keep if inrange(ao_proceso, 2007, 2014)


/**********************************************************************
* A.1. Verificar variables
**********************************************************************/

foreach v in ///
    mrun ///
    ao_proceso ///
    preferencia ///
    enrolls_target ///
    graduates_target_10y {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable en la base 10y: `v'"
        exit 111
    }
}


/**********************************************************************
* A.2. Detectar código target
**********************************************************************/

local targetcode ""

capture confirm variable t_codigo_carrera

if _rc == 0 {
    local targetcode "t_codigo_carrera"
}

if "`targetcode'" == "" {

    capture confirm variable codigo_carrera

    if _rc == 0 {
        local targetcode "codigo_carrera"
    }
}

if "`targetcode'" == "" {

    di as error ///
        "No existe t_codigo_carrera ni codigo_carrera en base10."

    exit 111
}

di as result ///
    "Código target utilizado en base10: `targetcode'"


/**********************************************************************
* A.3. Construir llaves estandarizadas
**********************************************************************/

capture confirm numeric variable mrun

if _rc == 0 {

    gen str30 mrun_key = ///
        strtrim(string(mrun, "%20.0f"))
}
else {

    gen str30 mrun_key = ///
        strtrim(mrun)
}


capture confirm numeric variable preferencia

if _rc == 0 {

    gen str10 preference_key = ///
        strtrim(string(preferencia, "%10.0f"))
}
else {

    gen str10 preference_key = ///
        strtrim(preferencia)
}


capture confirm numeric variable `targetcode'

if _rc == 0 {

    gen str20 target_program_key = ///
        strtrim(string(`targetcode', "%20.0f"))
}
else {

    gen str20 target_program_key = ///
        strtrim(`targetcode')
}


/**********************************************************************
* A.4. Construir outcome de programa matriculado a 10 años
*
* Para enrolls_target == 1:
*
*   programa target = programa efectivamente matriculado.
**********************************************************************/

gen byte graduates_enrolled_program_10y = ///
    graduates_target_10y ///
    if enrolls_target == 1

label variable graduates_enrolled_program_10y ///
    "Graduated from initially enrolled program within 10 years"


/**********************************************************************
* A.5. Chequeos del outcome
**********************************************************************/

count if ///
    enrolls_target == 1 ///
    & missing(graduates_target_10y)

di as result ///
    "Target enrollees sin outcome 10y: " ///
    %12.0fc r(N)


assert ///
    graduates_enrolled_program_10y == graduates_target_10y ///
    if enrolls_target == 1 ///
    & !missing(graduates_target_10y)


tabstat graduates_enrolled_program_10y ///
    if enrolls_target == 1, ///
    by(ao_proceso) ///
    statistics(n mean)


/**********************************************************************
* A.6. Mantener únicamente target enrollees
**********************************************************************/

keep if enrolls_target == 1

keep ///
    mrun_key ///
    ao_proceso ///
    preference_key ///
    target_program_key ///
    graduates_enrolled_program_10y


/**********************************************************************
* A.7. Verificar duplicados y outcomes contradictorios
**********************************************************************/

bysort ///
    mrun_key ///
    ao_proceso ///
    preference_key ///
    target_program_key: ///
    egen byte min_grad10 = ///
        min(graduates_enrolled_program_10y)

bysort ///
    mrun_key ///
    ao_proceso ///
    preference_key ///
    target_program_key: ///
    egen byte max_grad10 = ///
        max(graduates_enrolled_program_10y)


count if ///
    min_grad10 != max_grad10 ///
    & !missing(min_grad10, max_grad10)

local conflicting_rows = r(N)

di as result ///
    "Filas pertenecientes a llaves con outcomes contradictorios: " ///
    %12.0fc `conflicting_rows'


if `conflicting_rows' > 0 {

    di as error ///
        "Existen llaves con outcomes 10y contradictorios."

    exit 459
}


bysort ///
    mrun_key ///
    ao_proceso ///
    preference_key ///
    target_program_key: ///
    keep if _n == 1

drop min_grad10 max_grad10


isid ///
    mrun_key ///
    ao_proceso ///
    preference_key ///
    target_program_key


save "`crosswalk10'", replace

di as result ///
    "Crosswalk 10y guardado en:"

di as result ///
    "`crosswalk10'"


/**********************************************************************
***********************************************************************
* PARTE B
* INCORPORAR EL OUTCOME A LA BASE INFRAMARGINAL
***********************************************************************
**********************************************************************/

use "`masterinfra'", clear

keep if inrange(ao_proceso, 2007, 2014)


/**********************************************************************
* B.1. Verificar variables
**********************************************************************/

foreach v in ///
    mrun ///
    ao_proceso ///
    preferencia ///
    enrolls_target ///
    graduates_enrolled_program_8y {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable en la base inframarginal: `v'"
        exit 111
    }
}


/**********************************************************************
* B.2. Detectar código target
**********************************************************************/

local targetcode_master ""

capture confirm variable codigo_carrera

if _rc == 0 {
    local targetcode_master "codigo_carrera"
}

if "`targetcode_master'" == "" {

    capture confirm variable t_codigo_carrera

    if _rc == 0 {
        local targetcode_master "t_codigo_carrera"
    }
}

if "`targetcode_master'" == "" {

    di as error ///
        "No existe codigo_carrera ni t_codigo_carrera en master."

    exit 111
}

di as result ///
    "Código target utilizado en master: `targetcode_master'"


/**********************************************************************
* B.3. Construir las mismas llaves estandarizadas
**********************************************************************/

capture confirm numeric variable mrun

if _rc == 0 {

    gen str30 mrun_key = ///
        strtrim(string(mrun, "%20.0f"))
}
else {

    gen str30 mrun_key = ///
        strtrim(mrun)
}


capture confirm numeric variable preferencia

if _rc == 0 {

    gen str10 preference_key = ///
        strtrim(string(preferencia, "%10.0f"))
}
else {

    gen str10 preference_key = ///
        strtrim(preferencia)
}


capture confirm numeric variable `targetcode_master'

if _rc == 0 {

    gen str20 target_program_key = ///
        strtrim(string(`targetcode_master', "%20.0f"))
}
else {

    gen str20 target_program_key = ///
        strtrim(`targetcode_master')
}


/**********************************************************************
* B.4. Merge con outcome a 10 años
**********************************************************************/

merge m:1 ///
    mrun_key ///
    ao_proceso ///
    preference_key ///
    target_program_key ///
    using "`crosswalk10'"

tab _merge, missing


count if ///
    enrolls_target == 1 ///
    & _merge != 3

local unmatched_target = r(N)

di as result ///
    "Target enrollees sin match 10y: " ///
    %12.0fc `unmatched_target'


if `unmatched_target' > 0 {

    preserve

        keep if ///
            enrolls_target == 1 ///
            & _merge != 3

        keep ///
            mrun ///
            ao_proceso ///
            preferencia ///
            `targetcode_master' ///
            mrun_key ///
            preference_key ///
            target_program_key

        export delimited using ///
            "$processed/unmatched_target_enrollees_grad10y.csv", ///
            replace

    restore


    di as error ///
        "Hay target enrollees sin match."

    di as error ///
        "Se guardó un diagnóstico en:"

    di as error ///
        "$processed/unmatched_target_enrollees_grad10y.csv"

    exit 459
}


drop if _merge == 2

drop _merge


/**********************************************************************
* B.5. Detectar variables de inframarginalidad
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
        "No se encontró la variable First Cohort."

    describe infra*

    exit 111
}


if "`infra_min'" == "" {

    di as error ///
        "No se encontró la variable Minimum Cohort."

    describe infra*

    exit 111
}


di as result ///
    "Variable First Cohort: `infra_first'"

di as result ///
    "Variable Minimum Cohort: `infra_min'"


/**********************************************************************
* B.6. Verificar equivalencia con matrícula target
**********************************************************************/

count if ///
    `infra_first' == 1 ///
    & enrolls_target != 1

local first_not_target = r(N)


count if ///
    `infra_min' == 1 ///
    & enrolls_target != 1

local min_not_target = r(N)


di as result ///
    "First Cohort inframarginals not enrolled in target: " ///
    %12.0fc `first_not_target'

di as result ///
    "Minimum Cohort inframarginals not enrolled in target: " ///
    %12.0fc `min_not_target'


if `first_not_target' > 0 | `min_not_target' > 0 {

    di as error ///
        "Hay inframarginales no matriculados en target."

    di as error ///
        "En ese caso graduates_target_10y no es suficiente."

    exit 459
}


/**********************************************************************
* B.7. Chequear outcomes entre inframarginales
**********************************************************************/

foreach def in first min {

    if "`def'" == "first" {
        local infravar "`infra_first'"
    }

    if "`def'" == "min" {
        local infravar "`infra_min'"
    }


    count if ///
        `infravar' == 1 ///
        & missing(graduates_enrolled_program_8y)

    di as result ///
        "`def': inframarginales sin outcome 8y = " ///
        %12.0fc r(N)


    count if ///
        `infravar' == 1 ///
        & missing(graduates_enrolled_program_10y)

    di as result ///
        "`def': inframarginales sin outcome 10y = " ///
        %12.0fc r(N)
}


/**********************************************************************
* B.8. Guardar master enriquecida
**********************************************************************/

compress

save "`masterout'", replace

di as text "=================================================="
di as result "MASTER 2007--2014 CON OUTCOMES 8Y Y 10Y GUARDADA"
di as result "`masterout'"
di as text "=================================================="