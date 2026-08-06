/**********************************************************************
* 02_build_sua_markets_exposure.do
*
* Objetivos:
*
*   1. Incorporar geografía oficial 2018 al panel SIES.
*
*   2. Construir un crosswalk reutilizable entre alternativas DEMRE
*      y mercados académico-geográficos.
*
*   3. Construir exposición pretratamiento a la entrada de ocho
*      universidades al SUA en 2012.
*
* Período pretratamiento:
*   2009-2011.
*
* Campos académicos:
*
*   broad_area:
*       area_conocimiento
*
*   cine_subarea:
*       cine_f_97_subarea
*
*   generic_area:
*       area_carrera_generica
*
* Niveles geográficos:
*
*   region
*   provincia
*   comuna
*
* Mercado principal:
*   cine_subarea × region.
*
* Exposición:
*
*                    Entrant enrollment 2009-2011
*   -------------------------------------------------------------
*   Entrant enrollment + incumbent enrollment, 2009-2011
*
* Outputs:
*
*   $processed/sies_program_year_geo_2007_2016.dta
*
*   $processed/sua_demre_market_crosswalk_2007_2016.dta
*
*   $processed/sua_market_exposure_2009_2011.dta
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

/**********************************************************************
* 0. Rutas y archivos temporales
**********************************************************************/

local geo_codebook ///
    "C:/Users/jigodoy/Documents/GitHub/education_and_productitivity/Data/worked/geographic_codebook.dta"

local output_geo ///
    "$processed/sies_program_year_geo_2007_2016.dta"

local output_crosswalk ///
    "$processed/sua_demre_market_crosswalk_2007_2016.dta"

local output_exposure ///
    "$processed/sua_market_exposure_2009_2011.dta"

tempfile ///
    roster ///
    geo_clean ///
    sies_geo ///
    entrant_geo ///
    crosswalk_long ///
    demre_all ///
    entrant_markets ///
    incumbent_markets

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
* 2. Roster institucional
**********************************************************************/

use ///
    "$processed/sua_university_roster_manual.dta", ///
    clear

replace sigla_universidad = ///
    upper(itrim(ustrtrim(sigla_universidad)))

keep ///
    sigla_universidad ///
    sua_incumbent ///
    entrant_2012

isid sigla_universidad

save `roster', replace

/**********************************************************************
* 3. Preparar codebook geográfico oficial
**********************************************************************/

use "`geo_codebook'", clear

keep ///
    id_region ///
    region ///
    id_provincia ///
    provincia ///
    id_comuna ///
    comuna

make_text_key comuna, ///
    generate(comuna_key)

replace comuna_key = "CALERA" ///
    if comuna_key == "LA CALERA"

rename id_comuna ///
    id_comuna_2018

rename comuna ///
    comuna_2018

rename id_provincia ///
    id_provincia_2018

rename provincia ///
    provincia_2018

rename id_region ///
    id_region_2018

rename region ///
    region_2018

isid comuna_key

save `geo_clean', replace

/**********************************************************************
* 4. Incorporar geografía oficial al panel SIES
**********************************************************************/

use ///
    "$processed/sies_program_year_raw_2007_2016.dta", ///
    clear

make_text_key comuna_sede, ///
    generate(comuna_key)

replace comuna_key = "CALERA" ///
    if comuna_key == "LA CALERA"

merge m:1 ///
    comuna_key ///
    using `geo_clean', ///
    keep(master match) ///
    generate(_merge_geo)

assert _merge_geo == 3

drop ///
    _merge_geo ///
    comuna_key

isid ///
    codigo_unico ///
    ao_proceso

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
    id_comuna_2018 ///
    comuna_2018 ///
    id_provincia_2018 ///
    provincia_2018 ///
    id_region_2018 ///
    region_2018 ///
    comuna_sede ///
    provincia_sede ///
    region_sede

sort ///
    program_id_sies ///
    ao_proceso

compress

save "`output_geo'", replace
save `sies_geo', replace

/**********************************************************************
* 5. Definiciones de mercado
**********************************************************************/

local fieldvars ///
    area_conocimiento ///
    cine_f_97_subarea ///
    area_carrera_generica

local markettypes ///
    broad_area ///
    cine_subarea ///
    generic_area

local geoidvars ///
    id_region_2018 ///
    id_provincia_2018 ///
    id_comuna_2018

local geonamevars ///
    region_2018 ///
    provincia_2018 ///
    comuna_2018

local geotypes ///
    region ///
    provincia ///
    comuna

/**********************************************************************
* 6. Construir crosswalk DEMRE–mercado 2007-2016
*
* Formato largo:
*
*   market_type
*   geo_type
*   market_field
*   geo_id
*   geo_name
*
* Métodos:
*
*   1. universidad × año × código DEMRE
*
*   2. universidad × año × nombre de carrera × sede
*
* Solo se conservan llaves que identifican un único mercado dentro
* de cada combinación de campo académico y nivel geográfico.
**********************************************************************/

local first_crosswalk = 1

forvalues i = 1/3 {

    local fieldvar : word `i' of `fieldvars'
    local markettype : word `i' of `markettypes'

    forvalues g = 1/3 {

        local geoidvar : word `g' of `geoidvars'
        local geonamevar : word `g' of `geonamevars'
        local geotype : word `g' of `geotypes'

        tempfile ///
            crosswalk_code ///
            crosswalk_name

        /**************************************************************
        * 6.1 Correspondencia por código DEMRE
        **************************************************************/

        use `sies_geo', clear

        keep if ///
            sua_incumbent == 1 & ///
            !missing(codigo_demre)

        make_text_key `fieldvar', ///
            generate(market_field)

        keep ///
            ao_proceso ///
            sigla_universidad ///
            codigo_demre ///
            market_field ///
            `geoidvar' ///
            `geonamevar'

        rename `geoidvar' ///
            geo_id

        rename `geonamevar' ///
            geo_name

        drop if ///
            market_field == "" | ///
            missing(geo_id)

        duplicates drop

        bysort ///
            ao_proceso ///
            sigla_universidad ///
            codigo_demre: ///
            gen int n_code_markets = _N

        keep if n_code_markets == 1

        drop n_code_markets

        isid ///
            ao_proceso ///
            sigla_universidad ///
            codigo_demre

        gen str244 carrera_key = ""
        gen str244 sede_key = ""

        gen str20 market_type = ///
            "`markettype'"

        gen str12 geo_type = ///
            "`geotype'"

        gen byte market_match_method = 1

        save `crosswalk_code', replace

        /**************************************************************
        * 6.2 Correspondencia por nombre de carrera y sede
        **************************************************************/

        use `sies_geo', clear

        keep if sua_incumbent == 1

        make_text_key `fieldvar', ///
            generate(market_field)

        make_text_key nomb_carrera, ///
            generate(carrera_key)

        make_text_key nomb_sede, ///
            generate(sede_key)

        keep ///
            ao_proceso ///
            sigla_universidad ///
            carrera_key ///
            sede_key ///
            market_field ///
            `geoidvar' ///
            `geonamevar'

        rename `geoidvar' ///
            geo_id

        rename `geonamevar' ///
            geo_name

        drop if ///
            carrera_key == "" | ///
            sede_key == "" | ///
            market_field == "" | ///
            missing(geo_id)

        duplicates drop

        bysort ///
            ao_proceso ///
            sigla_universidad ///
            carrera_key ///
            sede_key: ///
            gen int n_name_markets = _N

        keep if n_name_markets == 1

        drop n_name_markets

        isid ///
            ao_proceso ///
            sigla_universidad ///
            carrera_key ///
            sede_key

        gen long codigo_demre = .

        gen str20 market_type = ///
            "`markettype'"

        gen str12 geo_type = ///
            "`geotype'"

        gen byte market_match_method = 2

        append using `crosswalk_code'

        order ///
            market_type ///
            geo_type ///
            market_match_method ///
            ao_proceso ///
            sigla_universidad ///
            codigo_demre ///
            carrera_key ///
            sede_key ///
            market_field ///
            geo_id ///
            geo_name

        if `first_crosswalk' == 1 {

            save `crosswalk_long', replace
            local first_crosswalk = 0
        }
        else {

            append using `crosswalk_long'
            save `crosswalk_long', replace
        }
    }
}

/**********************************************************************
* 6.3 Guardar crosswalk final
**********************************************************************/

use `crosswalk_long', clear

sort ///
    market_type ///
    geo_type ///
    market_match_method ///
    ao_proceso ///
    sigla_universidad ///
    codigo_demre ///
    carrera_key ///
    sede_key

compress

save "`output_crosswalk'", replace

/**********************************************************************
* 7. Incorporar geografía a entrantes pretratamiento
**********************************************************************/

use ///
    "$processed/sua_preperiod_program_year_2009_2011.dta", ///
    clear

merge 1:1 ///
    codigo_unico ///
    ao_proceso ///
    using `sies_geo', ///
    keep(master match) ///
    keepusing( ///
        id_comuna_2018 ///
        comuna_2018 ///
        id_provincia_2018 ///
        provincia_2018 ///
        id_region_2018 ///
        region_2018 ///
    ) ///
    generate(_merge_geo_pre)

assert _merge_geo_pre == 3

drop _merge_geo_pre

isid ///
    codigo_unico ///
    ao_proceso

save `entrant_geo', replace

/**********************************************************************
* 8. Construir matrícula entrante por mercado
**********************************************************************/

local first_entrant = 1

forvalues i = 1/3 {

    local fieldvar : word `i' of `fieldvars'
    local markettype : word `i' of `markettypes'

    forvalues g = 1/3 {

        local geoidvar : word `g' of `geoidvars'
        local geonamevar : word `g' of `geonamevars'
        local geotype : word `g' of `geotypes'

        use `entrant_geo', clear

        make_text_key `fieldvar', ///
            generate(market_field)

        rename `geoidvar' ///
            geo_id

        rename `geonamevar' ///
            geo_name

        drop if ///
            market_field == "" | ///
            missing(geo_id)

        gen double entrant_psu_sum = ///
            mean_psu_lm_firstyear * ///
            n_firstyear_psu ///
            if n_firstyear_psu > 0

        replace entrant_psu_sum = 0 ///
            if missing(entrant_psu_sum)

        egen byte tag_entrant_program = ///
            tag( ///
                codigo_unico ///
                market_field ///
                geo_id ///
            )

        collapse ///
            (sum) ///
                entrant_firstyear_3y = N_firstyear ///
                entrant_psu_students_3y = n_firstyear_psu ///
                entrant_psu_sum_3y = entrant_psu_sum ///
                n_entrant_programs = tag_entrant_program ///
            (firstnm) ///
                geo_name, ///
            by( ///
                market_field ///
                geo_id ///
            )

        gen str20 market_type = ///
            "`markettype'"

        gen str12 geo_type = ///
            "`geotype'"

        gen double entrant_selectivity = ///
            entrant_psu_sum_3y / ///
            entrant_psu_students_3y ///
            if entrant_psu_students_3y > 0

        gen double entrant_psu_coverage = ///
            entrant_psu_students_3y / ///
            entrant_firstyear_3y ///
            if entrant_firstyear_3y > 0

        drop entrant_psu_sum_3y

        if `first_entrant' == 1 {

            save `entrant_markets', replace
            local first_entrant = 0
        }
        else {

            append using `entrant_markets'
            save `entrant_markets', replace
        }
    }
}

/**********************************************************************
* 9. Construir matrícula incumbente Formulario D, 2009-2011
**********************************************************************/

local first_demre = 1

forvalues y = 2009/2011 {

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

    merge m:1 ///
        sigla_universidad ///
        using `roster', ///
        keep(match) ///
        nogen

    keep if sua_incumbent == 1

    make_text_key nombre_carrera, ///
        generate(carrera_key)

    make_text_key sede_carrera, ///
        generate(sede_key)

    gen byte one_student = 1

    collapse ///
        (sum) ///
            incumbent_firstyear = one_student, ///
        by( ///
            ao_proceso ///
            sigla_universidad ///
            codigo_carrera ///
            carrera_key ///
            sede_key ///
        )

    rename codigo_carrera ///
        codigo_demre

    if `first_demre' == 1 {

        save `demre_all', replace
        local first_demre = 0
    }
    else {

        append using `demre_all'
        save `demre_all', replace
    }
}

/**********************************************************************
* 10. Asignar matrícula incumbente a cada mercado
**********************************************************************/

local first_incumbent = 1

forvalues i = 1/3 {

    local markettype : word `i' of `markettypes'

    forvalues g = 1/3 {

        local geotype : word `g' of `geotypes'

        tempfile ///
            crosswalk_code_use ///
            crosswalk_name_use

        /**************************************************************
        * 10.1 Correspondencia por código DEMRE
        **************************************************************/

        use "`output_crosswalk'", clear

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

        save `crosswalk_code_use', replace

        /**************************************************************
        * 10.2 Correspondencia por carrera y sede
        **************************************************************/

        use "`output_crosswalk'", clear

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

        save `crosswalk_name_use', replace

        /**************************************************************
        * 10.3 Aplicar crosswalk a Formulario D
        **************************************************************/

        use `demre_all', clear

        merge m:1 ///
            ao_proceso ///
            sigla_universidad ///
            codigo_demre ///
            using `crosswalk_code_use', ///
            keep(master match) ///
            generate(_merge_code)

        merge m:1 ///
            ao_proceso ///
            sigla_universidad ///
            carrera_key ///
            sede_key ///
            using `crosswalk_name_use', ///
            keep(master match) ///
            generate(_merge_name)

        gen str244 market_field = ///
            market_field_code ///
            if _merge_code == 3

        replace market_field = ///
            market_field_name ///
            if ///
                market_field == "" & ///
                _merge_name == 3

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

        gen byte market_match_method = .

        replace market_match_method = 1 ///
            if _merge_code == 3

        replace market_match_method = 2 ///
            if ///
                missing(market_match_method) & ///
                _merge_name == 3

        drop if missing(market_match_method)

        egen byte tag_incumbent_option = ///
            tag( ///
                sigla_universidad ///
                codigo_demre ///
                carrera_key ///
                sede_key ///
                market_field ///
                geo_id ///
            )

        collapse ///
            (sum) ///
                incumbent_firstyear_3y = incumbent_firstyear ///
                n_incumbent_options = tag_incumbent_option ///
            (firstnm) ///
                geo_name, ///
            by( ///
                market_field ///
                geo_id ///
            )

        gen str20 market_type = ///
            "`markettype'"

        gen str12 geo_type = ///
            "`geotype'"

        if `first_incumbent' == 1 {

            save `incumbent_markets', replace
            local first_incumbent = 0
        }
        else {

            append using `incumbent_markets'
            save `incumbent_markets', replace
        }
    }
}

/**********************************************************************
* 11. Combinar matrícula entrante e incumbente
**********************************************************************/

use `entrant_markets', clear

merge 1:1 ///
    market_type ///
    geo_type ///
    market_field ///
    geo_id ///
    using `incumbent_markets', ///
    generate(_merge_market)

replace entrant_firstyear_3y = 0 ///
    if missing(entrant_firstyear_3y)

replace entrant_psu_students_3y = 0 ///
    if missing(entrant_psu_students_3y)

replace n_entrant_programs = 0 ///
    if missing(n_entrant_programs)

replace incumbent_firstyear_3y = 0 ///
    if missing(incumbent_firstyear_3y)

replace n_incumbent_options = 0 ///
    if missing(n_incumbent_options)

assert geo_name != ""

drop _merge_market

/**********************************************************************
* 12. Construir exposición
**********************************************************************/

gen double total_firstyear_3y = ///
    entrant_firstyear_3y + ///
    incumbent_firstyear_3y

gen double avg_entrant_firstyear = ///
    entrant_firstyear_3y / 3

gen double avg_incumbent_firstyear = ///
    incumbent_firstyear_3y / 3

gen double avg_total_firstyear = ///
    total_firstyear_3y / 3

gen double sua_exposure = ///
    entrant_firstyear_3y / ///
    total_firstyear_3y ///
    if total_firstyear_3y > 0

gen double sua_exposure_pct = ///
    100 * sua_exposure

gen byte market_has_entrant = ///
    entrant_firstyear_3y > 0

gen byte market_has_incumbent = ///
    incumbent_firstyear_3y > 0

egen long market_id = group( ///
    market_type ///
    geo_type ///
    market_field ///
    geo_id ///
), label

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

label variable sua_exposure ///
    "Entrant first-year enrollment share, 2009-2011"

label variable entrant_selectivity ///
    "Mean Language-Math PSU of entrant first-year students, 2009-2011"

label variable entrant_psu_coverage ///
    "Share of entrant first-year students with valid Language-Math PSU"

/**********************************************************************
* 13. Ordenar y guardar
**********************************************************************/

order ///
    market_id ///
    market_type ///
    geo_type ///
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

sort ///
    market_type ///
    geo_type ///
    geo_id ///
    market_field

compress

isid ///
    market_type ///
    geo_type ///
    market_field ///
    geo_id

save "`output_exposure'", replace

/**********************************************************************
* 14. Resumen final
**********************************************************************/

tab market_type geo_type

preserve

    collapse ///
        (sum) ///
            entrant_firstyear_3y ///
            incumbent_firstyear_3y ///
            total_firstyear_3y, ///
        by( ///
            market_type ///
            geo_type ///
        )

    format ///
        entrant_firstyear_3y ///
        incumbent_firstyear_3y ///
        total_firstyear_3y ///
        %15.0fc

    sort ///
        market_type ///
        geo_type

    list, noobs clean

restore

preserve

    keep if ///
        market_type == "cine_subarea" & ///
        geo_type == "region"

    count

    di as result ///
        "Main CINE-region markets: " r(N)

    count if market_has_entrant == 1

    di as result ///
        "Main CINE-region markets with entrants: " r(N)

    summarize sua_exposure, detail

restore

preserve

    collapse ///
        (count) ///
            n_markets = market_id ///
        (mean) ///
            mean_exposure = sua_exposure ///
        (min) ///
            min_exposure = sua_exposure ///
        (max) ///
            max_exposure = sua_exposure, ///
        by( ///
            market_type ///
            geo_type ///
        )

    sort ///
        market_type ///
        geo_type

    list, noobs clean

restore

di as result ///
    "Panel geográfico guardado en: `output_geo'"

di as result ///
    "Crosswalk DEMRE-market guardado en: `output_crosswalk'"

di as result ///
    "Exposición por mercado guardada en: `output_exposure'"