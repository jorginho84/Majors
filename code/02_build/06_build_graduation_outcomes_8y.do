/**********************************************************************
* 06_build_graduation_outcomes_8y.do
*
* Construye outcomes de titulación a 8 años usando bases SIES Titulados
* 2007-2024 y matrícula SIES para identificar programa objetivo.
*
* Inputs:
*   - $processed/analysis_sample_with_fields_final.dta
*   - CSV titulados en $tit_raw
*   - CSV matrícula en $mat_raw
*
* Output único:
*   - $processed/analysis_sample_with_fields_graduation_8y.dta
*
* Outcomes:
*   - graduates_he_8y
*   - graduates_uni_8y
*   - graduates_target_8y
**********************************************************************/

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

di as result "Titulados raw: $tit_raw"
di as result "Matricula raw: $mat_raw"
di as result "Processed: $processed"


************************************************************
* 1. Construir crosswalk DEMRE -> CODIGO_UNICO desde matrícula
************************************************************

tempfile xwalk_programs
local first 1

forvalues y = 2007/2016 {

    di as text "--------------------------------------------------"
    di as result "Procesando matrícula año: `y'"
    di as text "--------------------------------------------------"

    local files : dir "$mat_raw" files "*`y'*"

    if `"`files'"' == "" {
        di as error "No se encontró archivo de matrícula para `y'"
        continue
    }

    local file ""

    foreach f of local files {
        local fl = lower("`f'")
        if regexm("`fl'", "\.csv$") {
            local file "`f'"
            continue, break
        }
    }

    if "`file'" == "" {
        di as error "No se encontró CSV usable de matrícula para `y'"
        continue
    }

    di as result "Archivo usado: `file'"

    import delimited "$mat_raw/`file'", ///
        clear ///
        varnames(1) ///
        encoding(UTF-8) ///
        bindquote(strict)

    rename *, lower

    capture confirm variable cat_periodo
    if _rc != 0 {
        gen cat_periodo = `y'
    }

    capture confirm variable codigo_demre
    if _rc != 0 {
        di as error "No existe codigo_demre en matrícula `y'. Se salta."
        continue
    }

    capture confirm variable codigo_unico
    if _rc != 0 {
        di as error "No existe codigo_unico en matrícula `y'. Se salta."
        continue
    }

    keep cat_periodo codigo_demre codigo_unico

    rename cat_periodo ao_proceso
    rename codigo_demre t_codigo_carrera
    rename codigo_unico target_codigo_unico

    destring ao_proceso, replace force
    replace ao_proceso = `y' if missing(ao_proceso)

    tostring t_codigo_carrera, replace force
    replace t_codigo_carrera = trim(t_codigo_carrera)
    replace t_codigo_carrera = "" if t_codigo_carrera == "."
    replace t_codigo_carrera = "" if upper(t_codigo_carrera) == "NA"
    replace t_codigo_carrera = "" if upper(t_codigo_carrera) == "SIN INFORMACION"
    replace t_codigo_carrera = "" if upper(t_codigo_carrera) == "SIN INFORMACIÓN"

    destring t_codigo_carrera, replace force

    tostring target_codigo_unico, replace force
    replace target_codigo_unico = trim(target_codigo_unico)
    replace target_codigo_unico = "" if target_codigo_unico == "."

    drop if missing(ao_proceso)
    drop if missing(t_codigo_carrera)
    drop if target_codigo_unico == ""

    duplicates drop ao_proceso t_codigo_carrera target_codigo_unico, force

    if `first' == 1 {
        save `xwalk_programs', replace
        local first 0
    }
    else {
        append using `xwalk_programs'
        save `xwalk_programs', replace
    }
}

if `first' == 1 {
    di as error "No se pudo construir crosswalk DEMRE -> CODIGO_UNICO."
    exit 601
}

use `xwalk_programs', clear

di as text "=================================================="
di as result "Crosswalk DEMRE -> CODIGO_UNICO"
di as text "=================================================="

count
duplicates report ao_proceso t_codigo_carrera

tempfile demre_to_unico
save `demre_to_unico', replace


************************************************************
* 2. Append bases de titulados 2007-2024
************************************************************

tempfile all_tit
local first 1

forvalues y = 2007/2024 {

    di as text "--------------------------------------------------"
    di as result "Procesando titulados año: `y'"
    di as text "--------------------------------------------------"

    local files : dir "$tit_raw" files "*`y'*"

    if `"`files'"' == "" {
        di as error "No se encontró archivo de titulados para `y'"
        continue
    }

    local file ""

    foreach f of local files {
        local fl = lower("`f'")
        if regexm("`fl'", "\.csv$") {
            local file "`f'"
            continue, break
        }
    }

    if "`file'" == "" {
        di as error "No se encontró CSV usable de titulados para `y'"
        continue
    }

    di as result "Archivo usado: `file'"

    import delimited "$tit_raw/`file'", ///
        clear ///
        varnames(1) ///
        encoding(UTF-8) ///
        bindquote(strict)

    rename *, lower


    ************************************************************
    * 2.1 Año de titulación
    ************************************************************

    capture confirm variable cat_periodo
    if _rc != 0 {
        gen cat_periodo = `y'
    }

    capture confirm numeric variable cat_periodo
    if _rc == 0 {
        gen grad_year = cat_periodo
    }
    else {
        destring cat_periodo, gen(grad_year) force
    }

    replace grad_year = `y' if missing(grad_year)


    ************************************************************
    * 2.2 MRUN
    ************************************************************

    capture confirm variable mrun
    if _rc != 0 {
        di as error "No existe mrun en titulados `y'. Se salta."
        continue
    }

    capture confirm numeric variable mrun
    if _rc == 0 {
        tostring mrun, gen(mrun_str) format(%12.0f) force
    }
    else {
        gen mrun_str = trim(mrun)
    }

    replace mrun_str = trim(mrun_str)
    drop if mrun_str == "" | mrun_str == "."


    ************************************************************
    * 2.3 Año ingreso carrera origen
    ************************************************************

    local entryvar ""

    foreach cand in año_ing_carr_ori ano_ing_carr_ori anio_ing_carr_ori a_o_ing_carr_ori {
        capture confirm variable `cand'
        if _rc == 0 {
            local entryvar "`cand'"
            continue, break
        }
    }

    if "`entryvar'" == "" {
        ds *ing*carr*ori*
        local entryvar : word 1 of `r(varlist)'
    }

    if "`entryvar'" == "" {
        di as error "No se encontró variable de año ingreso carrera origen en titulados `y'."
        describe
        exit 111
    }

    di as result "Variable año ingreso carrera origen: `entryvar'"

    capture confirm numeric variable `entryvar'
    if _rc == 0 {
        tostring `entryvar', gen(entry_str) format(%12.0f) force
    }
    else {
        gen entry_str = trim(`entryvar')
    }

    destring entry_str, gen(grad_entry_year) force

    replace grad_entry_year = . if inlist(grad_entry_year, 9995, 9998, 9999, 1900)


    ***********************************************************
	* 2.4 Código único
	************************************************************

	capture confirm variable codigo_unico
	if _rc != 0 {
		di as error "No existe codigo_unico en titulados `y'. Se salta."
		continue
	}

	capture drop grad_codigo_unico

	capture confirm numeric variable codigo_unico
	if _rc == 0 {
		tostring codigo_unico, gen(grad_codigo_unico) format(%20.0f) force
	}
	else {
		gen grad_codigo_unico = trim(codigo_unico)
	}

	replace grad_codigo_unico = trim(grad_codigo_unico)
	replace grad_codigo_unico = "" if grad_codigo_unico == "."
	replace grad_codigo_unico = "" if upper(grad_codigo_unico) == "NA"
	replace grad_codigo_unico = "" if upper(grad_codigo_unico) == "SIN INFORMACION"
	replace grad_codigo_unico = "" if upper(grad_codigo_unico) == "SIN INFORMACIÓN"


    ************************************************************
    * 2.5 Variables institucionales
    ************************************************************

    capture confirm variable tipo_inst_1
    if _rc != 0 {
        gen tipo_inst_1 = ""
    }

    capture confirm variable tipo_inst_2
    if _rc != 0 {
        gen tipo_inst_2 = ""
    }

    capture confirm variable nivel_global
    if _rc != 0 {
        gen nivel_global = ""
    }

    replace tipo_inst_1 = upper(trim(tipo_inst_1))
    replace tipo_inst_2 = upper(trim(tipo_inst_2))
    replace nivel_global = upper(trim(nivel_global))

    * Mantener pregrado
    keep if nivel_global == "PREGRADO" | nivel_global == ""


    ************************************************************
    * 2.6 Mantener variables útiles
    ************************************************************

    local keepvars mrun_str grad_year grad_entry_year grad_codigo_unico ///
                   tipo_inst_1 tipo_inst_2 nivel_global

    foreach v in cod_carrera nomb_carrera nomb_inst cod_inst cod_sede ///
        area_cineunesco area_carrera_generica_n fecha_obtencion_titulo {
        
        capture confirm variable `v'
        if _rc == 0 {
            local keepvars `keepvars' `v'
        }
    }

    keep `keepvars'

    drop if grad_codigo_unico == ""
    drop if missing(grad_year)
    drop if missing(grad_entry_year)

    duplicates drop

    if `first' == 1 {
        save `all_tit', replace
        local first 0
    }
    else {
        append using `all_tit'
        save `all_tit', replace
    }
}

if `first' == 1 {
    di as error "No se procesó ningún archivo de titulados."
    exit 601
}

use `all_tit', clear

compress

di as text "=================================================="
di as result "Base temporal de titulados construida"
di as text "=================================================="

count

tempfile titulados_all
save `titulados_all', replace
save "$processed/diagnostic_titulados_all.dta", replace

************************************************************
* 3. Preparar muestra de postulaciones
************************************************************

use "$processed/analysis_sample_with_fields_final.dta", clear

* Con titulados hasta 2024, cohortes 2007-2016 tienen 8 años completos
keep if inrange(ao_proceso, 2007, 2016)

capture confirm numeric variable mrun
if _rc == 0 {
    tostring mrun, gen(mrun_str) format(%12.0f) force
}
else {
    gen mrun_str = trim(mrun)
}

replace mrun_str = trim(mrun_str)
drop if mrun_str == "" | mrun_str == "."

gen sample_id = _n

tempfile full_sample
save `full_sample', replace


************************************************************
* 4. Crear muestra única MRUN-año para outcomes generales
************************************************************

preserve

    keep mrun_str ao_proceso
    duplicates drop

    tempfile sample_keys
    save `sample_keys', replace

restore


************************************************************
* 5. Outcomes generales: graduates_he_8y y graduates_uni_8y
************************************************************

use `titulados_all', clear

joinby mrun_str using `sample_keys'

* Mantener titulación de la misma cohorte de entrada
keep if grad_entry_year == ao_proceso
keep if grad_year >= ao_proceso
keep if grad_year <= ao_proceso + 8

gen grad_he_aux = 1

gen grad_uni_aux = 0 
replace grad_uni_aux = 1 if regexm(upper(trim(tipo_inst_1)), "UNIVERS")
replace grad_uni_aux = 1 if regexm(upper(trim(tipo_inst_2)), "UNIVERS")

collapse ///
    (max) graduates_he_8y  = grad_he_aux ///
    (max) graduates_uni_8y = grad_uni_aux, ///
    by(mrun_str ao_proceso)

tempfile grad_general
save `grad_general', replace


************************************************************
* 6. Outcome target: graduates_target_8y
************************************************************

************************************************************
* 6.1 Muestra con código único objetivo
************************************************************

use `full_sample', clear

joinby ao_proceso t_codigo_carrera using `demre_to_unico'

rename target_codigo_unico grad_codigo_unico

tempfile sample_target
save `sample_target', replace


************************************************************
* 6.2 Cruzar titulados con muestra por MRUN + código único
************************************************************

use `titulados_all', clear

joinby mrun_str grad_codigo_unico using `sample_target'

keep if grad_entry_year == ao_proceso
keep if grad_year >= ao_proceso
keep if grad_year <= ao_proceso + 8

gen grad_target_aux = 1

collapse (max) graduates_target_8y = grad_target_aux, by(sample_id)

tempfile grad_target
save `grad_target', replace


************************************************************
* 7. Merge outcomes a muestra completa
************************************************************

use `full_sample', clear

merge m:1 mrun_str ao_proceso using `grad_general'

replace graduates_he_8y = 0 if missing(graduates_he_8y)
replace graduates_uni_8y = 0 if missing(graduates_uni_8y)

drop _merge

merge 1:1 sample_id using `grad_target'

replace graduates_target_8y = 0 if missing(graduates_target_8y)

drop _merge sample_id

label var graduates_he_8y     "Graduated from higher education within 8 years"
label var graduates_uni_8y    "Graduated from university within 8 years"
label var graduates_target_8y "Graduated from target program within 8 years"

compress

save "$processed/analysis_sample_with_fields_graduation_8y.dta", replace


************************************************************
* 8. Diagnóstico final
************************************************************

di as text "=================================================="
di as result "Graduation outcomes built"
di as text "=================================================="

count

tab graduates_he_8y
tab graduates_uni_8y
tab graduates_target_8y

tab field graduates_he_8y, row
tab field graduates_uni_8y, row
tab field graduates_target_8y, row

di as result "Output guardado en:"
di as result "$processed/analysis_sample_with_fields_graduation_8y.dta"