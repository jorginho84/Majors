/**********************************************************************
* 04d_selectivity_groups_diagnostics.do
*
* Objetivo:
*   Examinar la distribución de selectividad pretratamiento del
*   programa incumbente y comparar:
*
*       1. Terciles automáticos
*       2. Cortes manuales 550 / 600
*       3. Cortes manuales 550 / 645
*       4. Cortes manuales 550 / 650
*
* No estima regresiones.
*
* Muestra:
*   broad_area × region
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

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
    mean_psu_lm_firstyear, ///
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
* 3. Validar que inc_psu_pre sea constante dentro de programa
**********************************************************************/

bysort program_id: egen double min_inc_psu_pre = ///
    min(inc_psu_pre)

bysort program_id: egen double max_inc_psu_pre = ///
    max(inc_psu_pre)

gen double diff_inc_psu_pre = ///
    max_inc_psu_pre - min_inc_psu_pre

summarize diff_inc_psu_pre, detail

assert diff_inc_psu_pre < 0.0001

drop ///
    min_inc_psu_pre ///
    max_inc_psu_pre ///
    diff_inc_psu_pre

/**********************************************************************
* 4. Crear base única a nivel de programa
**********************************************************************/

preserve

    keep ///
        program_id ///
        inc_psu_pre ///
        field_pre ///
        market_pre

    duplicates drop

    bysort program_id: gen byte n_program_rows = _N
    assert n_program_rows == 1
    drop n_program_rows

    /******************************************************************
    * 5. Distribución general de selectividad
    ******************************************************************/

    summarize inc_psu_pre, detail

    centile inc_psu_pre, ///
        centile( ///
            1 ///
            5 ///
            10 ///
            25 ///
            33.333 ///
            50 ///
            66.667 ///
            75 ///
            90 ///
            95 ///
            99 ///
        )

    histogram inc_psu_pre, ///
        frequency ///
        width(10) ///
        xline( ///
            500 ///
            550 ///
            600 ///
            645 ///
            650 ///
            700, ///
            lpattern(dash) ///
        ) ///
        xtitle("PSU promedio pretratamiento del incumbente") ///
        ytitle("Número de programas") ///
        title("Distribución de selectividad pretratamiento") ///
        subtitle("Programas incumbentes; área amplia × región") ///
        name(selectivity_distribution, replace)

    graph export ///
        "$output/sua_incumbent_selectivity_distribution.png", ///
        replace ///
        width(2400)

    /******************************************************************
    * 6. Terciles automáticos
    ******************************************************************/

    xtile selectivity_tercile = ///
        inc_psu_pre, ///
        nq(3)

    label define selectivity_tercile_lbl ///
        1 "Baja" ///
        2 "Media" ///
        3 "Alta"

    label values ///
        selectivity_tercile ///
        selectivity_tercile_lbl

    tabstat inc_psu_pre, ///
        by(selectivity_tercile) ///
        statistics( ///
            count ///
            min ///
            p25 ///
            median ///
            mean ///
            p75 ///
            max ///
        ) ///
        columns(statistics) ///
        format(%9.2f)

    tabulate selectivity_tercile

    egen byte tag_market_tercile = ///
        tag(selectivity_tercile market_pre)

    tabulate selectivity_tercile ///
        if tag_market_tercile == 1

    drop tag_market_tercile

    /******************************************************************
    * 7. Cortes manuales A
    *
    *     Baja:  PSU < 550
    *     Media: 550 <= PSU < 600
    *     Alta:  PSU >= 600
    ******************************************************************/

    gen byte selectivity_manual_A = .

    replace selectivity_manual_A = 1 ///
        if inc_psu_pre < 550

    replace selectivity_manual_A = 2 ///
        if inc_psu_pre >= 550 & ///
           inc_psu_pre < 600

    replace selectivity_manual_A = 3 ///
        if inc_psu_pre >= 600

    label define selectivity_manual_A_lbl ///
        1 "Menos de 550" ///
        2 "550 a 599.9" ///
        3 "600 o más"

    label values ///
        selectivity_manual_A ///
        selectivity_manual_A_lbl

    tabulate selectivity_manual_A

    tabstat inc_psu_pre, ///
        by(selectivity_manual_A) ///
        statistics( ///
            count ///
            min ///
            median ///
            mean ///
            max ///
        ) ///
        columns(statistics) ///
        format(%9.2f)

    egen byte tag_market_A = ///
        tag(selectivity_manual_A market_pre)

    tabulate selectivity_manual_A ///
        if tag_market_A == 1

    drop tag_market_A

    /******************************************************************
    * 8. Cortes manuales C
    *
    *     Baja:  PSU < 550
    *     Media: 550 <= PSU < 645
    *     Alta:  PSU >= 645
    ******************************************************************/

    gen byte selectivity_manual_C = .

    replace selectivity_manual_C = 1 ///
        if inc_psu_pre < 550

    replace selectivity_manual_C = 2 ///
        if inc_psu_pre >= 550 & ///
           inc_psu_pre < 645

    replace selectivity_manual_C = 3 ///
        if inc_psu_pre >= 645

    label define selectivity_manual_C_lbl ///
        1 "Menos de 550" ///
        2 "550 a 644.9" ///
        3 "645 o más"

    label values ///
        selectivity_manual_C ///
        selectivity_manual_C_lbl

    tabulate selectivity_manual_C

    tabstat inc_psu_pre, ///
        by(selectivity_manual_C) ///
        statistics( ///
            count ///
            min ///
            median ///
            mean ///
            max ///
        ) ///
        columns(statistics) ///
        format(%9.2f)

    egen byte tag_market_C = ///
        tag(selectivity_manual_C market_pre)

    tabulate selectivity_manual_C ///
        if tag_market_C == 1

    drop tag_market_C

    /******************************************************************
    * 9. Cortes manuales D
    *
    *     Baja:  PSU < 550
    *     Media: 550 <= PSU < 650
    *     Alta:  PSU >= 650
    ******************************************************************/

    gen byte selectivity_manual_D = .

    replace selectivity_manual_D = 1 ///
        if inc_psu_pre < 550

    replace selectivity_manual_D = 2 ///
        if inc_psu_pre >= 550 & ///
           inc_psu_pre < 650

    replace selectivity_manual_D = 3 ///
        if inc_psu_pre >= 650

    label define selectivity_manual_D_lbl ///
        1 "Menos de 550" ///
        2 "550 a 649.9" ///
        3 "650 o más"

    label values ///
        selectivity_manual_D ///
        selectivity_manual_D_lbl

    tabulate selectivity_manual_D

    tabstat inc_psu_pre, ///
        by(selectivity_manual_D) ///
        statistics( ///
            count ///
            min ///
            median ///
            mean ///
            max ///
        ) ///
        columns(statistics) ///
        format(%9.2f)

    egen byte tag_market_D = ///
        tag(selectivity_manual_D market_pre)

    tabulate selectivity_manual_D ///
        if tag_market_D == 1

    drop tag_market_D

    /******************************************************************
    * 10. Guardar clasificación a nivel de programa
    ******************************************************************/

    keep ///
        program_id ///
        inc_psu_pre ///
        selectivity_tercile ///
        selectivity_manual_A ///
        selectivity_manual_C ///
        selectivity_manual_D

    isid program_id

    save ///
        "$processed/sua_incumbent_selectivity_groups.dta", ///
        replace

    export excel ///
        using "$output/sua_incumbent_selectivity_groups.xlsx", ///
        firstrow(variables) ///
        replace

restore

/**********************************************************************
* 11. Incorporar grupos al panel
**********************************************************************/

merge m:1 program_id ///
    using "$processed/sua_incumbent_selectivity_groups.dta", ///
    keep(match) ///
    nogen

/**********************************************************************
* 12. Programa auxiliar para mostrar tamaño de muestra
**********************************************************************/

capture program drop show_group_sizes

program define show_group_sizes

    syntax varname, Title(string)

    di as result ///
        "============================================================"

    di as result ///
        "`title'"

    forvalues g = 1/3 {

        quietly count ///
            if `varlist' == `g'
        local N_obs = r(N)

        egen byte tag_program_g = ///
            tag(program_id) ///
            if `varlist' == `g'

        quietly count ///
            if tag_program_g == 1
        local N_programs = r(N)

        egen byte tag_market_g = ///
            tag(market_pre) ///
            if `varlist' == `g'

        quietly count ///
            if tag_market_g == 1
        local N_markets = r(N)

        quietly summarize inc_psu_pre ///
            if `varlist' == `g'

        di as text ///
            "Grupo `g': " ///
            "N obs = " %9.0f `N_obs' ///
            "; programas = " %6.0f `N_programs' ///
            "; mercados = " %6.0f `N_markets' ///
            "; PSU min = " %7.2f r(min) ///
            "; PSU media = " %7.2f r(mean) ///
            "; PSU max = " %7.2f r(max)

        drop ///
            tag_program_g ///
            tag_market_g
    }

end

/**********************************************************************
* 13. Mostrar tamaños para cada clasificación
**********************************************************************/

show_group_sizes ///
    selectivity_tercile, ///
    title("TAMAÑO DE MUESTRA POR TERCILES")

show_group_sizes ///
    selectivity_manual_A, ///
    title("TAMAÑO DE MUESTRA: CORTES 550 / 600")

show_group_sizes ///
    selectivity_manual_C, ///
    title("TAMAÑO DE MUESTRA: CORTES 550 / 645")

show_group_sizes ///
    selectivity_manual_D, ///
    title("TAMAÑO DE MUESTRA: CORTES 550 / 650")

di as result ///
    "Diagnóstico de selectividad completado."

di as result ///
    "Archivo guardado en:"

di as result ///
    "$processed/sua_incumbent_selectivity_groups.dta"

di as result ///
    "$output/sua_incumbent_selectivity_groups.xlsx"