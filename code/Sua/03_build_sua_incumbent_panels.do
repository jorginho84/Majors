/**********************************************************************
* 03_build_sua_incumbent_panels.do
*
* Objetivo:
*   Construir los paneles 2007-2016 de alternativas de admisión de
*   las universidades incumbentes para nueve definiciones de mercado.
*
* Campos académicos:
*   1. broad_area
*   2. cine_subarea
*   3. generic_area
*
* Niveles geográficos:
*   1. region
*   2. provincia
*   3. comuna
*
* Especificación principal:
*   cine_subarea × region.
*
* Outcomes:
*   - Matrícula observada en Formulario D.
*   - PSU Lenguaje-Matemática promedio de los matriculados.
*
* Unidad:
*   universidad × código DEMRE × carrera × sede × año.
*
* Inputs:
*   $processed/sua_university_roster_manual.dta
*   $processed/psu_scores.dta
*   $processed/sua_demre_market_crosswalk_2007_2016.dta
*   $processed/sua_market_exposure_2009_2011.dta
*   Formulario D DEMRE 2007-2016
*
* Outputs:
*   Nueve paneles:
*
*   $processed/sua_incumbent_panel_<market>_<geo>_2007_2016.dta
*
*   Copia de la especificación principal:
*
*   $processed/sua_incumbent_panel_2007_2016.dta
**********************************************************************/

clear all
set more off

do "code/config.do"

/**********************************************************************
* 0. Archivos temporales
**********************************************************************/

tempfile ///
    roster ///
    psu_all ///
    incumbent_base ///
    coverage_summary

/**********************************************************************
* 1. Programa auxiliar para normalizar texto
**********************************************************************/

capture program drop make_text_key

program define make_text_key

    syntax varname, Generate(name)

    gen str244 `generate' = ///
        ustrupper( ///
            itrim( ///
                ustrtrim(`varlist') ///
            ) ///
        )

    replace `generate' = ///
        ustrnormalize(`generate', "nfd")

    replace `generate' = ///
        ustrregexra(`generate', "\p{Mark}", "")

    replace `generate' = ///
        ustrregexra( ///
            `generate', ///
            "[^A-Z0-9 ]", ///
            " " ///
        )

    replace `generate' = ///
        ustrregexra(`generate', " +", " ")

    replace `generate' = ///
        itrim(ustrtrim(`generate'))

end

/**********************************************************************
* 2. Roster de universidades incumbentes
**********************************************************************/

use ///
    "$processed/sua_university_roster_manual.dta", ///
    clear

replace sigla_universidad = ///
    upper(itrim(ustrtrim(sigla_universidad)))

keep if sua_incumbent == 1

keep ///
    sigla_universidad ///
    sua_incumbent

isid sigla_universidad

save `roster', replace

/**********************************************************************
* 3. Preparar puntajes PSU 2007-2016
*
* Prioridad:
*   1. Puntaje actual.
*   2. Puntaje anterior, cuando el actual no está disponible.
**********************************************************************/

use "$processed/psu_scores.dta", clear

keep if inrange(ao_proceso, 2007, 2016)

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

gen double psu_lm = ///
    psu_lm_actual

replace psu_lm = ///
    psu_lm_anterior ///
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

save `psu_all', replace

/**********************************************************************
* 4. Construir base común de incumbentes desde Formulario D
*
* Este bloque se ejecuta una sola vez y luego se reutiliza para las
* nueve definiciones de mercado.
**********************************************************************/

local first_year = 1

forvalues y = 2007/2016 {

    import delimited ///
        "$demre_raw/D_MATRICULA_`y'_PSU_MRUN.csv", ///
        delimiter(";") ///
        varnames(1) ///
        clear ///
        encoding(windows-1252)

    rename *, lower

    capture rename año_proceso ao_proceso
    capture rename ano_proceso ao_proceso
    capture rename a_o_proceso ao_proceso
    capture rename aæo_proceso ao_proceso

    capture confirm variable nombre_carrera

    if _rc {

        capture rename ///
            nomb_carrera ///
            nombre_carrera
    }

    foreach v in ///
        mrun ///
        ao_proceso ///
        codigo_carrera {

        capture confirm numeric variable `v'

        if _rc {

            destring `v', ///
                replace ///
                force
        }
    }

    replace ao_proceso = `y' ///
        if missing(ao_proceso)

    keep if ao_proceso == `y'

    replace sigla_universidad = ///
        upper(itrim(ustrtrim(sigla_universidad)))

    replace nombre_carrera = ///
        itrim(ustrtrim(nombre_carrera))

    replace sede_carrera = ///
        itrim(ustrtrim(sede_carrera))

    /******************************************************************
    * 4.1 Mantener únicamente universidades incumbentes
    ******************************************************************/

    merge m:1 ///
        sigla_universidad ///
        using `roster', ///
        keep(match) ///
        nogen

    /******************************************************************
    * 4.2 Incorporar PSU
    ******************************************************************/

    merge m:1 ///
        mrun ///
        ao_proceso ///
        using `psu_all', ///
        keep(master match) ///
        nogen

    /******************************************************************
    * 4.3 Normalizar nombre de carrera y sede
    ******************************************************************/

    make_text_key nombre_carrera, ///
        generate(carrera_key)

    make_text_key sede_carrera, ///
        generate(sede_key)

    /******************************************************************
    * 4.4 Agregar a alternativa DEMRE × sede × año
    ******************************************************************/

    gen byte one_student = 1

    gen byte one_psu = ///
        !missing(psu_lm)

    gen double psu_lm_sum = 0

    replace psu_lm_sum = ///
        psu_lm ///
        if !missing(psu_lm)

    collapse ///
        (sum) ///
            N_firstyear_incumbent = one_student ///
            n_firstyear_psu = one_psu ///
            psu_lm_sum = psu_lm_sum ///
        (firstnm) ///
            nombre_carrera ///
            sede_carrera, ///
        by( ///
            ao_proceso ///
            sigla_universidad ///
            codigo_carrera ///
            carrera_key ///
            sede_key ///
        )

    rename codigo_carrera ///
        codigo_demre

    gen double mean_psu_lm_firstyear = ///
        psu_lm_sum / ///
        n_firstyear_psu ///
        if n_firstyear_psu > 0

    gen double share_firstyear_psu = ///
        n_firstyear_psu / ///
        N_firstyear_incumbent

    drop psu_lm_sum

    if `first_year' == 1 {

        save `incumbent_base', replace
        local first_year = 0
    }
    else {

        append using `incumbent_base'
        save `incumbent_base', replace
    }
}

/**********************************************************************
* 5. Construir identificador estable de alternativa DEMRE
*
* Se crean llaves auxiliares para evitar que egen group() produzca
* missing cuando falta código DEMRE, nombre de carrera o sede.
*
* Los valores auxiliares no se utilizan para realizar los enlaces.
**********************************************************************/

use `incumbent_base', clear

gen str20 codigo_demre_id = ///
    string(codigo_demre, "%12.0f")

replace codigo_demre_id = ///
    "NO_DEMRE_CODE" ///
    if missing(codigo_demre)

gen str244 carrera_id_key = ///
    carrera_key

replace carrera_id_key = ///
    "NO_CAREER_NAME" ///
    if carrera_id_key == ""

gen str244 sede_id_key = ///
    sede_key

replace sede_id_key = ///
    "NO_CAMPUS_NAME" ///
    if sede_id_key == ""

egen long demre_program_id = group( ///
    sigla_universidad ///
    codigo_demre_id ///
    carrera_id_key ///
    sede_id_key ///
), label

assert !missing(demre_program_id)

isid ///
    demre_program_id ///
    ao_proceso

order ///
    demre_program_id ///
    ao_proceso ///
    sigla_universidad ///
    codigo_demre ///
    nombre_carrera ///
    sede_carrera ///
    carrera_key ///
    sede_key

sort ///
    demre_program_id ///
    ao_proceso

save `incumbent_base', replace

/**********************************************************************
* 6. Definiciones de mercado
**********************************************************************/

local markettypes ///
    broad_area ///
    cine_subarea ///
    generic_area

local geotypes ///
    region ///
    provincia ///
    comuna

/**********************************************************************
* 7. Construir los nueve paneles
**********************************************************************/

local first_summary = 1

forvalues i = 1/3 {

    local markettype : word `i' of `markettypes'

    forvalues g = 1/3 {

        local geotype : word `g' of `geotypes'

        tempfile ///
            exposure_selected ///
            crosswalk_code ///
            crosswalk_name

        /**************************************************************
        * 7.1 Preparar exposición del mercado seleccionado
        **************************************************************/

        use ///
            "$processed/sua_market_exposure_2009_2011.dta", ///
            clear

        keep if ///
            market_type == "`markettype'" & ///
            geo_type == "`geotype'"

        keep ///
            market_id ///
            market_field ///
            geo_id ///
            geo_name ///
            sua_exposure ///
            sua_exposure_pct ///
            entrant_firstyear_3y ///
            incumbent_firstyear_3y ///
            total_firstyear_3y ///
            avg_entrant_firstyear ///
            avg_incumbent_firstyear ///
            avg_total_firstyear ///
            entrant_selectivity ///
            entrant_psu_students_3y ///
            entrant_psu_coverage ///
            n_entrant_programs ///
            n_incumbent_options ///
            market_has_entrant ///
            market_has_incumbent

        isid ///
            market_field ///
            geo_id

        rename geo_name ///
            geo_name_exposure

        save `exposure_selected', replace

        /**************************************************************
        * 7.2 Crosswalk por código DEMRE
        **************************************************************/

        use ///
            "$processed/sua_demre_market_crosswalk_2007_2016.dta", ///
            clear

        keep if ///
            market_type == "`markettype'" & ///
            geo_type == "`geotype'" & ///
            market_match_method == 1

        keep ///
            ao_proceso ///
            sigla_universidad ///
            codigo_demre ///
            market_field ///
            geo_id ///
            geo_name

        isid ///
            ao_proceso ///
            sigla_universidad ///
            codigo_demre

        rename market_field ///
            market_field_code

        rename geo_id ///
            geo_id_code

        rename geo_name ///
            geo_name_code

        save `crosswalk_code', replace

        /**************************************************************
        * 7.3 Crosswalk por nombre de carrera y sede
        **************************************************************/

        use ///
            "$processed/sua_demre_market_crosswalk_2007_2016.dta", ///
            clear

        keep if ///
            market_type == "`markettype'" & ///
            geo_type == "`geotype'" & ///
            market_match_method == 2

        keep ///
            ao_proceso ///
            sigla_universidad ///
            carrera_key ///
            sede_key ///
            market_field ///
            geo_id ///
            geo_name

        isid ///
            ao_proceso ///
            sigla_universidad ///
            carrera_key ///
            sede_key

        rename market_field ///
            market_field_name

        rename geo_id ///
            geo_id_name

        rename geo_name ///
            geo_name_name

        save `crosswalk_name', replace

        /**************************************************************
        * 7.4 Incorporar mercado a la base común de incumbentes
        **************************************************************/

        use `incumbent_base', clear

        merge m:1 ///
            ao_proceso ///
            sigla_universidad ///
            codigo_demre ///
            using `crosswalk_code', ///
            keep(master match) ///
            generate(_merge_code)

        merge m:1 ///
            ao_proceso ///
            sigla_universidad ///
            carrera_key ///
            sede_key ///
            using `crosswalk_name', ///
            keep(master match) ///
            generate(_merge_name)

        /**************************************************************
        * 7.5 Definir campo académico
        **************************************************************/

        gen str244 market_field = ///
            market_field_code ///
            if _merge_code == 3

        replace market_field = ///
            market_field_name ///
            if ///
                market_field == "" & ///
                _merge_name == 3

        /**************************************************************
        * 7.6 Definir unidad geográfica
        **************************************************************/

        gen long geo_id = ///
            geo_id_code ///
            if _merge_code == 3

        replace geo_id = ///
            geo_id_name ///
            if ///
                missing(geo_id) & ///
                _merge_name == 3

        gen str80 geo_name = ///
            geo_name_code ///
            if _merge_code == 3

        replace geo_name = ///
            geo_name_name ///
            if ///
                geo_name == "" & ///
                _merge_name == 3

        /**************************************************************
        * 7.7 Método de correspondencia
        **************************************************************/

        gen byte market_match_method = .

        replace market_match_method = 1 ///
            if _merge_code == 3

        replace market_match_method = 2 ///
            if ///
                missing(market_match_method) & ///
                _merge_name == 3

        gen byte market_assigned = ///
            !missing(market_match_method)

        label define market_match_lbl ///
            1 "University-year-DEMRE code" ///
            2 "University-year-career-campus", ///
            replace

        label values market_match_method ///
            market_match_lbl

        drop ///
            _merge_code ///
            _merge_name ///
            market_field_code ///
            geo_id_code ///
            geo_name_code ///
            market_field_name ///
            geo_id_name ///
            geo_name_name

        /**************************************************************
        * 7.8 Incorporar exposición pretratamiento
        **************************************************************/

        merge m:1 ///
            market_field ///
            geo_id ///
            using `exposure_selected', ///
            keep(master match) ///
            generate(_merge_exposure)

        replace geo_name = ///
            geo_name_exposure ///
            if ///
                geo_name == "" & ///
                _merge_exposure == 3

        drop geo_name_exposure

        gen byte exposure_assigned = ///
            _merge_exposure == 3

        drop _merge_exposure

        /**************************************************************
        * 7.9 Variables de tratamiento
        **************************************************************/

        gen str20 market_type = ///
            "`markettype'"

        gen str12 geo_type = ///
            "`geotype'"

        gen byte post2012 = ///
            ao_proceso >= 2012

        gen double exposure_post = ///
            sua_exposure * post2012 ///
            if exposure_assigned == 1

        egen long field_geo_id = group( ///
            market_field ///
            geo_id ///
        ) if market_assigned == 1

        label variable market_type ///
            "Academic field definition"

        label variable geo_type ///
            "Geographic level"

        label variable market_field ///
            "Normalized academic field"

        label variable geo_id ///
            "Official geographic identifier"

        label variable geo_name ///
            "Official geographic name"

        label variable N_firstyear_incumbent ///
            "Enrollment in incumbent DEMRE admission alternative"

        label variable mean_psu_lm_firstyear ///
            "Mean Language-Math PSU of incumbent enrolled students"

        label variable n_firstyear_psu ///
            "Incumbent enrolled students with valid Language-Math PSU"

        label variable share_firstyear_psu ///
            "Share of incumbent enrolled students with valid PSU LM"

        label variable sua_exposure ///
            "Pre-treatment entrant enrollment share"

        label variable post2012 ///
            "Year 2012 or later"

        label variable exposure_post ///
            "Pre-treatment entrant exposure interacted with post-2012"

        /**************************************************************
        * 7.10 Verificar unidad de observación
        **************************************************************/

        assert !missing(demre_program_id)

        isid ///
            demre_program_id ///
            ao_proceso

        /**************************************************************
        * 7.11 Ordenar y guardar panel
        **************************************************************/

        order ///
            demre_program_id ///
            ao_proceso ///
            sigla_universidad ///
            codigo_demre ///
            nombre_carrera ///
            sede_carrera ///
            carrera_key ///
            sede_key ///
            market_type ///
            geo_type ///
            market_assigned ///
            market_match_method ///
            market_field ///
            field_geo_id ///
            geo_id ///
            geo_name ///
            exposure_assigned ///
            market_id ///
            sua_exposure ///
            sua_exposure_pct ///
            post2012 ///
            exposure_post ///
            N_firstyear_incumbent ///
            mean_psu_lm_firstyear ///
            n_firstyear_psu ///
            share_firstyear_psu ///
            entrant_firstyear_3y ///
            incumbent_firstyear_3y ///
            total_firstyear_3y ///
            avg_entrant_firstyear ///
            avg_incumbent_firstyear ///
            avg_total_firstyear ///
            entrant_selectivity ///
            entrant_psu_students_3y ///
            entrant_psu_coverage ///
            n_entrant_programs ///
            n_incumbent_options ///
            market_has_entrant ///
            market_has_incumbent ///
            codigo_demre_id ///
            carrera_id_key ///
            sede_id_key

        sort ///
            demre_program_id ///
            ao_proceso

        compress

        local output_panel ///
            "$processed/sua_incumbent_panel_`markettype'_`geotype'_2007_2016.dta"

        save "`output_panel'", replace

        /**************************************************************
        * 7.12 Guardar copia de la especificación principal
        **************************************************************/

        if ///
            "`markettype'" == "cine_subarea" & ///
            "`geotype'" == "region" {

            save ///
                "$processed/sua_incumbent_panel_2007_2016.dta", ///
                replace
        }

        /**************************************************************
        * 7.13 Construir resumen de cobertura
        **************************************************************/

        count

        local N_total = r(N)

        count if market_assigned == 1

        local N_market = r(N)

        count if exposure_assigned == 1

        local N_exposure = r(N)

        preserve

            clear

            set obs 1

            gen str20 market_type = ///
                "`markettype'"

            gen str12 geo_type = ///
                "`geotype'"

            gen long N_total = ///
                `N_total'

            gen long N_market_assigned = ///
                `N_market'

            gen long N_exposure_assigned = ///
                `N_exposure'

            gen double share_market_assigned = ///
                N_market_assigned / ///
                N_total

            gen double share_exposure_assigned = ///
                N_exposure_assigned / ///
                N_total

            if `first_summary' == 1 {

                save `coverage_summary', replace
                local first_summary = 0
            }
            else {

                append using `coverage_summary'
                save `coverage_summary', replace
            }

        restore

        di as result ///
            "`markettype' × `geotype': panel guardado en `output_panel'"
    }
}

/**********************************************************************
* 8. Guardar y mostrar resumen de cobertura
**********************************************************************/

use `coverage_summary', clear

format ///
    share_market_assigned ///
    share_exposure_assigned ///
    %9.3f

sort ///
    market_type ///
    geo_type

list, noobs clean

save ///
    "$processed/sua_incumbent_panel_coverage_2007_2016.dta", ///
    replace

/**********************************************************************
* 9. Confirmar outputs principales
**********************************************************************/

di as result ///
    "Nueve paneles de incumbentes construidos."

di as result ///
    "Panel principal guardado en:"

di as result ///
    "$processed/sua_incumbent_panel_2007_2016.dta"

di as result ///
    "Resumen de cobertura guardado en:"

di as result ///
    "$processed/sua_incumbent_panel_coverage_2007_2016.dta"