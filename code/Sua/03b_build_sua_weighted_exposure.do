/**********************************************************************
* 03b_build_sua_weighted_exposure.do
*
* Objetivo:
*   Construir exposiciones a la entrada al SUA ponderadas por la
*   distancia de selectividad entre programas incumbentes y entrantes.
*
* Kernels:
*
*   Triangular:
*       w_pq = max(0, 1 - |S_p-S_q|/50)
*
*   Gaussiano:
*       w_pq = exp[-0.5(|S_p-S_q|/50)^2]
*
* Exposición:
*
*       E_p^w = sum_q(w_pq * N_q,2009-2011)
*               ------------------------------
*               N_total mercado,2009-2011
*
* Inputs:
*   sua_preperiod_program_year_2009_2011.dta
*   sies_program_year_geo_2007_2016.dta
*   sua_incumbent_panel_<market>_<geo>_2007_2016.dta
*
* Outputs:
*   sua_incumbent_panel_w_<market>_<geo>_2007_2016.dta
*   sua_weighted_exposure_coverage.dta
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

/**********************************************************************
* 0. Parámetros y definiciones
**********************************************************************/

local h = 50

local markettypes ///
    broad_area ///
    cine_subarea ///
    generic_area

local fieldvars ///
    area_conocimiento ///
    cine_f_97_subarea ///
    area_carrera_generica

local geotypes ///
    region ///
    provincia ///
    comuna

local geoidvars ///
    id_region_2018 ///
    id_provincia_2018 ///
    id_comuna_2018

local geonamevars ///
    region_2018 ///
    provincia_2018 ///
    comuna_2018

tempfile ///
    entrants_pre ///
    coverage

tempname covpost

/**********************************************************************
* 1. Programa para normalizar variables de texto
**********************************************************************/

capture program drop make_text_key

program define make_text_key

    syntax varname, Generate(name)

    gen str244 `generate' = ///
        ustrupper(itrim(ustrtrim(`varlist')))

    replace `generate' = ///
        ustrnormalize(`generate', "nfd")

    replace `generate' = ///
        ustrregexra(`generate', "\p{Mark}", "")

    replace `generate' = ///
        ustrregexra(`generate', "[^A-Z0-9 ]", " ")

    replace `generate' = ///
        ustrregexra(`generate', " +", " ")

    replace `generate' = ///
        itrim(ustrtrim(`generate'))

end

/**********************************************************************
* 2. Preparar programas entrantes 2009-2011
*
* La base preperiod ya contiene la matrícula y PSU de los programas
* entrantes. Solo incorporamos los códigos geográficos del 02.
**********************************************************************/

use ///
    "$processed/sua_preperiod_program_year_2009_2011.dta", ///
    clear

keep if inrange(ao_proceso, 2009, 2011)

merge 1:1 ///
    codigo_unico ///
    ao_proceso ///
    using "$processed/sies_program_year_geo_2007_2016.dta", ///
    keep(master match) ///
    keepusing( ///
        id_region_2018 ///
        region_2018 ///
        id_provincia_2018 ///
        provincia_2018 ///
        id_comuna_2018 ///
        comuna_2018 ///
    ) ///
    generate(_merge_geo)

assert _merge_geo == 3

drop _merge_geo

isid ///
    codigo_unico ///
    ao_proceso

save `entrants_pre', replace

/**********************************************************************
* 3. Archivo compacto de cobertura
**********************************************************************/

postfile `covpost' ///
    str20 market_type ///
    str12 geo_type ///
    long n_programs ///
    long n_inc_psu ///
    long n_weighted ///
    double inc_psu_share ///
    double ent_psu_cov ///
    double mean_exp_unw ///
    double mean_exp_tri ///
    double mean_exp_gau ///
    using `coverage', ///
    replace

/**********************************************************************
* 4. Construir las exposiciones para nueve mercados
**********************************************************************/

forvalues i = 1/3 {

    local markettype : word `i' of `markettypes'
    local fieldvar   : word `i' of `fieldvars'

    forvalues g = 1/3 {

        local geotype  : word `g' of `geotypes'
        local geoid    : word `g' of `geoidvars'
        local geoname  : word `g' of `geonamevars'

        tempfile ///
            entrant_programs ///
            panel_py ///
            inc_scores ///
            inc_baseline ///
            inc_programs ///
            weighted_exp

        di as text ///
            "------------------------------------------------------------"

        di as result ///
            "Construyendo `markettype' × `geotype'"

        /**************************************************************
        * 4.1 Selectividad y matrícula de cada programa entrante
        **************************************************************/

        use `entrants_pre', clear

        make_text_key `fieldvar', ///
            generate(field_pre)

        rename `geoid' ///
            geo_pre

        rename `geoname' ///
            geo_name_pre

        drop if ///
            field_pre == "" | ///
            missing(geo_pre)

        gen double ent_psu_sum = ///
            mean_psu_lm_firstyear * ///
            n_firstyear_psu ///
            if ///
                !missing(mean_psu_lm_firstyear) & ///
                n_firstyear_psu > 0

        replace ent_psu_sum = 0 ///
            if missing(ent_psu_sum)

        collapse ///
            (sum) ///
                ent_n3 = N_firstyear ///
                ent_psu_n3 = n_firstyear_psu ///
                ent_psu_sum ///
            (firstnm) ///
                geo_name_pre, ///
            by( ///
                codigo_unico ///
                field_pre ///
                geo_pre ///
            )

        gen double ent_psu_pre = ///
            ent_psu_sum / ///
            ent_psu_n3 ///
            if ent_psu_n3 > 0

        drop ent_psu_sum

        rename codigo_unico ///
            entrant_id

        isid ///
            entrant_id ///
            field_pre ///
            geo_pre

        save `entrant_programs', replace

        /**************************************************************
        * 4.2 Cargar panel incumbente del 03
        **************************************************************/

        use ///
            "$processed/sua_incumbent_panel_`markettype'_`geotype'_2007_2016.dta", ///
            clear

        keep if ///
            exposure_assigned == 1 & ///
            market_has_incumbent == 1

        drop if missing( ///
            codigo_demre, ///
            sigla_universidad, ///
            ao_proceso, ///
            market_field, ///
            geo_id ///
        )

        /**************************************************************
        * 4.3 Armonizar código DEMRE
        *
        * Ejemplo:
        *   1142 -> 11042
        **************************************************************/

        gen str12 code_string = ///
            strtrim(string(codigo_demre, "%12.0f"))

        gen long demre_code_h = ///
            codigo_demre

        replace demre_code_h = ///
            real( ///
                substr( ///
                    code_string, ///
                    1, ///
                    length(code_string) - 2 ///
                ) + ///
                "0" + ///
                substr( ///
                    code_string, ///
                    length(code_string) - 1, ///
                    2 ///
                ) ///
            ) ///
            if length(code_string) == 4

        drop code_string

        assert !missing(demre_code_h)

        egen long program_id = group( ///
            sigla_universidad ///
            demre_code_h ///
        ), label

        assert !missing(program_id)

        /**************************************************************
        * 4.4 Recuperar unidad programa × año
        **************************************************************/

        gen double inc_psu_sum = ///
            mean_psu_lm_firstyear * ///
            n_firstyear_psu ///
            if ///
                !missing(mean_psu_lm_firstyear) & ///
                n_firstyear_psu > 0

        replace inc_psu_sum = 0 ///
            if missing(inc_psu_sum)

        collapse ///
            (sum) ///
                N_firstyear_incumbent ///
                n_firstyear_psu ///
                inc_psu_sum ///
            (firstnm) ///
                sigla_universidad ///
                demre_code_h ///
                nombre_carrera ///
                sede_carrera ///
                market_field ///
                geo_id ///
                geo_name ///
                market_id ///
                sua_exposure ///
                entrant_firstyear_3y ///
                incumbent_firstyear_3y ///
                total_firstyear_3y ///
                market_has_entrant ///
                market_has_incumbent ///
                post2012, ///
            by( ///
                program_id ///
                ao_proceso ///
            )

        gen double mean_psu_lm_firstyear = ///
            inc_psu_sum / ///
            n_firstyear_psu ///
            if n_firstyear_psu > 0

        gen double share_firstyear_psu = ///
            n_firstyear_psu / ///
            N_firstyear_incumbent ///
            if N_firstyear_incumbent > 0

        isid ///
            program_id ///
            ao_proceso

        save `panel_py', replace

        /**************************************************************
        * 4.5 Selectividad pretratamiento incumbente
        *
        * S_p se calcula usando 2009-2011.
        **************************************************************/

        preserve

            keep if inrange(ao_proceso, 2009, 2011)

            collapse ///
                (sum) ///
                    inc_psu_sum ///
                    inc_psu_n3 = n_firstyear_psu ///
                    inc_n3 = N_firstyear_incumbent, ///
                by(program_id)

            gen double inc_psu_pre = ///
                inc_psu_sum / ///
                inc_psu_n3 ///
                if inc_psu_n3 > 0

            gen double inc_psu_cov = ///
                inc_psu_n3 / ///
                inc_n3 ///
                if inc_n3 > 0

            keep ///
                program_id ///
                inc_psu_pre ///
                inc_psu_n3 ///
                inc_n3 ///
                inc_psu_cov

            isid program_id

            save `inc_scores', replace

        restore

        /**************************************************************
        * 4.6 Mercado pretratamiento del incumbente
        *
        * Se usa la observación más reciente disponible en 2009-2011.
        **************************************************************/

        preserve

            keep if inrange(ao_proceso, 2009, 2011)

            gsort ///
                program_id ///
                -ao_proceso

            by program_id: ///
                keep if _n == 1

            keep ///
                program_id ///
                ao_proceso ///
                market_field ///
                geo_id ///
                geo_name ///
                market_id ///
                sua_exposure ///
                entrant_firstyear_3y ///
                incumbent_firstyear_3y ///
                total_firstyear_3y ///
                market_has_entrant

            rename ao_proceso ///
                market_year

            rename market_field ///
                field_pre

            rename geo_id ///
                geo_pre

            rename geo_name ///
                geo_name_pre

            rename market_id ///
                market_pre

            rename sua_exposure ///
                exp_unw

            rename entrant_firstyear_3y ///
                ent_n3_mkt

            rename incumbent_firstyear_3y ///
                inc_n3_mkt

            rename total_firstyear_3y ///
                total_n3_mkt

            rename market_has_entrant ///
                has_entrant

            isid program_id

            save `inc_baseline', replace

        restore

        /**************************************************************
        * 4.7 Combinar mercado y selectividad del incumbente
        **************************************************************/

        use `inc_baseline', clear

        merge 1:1 ///
            program_id ///
            using `inc_scores', ///
            keep(master match) ///
            nogen

        save `inc_programs', replace

        /**************************************************************
        * 4.8 Formar pares incumbente × entrante dentro del mercado
        **************************************************************/

        joinby ///
            field_pre ///
            geo_pre ///
            using `entrant_programs', ///
            unmatched(master)

        /**************************************************************
        * 4.9 Distancia de selectividad
        **************************************************************/

        gen double psu_gap = ///
            abs(inc_psu_pre - ent_psu_pre) ///
            if ///
                !missing(inc_psu_pre) & ///
                !missing(ent_psu_pre)

        /**************************************************************
        * 4.10 Kernels
        **************************************************************/

        gen double w_tri50 = ///
            max(0, 1 - psu_gap / `h') ///
            if !missing(psu_gap)

        gen double w_gau50 = ///
            exp(-0.5 * (psu_gap / `h')^2) ///
            if !missing(psu_gap)

        /**************************************************************
        * 4.11 Matrícula entrante ponderada
        **************************************************************/

        gen double tri_n = ///
            w_tri50 * ent_n3 ///
            if !missing(w_tri50)

        gen double gau_n = ///
            w_gau50 * ent_n3 ///
            if !missing(w_gau50)

        replace tri_n = 0 ///
            if missing(tri_n)

        replace gau_n = 0 ///
            if missing(gau_n)

        gen double ent_n_score = ///
            ent_n3 ///
            if !missing(ent_psu_pre)

        replace ent_n_score = 0 ///
            if missing(ent_n_score)

        gen byte ent_pair = ///
            !missing(entrant_id)

        gen byte ent_score = ///
            !missing(ent_psu_pre)

        /**************************************************************
        * 4.12 Colapsar a programa incumbente
        **************************************************************/

        collapse ///
            (sum) ///
                tri_n ///
                gau_n ///
                ent_n_score ///
                n_ent_pair = ent_pair ///
                n_ent_score = ent_score ///
            (firstnm) ///
                market_year ///
                field_pre ///
                geo_pre ///
                geo_name_pre ///
                market_pre ///
                exp_unw ///
                ent_n3_mkt ///
                inc_n3_mkt ///
                total_n3_mkt ///
                has_entrant ///
                inc_psu_pre ///
                inc_psu_n3 ///
                inc_n3 ///
                inc_psu_cov, ///
            by(program_id)

        /**************************************************************
        * 4.13 Construir exposiciones ponderadas
        **************************************************************/

        gen double exp_tri50 = ///
            tri_n / ///
            total_n3_mkt ///
            if ///
                total_n3_mkt > 0 & ///
                !missing(inc_psu_pre)

        gen double exp_gau50 = ///
            gau_n / ///
            total_n3_mkt ///
            if ///
                total_n3_mkt > 0 & ///
                !missing(inc_psu_pre)

        /*
        Los mercados sin entrantes tienen exposición ponderada cero.
        */

        replace exp_tri50 = 0 ///
            if ///
                has_entrant == 0 & ///
                !missing(inc_psu_pre)

        replace exp_gau50 = 0 ///
            if ///
                has_entrant == 0 & ///
                !missing(inc_psu_pre)

        gen double ent_psu_cov = ///
            ent_n_score / ///
            ent_n3_mkt ///
            if ent_n3_mkt > 0

        gen byte has_wexp = ///
            !missing(exp_tri50) & ///
            !missing(exp_gau50)

        /**************************************************************
        * 4.14 Validaciones
        **************************************************************/

        assert inrange(exp_tri50, 0, 1) ///
            if !missing(exp_tri50)

        assert inrange(exp_gau50, 0, 1) ///
            if !missing(exp_gau50)

        assert exp_tri50 <= exp_unw + 1e-10 ///
            if !missing(exp_tri50, exp_unw)

        assert exp_gau50 <= exp_unw + 1e-10 ///
            if !missing(exp_gau50, exp_unw)

        isid program_id

        save `weighted_exp', replace

        /**************************************************************
        * 4.15 Adjuntar exposiciones al panel 2007-2016
        **************************************************************/

        use `panel_py', clear

        merge m:1 ///
            program_id ///
            using `weighted_exp', ///
            keep(master match) ///
            generate(_merge_w)

        gen byte has_market_pre = ///
            _merge_w == 3

        drop _merge_w

        /**************************************************************
        * 4.16 Interacciones post-2012
        *
        * Una unidad equivale a 10 puntos porcentuales.
        **************************************************************/

        gen double z_unw10 = ///
            10 * exp_unw * post2012 ///
            if !missing(exp_unw)

        gen double z_tri10 = ///
            10 * exp_tri50 * post2012 ///
            if !missing(exp_tri50)

        gen double z_gau10 = ///
            10 * exp_gau50 * post2012 ///
            if !missing(exp_gau50)

        gen str20 market_type_w = ///
            "`markettype'"

        gen str12 geo_type_w = ///
            "`geotype'"

        /**************************************************************
        * 4.17 Etiquetas
        **************************************************************/

        label variable inc_psu_pre ///
            "Incumbent mean LM PSU, 2009-2011"

        label variable exp_unw ///
            "Unweighted entrant exposure"

        label variable exp_tri50 ///
            "Triangular selectivity exposure, h=50"

        label variable exp_gau50 ///
            "Gaussian selectivity exposure, h=50"

        label variable ent_psu_cov ///
            "Entrant enrollment share with program PSU"

        label variable z_unw10 ///
            "10 p.p. unweighted exposure x post-2012"

        label variable z_tri10 ///
            "10 p.p. triangular exposure x post-2012"

        label variable z_gau10 ///
            "10 p.p. Gaussian exposure x post-2012"

        /**************************************************************
        * 4.18 Verificar que las exposiciones sean fijas por programa
        **************************************************************/

        isid ///
            program_id ///
            ao_proceso

        bysort program_id: ///
            assert exp_unw == exp_unw[1] ///
            if !missing(exp_unw)

        bysort program_id: ///
            assert exp_tri50 == exp_tri50[1] ///
            if !missing(exp_tri50)

        bysort program_id: ///
            assert exp_gau50 == exp_gau50[1] ///
            if !missing(exp_gau50)

        /**************************************************************
        * 4.19 Ordenar y guardar
        **************************************************************/

        order ///
            program_id ///
            ao_proceso ///
            sigla_universidad ///
            demre_code_h ///
            nombre_carrera ///
            sede_carrera ///
            market_type_w ///
            geo_type_w ///
            market_year ///
            field_pre ///
            geo_pre ///
            geo_name_pre ///
            market_pre ///
            inc_psu_pre ///
            inc_psu_cov ///
            ent_psu_cov ///
            exp_unw ///
            exp_tri50 ///
            exp_gau50 ///
            post2012 ///
            z_unw10 ///
            z_tri10 ///
            z_gau10 ///
            N_firstyear_incumbent ///
            mean_psu_lm_firstyear ///
            n_firstyear_psu ///
            share_firstyear_psu

        sort ///
            program_id ///
            ao_proceso

        compress

        local output ///
            "$processed/sua_incumbent_panel_w_`markettype'_`geotype'_2007_2016.dta"

        save "`output'", replace

        /**************************************************************
        * 4.20 Resumen mínimo de cobertura
        **************************************************************/

        egen byte tag_program = ///
            tag(program_id)

        quietly count if tag_program == 1
        local n_programs = r(N)

        quietly count if ///
            tag_program == 1 & ///
            !missing(inc_psu_pre)

        local n_inc_psu = r(N)

        quietly count if ///
            tag_program == 1 & ///
            has_wexp == 1

        local n_weighted = r(N)

        local inc_psu_share = ///
            `n_inc_psu' / `n_programs'

        quietly summarize ///
            ent_psu_cov ///
            if tag_program == 1

        local ent_cov = r(mean)

        quietly summarize ///
            exp_unw ///
            if tag_program == 1

        local mean_unw = r(mean)

        quietly summarize ///
            exp_tri50 ///
            if tag_program == 1

        local mean_tri = r(mean)

        quietly summarize ///
            exp_gau50 ///
            if tag_program == 1

        local mean_gau = r(mean)

        post `covpost' ///
            ("`markettype'") ///
            ("`geotype'") ///
            (`n_programs') ///
            (`n_inc_psu') ///
            (`n_weighted') ///
            (`inc_psu_share') ///
            (`ent_cov') ///
            (`mean_unw') ///
            (`mean_tri') ///
            (`mean_gau')

        di as result ///
            "`markettype' × `geotype' guardado."
    }
}

postclose `covpost'

/**********************************************************************
* 5. Guardar resumen de cobertura
**********************************************************************/

use `coverage', clear

gen byte market_order = .

replace market_order = 1 ///
    if market_type == "broad_area"

replace market_order = 2 ///
    if market_type == "cine_subarea"

replace market_order = 3 ///
    if market_type == "generic_area"

gen byte geo_order = .

replace geo_order = 1 ///
    if geo_type == "region"

replace geo_order = 2 ///
    if geo_type == "provincia"

replace geo_order = 3 ///
    if geo_type == "comuna"

sort ///
    market_order ///
    geo_order

format ///
    inc_psu_share ///
    ent_psu_cov ///
    mean_exp_unw ///
    mean_exp_tri ///
    mean_exp_gau ///
    %9.3f

list, ///
    noobs ///
    clean ///
    separator(3)

save ///
    "$processed/sua_weighted_exposure_coverage.dta", ///
    replace

export excel ///
    using "$output/sua_weighted_exposure_coverage.xlsx", ///
    firstrow(variables) ///
    replace

di as result ///
    "Exposiciones ponderadas construidas para nueve mercados."