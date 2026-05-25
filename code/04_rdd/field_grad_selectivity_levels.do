/**********************************************************************
* field_grad_selectivity_levels.do
*
* Objetivo:
*   Graficar relación entre:
*
*       y = graduation rate del target
*       x = selectivity del target
*
*   Agrupado por field.
*
*   Cada línea representa un field.
*   Se usan 100 bins por field.
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

capture mkdir "$output/figures"
capture mkdir "$output/figures/field_relationships"

local nbins = 5
local min_n = 100


/**********************************************************************
* 1. Cargar base con atributos target / next-best
**********************************************************************/

use "$processed/next_best_admitted_all_attributes.dta", clear


/**********************************************************************
* 2. Revisar llave target
*
* En esta base:
*   target_codigo_carrera = código del programa target
**********************************************************************/

foreach v in ao_proceso target_codigo_carrera {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable necesaria: `v'"
        exit 111
    }
}


/**********************************************************************
* 3. Asegurar variable field
*
* En analysis_sample_with_fields_final.dta:
*   t_codigo_carrera = código del programa target
*
* Para mergear:
*   renombramos t_codigo_carrera -> target_codigo_carrera
**********************************************************************/

capture confirm variable field

if _rc != 0 {

    capture confirm variable target_field

    if _rc == 0 {
        rename target_field field
    }

    else {

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

            rename t_codigo_carrera target_codigo_carrera

            tempfile fields
            save `fields', replace

        restore

        merge m:1 ao_proceso target_codigo_carrera using `fields'

        tab _merge

        count if _merge == 3

        if r(N) == 0 {
            di as error "ERROR: el merge de field tuvo 0 matches."
            di as error "Revisar llaves: ao_proceso target_codigo_carrera."
            exit 111
        }

        keep if _merge == 3
        drop _merge
    }
}


/**********************************************************************
* 4. Revisar variables necesarias
**********************************************************************/

foreach v in field target_selectivity target_grad_target_8y {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable necesaria: `v'"
        di as error "Revisa nombres con: ds *field* *select* *grad*"
        exit 111
    }
}


/**********************************************************************
* 5. Limpiar muestra
**********************************************************************/

drop if missing(field)
drop if field == "Missing"

keep if !missing(target_selectivity, target_grad_target_8y)


/**********************************************************************
* 6. Variables para gráfico
**********************************************************************/

gen x_selectivity = target_selectivity
gen y_grad_rate   = target_grad_target_8y


/**********************************************************************
* 7. Mantener campos con tamaño mínimo
**********************************************************************/

capture drop field_n

bysort field: gen field_n = _N

di as text "Campos disponibles antes del filtro:"
tab field, missing

di as text "Minimum N per field: `min_n'"

keep if field_n >= `min_n'

di as text "Campos que quedan después del filtro:"
tab field, missing


/**********************************************************************
* 8. Crear 100 bins por field
**********************************************************************/

sort field x_selectivity

by field: gen rank_in_field = _n
by field: gen n_field = _N

gen bin = ceil(rank_in_field / n_field * `nbins')

replace bin = 1 if bin < 1
replace bin = `nbins' if bin > `nbins'


/**********************************************************************
* 9. Colapsar a nivel field-bin
**********************************************************************/

collapse ///
    (mean) selectivity = x_selectivity ///
    (mean) grad_rate   = y_grad_rate ///
    (count) n_bin      = y_grad_rate, ///
    by(field bin)

encode field, gen(field_id)

sort field_id selectivity

/**********************************************************************
* 10. Gráfico: una línea ajustada por field
**********************************************************************/

levelsof field_id, local(fieldids)

local plots ""
local legend_order ""
local i = 1

foreach f of local fieldids {

    local fname : label field_id `f'

    * Puntos binned por field
    local plots `"`plots' (scatter grad_rate selectivity if field_id == `f', msymbol(O) msize(tiny))"'

    * Línea ajustada por field
    local plots `"`plots' (lfit grad_rate selectivity if field_id == `f', lwidth(medthin))"'

    * La leyenda muestra solo la línea, no los puntos
    local legend_order `"`legend_order' `=`i'+1' "`fname'""'

    local i = `i' + 2
}

twoway `plots', ///
    xtitle("Selectivity") ///
    ytitle("Graduation rate") ///
    title("Graduation Rate and Selectivity by Field") ///
    subtitle("Target program attributes. `nbins' bins by field") ///
    legend(order(`legend_order') cols(2) size(vsmall)) ///
    graphregion(color(white)) ///
    plotregion(color(white))

graph export "$output/figures/field_relationships/grad_rate_selectivity_by_field.pdf", replace
/**********************************************************************
* 11. Guardar base colapsada para revisar
**********************************************************************/

save "$processed/field_grad_selectivity_levels_bins.dta", replace

di as text "=================================================="
di as result "Listo. Figura creada:"
di as result "$output/figures/field_relationships/grad_rate_selectivity_by_field.pdf"
di as result "Base de bins:"
di as result "$processed/field_grad_selectivity_levels_bins.dta"
di as text "=================================================="