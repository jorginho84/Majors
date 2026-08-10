/**********************************************************************
* 20_rdd_same_field_nextbest_enrollment_graduation.do
*
* Objetivo:
*   Estimar RDD separando observaciones donde el target y el next-best
*   pertenecen al mismo field versus distinto field.
*
* Inputs:
*   $processed/analysis_sample_delta_groups.dta
*   $processed/next_best_all_targets_with_attributes.dta
*   $processed/analysis_sample_with_fields_graduation_8y.dta
*
* Outputs:
*   Solo figuras PDF en:
*       $output/figures/same_field_nextbest/
*
* Figuras:
*   rdd_cutoff_same_field_8y.pdf
*   rdd_cutoff_different_field_8y.pdf
*   rdd_delta_same_field_8y.pdf
*   rdd_delta_different_field_8y.pdf
*
* No guarda:
*   - bases intermedias permanentes
*   - resultados .dta
*   - CSV
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local bw 25
local binw 2.5

capture mkdir "$output/figures"
capture mkdir "$output/figures/same_field_nextbest"


/**********************************************************************
* 1. Inputs
**********************************************************************/

local analysis "$processed/analysis_sample_delta_groups.dta"
local nextbest "$processed/next_best_all_targets_with_attributes.dta"
local fields   "$processed/analysis_sample_with_fields_graduation_8y.dta"

foreach f in "`analysis'" "`nextbest'" "`fields'" {
    capture confirm file "`f'"
    if _rc != 0 {
        di as error "No existe archivo requerido: `f'"
        exit 601
    }
}


/**********************************************************************
* 2. Preparar next-best desde output del 09
**********************************************************************/

tempfile nextbest_short

use "`nextbest'", clear

foreach v in ///
    mrun ///
    ao_proceso ///
    target_preferencia ///
    target_codigo_carrera ///
    has_nextbest ///
    nextbest_preferencia ///
    nextbest_codigo_carrera ///
    delta_selectivity ///
    target_selectivity ///
    nextbest_selectivity ///
    delta_grad_target_8y ///
    target_grad_target_8y ///
    nextbest_grad_target_8y {

    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable en next-best 09: `v'"
        exit 111
    }
}

capture confirm numeric variable ao_proceso
if _rc != 0 destring ao_proceso, replace force

capture confirm numeric variable target_codigo_carrera
if _rc != 0 destring target_codigo_carrera, replace force

capture confirm numeric variable nextbest_codigo_carrera
if _rc != 0 destring nextbest_codigo_carrera, replace force

rename target_preferencia preferencia
rename target_codigo_carrera t_codigo_carrera

keep mrun ao_proceso preferencia t_codigo_carrera ///
     has_nextbest ///
     nextbest_preferencia nextbest_codigo_carrera ///
     target_selectivity nextbest_selectivity delta_selectivity ///
     target_grad_target_8y nextbest_grad_target_8y delta_grad_target_8y

duplicates drop mrun ao_proceso preferencia t_codigo_carrera, force

save `nextbest_short', replace


/**********************************************************************
* 3. Preparar lookup de field por programa-año
*
* Nota:
*   Se usa la base oficial con field + graduation 8y.
*   Para next-best, buscamos field por ao_proceso x codigo_carrera.
**********************************************************************/

tempfile field_lookup

use "`fields'", clear

capture confirm variable t_codigo_carrera
if _rc != 0 {
    capture confirm variable codigo_carrera
    if _rc == 0 rename codigo_carrera t_codigo_carrera
    else {
        di as error "No existe t_codigo_carrera ni codigo_carrera en fields."
        exit 111
    }
}

foreach v in ao_proceso t_codigo_carrera field {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable en fields: `v'"
        exit 111
    }
}

capture confirm numeric variable ao_proceso
if _rc != 0 destring ao_proceso, replace force

capture confirm numeric variable t_codigo_carrera
if _rc != 0 destring t_codigo_carrera, replace force

keep ao_proceso t_codigo_carrera field
drop if missing(ao_proceso, t_codigo_carrera)
drop if missing(field)
drop if field == "Missing"

duplicates drop ao_proceso t_codigo_carrera, force

rename t_codigo_carrera codigo_carrera
rename field lookup_field

save `field_lookup', replace


/**********************************************************************
* 4. Cargar base canónica y pegar next-best
**********************************************************************/

use "`analysis'", clear

foreach v in ///
    mrun ///
    ao_proceso ///
    preferencia ///
    score_rd ///
    above_cutoff ///
    program_year_id ///
    field ///
    enrolls_target ///
    enrolls_uni ///
    enrolls_he ///
    graduates_target_8y ///
    graduates_uni_8y ///
    graduates_he_8y {

    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable en analysis_sample_delta_groups: `v'"
        exit 111
    }
}

capture confirm variable t_codigo_carrera
if _rc != 0 {
    capture confirm variable codigo_carrera
    if _rc == 0 rename codigo_carrera t_codigo_carrera
    else {
        di as error "No existe t_codigo_carrera ni codigo_carrera en analysis."
        exit 111
    }
}

capture confirm numeric variable ao_proceso
if _rc != 0 destring ao_proceso, replace force

capture confirm numeric variable t_codigo_carrera
if _rc != 0 destring t_codigo_carrera, replace force

foreach v in ///
    has_nextbest ///
    nextbest_preferencia ///
    nextbest_codigo_carrera ///
    target_selectivity ///
    nextbest_selectivity ///
    delta_selectivity ///
    target_grad_target_8y ///
    nextbest_grad_target_8y ///
    delta_grad_target_8y ///
    target_field ///
    nextbest_field ///
    same_field_nextbest ///
    delta_group ///
    group_delta_selectivity {

    capture drop `v'
}

merge m:1 mrun ao_proceso preferencia t_codigo_carrera ///
    using `nextbest_short', ///
    keep(master match) nogen

replace has_nextbest = 0 if missing(has_nextbest)

label define has_nextbest_lbl ///
    0 "No next-best feasible alternative" ///
    1 "Has next-best feasible alternative", replace

label values has_nextbest has_nextbest_lbl


/**********************************************************************
* 5. Crear target_field y nextbest_field
**********************************************************************/

gen str40 target_field = field

gen codigo_carrera = nextbest_codigo_carrera

merge m:1 ao_proceso codigo_carrera using `field_lookup', ///
    keep(master match) nogen

rename lookup_field nextbest_field

drop codigo_carrera

gen byte same_field_nextbest = .

replace same_field_nextbest = 1 if ///
    has_nextbest == 1 ///
    & !missing(target_field) ///
    & !missing(nextbest_field) ///
    & target_field == nextbest_field

replace same_field_nextbest = 0 if ///
    has_nextbest == 1 ///
    & !missing(target_field) ///
    & !missing(nextbest_field) ///
    & target_field != nextbest_field

label define samefield_lbl ///
    0 "Different field" ///
    1 "Same field", replace

label values same_field_nextbest samefield_lbl


/************************************************************
* 5.1 Diagnóstico de field recovery
************************************************************/

di as text "=================================================="
di as result "Diagnóstico same_field_nextbest dentro de BW"
di as text "=================================================="

tab has_nextbest if abs(score_rd) <= `bw', missing

tab same_field_nextbest if abs(score_rd) <= `bw', missing

tab same_field_nextbest has_nextbest if abs(score_rd) <= `bw', missing

gen str30 missing_samefield_reason = ""

replace missing_samefield_reason = "No next-best" ///
    if has_nextbest == 0

replace missing_samefield_reason = "Missing target field" ///
    if has_nextbest == 1 ///
    & missing(target_field)

replace missing_samefield_reason = "Missing next-best field" ///
    if has_nextbest == 1 ///
    & missing(nextbest_field)

replace missing_samefield_reason = "Other" ///
    if missing_samefield_reason == "" ///
    & missing(same_field_nextbest)

tab missing_samefield_reason if abs(score_rd) <= `bw', missing


/**********************************************************************
* 6. Definición manual de delta_group
*
* IMPORTANTE:
* Este bloque debe ser idéntico en 14, 15, 18 y 20.
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

gen byte group_delta_selectivity = delta_group
label values group_delta_selectivity delta_group_lbl


/************************************************************
* 6.1 Diagnóstico delta groups x same-field
************************************************************/

di as text "=================================================="
di as result "Delta groups x same-field dentro de BW"
di as text "=================================================="

tab same_field_nextbest delta_group if abs(score_rd) <= `bw', missing row


/**********************************************************************
* 7. Figuras cutoff tipo RD plot con histograma
**********************************************************************/

global bw_global `bw'
global binw_global `binw'

capture program drop make_rd_hist_cutoff

program define make_rd_hist_cutoff

    syntax varname, SAMEFIELD(integer) TITLE(string) GNAME(name)

    preserve

        keep if abs(score_rd) <= $bw_global
        keep if same_field_nextbest == `samefield'
        keep if !missing(`varlist', score_rd, above_cutoff, program_year_id)

        quietly count
        local N = r(N)

        quietly levelsof program_year_id, local(clustlist)
        local K : word count `clustlist'

        quietly summarize above_cutoff, meanonly
        local min_above = r(min)
        local max_above = r(max)

        if `N' == 0 | `K' <= 1 | `min_above' == `max_above' {
            restore
            exit
        }

        quietly reghdfe `varlist' ///
            above_cutoff ///
            c.score_rd ///
            1.above_cutoff#c.score_rd, ///
            absorb(program_year_id) ///
            vce(cluster program_year_id)

        local beta = _b[above_cutoff]
        local se   = _se[above_cutoff]

        local beta_fmt : display %5.3f `beta'
        local se_fmt   : display %5.3f `se'

        gen double bin = floor(score_rd / $binw_global) * $binw_global + $binw_global / 2

        collapse ///
            (mean) ymean = `varlist' ///
            (count) n = `varlist', ///
            by(bin)

        gen byte left = bin < 0
        gen byte right = bin >= 0

        /************************************************************
        * Escalas fijas para outcome en eje derecho
        ************************************************************/

        local ymin = 0
        local ymax = 1
        local ystep = 0.1

        if "`varlist'" == "enrolls_target" {
            local ymin = 0
            local ymax = 0.8
            local ystep = 0.1
        }

        if inlist("`varlist'", "enrolls_uni", "enrolls_he") {
            local ymin = 0
            local ymax = 1
            local ystep = 0.1
        }

        if "`varlist'" == "graduates_target_8y" {
            local ymin = 0
            local ymax = 0.35
            local ystep = 0.05
        }

        if inlist("`varlist'", "graduates_uni_8y", "graduates_he_8y") {
            local ymin = 0
            local ymax = 0.55
            local ystep = 0.05
        }

        twoway ///
            (bar n bin, ///
                yaxis(1) ///
                barwidth($binw_global) ///
                fcolor(eltblue%25) ///
                lcolor(eltblue%10)) ///
            (scatter ymean bin if left == 1, ///
                yaxis(2) ///
                msymbol(circle) ///
                msize(small) ///
                mcolor(black)) ///
            (scatter ymean bin if right == 1, ///
                yaxis(2) ///
                msymbol(circle) ///
                msize(small) ///
                mcolor(black)) ///
            (lfit ymean bin [aw=n] if left == 1, ///
                yaxis(2) ///
                lwidth(medthin) ///
                lcolor(black)) ///
            (lfit ymean bin [aw=n] if right == 1, ///
                yaxis(2) ///
                lwidth(medthin) ///
                lcolor(black)), ///
            xline(0, lpattern(dash) lcolor(gs8)) ///
            xlabel(-25(10)25, labsize(vsmall)) ///
            xtitle("Distance to admission cutoff", size(vsmall)) ///
            ytitle("Observations", axis(1) size(vsmall)) ///
            ytitle("Mean outcome", axis(2) size(vsmall)) ///
            ylabel(, axis(1) labsize(vsmall)) ///
            ylabel(`ymin'(`ystep')`ymax', axis(2) labsize(vsmall)) ///
            yscale(axis(2) range(`ymin' `ymax')) ///
            title("`title'", size(small)) ///
            subtitle("RDD = `beta_fmt' (`se_fmt'); N=`N'; clusters=`K'", size(vsmall)) ///
            legend(off) ///
            graphregion(color(white)) ///
            plotregion(color(white)) ///
            name(`gname', replace)

    restore

end


/************************************************************
* 7.1 Crear cutoff PDFs: same field y different field
************************************************************/

foreach s in 0 1 {

    if `s' == 1 {
        local sname "Same field"
        local suffix "same_field"
        local ss "sf"
    }

    if `s' == 0 {
        local sname "Different field"
        local suffix "different_field"
        local ss "df"
    }

    local graphnames ""

    make_rd_hist_cutoff enrolls_target, ///
        samefield(`s') ///
        title("Enroll target") ///
        gname(g_`ss'_et)

    capture graph describe g_`ss'_et
    if _rc == 0 local graphnames "`graphnames' g_`ss'_et"

    make_rd_hist_cutoff enrolls_uni, ///
        samefield(`s') ///
        title("Enroll university") ///
        gname(g_`ss'_eu)

    capture graph describe g_`ss'_eu
    if _rc == 0 local graphnames "`graphnames' g_`ss'_eu"

    make_rd_hist_cutoff enrolls_he, ///
        samefield(`s') ///
        title("Enroll HE") ///
        gname(g_`ss'_eh)

    capture graph describe g_`ss'_eh
    if _rc == 0 local graphnames "`graphnames' g_`ss'_eh"

    make_rd_hist_cutoff graduates_target_8y, ///
        samefield(`s') ///
        title("Graduate target 8y") ///
        gname(g_`ss'_gt)

    capture graph describe g_`ss'_gt
    if _rc == 0 local graphnames "`graphnames' g_`ss'_gt"

    make_rd_hist_cutoff graduates_uni_8y, ///
        samefield(`s') ///
        title("Graduate university 8y") ///
        gname(g_`ss'_gu)

    capture graph describe g_`ss'_gu
    if _rc == 0 local graphnames "`graphnames' g_`ss'_gu"

    make_rd_hist_cutoff graduates_he_8y, ///
        samefield(`s') ///
        title("Graduate HE 8y") ///
        gname(g_`ss'_gh)

    capture graph describe g_`ss'_gh
    if _rc == 0 local graphnames "`graphnames' g_`ss'_gh"

    graph combine `graphnames', ///
        cols(3) ///
        imargin(tiny) ///
        title("RDD around cutoff: `sname'", size(medsmall)) ///
        subtitle("Binned means, local linear fits, and running-variable histogram. BW = ±`bw'.", ///
            size(vsmall)) ///
        graphregion(color(white))

    graph export "$output/figures/same_field_nextbest/rdd_cutoff_`suffix'_8y.pdf", replace
}


/**********************************************************************
* 8. RDD por delta_group y same_field_nextbest
**********************************************************************/

local outcomes ///
    enrolls_target ///
    enrolls_uni ///
    enrolls_he ///
    graduates_target_8y ///
    graduates_uni_8y ///
    graduates_he_8y

tempfile rdd_delta_results

tempname handle

postfile `handle' ///
    str40 outcome ///
    byte same_field_nextbest ///
    byte delta_group ///
    double beta se ci_low ci_high N clusters ///
    using `rdd_delta_results', replace

foreach y of local outcomes {

    foreach s in 0 1 {

        forvalues g = 1/5 {

            quietly count if abs(score_rd) <= `bw' ///
                & same_field_nextbest == `s' ///
                & delta_group == `g' ///
                & !missing(`y', above_cutoff, score_rd, program_year_id)

            local N = r(N)

            quietly levelsof program_year_id if abs(score_rd) <= `bw' ///
                & same_field_nextbest == `s' ///
                & delta_group == `g' ///
                & !missing(`y', above_cutoff, score_rd, program_year_id), ///
                local(clustlist)

            local K : word count `clustlist'

            quietly summarize above_cutoff if abs(score_rd) <= `bw' ///
                & same_field_nextbest == `s' ///
                & delta_group == `g' ///
                & !missing(`y', above_cutoff, score_rd, program_year_id), meanonly

            local min_above = r(min)
            local max_above = r(max)

            if `N' > 0 & `K' > 1 & `min_above' != `max_above' {

                di as text "=================================================="
                di as result "RDD | outcome=`y' | same_field=`s' | delta_group=`g'"
                di as result "N=`N', clusters=`K'"
                di as text "=================================================="

                capture noisily reghdfe `y' ///
                    above_cutoff ///
                    c.score_rd ///
                    1.above_cutoff#c.score_rd ///
                    if abs(score_rd) <= `bw' ///
                    & same_field_nextbest == `s' ///
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
                        (`s') ///
                        (`g') ///
                        (`b') (`se') (`lo') (`hi') (`N') (`K')
                }
            }
        }
    }
}

postclose `handle'


/**********************************************************************
* 9. Figuras por delta_group: same vs different field
**********************************************************************/

use `rdd_delta_results', clear

capture confirm variable beta
if _rc != 0 {
    di as error "No se generaron resultados RDD."
    exit 111
}

gen beta_label = string(beta, "%5.3f")

capture program drop make_delta_samefield_bar

program define make_delta_samefield_bar

    syntax, OUTCOME(string) SAMEFIELD(integer) OUTNAME(name)

    preserve

        keep if outcome == "`outcome'" ///
            & same_field_nextbest == `samefield'

        quietly count
        if r(N) == 0 {
            restore
            exit
        }

        sort delta_group

        local title ""

        if "`outcome'" == "enrolls_target" {
            local title "Enroll target"
        }

        if "`outcome'" == "enrolls_uni" {
            local title "Enroll university"
        }

        if "`outcome'" == "enrolls_he" {
            local title "Enroll HE"
        }

        if "`outcome'" == "graduates_target_8y" {
            local title "Graduate target 8y"
        }

        if "`outcome'" == "graduates_uni_8y" {
            local title "Graduate university 8y"
        }

        if "`outcome'" == "graduates_he_8y" {
            local title "Graduate HE 8y"
        }

        /************************************************************
        * Escalas fijas por outcome
        ************************************************************/

        local ymin = 0
        local ymax = 0.7
        local ystep = 0.1

        if "`outcome'" == "enrolls_target" {
            local ymin = 0.45
            local ymax = 0.70
            local ystep = 0.05
        }

        if inlist("`outcome'", "enrolls_uni", "enrolls_he") {
            local ymin = -0.02
            local ymax = 0.10
            local ystep = 0.02
        }

        if "`outcome'" == "graduates_target_8y" {
            local ymin = 0.10
            local ymax = 0.32
            local ystep = 0.04
        }

        if inlist("`outcome'", "graduates_uni_8y", "graduates_he_8y") {
            local ymin = -0.04
            local ymax = 0.12
            local ystep = 0.04
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
            ylabel(`ymin'(`ystep')`ymax', labsize(vsmall)) ///
            xlabel(1 "d1" ///
                   2 "d2" ///
                   3 "d3" ///
                   4 "d4" ///
                   5 "d5", ///
                   labsize(vsmall)) ///
            xscale(range(0.5 5.5)) ///
            xtitle("") ///
            ytitle("") ///
            title("`title'", size(small)) ///
            legend(off) ///
            graphregion(color(white)) ///
            plotregion(color(white)) ///
            name(`outname', replace)

    restore

end


foreach s in 0 1 {

    local graphnames ""

    if `s' == 1 {
        local sname "Same field"
        local suffix "same_field"
        local ss "sf"
    }

    if `s' == 0 {
        local sname "Different field"
        local suffix "different_field"
        local ss "df"
    }

    foreach y in enrolls_target enrolls_uni enrolls_he ///
                 graduates_target_8y graduates_uni_8y graduates_he_8y {

        local shorty ""

        if "`y'" == "enrolls_target" local shorty "et"
        if "`y'" == "enrolls_uni"    local shorty "eu"
        if "`y'" == "enrolls_he"     local shorty "eh"

        if "`y'" == "graduates_target_8y" local shorty "gt"
        if "`y'" == "graduates_uni_8y"    local shorty "gu"
        if "`y'" == "graduates_he_8y"     local shorty "gh"

        local gname = "d_`ss'_`shorty'"

        make_delta_samefield_bar, ///
            outcome("`y'") ///
            samefield(`s') ///
            outname(`gname')

        capture graph describe `gname'
        if _rc == 0 {
            local graphnames "`graphnames' `gname'"
        }
    }

    graph combine `graphnames', ///
        cols(3) ///
        imargin(tiny) ///
        title("RDD by delta group: `sname'", size(medsmall)) ///
        subtitle("d1 < -10; d2 [-10,10); d3 [10,30); d4 [30,50); d5 >= 50. BW = ±`bw'.", ///
            size(vsmall)) ///
        graphregion(color(white))

    graph export "$output/figures/same_field_nextbest/rdd_delta_`suffix'_8y.pdf", replace
}


/**********************************************************************
* 10. Resultados finales en log
**********************************************************************/

use `rdd_delta_results', clear

sort outcome same_field_nextbest delta_group

di as text "=================================================="
di as result "Resultados RDD same-field / different-field por delta group"
di as text "=================================================="

list outcome same_field_nextbest delta_group beta se ci_low ci_high N clusters, ///
    sepby(outcome same_field_nextbest) abbreviate(24)

di as text "=================================================="
di as result "20 terminado correctamente."
di as result "Figuras guardadas en:"
di as result "$output/figures/same_field_nextbest/"
di as text "Archivos esperados:"
di as result "  rdd_cutoff_same_field_8y.pdf"
di as result "  rdd_cutoff_different_field_8y.pdf"
di as result "  rdd_delta_same_field_8y.pdf"
di as result "  rdd_delta_different_field_8y.pdf"
di as text "=================================================="