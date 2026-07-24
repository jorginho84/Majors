/**********************************************************************
* 06b_build_graduation_outcomes_enrolled_program_8y_CHECKPOINTS.do
*
* Construye outcomes de titulacion a 8 anos, agregando un outcome nuevo
* para inframarginales:
*
*   graduates_enrolled_program_8y = 1 si el estudiante se titulo dentro
*   de 8 anos del mismo programa/carrera en que efectivamente se matriculo.
*
* Diferencia conceptual:
*   - graduates_target_8y: programa target de la postulacion.
*   - graduates_enrolled_program_8y: programa de matricula efectiva.
*
* Este archivo NO sobreescribe la base antigua. Guarda:
*   $processed/analysis_sample_with_fields_graduation_8y_enrolledprogram.dta
*
* Ademas guarda checkpoints permanentes para no tener que correr todo desde
* cero si falla algun bloque final:
*   $processed/check_06b_demre_to_unico.dta
*   $processed/check_06b_titulados_all.dta
*   $processed/check_06b_full_sample.dta
*   $processed/check_06b_sample_keys.dta
*   $processed/check_06b_grad_general.dta
*   $processed/check_06b_sample_target.dta
*   $processed/check_06b_sample_enrolled_program.dta
*   $processed/check_06b_grad_target.dta
*   $processed/check_06b_grad_enrolled_program.dta
**********************************************************************/

clear
set more off

************************************************************
* 0. Cargar configuracion
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

di as result "Titulados raw: $tit_raw"
di as result "Matricula raw: $mat_raw"
di as result "Processed: $processed"

local output "$processed/analysis_sample_with_fields_graduation_8y_enrolledprogram.dta"

local ck_xwalk     "$processed/check_06b_demre_to_unico.dta"
local ck_tit       "$processed/check_06b_titulados_all.dta"
local ck_full      "$processed/check_06b_full_sample.dta"
local ck_keys      "$processed/check_06b_sample_keys.dta"
local ck_general   "$processed/check_06b_grad_general.dta"
local ck_starget   "$processed/check_06b_sample_target.dta"
local ck_senrolled "$processed/check_06b_sample_enrolled_program.dta"
local ck_gtarget   "$processed/check_06b_grad_target.dta"
local ck_genrolled "$processed/check_06b_grad_enrolled_program.dta"

************************************************************
* 1. Construir o cargar crosswalk DEMRE -> CODIGO_UNICO
************************************************************

capture confirm file "`ck_xwalk'"
if _rc == 0 {
    di as result "Checkpoint encontrado: `ck_xwalk'"
}
else {

    tempfile xwalk_programs
    local first 1

    forvalues y = 2007/2016 {

        di as text "--------------------------------------------------"
        di as result "Procesando matricula ano: `y'"
        di as text "--------------------------------------------------"

        local files : dir "$mat_raw" files "*`y'*"

        if `"`files'"' == "" {
            di as error "No se encontro archivo de matricula para `y'"
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
            di as error "No se encontro CSV usable de matricula para `y'"
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
            di as error "No existe codigo_demre en matricula `y'. Se salta."
            continue
        }

        capture confirm variable codigo_unico
        if _rc != 0 {
            di as error "No existe codigo_unico en matricula `y'. Se salta."
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
        replace t_codigo_carrera = "" if upper(t_codigo_carrera) == "SIN INFORMACION"

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
    compress
    save "`ck_xwalk'", replace
}

use "`ck_xwalk'", clear

di as text "=================================================="
di as result "Crosswalk DEMRE -> CODIGO_UNICO"
di as text "=================================================="
count
duplicates report ao_proceso t_codigo_carrera

************************************************************
* 2. Append bases de titulados 2007-2024, o cargar checkpoint
************************************************************

capture confirm file "`ck_tit'"
if _rc == 0 {
    di as result "Checkpoint encontrado: `ck_tit'"
}
else {

    tempfile all_tit
    local first 1

    forvalues y = 2007/2024 {

        di as text "--------------------------------------------------"
        di as result "Procesando titulados ano: `y'"
        di as text "--------------------------------------------------"

        local files : dir "$tit_raw" files "*`y'*"

        if `"`files'"' == "" {
            di as error "No se encontro archivo de titulados para `y'"
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
            di as error "No se encontro CSV usable de titulados para `y'"
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
        * 2.1 Ano de titulacion
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
        * 2.3 Ano ingreso carrera origen
        ************************************************************

        local entryvar ""

        foreach cand in ano_ing_carr_ori anio_ing_carr_ori a_o_ing_carr_ori año_ing_carr_ori {
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
            di as error "No se encontro variable de ano ingreso carrera origen en titulados `y'."
            describe
            exit 111
        }

        di as result "Variable ano ingreso carrera origen: `entryvar'"

        capture confirm numeric variable `entryvar'
        if _rc == 0 {
            tostring `entryvar', gen(entry_str) format(%12.0f) force
        }
        else {
            gen entry_str = trim(`entryvar')
        }

        destring entry_str, gen(grad_entry_year) force

        replace grad_entry_year = . if inlist(grad_entry_year, 9995, 9998, 9999, 1900)

        ************************************************************
        * 2.4 Codigo unico
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
        replace grad_codigo_unico = "" if upper(grad_codigo_unico) == "SIN INFORMACION"

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

        keep if nivel_global == "PREGRADO" | nivel_global == ""

        ************************************************************
        * 2.6 Mantener variables utiles
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
        di as error "No se proceso ningun archivo de titulados."
        exit 601
    }

    use `all_tit', clear
    compress
    save "`ck_tit'", replace
}

use "`ck_tit'", clear

di as text "=================================================="
di as result "Base de titulados construida/cargada"
di as text "=================================================="
count

************************************************************
* 3. Preparar muestra de postulaciones, o cargar checkpoint
************************************************************

capture confirm file "`ck_full'"
if _rc == 0 {
    di as result "Checkpoint encontrado: `ck_full'"
}
else {
    use "$processed/analysis_sample_with_fields_final.dta", clear

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

    compress
    save "`ck_full'", replace
}

use "`ck_full'", clear
count

************************************************************
* 4. Crear muestra unica MRUN-ano para outcomes generales
************************************************************

capture confirm file "`ck_keys'"
if _rc == 0 {
    di as result "Checkpoint encontrado: `ck_keys'"
}
else {
    use "`ck_full'", clear
    keep mrun_str ao_proceso
    duplicates drop
    compress
    save "`ck_keys'", replace
}

************************************************************
* 5. Outcomes generales: graduates_he_8y y graduates_uni_8y
************************************************************

capture confirm file "`ck_general'"
if _rc == 0 {
    di as result "Checkpoint encontrado: `ck_general'"
}
else {
    use "`ck_tit'", clear

    joinby mrun_str using "`ck_keys'"

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

    compress
    save "`ck_general'", replace
}

************************************************************
* 6A. Outcome antiguo: graduates_target_8y
*     Programa target de postulacion.
************************************************************

capture confirm file "`ck_starget'"
if _rc == 0 {
    di as result "Checkpoint encontrado: `ck_starget'"
}
else {
    use "`ck_full'", clear

    capture confirm numeric variable t_codigo_carrera
    if _rc != 0 {
        destring t_codigo_carrera, replace force
    }

    joinby ao_proceso t_codigo_carrera using "`ck_xwalk'"

    rename target_codigo_unico grad_codigo_unico

    compress
    save "`ck_starget'", replace
}

capture confirm file "`ck_gtarget'"
if _rc == 0 {
    di as result "Checkpoint encontrado: `ck_gtarget'"
}
else {
    use "`ck_tit'", clear

    joinby mrun_str grad_codigo_unico using "`ck_starget'"

    keep if grad_entry_year == ao_proceso
    keep if grad_year >= ao_proceso
    keep if grad_year <= ao_proceso + 8

    gen grad_target_aux = 1

    collapse (max) graduates_target_8y = grad_target_aux, by(sample_id)

    compress
    save "`ck_gtarget'", replace
}

************************************************************
* 6B. Outcome nuevo: graduates_enrolled_program_8y
*     Programa/carrera efectivamente matriculado inicialmente.
************************************************************

capture confirm file "`ck_senrolled'"
if _rc == 0 {
    di as result "Checkpoint encontrado: `ck_senrolled'"
}
else {
    use "`ck_full'", clear

    capture confirm variable codigo_carrera_mineduc
    if _rc != 0 {
        di as error "No existe codigo_carrera_mineduc en la muestra. Debe venir desde 03_build_outcomes.do."
        exit 111
    }

    capture confirm variable codigo_carrera_demre
    if _rc != 0 {
        di as error "No existe codigo_carrera_demre en la muestra. Debe venir desde 03_build_outcomes.do."
        exit 111
    }

    capture confirm numeric variable codigo_carrera_mineduc
    if _rc != 0 {
        destring codigo_carrera_mineduc, replace force
    }

    capture confirm numeric variable codigo_carrera_demre
    if _rc != 0 {
        destring codigo_carrera_demre, replace force
    }

    gen enrolled_codigo_carrera = codigo_carrera_mineduc
    replace enrolled_codigo_carrera = codigo_carrera_demre ///
        if missing(enrolled_codigo_carrera) & !missing(codigo_carrera_demre)

    label var enrolled_codigo_carrera ///
        "Program code effectively enrolled in: MINEDUC, then DEMRE fallback"

    keep if !missing(enrolled_codigo_carrera)

    * El crosswalk espera que el codigo DEMRE del programa se llame t_codigo_carrera.
    * Por eso reemplazamos temporalmente el t_codigo_carrera de postulacion por el
    * codigo de matricula efectiva. Esto afecta solo este checkpoint.
    drop t_codigo_carrera
    rename enrolled_codigo_carrera t_codigo_carrera

    joinby ao_proceso t_codigo_carrera using "`ck_xwalk'"

    * Importante: el joinby con titulados espera el mismo nombre que en titulados.
    rename target_codigo_unico grad_codigo_unico

    keep sample_id mrun_str ao_proceso t_codigo_carrera grad_codigo_unico
    duplicates drop

    compress
    save "`ck_senrolled'", replace
}

capture confirm file "`ck_genrolled'"
if _rc == 0 {
    di as result "Checkpoint encontrado: `ck_genrolled'"
}
else {
    use "`ck_tit'", clear

    joinby mrun_str grad_codigo_unico using "`ck_senrolled'"

    keep if grad_entry_year == ao_proceso
    keep if grad_year >= ao_proceso
    keep if grad_year <= ao_proceso + 8

    gen grad_enrolled_program_aux = 1

    collapse (max) graduates_enrolled_program_8y = grad_enrolled_program_aux, by(sample_id)

    compress
    save "`ck_genrolled'", replace
}

************************************************************
* 7. Merge outcomes a muestra completa
************************************************************

use "`ck_full'", clear

merge m:1 mrun_str ao_proceso using "`ck_general'"
replace graduates_he_8y = 0 if missing(graduates_he_8y)
replace graduates_uni_8y = 0 if missing(graduates_uni_8y)
drop _merge

merge 1:1 sample_id using "`ck_gtarget'"
replace graduates_target_8y = 0 if missing(graduates_target_8y)
drop _merge

merge 1:1 sample_id using "`ck_genrolled'"
replace graduates_enrolled_program_8y = 0 if missing(graduates_enrolled_program_8y)
drop _merge sample_id

label var graduates_he_8y     "Graduated from higher education within 8 years"
label var graduates_uni_8y    "Graduated from university within 8 years"
label var graduates_target_8y "Graduated from target application program within 8 years"
label var graduates_enrolled_program_8y ///
    "Graduated from initially enrolled program within 8 years"

compress

save "`output'", replace

************************************************************
* 8. Diagnostico final
************************************************************

di as text "=================================================="
di as result "Graduation outcomes built: old target + enrolled program"
di as text "=================================================="

count

tab graduates_he_8y
tab graduates_uni_8y
tab graduates_target_8y
tab graduates_enrolled_program_8y

di as text "Comparacion target antiguo vs enrolled-program nuevo:"
tab graduates_target_8y graduates_enrolled_program_8y, missing

di as text "Comparacion solo entre quienes enrolls_target == 1, si existe esa variable:"
capture confirm variable enrolls_target
if _rc == 0 {
    tab graduates_target_8y graduates_enrolled_program_8y if enrolls_target == 1, missing
}

capture confirm variable field
if _rc == 0 {
    tab field graduates_he_8y, row
    tab field graduates_uni_8y, row
    tab field graduates_target_8y, row
    tab field graduates_enrolled_program_8y, row
}

di as result "Output guardado en:"
di as result "`output'"

di as text "Checkpoints usados/creados en $processed con prefijo check_06b_"
