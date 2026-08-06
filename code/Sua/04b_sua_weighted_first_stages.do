/**********************************************************************
* 04b_sua_weighted_first_stages.do
*
* Objetivo:
*   Estimar primeras etapas utilizando exclusivamente la exposición
*   cercana en selectividad.
*
*      Variables dependientes:
*        1. Matrícula de primer año del programa incumbente
*        2. PSU LM promedio de los matriculados de primer año
*
*      Instrumento:
*        Exposición ponderada por cercanía en selectividad × post-2012
*
*   Se estiman dos variantes:
*
*      A. Kernel triangular, bandwidth = 50 PSU
*      B. Kernel gaussiano, bandwidth = 50 PSU
*
* Especificación:
*
*   X_pt = pi Z_weighted_pt
*          + FE programa
*          + FE campo pretratamiento × año
*          + error_pt
*
* Inferencia:
*   Errores estándar agrupados por mercado pretratamiento.
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

    di as error ///
        "Ejecutar: ssc install reghdfe, replace"

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

/*
Dos especificaciones ponderadas:

    tri = triangular h=50
    gau = gaussiana h=50
*/

local kernels ///
    tri ///
    gau

tempfile results

tempname resultspost

/**********************************************************************
* El archivo final tendrá una fila por:
*
*   mercado × geografía × kernel × outcome × instrumento
*
* Ejemplo:
*
*   broad_area × region
*   triangular
*   enrollment
*   unweighted
**********************************************************************/

postfile `resultspost' ///
    str20 market_type ///
    str12 geo_type ///
    str12 kernel ///
    str12 outcome ///
    str12 instrument ///
    byte main_spec ///
    double beta ///
    double se ///
    double pvalue ///
    double ci_low ///
    double ci_high ///
    double joint_F ///
    double partial_R2 ///
    double outcome_pre_mean ///
    long N ///
    long N_programs ///
    long N_markets ///
    using `results', ///
    replace

/**********************************************************************
* 2. Loop por las nueve definiciones de mercado
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
        * 2.1 Muestra analítica
        **************************************************************/

        drop if missing( ///
            program_id, ///
            ao_proceso, ///
            field_pre, ///
            market_pre, ///
            N_firstyear_incumbent, ///
            mean_psu_lm_firstyear, ///
            z_unw10, ///
            z_tri10, ///
            z_gau10 ///
        )

        /*
        Mantener programas observados antes y después de la reforma.
        */

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

        /*
        Como PSU y matrícula son los dos regresores endógenos del
        modelo posterior, usamos una muestra común para las dos
        primeras etapas.
        */

        gen byte first_stage_sample = ///
            !missing( ///
                N_firstyear_incumbent, ///
                mean_psu_lm_firstyear, ///
                z_unw10, ///
                z_tri10, ///
                z_gau10, ///
                field_pre, ///
                market_pre ///
            )

        keep if first_stage_sample == 1

        assert _N > 0

        /**************************************************************
        * 2.2 Efectos fijos campo pretratamiento × año
        **************************************************************/

        egen long field_year_id = group( ///
            field_pre ///
            ao_proceso ///
        )

        /**************************************************************
        * 2.3 Conteos
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
        * 2.4 Medias pretratamiento
        **************************************************************/

        quietly summarize ///
            N_firstyear_incumbent ///
            if ao_proceso <= 2011

        local mean_N_pre = r(mean)

        quietly summarize ///
            mean_psu_lm_firstyear ///
            if ao_proceso <= 2011

        local mean_S_pre = r(mean)

        /**************************************************************
        * 2.5 Identificar especificación principal
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

            if "`kernel'" == "tri" {

                local z_weighted ///
                    z_tri10

                local kernel_name ///
                    triangular
            }

            if "`kernel'" == "gau" {

                local z_weighted ///
                    z_gau10

                local kernel_name ///
                    gaussian
            }

            di as result ///
                "Kernel: `kernel_name'"

            
/**********************************************************
* 2.7 Primera etapa de matrícula
*
* N_pt sobre exposición cercana en selectividad.
**********************************************************/

reghdfe ///
    N_firstyear_incumbent ///
    `z_weighted', ///
    absorb( ///
        program_id ///
        field_year_id ///
    ) ///
    vce(cluster market_pre)

local N_enroll = e(N)

/*
Con un solo instrumento excluido, este es el estadístico F
de relevancia del instrumento.
*/

test `z_weighted'

local F_enroll = r(F)

/*
R2 parcial del instrumento ponderado.
*/

local rss_unrestricted = e(rss)

quietly reghdfe ///
    N_firstyear_incumbent, ///
    absorb( ///
        program_id ///
        field_year_id ///
    ) ///
    vce(cluster market_pre)

local rss_restricted = e(rss)

local pr2_enroll = ///
    (`rss_restricted' - `rss_unrestricted') / ///
    `rss_restricted'

/*
Volver a estimar para recuperar coeficiente y error estándar.
*/

quietly reghdfe ///
    N_firstyear_incumbent ///
    `z_weighted', ///
    absorb( ///
        program_id ///
        field_year_id ///
    ) ///
    vce(cluster market_pre)

local beta = ///
    _b[`z_weighted']

local se = ///
    _se[`z_weighted']

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
    `beta' - ///
    `critical' * `se'

local ci_high = ///
    `beta' + ///
    `critical' * `se'

post `resultspost' ///
    ("`markettype'") ///
    ("`geotype'") ///
    ("`kernel_name'") ///
    ("enrollment") ///
    ("weighted") ///
    (`main') ///
    (`beta') ///
    (`se') ///
    (`pvalue') ///
    (`ci_low') ///
    (`ci_high') ///
    (`F_enroll') ///
    (`pr2_enroll') ///
    (`mean_N_pre') ///
    (`N_enroll') ///
    (`N_programs') ///
    (`N_markets')			
			        }   // Cierra foreach kernel
    }       // Cierra forvalues g
}           // Cierra forvalues i

postclose `resultspost'
/**********************************************************************
* 3. Preparar resultados
**********************************************************************/

use `results', clear

/**********************************************************************
* 3.1 Estrellas
**********************************************************************/

gen str3 stars = ""

replace stars = "*" ///
    if pvalue < 0.10

replace stars = "**" ///
    if pvalue < 0.05

replace stars = "***" ///
    if pvalue < 0.01

gen str20 estimate = ///
    string(beta, "%9.3f") + ///
    stars

gen str20 standard_error = ///
    "(" + ///
    string(se, "%9.3f") + ///
    ")"

/**********************************************************************
* 3.2 Orden
**********************************************************************/

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

gen byte instrument_order = .

replace instrument_order = 1 ///
    if instrument == "unweighted"

replace instrument_order = 2 ///
    if instrument == "weighted"

sort ///
    market_order ///
    geo_order ///
    kernel_order ///
    outcome_order ///
    instrument_order

/**********************************************************************
* 3.3 Formatos
**********************************************************************/

format ///
    beta ///
    se ///
    ci_low ///
    ci_high ///
    joint_F ///
    outcome_pre_mean ///
    %10.3f

format ///
    partial_R2 ///
    %9.4f

format ///
    pvalue ///
    %9.4f

order ///
    market_type ///
    geo_type ///
    kernel ///
    outcome ///
    instrument ///
    main_spec ///
    beta ///
    se ///
    pvalue ///
    joint_F ///
    partial_R2 ///
    outcome_pre_mean ///
    N ///
    N_programs ///
    N_markets ///
    stars ///
    estimate ///
    standard_error

/**********************************************************************
* 4. Mostrar especificación principal
**********************************************************************/

list ///
    kernel ///
    outcome ///
    instrument ///
    beta ///
    se ///
    pvalue ///
    joint_F ///
    partial_R2 ///
    N ///
    N_programs ///
    N_markets ///
    if main_spec == 1, ///
    noobs ///
    clean ///
    separator(2)

/**********************************************************************
* 5. Guardar
**********************************************************************/

save ///
    "$processed/sua_weighted_first_stage_results.dta", ///
    replace

export excel ///
    using "$output/sua_weighted_first_stage_results.xlsx", ///
    firstrow(variables) ///
    replace

di as result ///
    "Matriz de primeras etapas guardada en:"

di as result ///
    "$processed/sua_weighted_first_stage_results.dta"

di as result ///
    "$output/sua_weighted_first_stage_results.xlsx"