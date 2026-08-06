/**********************************************************************
* 04_sua_first_stage.do
*
* Objetivo:
*   Estimar el first stage del diseño IV basado en la incorporación
*   de universidades privadas al SUA.
*
* Ecuación:
*
*   N_total_pt =
*       pi(E_p × Post_t)
*       + FE programa
*       + FE campo × año
*       + error_pt
*
* Instrumento:
*   Exposición pretratamiento × post-2012.
*
* Interpretación:
*   El coeficiente corresponde al efecto de 10 puntos porcentuales
*   adicionales de exposición pretratamiento.
*
* Especificación principal del PDF:
*   broad_area × region.
*
* Robustez:
*   Tres definiciones académicas × tres niveles geográficos.
*
* Outputs:
*   $processed/sua_first_stage_results.dta
*   $output/sua_first_stage_results.xlsx
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

tempfile first_stage_results

tempname results_post

postfile `results_post' ///
    str20 market_type ///
    str12 geo_type ///
    byte main_spec ///
    double beta ///
    double se ///
    double pvalue ///
    double first_stage_F ///
    double ci_low ///
    double ci_high ///
    double mean_outcome_pre ///
    double mean_exposure ///
    long N ///
    long N_programs ///
    long N_markets ///
    using `first_stage_results', ///
    replace

/**********************************************************************
* 2. Estimar first stage para las nueve definiciones
**********************************************************************/

forvalues i = 1/3 {

    local markettype : word `i' of `markettypes'

    forvalues g = 1/3 {

        local geotype : word `g' of `geotypes'

        local input ///
            "$processed/sua_incumbent_panel_`markettype'_`geotype'_2007_2016.dta"

        use "`input'", clear

        /**************************************************************
        * 2.1 Muestra con exposición identificada
        **************************************************************/

        keep if ///
            exposure_assigned == 1 & ///
            market_has_incumbent == 1

        drop if missing( ///
            N_firstyear_incumbent, ///
            sua_exposure, ///
            codigo_demre, ///
            sigla_universidad, ///
            market_id, ///
            market_field, ///
            geo_id, ///
            ao_proceso ///
        )

        assert _N > 0

       /**********************************************************************
		* 2.2 Armonizar códigos DEMRE 2007-2016
		*
		* Antes de 2012 los códigos tienen cuatro dígitos. Se convierten al
		* formato posterior insertando un cero antes de los últimos dos.
		*
		* Ejemplo:
		*   1142 -> 11042
		**********************************************************************/

		gen str12 codigo_demre_string = ///
			strtrim(string(codigo_demre, "%12.0f"))

		gen long codigo_carrera_harmonized = ///
			codigo_demre

		replace codigo_carrera_harmonized = ///
			real( ///
				substr( ///
					codigo_demre_string, ///
					1, ///
					length(codigo_demre_string) - 2 ///
				) + ///
				"0" + ///
				substr( ///
					codigo_demre_string, ///
					length(codigo_demre_string) - 1, ///
					2 ///
				) ///
			) ///
			if length(codigo_demre_string) == 4

		drop codigo_demre_string

		assert !missing(codigo_carrera_harmonized)

		/**********************************************************************
		* 2.3 Identificador longitudinal de programa
		*
		* Misma definición utilizada en el ejercicio inframarginal:
		*   universidad × código DEMRE armonizado.
		**********************************************************************/

		egen long program_panel_id = group( ///
			sigla_universidad ///
			codigo_carrera_harmonized ///
		), label

		assert !missing(program_panel_id)

		/**********************************************************************
		* 2.3.1 Agregar cuando existe más de una fila programa-año
		*
		* Formulario D puede distinguir nombres o sedes dentro del mismo código.
		* Para el first stage recuperamos la unidad programa DEMRE-año sumando
		* la matrícula.
		**********************************************************************/

		duplicates tag ///
			program_panel_id ///
			ao_proceso, ///
			generate(dup_program_year)

		quietly count if dup_program_year > 0

		if r(N) > 0 {

			collapse ///
				(sum) ///
					N_firstyear_incumbent ///
					n_firstyear_psu ///
				(firstnm) ///
					mean_psu_lm_firstyear ///
					share_firstyear_psu ///
					sua_exposure ///
					sua_exposure_pct ///
					post2012 ///
					market_id ///
					market_field ///
					geo_id ///
					geo_name ///
					market_type ///
					geo_type ///
					market_has_incumbent ///
					codigo_carrera_harmonized ///
					sigla_universidad, ///
				by( ///
					program_panel_id ///
					ao_proceso ///
				)
		}

		isid ///
			program_panel_id ///
			ao_proceso
	
        /**************************************************************
        * 2.4 Programas observados antes y después de la reforma
        **************************************************************/

        bysort program_panel_id: ///
            egen byte observed_pre = ///
                max(ao_proceso <= 2011)

        bysort program_panel_id: ///
            egen byte observed_post = ///
                max(ao_proceso >= 2012)

        gen byte spans_reform = ///
            observed_pre == 1 & ///
            observed_post == 1

        quietly count if spans_reform == 1

        di as result ///
            "`markettype' × `geotype': " ///
            "program-years spanning reform = " r(N)

        keep if spans_reform == 1

        assert _N > 0

        /**************************************************************
        * 2.5 Instrumento escalado
        *
        * exposure_10 = 1 equivale a 10 puntos porcentuales de
        * exposición pretratamiento.
        **************************************************************/

        gen double exposure_10 = ///
            10 * sua_exposure

        gen double exposure_10_post = ///
            exposure_10 * post2012

        label variable exposure_10_post ///
            "10 p.p. entrant exposure × post-2012"

        /**************************************************************
        * 2.6 Efectos fijos campo × año
        *
        * Corresponde a alpha_f(p),t en la ecuación del PDF.
        **************************************************************/

        egen long field_year_id = group( ///
            market_field ///
            ao_proceso ///
        )

        assert !missing(field_year_id)

        /**************************************************************
        * 2.7 Conteos y estadísticas descriptivas
        **************************************************************/

        egen byte tag_program = ///
            tag(program_panel_id)

        egen byte tag_market = ///
            tag(market_id)

        quietly count if tag_program == 1
        local N_programs = r(N)

        quietly count if tag_market == 1
        local N_markets = r(N)

        quietly summarize ///
            N_firstyear_incumbent ///
            if ao_proceso <= 2011

        local mean_pre = r(mean)

        /*
        Promedio de exposición entre programas, no entre mercados.
        */

        quietly summarize sua_exposure
        local mean_exposure = r(mean)

        /**************************************************************
        * 2.8 First stage
        **************************************************************/

        reghdfe ///
            N_firstyear_incumbent ///
            exposure_10_post, ///
            absorb( ///
                program_panel_id ///
                field_year_id ///
            ) ///
            vce(cluster market_id)

        local beta = ///
            _b[exposure_10_post]

        local se = ///
            _se[exposure_10_post]

        local tstat = ///
            `beta' / `se'

        /*
        Con un único instrumento excluido, el estadístico F corresponde
        al cuadrado del estadístico t del coeficiente.
        */

        local Fstat = ///
            `tstat'^2

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

        local N = e(N)

        local main = 0

        if ///
            "`markettype'" == "broad_area" & ///
            "`geotype'" == "region" {

            local main = 1
        }

        post `results_post' ///
            ("`markettype'") ///
            ("`geotype'") ///
            (`main') ///
            (`beta') ///
            (`se') ///
            (`pvalue') ///
            (`Fstat') ///
            (`ci_low') ///
            (`ci_high') ///
            (`mean_pre') ///
            (`mean_exposure') ///
            (`N') ///
            (`N_programs') ///
            (`N_markets')

        di as result ///
            "`markettype' × `geotype': " ///
            "beta = " %9.3f `beta' ///
            ", SE = " %9.3f `se' ///
            ", F = " %9.2f `Fstat' ///
            ", N = " %9.0f `N'
    }
}

postclose `results_post'

/**********************************************************************
* 3. Preparar resultados
**********************************************************************/

use `first_stage_results', clear

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
* 3.1 Orden de las definiciones académicas
**********************************************************************/

gen byte market_order = .

replace market_order = 1 ///
    if market_type == "broad_area"

replace market_order = 2 ///
    if market_type == "cine_subarea"

replace market_order = 3 ///
    if market_type == "generic_area"

/**********************************************************************
* 3.2 Orden de los niveles geográficos
**********************************************************************/

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

/**********************************************************************
* 3.3 Etiquetas y formatos
**********************************************************************/

label variable beta ///
    "Effect of 10 p.p. higher entrant exposure"

label variable se ///
    "Market-clustered standard error"

label variable pvalue ///
    "P-value"

label variable first_stage_F ///
    "First-stage F statistic"

label variable mean_outcome_pre ///
    "Mean incumbent enrollment, 2007-2011"

label variable mean_exposure ///
    "Mean entrant exposure in analytical sample"

label variable main_spec ///
    "Ten-field harmonization × region"

format ///
    beta ///
    se ///
    ci_low ///
    ci_high ///
    mean_outcome_pre ///
    mean_exposure ///
    first_stage_F ///
    %10.3f

format pvalue %9.4f

order ///
    market_type ///
    geo_type ///
    main_spec ///
    beta ///
    se ///
    pvalue ///
    first_stage_F ///
    ci_low ///
    ci_high ///
    mean_outcome_pre ///
    mean_exposure ///
    N ///
    N_programs ///
    N_markets ///
    stars ///
    estimate ///
    standard_error

/**********************************************************************
* 4. Mostrar resultados
**********************************************************************/

list ///
    market_type ///
    geo_type ///
    beta ///
    se ///
    pvalue ///
    first_stage_F ///
    mean_outcome_pre ///
    N ///
    N_programs ///
    N_markets, ///
    noobs ///
    clean ///
    separator(3)

/**********************************************************************
* 5. Guardar resultados
**********************************************************************/

save ///
    "$processed/sua_first_stage_results.dta", ///
    replace

export excel ///
    using "$output/sua_first_stage_results.xlsx", ///
    firstrow(variables) ///
    replace

di as result ///
    "First-stage results guardados en:"

di as result ///
    "$processed/sua_first_stage_results.dta"

di as result ///
    "$output/sua_first_stage_results.xlsx"