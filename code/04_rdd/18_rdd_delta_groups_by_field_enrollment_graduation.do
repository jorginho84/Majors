/**********************************************************************
* 18_rdd_delta_groups_by_field_enrollment_graduation.do
*
* Objetivo:
*   Estimar RDD por field x delta_group para outcomes de enrollment
*   y graduation 8y, usando la base canónica creada por el 14.
*
* Input:
*   $processed/analysis_sample_delta_groups.dta
*
* Outcomes:
*   Enrollment:
*       enrolls_target
*       enrolls_uni
*       enrolls_he
*
*   Graduation 8y:
*       graduates_target_8y
*       graduates_uni_8y
*       graduates_he_8y
*
* Outputs:
*   Solo figuras PDF en:
*       $output/figures/delta_by_field/
*
* Figuras:
*   field_N.pdf
*   field_enroll_target.pdf
*   field_enroll_uni.pdf
*   field_enroll_he.pdf
*   field_grad_target8y.pdf
*   field_grad_uni8y.pdf
*   field_grad_he8y.pdf
*
* No guarda:
*   - bases intermedias
*   - resultados .dta
*   - CSV
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local bw 25
local min_n_field 1000

capture mkdir "$output/figures"
capture mkdir "$output/figures/delta_by_field"


/**********************************************************************
* 1. Cargar base canónica creada por el 14
**********************************************************************/

use "$processed/analysis_sample_delta_groups.dta", clear


/**********************************************************************
* 2. Verificar variables necesarias
**********************************************************************/

foreach v in ///
    score_rd ///
    above_cutoff ///
    program_year_id ///
    delta_selectivity ///
    has_nextbest ///
    field ///
    enrolls_target ///
    enrolls_uni ///
    enrolls_he ///
    graduates_target_8y ///
    graduates_uni_8y ///
    graduates_he_8y {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable necesaria: `v'"
        di as error "Revisar que el 14 haya creado analysis_sample_delta_groups.dta desde analysis_sample_with_fields_graduation_8y.dta."
        exit 111
    }
}


/**********************************************************************
* 3. Definición manual de grupos de delta_selectivity
*
* IMPORTANTE:
* Este bloque debe ser idéntico en 14, 15 y 18 si se quiere modificar
* manualmente los cortes de forma consistente.
*
* Grupos vigentes:
*   d1: < -10
*   d2: [-10,10)
*   d3: [10,30)
*   d4: [30,50)
*   d5: >= 50
**********************************************************************/

capture drop delta_group
capture drop group_delta_selectivity

gen byte delta_group = .

replace delta_group = 1 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity < -10

replace delta_group = 2 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= -10 ///
    & delta_selectivity < 10

replace delta_group = 3 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= 10 ///
    & delta_selectivity < 30

replace delta_group = 4 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= 30 ///
    & delta_selectivity < 50

replace delta_group = 5 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= 50

label define delta_group_lbl ///
    1 "d1: < -10" ///
    2 "d2: [-10,10)" ///
    3 "d3: [10,30)" ///
    4 "d4: [30,50)" ///
    5 "d5: >= 50", replace

label values delta_group delta_group_lbl

* Alias de compatibilidad con códigos previos
gen byte group_delta_selectivity = delta_group
label values group_delta_selectivity delta_group_lbl


/**********************************************************************
* 4. Limpiar muestra base
**********************************************************************/

drop if missing(field)
drop if field == "Missing"

keep if !missing(score_rd, above_cutoff, program_year_id)
keep if !missing(delta_selectivity, delta_group)


/**********************************************************************
* 5. Diagnósticos generales
**********************************************************************/

di as text "=================================================="
di as result "Diagnóstico 18: delta_group dentro de BW"
di as text "=================================================="

tab delta_group if abs(score_rd) <= `bw', missing

di as text "=================================================="
di as result "has_nextbest dentro de BW"
di as text "=================================================="

tab has_nextbest if abs(score_rd) <= `bw', missing

di as text "=================================================="
di as result "delta_group por lado del cutoff"
di as text "=================================================="

tab above_cutoff delta_group if abs(score_rd) <= `bw', missing

di as text "=================================================="
di as result "N por field dentro de BW"
di as text "=================================================="

preserve

    keep if abs(score_rd) <= `bw'
    collapse (count) N = score_rd, by(field)
    sort field
    list field N, noobs abbreviate(30)

restore


/**********************************************************************
* 6. Mantener fields con N suficiente
**********************************************************************/

capture drop field_n_bw

bysort field: egen field_n_bw = total(abs(score_rd) <= `bw')

keep if field_n_bw >= `min_n_field'

di as text "=================================================="
di as result "Fields incluidos"
di as text "=================================================="

tab field if abs(score_rd) <= `bw', missing


/**********************************************************************
* 7. Codificar field
**********************************************************************/

encode field, gen(field_id)

levelsof field_id, local(fieldids)


/**********************************************************************
* 8. Estimar RDD por outcome, field y delta_group
*
* Resultados se guardan solo en tempfile.
**********************************************************************/

local outcomes ///
    enrolls_target ///
    enrolls_uni ///
    enrolls_he ///
    graduates_target_8y ///
    graduates_uni_8y ///
    graduates_he_8y

tempfile rdd_results

tempname handle

postfile `handle' ///
    str40 outcome ///
    int field_id ///
    str40 field ///
    byte delta_group ///
    double beta se ci_low ci_high N clusters ///
    using `rdd_results', replace


foreach y of local outcomes {

    foreach f of local fieldids {

        local fname : label field_id `f'

        forvalues g = 1/5 {

            quietly count if abs(score_rd) <= `bw' ///
                & field_id == `f' ///
                & delta_group == `g' ///
                & !missing(`y', above_cutoff, score_rd, program_year_id)

            local N = r(N)

            quietly levelsof program_year_id if abs(score_rd) <= `bw' ///
                & field_id == `f' ///
                & delta_group == `g' ///
                & !missing(`y', above_cutoff, score_rd, program_year_id), ///
                local(clustlist)

            local K : word count `clustlist'

            quietly summarize above_cutoff if abs(score_rd) <= `bw' ///
                & field_id == `f' ///
                & delta_group == `g' ///
                & !missing(`y', above_cutoff, score_rd, program_year_id), meanonly

            local min_above = r(min)
            local max_above = r(max)

            if `N' > 0 & `K' > 1 & `min_above' != `max_above' {

                di as text "=================================================="
                di as result "RDD | outcome=`y' | field=`fname' | delta_group=`g'"
                di as result "N=`N', clusters=`K'"
                di as text "=================================================="

                capture noisily reghdfe `y' ///
                    above_cutoff ///
                    c.score_rd ///
                    1.above_cutoff#c.score_rd ///
                    if abs(score_rd) <= `bw' ///
                    & field_id == `f' ///
                    & delta_group == `g', ///
                    absorb(program_year_id) ///
                    vce(cluster program_year_id)

                if _rc == 0 {

                    local b  = _b[above_cutoff]
                    local se = _se[above_cutoff]
                    local lo = `b' - 1.96 * `se'
                    local hi = `b' + 1.96 * `se'

                    post `handle' ///
                        ("`y'") ///
                        (`f') ///
                        ("`fname'") ///
                        (`g') ///
                        (`b') (`se') (`lo') (`hi') (`N') (`K')
                }
                else {
                    di as error "RDD falló: outcome `y', field `fname', grupo `g'"
                }
            }
            else {
                di as text "Se salta: `y' | `fname' | grupo `g' | N=`N', clusters=`K'"
            }
        }
    }
}

postclose `handle'


/**********************************************************************
* 9. Preparar resultados para gráficos
**********************************************************************/

use `rdd_results', clear

capture confirm variable beta
if _rc != 0 {
    di as error "No se generaron resultados RDD."
    exit 111
}

gen beta_label = string(beta, "%5.3f")

label define dgrp_axis ///
    1 "d1" ///
    2 "d2" ///
    3 "d3" ///
    4 "d4" ///
    5 "d5", replace

label values delta_group dgrp_axis

levelsof field_id, local(fieldids)


/**********************************************************************
* 10. Programa para crear panel individual por field
**********************************************************************/

capture program drop make_delta_field_bar

program define make_delta_field_bar

    syntax, OUTCOME(string) FIELDID(integer) OUTNAME(name)

    preserve

        keep if outcome == "`outcome'" ///
            & field_id == `fieldid'

        quietly count
        if r(N) == 0 {
            restore
            exit
        }

        sort delta_group

        local fname = field[1]

        /************************************************************
        * Escalas fijas por outcome
        ************************************************************/

        local ymin = -0.02
        local ymax = 0.12
        local ystep = 0.02

        if "`outcome'" == "enrolls_target" {
            local ymin = 0.35
            local ymax = 0.75
            local ystep = 0.10
        }

        if inlist("`outcome'", "enrolls_uni", "enrolls_he") {
            local ymin = -0.02
            local ymax = 0.12
            local ystep = 0.02
        }

        if "`outcome'" == "graduates_target_8y" {
            local ymin = 0.05
            local ymax = 0.35
            local ystep = 0.05
        }

        if inlist("`outcome'", "graduates_uni_8y", "graduates_he_8y") {
            local ymin = -0.05
            local ymax = 0.12
            local ystep = 0.05
        }

        twoway ///
            (bar beta delta_group, ///
                barwidth(0.65) ///
                fcolor(navy%70) ///
                lcolor(navy)) ///
            (rcap ci_high ci_low delta_group, ///
                lwidth(vthin) ///
                lcolor(maroon)) ///
            (scatter beta delta_group, ///
                msymbol(none) ///
                mlabel(beta_label) ///
                mlabposition(12) ///
                mlabsize(tiny)), ///
            yline(0, lpattern(dash) lcolor(gs8)) ///
            yscale(range(`ymin' `ymax')) ///
            ylabel(`ymin'(`ystep')`ymax', labsize(tiny)) ///
            xlabel(1 "d1" ///
                   2 "d2" ///
                   3 "d3" ///
                   4 "d4" ///
                   5 "d5", ///
                   labsize(vsmall)) ///
            xscale(range(0.5 5.5)) ///
            xtitle("") ///
            ytitle("") ///
            title("`fname'", size(small)) ///
            legend(off) ///
            graphregion(color(white)) ///
            plotregion(color(white)) ///
            name(`outname', replace)

    restore

end


/**********************************************************************
* 11. Crear PDFs combinados por outcome
**********************************************************************/

foreach y of local outcomes {

    local graphnames ""

    foreach f of local fieldids {

        /*
        Nombres internos cortos por límite de Stata.
        */
        local shorty ""

        if "`y'" == "enrolls_target" {
            local shorty "et"
        }

        if "`y'" == "enrolls_uni" {
            local shorty "eu"
        }

        if "`y'" == "enrolls_he" {
            local shorty "eh"
        }

        if "`y'" == "graduates_target_8y" {
            local shorty "gt"
        }

        if "`y'" == "graduates_uni_8y" {
            local shorty "gu"
        }

        if "`y'" == "graduates_he_8y" {
            local shorty "gh"
        }

        local gname = "g_`shorty'_`f'"

        make_delta_field_bar, ///
            outcome("`y'") ///
            fieldid(`f') ///
            outname(`gname')

        capture graph describe `gname'
        if _rc == 0 {
            local graphnames "`graphnames' `gname'"
        }
    }

    local mytitle ""
    local outfile ""

    if "`y'" == "enrolls_target" {
        local mytitle "RDD by field and delta group: Target enrollment"
        local outfile "field_enroll_target"
    }

    if "`y'" == "enrolls_uni" {
        local mytitle "RDD by field and delta group: University enrollment"
        local outfile "field_enroll_uni"
    }

    if "`y'" == "enrolls_he" {
        local mytitle "RDD by field and delta group: Higher education enrollment"
        local outfile "field_enroll_he"
    }

    if "`y'" == "graduates_target_8y" {
        local mytitle "RDD by field and delta group: Target graduation 8y"
        local outfile "field_grad_target8y"
    }

    if "`y'" == "graduates_uni_8y" {
        local mytitle "RDD by field and delta group: University graduation 8y"
        local outfile "field_grad_uni8y"
    }

    if "`y'" == "graduates_he_8y" {
        local mytitle "RDD by field and delta group: HE graduation 8y"
        local outfile "field_grad_he8y"
    }

    graph combine `graphnames', ///
        cols(5) ///
        imargin(tiny) ///
        title("`mytitle'", size(medsmall)) ///
        subtitle("d1 < -10; d2 [-10,10); d3 [10,30); d4 [30,50); d5 >= 50. BW = ±`bw'.", ///
            size(vsmall)) ///
        graphregion(color(white))

    graph export "$output/figures/delta_by_field/`outfile'.pdf", replace
}


/**********************************************************************
* 12. Crear figura descriptiva N por field y delta group
**********************************************************************/

use "$processed/analysis_sample_delta_groups.dta", clear

drop if missing(field)
drop if field == "Missing"

keep if abs(score_rd) <= `bw'
keep if !missing(field, delta_selectivity)

capture drop delta_group

gen byte delta_group = .

replace delta_group = 1 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity < -10

replace delta_group = 2 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= -10 ///
    & delta_selectivity < 10

replace delta_group = 3 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= 10 ///
    & delta_selectivity < 30

replace delta_group = 4 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= 30 ///
    & delta_selectivity < 50

replace delta_group = 5 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= 50

keep if !missing(delta_group)

bysort field: egen field_n_bw = total(!missing(score_rd))
keep if field_n_bw >= `min_n_field'

collapse (count) N = score_rd, by(field delta_group)

encode field, gen(field_id)

levelsof field_id, local(fieldids)

local graphnames ""

foreach f of local fieldids {

    local fname : label field_id `f'
    local gname = "n_`f'"

    twoway ///
        (bar N delta_group if field_id == `f', ///
            barwidth(0.65) ///
            fcolor(navy%70) ///
            lcolor(navy)), ///
        xlabel(1 "d1" ///
               2 "d2" ///
               3 "d3" ///
               4 "d4" ///
               5 "d5", ///
               labsize(vsmall)) ///
        xtitle("") ///
        ytitle("") ///
        title("`fname'", size(small)) ///
        legend(off) ///
        graphregion(color(white)) ///
        plotregion(color(white)) ///
        name(`gname', replace)

    local graphnames "`graphnames' `gname'"
}

graph combine `graphnames', ///
    cols(5) ///
    imargin(tiny) ///
    title("Observations by field and delta group", size(medsmall)) ///
    subtitle("Sample: |score_rd| <= `bw'", size(vsmall)) ///
    graphregion(color(white))

graph export "$output/figures/delta_by_field/field_N.pdf", replace


/**********************************************************************
* 13. Mostrar resultados
**********************************************************************/

use `rdd_results', clear

sort outcome field_id delta_group

di as text "=================================================="
di as result "Resultados RDD por outcome, field y delta group"
di as text "=================================================="

list outcome field delta_group beta se ci_low ci_high N clusters, ///
    sepby(outcome field) abbreviate(24)


di as text "=================================================="
di as result "18 terminado correctamente."
di as result "Input:"
di as result "$processed/analysis_sample_delta_groups.dta"
di as text "Figuras guardadas en:"
di as result "$output/figures/delta_by_field/"
di as text "Archivos esperados:"
di as result "  field_N.pdf"
di as result "  field_enroll_target.pdf"
di as result "  field_enroll_uni.pdf"
di as result "  field_enroll_he.pdf"
di as result "  field_grad_target8y.pdf"
di as result "  field_grad_uni8y.pdf"
di as result "  field_grad_he8y.pdf"
di as text "=================================================="