/**********************************************************************
* 01_build_sua_program_year_base.do
*
* Objetivo:
*   1. Construir un panel SIES programa-campus-año para las
*      universidades incumbentes y entrantes.
*
*   2. Construir la matrícula nueva de las universidades entrantes
*      durante 2009-2011, antes de su incorporación al SUA.
*
* Unidad del panel general:
*   codigo_unico × ao_proceso
*
* Unidad de la base pretratamiento:
*   codigo_unico × ao_proceso
*
* N_firstyear en pretratamiento:
*   Estudiantes de las ocho universidades entrantes cuyo año de ingreso
*   a la carrera de origen coincide con el año observado.
*
* Outputs:
*   $processed/sies_program_year_raw_2007_2016.dta
*   $processed/sua_preperiod_program_year_2009_2011.dta
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

tempfile ///
    roster ///
    psu_pre ///
    all_programs ///
    entrant_pre

local first_program 1
local first_entrant 1

/**********************************************************************
* 1. Roster SUA
**********************************************************************/

use "$processed/sua_university_roster_manual.dta", clear

capture confirm numeric variable cod_inst

if !_rc {

    tostring cod_inst, ///
        replace ///
        format(%20.0f) ///
        force
}

replace cod_inst = ///
    itrim(ustrtrim(cod_inst))

replace sigla_universidad = ///
    upper(itrim(ustrtrim(sigla_universidad)))

keep ///
    cod_inst ///
    sigla_universidad ///
    sua_incumbent ///
    entrant_2012

isid cod_inst

save `roster', replace

/**********************************************************************
* 2. PSU 2009-2011
**********************************************************************/

use "$processed/psu_scores.dta", clear

keep if inrange(ao_proceso, 2009, 2011)

gen double psu_lm_actual = ///
    (lyc_actual + mate_actual) / 2 ///
    if ///
        inrange(lyc_actual, 150, 850) & ///
        inrange(mate_actual, 150, 850)

gen double psu_lm_anterior = ///
    (lyc_anterior + mate_anterior) / 2 ///
    if ///
        inrange(lyc_anterior, 150, 850) & ///
        inrange(mate_anterior, 150, 850)

gen double psu_lm = psu_lm_actual

replace psu_lm = psu_lm_anterior ///
    if ///
        missing(psu_lm) & ///
        !missing(psu_lm_anterior)

keep ///
    mrun ///
    ao_proceso ///
    psu_lm

isid ///
    mrun ///
    ao_proceso

save `psu_pre', replace

/**********************************************************************
* 3. Procesar matrícula SIES
**********************************************************************/

forvalues y = 2007/2016 {

    import delimited ///
        "$mat_raw/Matrícula_Ed_Superior_`y'.csv", ///
        delimiter(";") ///
        varnames(1) ///
        clear ///
        encoding(UTF-8) ///
        bindquote(strict)

    rename *, lower

    gen int ao_proceso = `y'

    /******************************************************************
    * 3.1 Identificadores
    ******************************************************************/

    capture confirm numeric variable mrun

    if _rc {

        destring mrun, ///
            replace ///
            force
    }

    capture confirm numeric variable codigo_demre

    if _rc {

        destring codigo_demre, ///
            replace ///
            force
    }

    capture confirm numeric variable cod_inst

    if !_rc {

        tostring cod_inst, ///
            replace ///
            format(%20.0f) ///
            force
    }

    replace cod_inst = ///
        itrim(ustrtrim(cod_inst))

    capture confirm numeric variable codigo_unico

    if !_rc {

        tostring codigo_unico, ///
            replace ///
            format(%20.0f) ///
            force
    }

    replace codigo_unico = ///
        itrim(ustrtrim(codigo_unico))

    drop if ///
        codigo_unico == "" | ///
        missing(mrun)

    /******************************************************************
    * 3.2 Universo académico
    ******************************************************************/

    replace nivel_global = ///
        lower(itrim(ustrtrim(nivel_global)))

    replace tipo_plan_carr = ///
        lower(itrim(ustrtrim(tipo_plan_carr)))

    keep if strpos(nivel_global, "pregrado") > 0
    keep if tipo_plan_carr == "plan regular"

    merge m:1 ///
        cod_inst ///
        using `roster', ///
        keep(match) ///
        nogen

    /******************************************************************
    * 3.3 Limpiar variables que se conservarán
    ******************************************************************/

		foreach v in ///
		nomb_inst ///
		nomb_sede ///
		nomb_carrera ///
		area_conocimiento ///
		cine_f_97_subarea ///
		area_carrera_generica ///
		comuna_sede ///
		provincia_sede ///
		region_sede {

		capture confirm string variable `v'

		if _rc {

			tostring `v', ///
				replace ///
				force
		}

		replace `v' = ///
			itrim(ustrtrim(`v'))
	}

    /******************************************************************
    * 3.4 Panel general de programas
    ******************************************************************/

    preserve

        keep ///
			codigo_unico ///
			ao_proceso ///
			cod_inst ///
			sigla_universidad ///
			sua_incumbent ///
			entrant_2012 ///
			codigo_demre ///
			nomb_inst ///
			nomb_sede ///
			nomb_carrera ///
			area_conocimiento ///
			cine_f_97_subarea ///
			area_carrera_generica ///
			comuna_sede ///
			provincia_sede ///
			region_sede

        duplicates drop

        bysort ///
            codigo_unico ///
            ao_proceso: ///
            keep if _n == 1

        isid ///
            codigo_unico ///
            ao_proceso

        if `first_program' == 1 {

            save `all_programs', replace
            local first_program 0
        }
        else {

            append using `all_programs'
            save `all_programs', replace
        }

    restore

    /******************************************************************
    * 3.5 Entrantes durante 2009-2011
    ******************************************************************/

    if inrange(`y', 2009, 2011) {

        keep if entrant_2012 == 1

        keep if ///
            anio_ing_carr_ori == ao_proceso

        duplicates drop ///
            mrun ///
            ao_proceso ///
            codigo_unico, ///
            force

        merge m:1 ///
            mrun ///
            ao_proceso ///
            using `psu_pre', ///
            keep(master match) ///
            nogen

        gen byte one_student = 1

        gen byte one_psu = ///
            !missing(psu_lm)

        collapse ///
            (sum) ///
                N_firstyear = one_student ///
                n_firstyear_psu = one_psu ///
            (mean) ///
                mean_psu_lm_firstyear = psu_lm, ///
            by( ///
                codigo_unico ///
                ao_proceso ///
            )

        isid ///
            codigo_unico ///
            ao_proceso

        if `first_entrant' == 1 {

            save `entrant_pre', replace
            local first_entrant 0
        }
        else {

            append using `entrant_pre'
            save `entrant_pre', replace
        }
    }
}

/**********************************************************************
* 4. Guardar panel general SIES
**********************************************************************/

use `all_programs', clear

isid ///
    codigo_unico ///
    ao_proceso

egen long program_id_sies = ///
    group(codigo_unico), ///
    label

order ///
    program_id_sies ///
    codigo_unico ///
    ao_proceso ///
    cod_inst ///
    sigla_universidad ///
    sua_incumbent ///
    entrant_2012 ///
    codigo_demre ///
    nomb_inst ///
    nomb_sede ///
    nomb_carrera ///
    area_conocimiento ///
    cine_f_97_subarea ///
    area_carrera_generica ///
    comuna_sede ///
    provincia_sede ///
    region_sede


sort ///
    program_id_sies ///
    ao_proceso

compress

save ///
    "$processed/sies_program_year_raw_2007_2016.dta", ///
    replace

/**********************************************************************
* 5. Guardar base pretratamiento de entrantes
**********************************************************************/

use `entrant_pre', clear

merge 1:1 ///
    codigo_unico ///
    ao_proceso ///
    using `all_programs', ///
    keep(match) ///
    nogen

isid ///
    codigo_unico ///
    ao_proceso

assert ///
    entrant_2012 == 1

assert ///
    inrange(ao_proceso, 2009, 2011)

assert ///
    N_firstyear > 0

assert ///
    n_firstyear_psu >= 0

assert ///
    n_firstyear_psu <= N_firstyear

assert ///
    inrange(mean_psu_lm_firstyear, 150, 850) ///
    if !missing(mean_psu_lm_firstyear)

egen long program_id_sies = ///
    group(codigo_unico), ///
    label

order ///
    program_id_sies ///
    codigo_unico ///
    ao_proceso ///
    cod_inst ///
    sigla_universidad ///
    entrant_2012 ///
    codigo_demre ///
    nomb_inst ///
    nomb_sede ///
    nomb_carrera ///
    area_conocimiento ///
    cine_f_97_subarea ///
    area_carrera_generica ///
    comuna_sede ///
    provincia_sede ///
    region_sede ///
    N_firstyear ///
    mean_psu_lm_firstyear ///
    n_firstyear_psu


sort ///
    program_id_sies ///
    ao_proceso

compress

save ///
    "$processed/sua_preperiod_program_year_2009_2011.dta", ///
    replace

/**********************************************************************
* 6. Resumen final
**********************************************************************/

count

di as result ///
    "Programa-año entrantes 2009-2011: " r(N)

egen byte tag_program = ///
    tag(codigo_unico)

count if tag_program == 1

di as result ///
    "Programas entrantes distintos: " r(N)

collapse ///
    (sum) ///
        N_firstyear ///
        n_firstyear_psu, ///
    by(ao_proceso)

gen double share_psu = ///
    n_firstyear_psu / N_firstyear

format ///
    N_firstyear ///
    n_firstyear_psu ///
    %12.0fc

format ///
    share_psu ///
    %9.3f

list, noobs clean