/**********************************************************************
* 04c_sua_event_study.do
*
* Objetivo:
*   Estimar event studies para matrícula y PSU promedio utilizando:
*
*       1. Exposición no ponderada
*       2. Exposición ponderada por selectividad
*
*   Se estiman dos sistemas:
*
*       A. No ponderada + triangular h=50
*       B. No ponderada + gaussiana h=50
*
* Especificación:
*
*   Y_pt =
*       sum_s beta_unw_s (E_unw_p × 1{t=s})
*       + sum_s beta_w_s (E_w_p × 1{t=s})
*       + FE programa
*       + FE campo pretratamiento × año
*       + error_pt
*
* Año omitido:
*   2011.
*
* Inferencia:
*   Errores agrupados por mercado pretratamiento.
*
* Outputs:
*   $processed/sua_event_study_results.dta
*   $output/sua_event_study_results.xlsx
*
* Figuras principales:
*   broad_area × region.
**********************************************************************/

clear all
set more off

do "code/config.do"

/**********************************************************************
* 0. Verificar reghdfe
**********************************************************************/

capture which reghdfe

if _rc {

    di as error ///
        "reghdfe no está instalado."

    exit 199
}

/**********************************************************************
* 1. Definiciones
**********************************************************************/

local markettypes ///
    broad_area ///
    cine_subarea ///
    generic_area

local geotypes ///
    region ///
    provincia ///
    comuna

local kernels ///
    triangular ///
    gaussian

local outcomes ///
    N_firstyear_incumbent ///
    mean_psu_lm_firstyear

local years ///
    2007 ///
    2008 ///
    2009 ///
    2010 ///
    2011 ///
    2012 ///
    2013 ///
    2014 ///
    2015 ///
    2016

tempfile results

tempname resultspost

postfile `resultspost' ///
    str20 market_type ///
    str12 geo_type ///
    str12 kernel ///
    str12 outcome ///
    str12 exposure ///
    byte main_spec ///
    int year ///
    double beta ///
    double se ///
    double pvalue ///
    double ci_low ///
    double ci_high ///
    double pretrend_F ///
    double pretrend_p ///
    double joint_pre_F ///
    double joint_pre_p ///
    long N ///
    long N_programs ///
    long N_markets ///
    using `results', ///
    replace

/**********************************************************************
* 2. Estimar event studies
**********************************************************************/

forvalues i = 1/3 {

    local markettype : word `i' of `markettypes'

    forvalues g = 1/3 {

        local geotype : word `g' of `geotypes'

        local input ///
            "$processed/sua_incumbent_panel_w_`markettype'_`geotype'_2007_2016.dta"

        use "`input'", clear

        di as text ///
            "------------------------------------------------------------"

        di as result ///
            "Mercado: `markettype' × `geotype'"

        /**************************************************************
        * 2.1 Muestra común
        *
        * Se conserva la misma lógica del 04b:
        * matrícula, PSU y las tres exposiciones deben estar observadas.
        **************************************************************/

        drop if missing( ///
            program_id, ///
            ao_proceso, ///
            field_pre, ///
            market_pre, ///
            N_firstyear_incumbent, ///
            mean_psu_lm_firstyear, ///
            exp_unw, ///
            exp_tri50, ///
            exp_gau50 ///
        )

        /**************************************************************
        * Programas observados antes y después de 2012
        **************************************************************/

        bysort program_id: ///
            egen byte observed_pre = ///
                max(ao_proceso <= 2011)

        bysort program_id: ///
            egen byte observed_post = ///
                max(ao_proceso >= 2012)

        keep if ///
            observed_pre == 1 & ///
            observed_post == 1

        assert _N > 0

        /**************************************************************
        * 2.2 Exposición escalada
        *
        * Una unidad representa 10 puntos porcentuales.
        **************************************************************/

        gen double exp_unw10 = ///
            10 * exp_unw

        gen double exp_tri10 = ///
            10 * exp_tri50

        gen double exp_gau10 = ///
            10 * exp_gau50

        /**************************************************************
        * 2.3 Efectos fijos campo pretratamiento × año
        **************************************************************/

        egen long field_year_id = group( ///
            field_pre ///
            ao_proceso ///
        )

        /**************************************************************
        * 2.4 Conteos
        **************************************************************/

        egen byte tag_program = ///
            tag(program_id)

        egen byte tag_market = ///
            tag(market_pre)

        quietly count if tag_program == 1
        local N_programs = r(N)

        quietly count if tag_market == 1
        local N_markets = r(N)

        /**************************************************************
        * 2.5 Especificación principal
        **************************************************************/

        local main = 0

        if ///
            "`markettype'" == "broad_area" & ///
            "`geotype'" == "region" {

            local main = 1
        }

        /**************************************************************
        * 2.6 Loop por kernel
        **************************************************************/

        foreach kernel of local kernels {

            if "`kernel'" == "triangular" {

                local exp_weighted ///
                    exp_tri10
            }

            if "`kernel'" == "gaussian" {

                local exp_weighted ///
                    exp_gau10
            }

            /**********************************************************
            * 2.7 Loop por outcome
            **********************************************************/

            foreach outcome of local outcomes {

                if "`outcome'" == ///
                    "N_firstyear_incumbent" {

                    local outcome_name ///
                        enrollment
                }

                if "`outcome'" == ///
                    "mean_psu_lm_firstyear" {

                    local outcome_name ///
                        score
                }

                di as result ///
                    "`kernel' - `outcome_name'"

                /******************************************************
                * Event study conjunto
                *
                * 2011 queda omitido.
                ******************************************************/

                reghdfe ///
                    `outcome' ///
                    ib2011.ao_proceso#c.exp_unw10 ///
                    ib2011.ao_proceso#c.`exp_weighted', ///
                    absorb( ///
                        program_id ///
                        field_year_id ///
                    ) ///
                    vce(cluster market_pre)

                local N_reg = e(N)

                /******************************************************
                * 2.8 Test de pretrends: exposición no ponderada
                ******************************************************/

                test ///
                    2007.ao_proceso#c.exp_unw10 ///
                    2008.ao_proceso#c.exp_unw10 ///
                    2009.ao_proceso#c.exp_unw10 ///
                    2010.ao_proceso#c.exp_unw10

                local pre_F_unw = r(F)
                local pre_p_unw = r(p)

                /******************************************************
                * 2.9 Test de pretrends: exposición ponderada
                ******************************************************/

                test ///
                    2007.ao_proceso#c.`exp_weighted' ///
                    2008.ao_proceso#c.`exp_weighted' ///
                    2009.ao_proceso#c.`exp_weighted' ///
                    2010.ao_proceso#c.`exp_weighted'

                local pre_F_w = r(F)
                local pre_p_w = r(p)

                /******************************************************
                * 2.10 Test conjunto de todos los coeficientes pre
                ******************************************************/

                test ///
                    2007.ao_proceso#c.exp_unw10 ///
                    2008.ao_proceso#c.exp_unw10 ///
                    2009.ao_proceso#c.exp_unw10 ///
                    2010.ao_proceso#c.exp_unw10 ///
                    2007.ao_proceso#c.`exp_weighted' ///
                    2008.ao_proceso#c.`exp_weighted' ///
                    2009.ao_proceso#c.`exp_weighted' ///
                    2010.ao_proceso#c.`exp_weighted'

                local pre_F_joint = r(F)
                local pre_p_joint = r(p)

                /******************************************************
                * Volver a dejar activa la regresión
                ******************************************************/

                quietly reghdfe ///
                    `outcome' ///
                    ib2011.ao_proceso#c.exp_unw10 ///
                    ib2011.ao_proceso#c.`exp_weighted', ///
                    absorb( ///
                        program_id ///
                        field_year_id ///
                    ) ///
                    vce(cluster market_pre)

                /******************************************************
                * 2.11 Guardar coeficientes no ponderados
                ******************************************************/

                foreach year of local years {

                    if `year' == 2011 {

                        local beta = 0
                        local se = 0
                        local pvalue = .
                        local ci_low = 0
                        local ci_high = 0
                    }

                    else {

                        capture lincom ///
                            `year'.ao_proceso#c.exp_unw10

                        if _rc {

                            local beta = .
                            local se = .
                            local pvalue = .
                            local ci_low = .
                            local ci_high = .
                        }

                        else {

                            local beta = r(estimate)
                            local se = r(se)
                            local pvalue = r(p)
                            local ci_low = r(lb)
                            local ci_high = r(ub)
                        }
                    }

                    post `resultspost' ///
                        ("`markettype'") ///
                        ("`geotype'") ///
                        ("`kernel'") ///
                        ("`outcome_name'") ///
                        ("unweighted") ///
                        (`main') ///
                        (`year') ///
                        (`beta') ///
                        (`se') ///
                        (`pvalue') ///
                        (`ci_low') ///
                        (`ci_high') ///
                        (`pre_F_unw') ///
                        (`pre_p_unw') ///
                        (`pre_F_joint') ///
                        (`pre_p_joint') ///
                        (`N_reg') ///
                        (`N_programs') ///
                        (`N_markets')
                }

                /******************************************************
                * Volver a dejar activa la regresión antes de guardar
                * la exposición ponderada.
                ******************************************************/

                quietly reghdfe ///
                    `outcome' ///
                    ib2011.ao_proceso#c.exp_unw10 ///
                    ib2011.ao_proceso#c.`exp_weighted', ///
                    absorb( ///
                        program_id ///
                        field_year_id ///
                    ) ///
                    vce(cluster market_pre)

                /******************************************************
                * 2.12 Guardar coeficientes ponderados
                ******************************************************/

                foreach year of local years {

                    if `year' == 2011 {

                        local beta = 0
                        local se = 0
                        local pvalue = .
                        local ci_low = 0
                        local ci_high = 0
                    }

                    else {

                        capture lincom ///
                            `year'.ao_proceso#c.`exp_weighted'

                        if _rc {

                            local beta = .
                            local se = .
                            local pvalue = .
                            local ci_low = .
                            local ci_high = .
                        }

                        else {

                            local beta = r(estimate)
                            local se = r(se)
                            local pvalue = r(p)
                            local ci_low = r(lb)
                            local ci_high = r(ub)
                        }
                    }

                    post `resultspost' ///
                        ("`markettype'") ///
                        ("`geotype'") ///
                        ("`kernel'") ///
                        ("`outcome_name'") ///
                        ("weighted") ///
                        (`main') ///
                        (`year') ///
                        (`beta') ///
                        (`se') ///
                        (`pvalue') ///
                        (`ci_low') ///
                        (`ci_high') ///
                        (`pre_F_w') ///
                        (`pre_p_w') ///
                        (`pre_F_joint') ///
                        (`pre_p_joint') ///
                        (`N_reg') ///
                        (`N_programs') ///
                        (`N_markets')
                }

                di as text ///
                    "Pretrend p, unweighted = " ///
                    %7.4f `pre_p_unw'

                di as text ///
                    "Pretrend p, weighted   = " ///
                    %7.4f `pre_p_w'

                di as text ///
                    "Pretrend p, joint      = " ///
                    %7.4f `pre_p_joint'
            }
        }
    }
}

postclose `resultspost'

/**********************************************************************
* 3. Preparar resultados
**********************************************************************/

use `results', clear

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

gen byte kernel_order = .

replace kernel_order = 1 ///
    if kernel == "triangular"

replace kernel_order = 2 ///
    if kernel == "gaussian"

gen byte outcome_order = .

replace outcome_order = 1 ///
    if outcome == "enrollment"

replace outcome_order = 2 ///
    if outcome == "score"

gen byte exposure_order = .

replace exposure_order = 1 ///
    if exposure == "unweighted"

replace exposure_order = 2 ///
    if exposure == "weighted"

sort ///
    market_order ///
    geo_order ///
    kernel_order ///
    outcome_order ///
    exposure_order ///
    year

format ///
    beta ///
    se ///
    ci_low ///
    ci_high ///
    pretrend_F ///
    joint_pre_F ///
    %9.3f

format ///
    pvalue ///
    pretrend_p ///
    joint_pre_p ///
    %9.4f

save ///
    "$processed/sua_event_study_results.dta", ///
    replace

export excel ///
    using "$output/sua_event_study_results.xlsx", ///
    firstrow(variables) ///
    replace

/**********************************************************************
* 4. Mostrar tests de pretrends de la especificación principal
**********************************************************************/

preserve

    keep if main_spec == 1

    keep ///
        kernel ///
        outcome ///
        exposure ///
        pretrend_F ///
        pretrend_p ///
        joint_pre_F ///
        joint_pre_p

    duplicates drop

    sort ///
        kernel ///
        outcome ///
        exposure

    list, ///
        noobs ///
        clean ///
        separator(2)

restore

/**********************************************************************
* 5. Figuras de la especificación principal
**********************************************************************/

preserve

    keep if main_spec == 1

    foreach kernel in triangular gaussian {

        foreach outcome in enrollment score {

            twoway ///
                (rcap ci_low ci_high year ///
                    if ///
                        kernel == "`kernel'" & ///
                        outcome == "`outcome'" & ///
                        exposure == "unweighted") ///
                (connected beta year ///
                    if ///
                        kernel == "`kernel'" & ///
                        outcome == "`outcome'" & ///
                        exposure == "unweighted") ///
                (rcap ci_low ci_high year ///
                    if ///
                        kernel == "`kernel'" & ///
                        outcome == "`outcome'" & ///
                        exposure == "weighted") ///
                (connected beta year ///
                    if ///
                        kernel == "`kernel'" & ///
                        outcome == "`outcome'" & ///
                        exposure == "weighted"), ///
                xline(2011.5, lpattern(dash)) ///
                yline(0, lpattern(shortdash)) ///
                xlabel(2007(1)2016, angle(45)) ///
                xtitle("Admission year") ///
                ytitle("Effect of 10 p.p. higher exposure") ///
                title( ///
                    "`outcome': `kernel' kernel" ///
                ) ///
                subtitle( ///
                    "Broad area × region; omitted year: 2011" ///
                ) ///
                legend( ///
                    order( ///
                        2 "Unweighted exposure" ///
                        4 "Weighted exposure" ///
                    ) ///
                    rows(1) ///
                ) ///
                name( ///
                    event_`kernel'_`outcome', ///
                    replace ///
                )

            graph export ///
                "$output/sua_event_`kernel'_`outcome'.png", ///
                replace ///
                width(2400)
        }
    }

restore

di as result ///
    "Event-study results guardados en:"

di as result ///
    "$processed/sua_event_study_results.dta"

di as result ///
    "$output/sua_event_study_results.xlsx"