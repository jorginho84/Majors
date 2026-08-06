/**********************************************************************
* 04e_sua_first_stage_by_selectivity.do
*
* Objetivo:
*   Estimar heterogeneidad del first stage según la selectividad
*   pretratamiento del programa incumbente.
*
* Clasificaciones:
*   1. Terciles de inc_psu_pre
*   2. Cortes manuales:
*        Baja:  PSU < 550
*        Media: 550 <= PSU < 650
*        Alta:  PSU >= 650
*
* Especificación:
*
*   N_pt =
*       pi_1 (E_p × Post_t)
*       + pi_2 (E_p^w × Post_t)
*       + FE programa
*       + FE campo × año
*       + error_pt
*
* Kernels:
*   - Triangular, h = 50
*   - Gaussiano, h = 50
*
* Mercado:
*   broad_area × region
*
* Output:
*   $processed/sua_first_stage_by_selectivity.dta
*   $output/sua_first_stage_by_selectivity.xlsx
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

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
* 1. Abrir panel principal
**********************************************************************/

use ///
    "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta", ///
    clear

/**********************************************************************
* 2. Replicar muestra analítica del first stage ponderado
**********************************************************************/

drop if missing( ///
    program_id, ///
    ao_proceso, ///
    field_pre, ///
    market_pre, ///
    N_firstyear_incumbent, ///
    inc_psu_pre, ///
    z_unw10, ///
    z_tri10, ///
    z_gau10 ///
)

bysort program_id: egen byte observed_pre = ///
    max(ao_proceso <= 2011)

bysort program_id: egen byte observed_post = ///
    max(ao_proceso >= 2012)

keep if ///
    observed_pre == 1 & ///
    observed_post == 1

assert _N > 0

/**********************************************************************
* 3. Incorporar grupos de selectividad creados en el 04d
**********************************************************************/

merge m:1 program_id ///
    using "$processed/sua_incumbent_selectivity_groups.dta", ///
    keep(match) ///
    nogen

assert !missing(selectivity_tercile)
assert !missing(selectivity_manual_D)

/**********************************************************************
* 4. Validaciones
**********************************************************************/

/*
La selectividad y los grupos deben permanecer constantes dentro
de cada programa.
*/

bysort program_id: assert ///
    inc_psu_pre == inc_psu_pre[1]

bysort program_id: assert ///
    selectivity_tercile == selectivity_tercile[1]

bysort program_id: assert ///
    selectivity_manual_D == selectivity_manual_D[1]

/*
FE de campo pretratamiento × año.
*/

egen long field_year_id = group( ///
    field_pre ///
    ao_proceso ///
)

/**********************************************************************
* 5. Guardar panel analítico temporal
**********************************************************************/

tempfile analytic_panel
save `analytic_panel'

/**********************************************************************
* 6. Archivo de resultados
**********************************************************************/

tempfile results
tempname resultspost

postfile `resultspost' ///
    str20 classification ///
    byte selectivity_group ///
    str24 group_label ///
    str12 kernel ///
    str20 instrument ///
    double beta ///
    double se ///
    double pvalue ///
    double ci_low ///
    double ci_high ///
    double joint_F ///
    double joint_p ///
    double partial_R2 ///
    double psu_min ///
    double psu_mean ///
    double psu_max ///
    long N ///
    long N_programs ///
    long N_markets ///
    using `results', ///
    replace

/**********************************************************************
* 7. Clasificaciones a estimar
**********************************************************************/

local classifications ///
    selectivity_tercile ///
    selectivity_manual_D

local kernels ///
    triangular ///
    gaussian

/**********************************************************************
* 8. Loop por clasificación
**********************************************************************/

foreach classification of local classifications {

    if "`classification'" == "selectivity_tercile" {

        local classification_name ///
            terciles
    }

    if "`classification'" == "selectivity_manual_D" {

        local classification_name ///
            manual_550_650
    }

    /******************************************************************
    * 8.1 Loop por grupo
    ******************************************************************/

    forvalues g = 1/3 {

        if "`classification'" == "selectivity_tercile" {

            if `g' == 1 local group_label ///
                "T1: baja"

            if `g' == 2 local group_label ///
                "T2: media"

            if `g' == 3 local group_label ///
                "T3: alta"
        }

        if "`classification'" == "selectivity_manual_D" {

            if `g' == 1 local group_label ///
                "Baja: PSU < 550"

            if `g' == 2 local group_label ///
                "Media: 550-649.9"

            if `g' == 3 local group_label ///
                "Alta: PSU >= 650"
        }

        di as text ///
            "============================================================"

        di as result ///
            "Clasificación: `classification_name'"

        di as result ///
            "Grupo: `group_label'"

        /**************************************************************
        * Estadísticas de PSU del grupo
        **************************************************************/

        quietly summarize inc_psu_pre ///
            if `classification' == `g'

        local psu_min = r(min)
        local psu_mean = r(mean)
        local psu_max = r(max)

        /**************************************************************
        * 8.2 Loop por kernel
        **************************************************************/

        foreach kernel of local kernels {

            if "`kernel'" == "triangular" {

                local z_weighted ///
                    z_tri10
            }

            if "`kernel'" == "gaussian" {

                local z_weighted ///
                    z_gau10
            }

            di as result ///
                "Kernel: `kernel'"

            /**********************************************************
            * Modelo irrestricto
            **********************************************************/

            reghdfe ///
                N_firstyear_incumbent ///
                z_unw10 ///
                `z_weighted' ///
                if `classification' == `g', ///
                absorb( ///
                    program_id ///
                    field_year_id ///
                ) ///
                vce(cluster market_pre)

            local N_reg = e(N)
            local rss_unrestricted = e(rss)
            local df_reg = e(df_r)

            /*
            Guardar la muestra efectiva de reghdfe.
            */

            tempvar estimation_sample
            gen byte `estimation_sample' = e(sample)

            /**********************************************************
            * Test conjunto de las dos exposiciones
            **********************************************************/

            test ///
                z_unw10 ///
                `z_weighted'

            local joint_F = r(F)
            local joint_p = r(p)

            /**********************************************************
            * Conteos dentro de la muestra efectiva
            **********************************************************/

            tempvar tag_program tag_market

            egen byte `tag_program' = ///
                tag(program_id) ///
                if `estimation_sample' == 1

            quietly count ///
                if `tag_program' == 1

            local N_programs = r(N)

            egen byte `tag_market' = ///
                tag(market_pre) ///
                if `estimation_sample' == 1

            quietly count ///
                if `tag_market' == 1

            local N_markets = r(N)

            /**********************************************************
            * Partial R2 conjunto
            *
            * Modelo restringido estimado sobre exactamente la misma
            * muestra efectiva que el modelo con instrumentos.
            **********************************************************/

            quietly reghdfe ///
                N_firstyear_incumbent ///
                if `estimation_sample' == 1, ///
                absorb( ///
                    program_id ///
                    field_year_id ///
                ) ///
                vce(cluster market_pre)

            local rss_restricted = e(rss)

            local partial_R2 = ///
                (`rss_restricted' - `rss_unrestricted') / ///
                `rss_restricted'

            /**********************************************************
            * Recuperar nuevamente modelo irrestricto
            **********************************************************/

            quietly reghdfe ///
                N_firstyear_incumbent ///
                z_unw10 ///
                `z_weighted' ///
                if `estimation_sample' == 1, ///
                absorb( ///
                    program_id ///
                    field_year_id ///
                ) ///
                vce(cluster market_pre)

            /**********************************************************
            * Guardar exposición total
            **********************************************************/

            local beta = _b[z_unw10]
            local se = _se[z_unw10]

            local tstat = ///
                `beta' / `se'

            local pvalue = ///
                2 * ttail( ///
                    e(df_r), ///
                    abs(`tstat') ///
                )

            local critical = ///
                invttail(e(df_r), 0.025)

            local ci_low = ///
                `beta' - `critical' * `se'

            local ci_high = ///
                `beta' + `critical' * `se'

            post `resultspost' ///
                ("`classification_name'") ///
                (`g') ///
                ("`group_label'") ///
                ("`kernel'") ///
                ("total") ///
                (`beta') ///
                (`se') ///
                (`pvalue') ///
                (`ci_low') ///
                (`ci_high') ///
                (`joint_F') ///
                (`joint_p') ///
                (`partial_R2') ///
                (`psu_min') ///
                (`psu_mean') ///
                (`psu_max') ///
                (`N_reg') ///
                (`N_programs') ///
                (`N_markets')

            /**********************************************************
            * Guardar exposición cercana
            **********************************************************/

            local beta = _b[`z_weighted']
            local se = _se[`z_weighted']

            local tstat = ///
                `beta' / `se'

            local pvalue = ///
                2 * ttail( ///
                    e(df_r), ///
                    abs(`tstat') ///
                )

            local critical = ///
                invttail(e(df_r), 0.025)

            local ci_low = ///
                `beta' - `critical' * `se'

            local ci_high = ///
                `beta' + `critical' * `se'

            post `resultspost' ///
                ("`classification_name'") ///
                (`g') ///
                ("`group_label'") ///
                ("`kernel'") ///
                ("close_selectivity") ///
                (`beta') ///
                (`se') ///
                (`pvalue') ///
                (`ci_low') ///
                (`ci_high') ///
                (`joint_F') ///
                (`joint_p') ///
                (`partial_R2') ///
                (`psu_min') ///
                (`psu_mean') ///
                (`psu_max') ///
                (`N_reg') ///
                (`N_programs') ///
                (`N_markets')

            di as text ///
                "N = " %9.0f `N_reg' ///
                "; programas = " %6.0f `N_programs' ///
                "; mercados = " %6.0f `N_markets'

            di as text ///
                "F conjunto = " %8.2f `joint_F' ///
                "; p = " %7.4f `joint_p' ///
                "; partial R2 = " %7.4f `partial_R2'

            drop ///
                `estimation_sample' ///
                `tag_program' ///
                `tag_market'
        }
    }
}

postclose `resultspost'

/**********************************************************************
* 9. Preparar archivo de resultados
**********************************************************************/

use `results', clear

/**********************************************************************
* 9.1 Estrellas
**********************************************************************/

gen str3 stars = ""

replace stars = "*" ///
    if pvalue < 0.10

replace stars = "**" ///
    if pvalue < 0.05

replace stars = "***" ///
    if pvalue < 0.01

gen str20 estimate = ///
    string(beta, "%9.3f") + stars

gen str20 standard_error = ///
    "(" + string(se, "%9.3f") + ")"

/**********************************************************************
* 9.2 Orden
**********************************************************************/

gen byte classification_order = .

replace classification_order = 1 ///
    if classification == "terciles"

replace classification_order = 2 ///
    if classification == "manual_550_650"

gen byte kernel_order = .

replace kernel_order = 1 ///
    if kernel == "triangular"

replace kernel_order = 2 ///
    if kernel == "gaussian"

gen byte instrument_order = .

replace instrument_order = 1 ///
    if instrument == "total"

replace instrument_order = 2 ///
    if instrument == "close_selectivity"

sort ///
    classification_order ///
    selectivity_group ///
    kernel_order ///
    instrument_order

/**********************************************************************
* 9.3 Formatos
**********************************************************************/

format ///
    beta ///
    se ///
    ci_low ///
    ci_high ///
    joint_F ///
    psu_min ///
    psu_mean ///
    psu_max ///
    %9.3f

format ///
    pvalue ///
    joint_p ///
    partial_R2 ///
    %9.4f

order ///
    classification ///
    selectivity_group ///
    group_label ///
    kernel ///
    instrument ///
    beta ///
    se ///
    pvalue ///
    joint_F ///
    joint_p ///
    partial_R2 ///
    psu_min ///
    psu_mean ///
    psu_max ///
    N ///
    N_programs ///
    N_markets ///
    stars ///
    estimate ///
    standard_error

/**********************************************************************
* 10. Mostrar resultados
**********************************************************************/

list ///
    classification ///
    group_label ///
    kernel ///
    instrument ///
    beta ///
    se ///
    pvalue ///
    joint_F ///
    partial_R2 ///
    N ///
    N_programs ///
    N_markets, ///
    noobs ///
    clean ///
    separator(4)

/**********************************************************************
* 11. Guardar
**********************************************************************/

*save ///
    "$processed/sua_first_stage_by_selectivity.dta", ///
    replace

*export excel ///
    using "$output/sua_first_stage_by_selectivity.xlsx", ///
    firstrow(variables) ///
    replace

di as result ///
    "Resultados de heterogeneidad guardados en:"

di as result ///
    "$processed/sua_first_stage_by_selectivity.dta"

di as result ///
    "$output/sua_first_stage_by_selectivity.xlsx"