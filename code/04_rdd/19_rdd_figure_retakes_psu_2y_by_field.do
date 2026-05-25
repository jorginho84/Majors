/**********************************************************************
* 19_rdd_figure_retakes_psu_2y_by_field.do
*
* Objetivo:
*   Estimar y graficar RDD de retakes_psu_2y por field.
*
* Outcome:
*   retakes_psu_2y = 1 si el estudiante vuelve a rendir PSU
*   en t+1 o t+2.
*
* Regresión:
*   |score_rd| <= 25
*
* Figura:
*   Un panel por field.
*   Gráfico combinado exportado a PDF.
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local bw_reg  25
local bw_plot 50
local binw    5
local min_n   1000

capture mkdir "$output/figures"
capture mkdir "$output/figures/retakes_psu"


/**********************************************************************
* 1. Cargar base con retakes_psu_2y
**********************************************************************/

use "$processed/analysis_sample_retakes_psu_2y.dta", clear


/**********************************************************************
* 2. Crear program_year_id si no existe
**********************************************************************/

capture confirm variable program_year_id

if _rc != 0 {
    di as text "program_year_id no existe. Creándolo."
    egen program_year_id = group(ao_proceso t_codigo_carrera)
    label variable program_year_id "Program-year FE: ao_proceso x t_codigo_carrera"
}


/**********************************************************************
* 3. Asegurar field
*
* Si field no está en la base, se mergea desde
* analysis_sample_with_fields_final.dta usando:
*
*   ao_proceso t_codigo_carrera
**********************************************************************/

capture confirm variable field

if _rc != 0 {

    di as text "field no existe. Mergeando desde analysis_sample_with_fields_final.dta"

    preserve

        use "$processed/analysis_sample_with_fields_final.dta", clear

        foreach v in ao_proceso t_codigo_carrera field {
            capture confirm variable `v'
            if _rc != 0 {
                di as error "Falta `v' en analysis_sample_with_fields_final.dta"
                exit 111
            }
        }

        keep ao_proceso t_codigo_carrera field

        drop if missing(field)
        drop if field == "Missing"

        duplicates drop ao_proceso t_codigo_carrera field, force
        bysort ao_proceso t_codigo_carrera: keep if _n == 1

        tempfile fields
        save `fields', replace

    restore

    merge m:1 ao_proceso t_codigo_carrera using `fields'

    tab _merge

    count if _merge == 3

    if r(N) == 0 {
        di as error "ERROR: el merge de field tuvo 0 matches."
        exit 111
    }

    keep if _merge == 3
    drop _merge
}


/**********************************************************************
* 4. Revisar variables necesarias
**********************************************************************/

foreach v in retakes_psu_2y score_rd above_cutoff program_year_id field {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable necesaria: `v'"
        exit 111
    }
}


/**********************************************************************
* 5. Limpiar muestra
**********************************************************************/

drop if missing(field)
drop if field == "Missing"
keep if !missing(retakes_psu_2y, score_rd, above_cutoff, program_year_id)


/**********************************************************************
* 6. Mantener fields con N suficiente dentro del bandwidth
**********************************************************************/

preserve

    keep if abs(score_rd) <= `bw_reg'

    collapse (count) N = retakes_psu_2y, by(field)

    sort field

    di as text "=================================================="
    di as result "N por field dentro de BW ±`bw_reg'"
    di as text "=================================================="

    list field N, noobs abbreviate(30)

restore

bysort field: egen field_n_bw = total(abs(score_rd) <= `bw_reg')
keep if field_n_bw >= `min_n'

di as text "=================================================="
di as result "Fields incluidos en la figura"
di as text "=================================================="

tab field, missing


/**********************************************************************
* 7. Codificar field
**********************************************************************/

encode field, gen(field_id)

levelsof field_id, local(fieldids)


/**********************************************************************
* 8. Programa interno para crear gráfico RDD por field
**********************************************************************/

capture program drop make_retakes_field_graph

program define make_retakes_field_graph

    syntax, FIELDID(integer) ///
        BWREG(integer) ///
        BWPLOT(integer) ///
        BINW(real) ///
        OUTNAME(string)

    local fid     = `fieldid'
    local bw_reg  = `bwreg'
    local bw_plot = `bwplot'
    local binw    = `binw'
    local barw    = `binw' * 0.90

    local fname : label field_id `fid'

    /************************************************************
    * Estimar RDD para este field
    ************************************************************/

    quietly count if field_id == `fid' ///
        & abs(score_rd) <= `bw_reg' ///
        & !missing(retakes_psu_2y, above_cutoff, score_rd, program_year_id)

    local N0 = r(N)

    quietly levelsof program_year_id if field_id == `fid' ///
        & abs(score_rd) <= `bw_reg' ///
        & !missing(retakes_psu_2y, above_cutoff, score_rd, program_year_id), ///
        local(clusters)

    local G0 : word count `clusters'

    if `N0' == 0 | `G0' <= 1 {
        di as text "Se salta `fname': N=`N0', clusters=`G0'"
        exit
    }

    quietly reghdfe retakes_psu_2y ///
        above_cutoff ///
        c.score_rd ///
        1.above_cutoff#c.score_rd ///
        if field_id == `fid' ///
        & abs(score_rd) <= `bw_reg', ///
        absorb(program_year_id) ///
        vce(cluster program_year_id)

    local beta = _b[above_cutoff]
    local se   = _se[above_cutoff]
    local N    = e(N)
    local G    = e(N_clust)

    local beta_txt : display %5.3f `beta'
    local se_txt   : display %5.3f `se'


    /************************************************************
    * Crear bins del outcome
    ************************************************************/

    tempfile outcome_bins hist_bins

    preserve

        keep if field_id == `fid'
        keep if abs(score_rd) <= `bw_plot'
        keep if !missing(retakes_psu_2y, score_rd, above_cutoff)

        gen bin = floor(score_rd / `binw') * `binw' + (`binw' / 2)

        collapse ///
            (mean) mean_y = retakes_psu_2y, ///
            by(bin above_cutoff)

        save `outcome_bins', replace

    restore


    /************************************************************
    * Crear bins del histograma
    ************************************************************/

    preserve

        keep if field_id == `fid'
        keep if abs(score_rd) <= `bw_plot'
        keep if !missing(score_rd)

        gen bin = floor(score_rd / `binw') * `binw' + (`binw' / 2)

        collapse ///
            (count) freq = score_rd, ///
            by(bin)

        save `hist_bins', replace

    restore


    /************************************************************
    * Graficar panel
    ************************************************************/

    preserve

        use `outcome_bins', clear

        merge m:1 bin using `hist_bins', ///
            keep(master match) nogen

        summarize mean_y, meanonly

        local y_min = r(min)
        local y_max = r(max)

        local text_y = `y_min' + 0.10 * (`y_max' - `y_min')
        local text_x = 45

        twoway ///
            (bar freq bin, ///
                yaxis(1) ///
                barwidth(`barw') ///
                color(eltblue%25) ///
                lcolor(eltblue%0)) ///
            (scatter mean_y bin if above_cutoff == 0, ///
                yaxis(2) ///
                msymbol(O) ///
                msize(tiny) ///
                color(black)) ///
            (scatter mean_y bin if above_cutoff == 1, ///
                yaxis(2) ///
                msymbol(O) ///
                msize(tiny) ///
                color(black)) ///
            (lfit mean_y bin if above_cutoff == 0 & abs(bin) <= `bw_reg', ///
                yaxis(2) ///
                lwidth(medthin) ///
                color(black)) ///
            (lfit mean_y bin if above_cutoff == 1 & abs(bin) <= `bw_reg', ///
                yaxis(2) ///
                lwidth(medthin) ///
                color(black)), ///
            xline(0, lpattern(dash) lcolor(gs8)) ///
			xlabel(-50(25)50, labsize(vsmall)) ///
			xscale(range(-50 50)) ///
			yscale(axis(1) range(0 .)) ///
			yscale(axis(2) range(0 1)) ///
			ylabel(, axis(1) labsize(vsmall)) ///
			ylabel(0(.1)1, axis(2) labsize(vsmall)) ///
			xtitle("") ///
			ytitle("", axis(1)) ///
			ytitle("", axis(2)) ///
            title("`fname'", size(small)) ///
            subtitle("β=`beta_txt' (`se_txt')", size(vsmall)) ///
            legend(off) ///
            graphregion(color(white)) ///
            plotregion(color(white)) ///
            name(`outname', replace)

    restore

end


/**********************************************************************
* 9. Crear gráficos individuales por field
**********************************************************************/

local graphnames ""

foreach f of local fieldids {

    local gname = "g_field_`f'"

    make_retakes_field_graph, ///
        fieldid(`f') ///
        bwreg(`bw_reg') ///
        bwplot(`bw_plot') ///
        binw(`binw') ///
        outname(`gname')

    local graphnames "`graphnames' `gname'"
}


/**********************************************************************
* 10. Combinar gráficos en un PDF
**********************************************************************/

graph combine `graphnames', ///
    cols(5) ///
    title("RDD: Retakes PSU Within Two Years by Field", size(medsmall)) ///
    subtitle("Outcome: retakes_psu_2y. Regression BW = ±`bw_reg'; plot range = ±`bw_plot'", size(small)) ///
    graphregion(color(white))

graph export "$output/figures/retakes_psu/rdd_retakes_psu_2y_by_field_combined.pdf", replace


/**********************************************************************
* 11. Final
**********************************************************************/

di as text "=================================================="
di as result "Listo. Figura combinada:"
di as result "$output/figures/retakes_psu/rdd_retakes_psu_2y_by_field_combined.pdf"
di as text "=================================================="