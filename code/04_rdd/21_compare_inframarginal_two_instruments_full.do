/**********************************************************************
* 22_compare_inframarginal_two_instruments_full.do
*
* Compara dos instrumentos:
*   1. D_Z_total_cupos
*   2. D_Z_vacantes_1sem
*
* Para:
*   - 2007-2012
*   - 2013-2016
*
* Estima:
*   - First stage
*   - Reduced form
*   - 2SLS
*   - First-stage graphs
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

cap mkdir "$output/figures"

****************************************************
* 1. Append panels
****************************************************

use "$processed/inframarginal_program_year_panel_2007_2012.dta", clear
gen period = "2007-2012"
tempfile panel_pre
save `panel_pre'

use "$processed/inframarginal_program_year_panel_2013_2016.dta", clear
gen period = "2013-2016"

append using `panel_pre'

keep if !missing(D_N_enter, avg_N_enter, ao_proceso, program_id)

tempfile both
save `both', replace


****************************************************
* 2. Ensure instrument differences exist
****************************************************

use `both', clear

xtset program_id ao_proceso

capture confirm variable D_Z_total_cupos
if _rc {
    gen D_Z_total_cupos = D.Z_total_cupos
}

capture confirm variable D_Z_vacantes_1sem
if _rc {
    gen D_Z_vacantes_1sem = D.Z_vacantes_1sem
}

save `both', replace


****************************************************
* 3. Store full results
****************************************************

tempname handle
tempfile results

postfile `handle' ///
    str10 period ///
    str20 instrument ///
    str30 outcome ///
    str15 model ///
    double N clusters beta se pval Fstat ///
    using `results', replace


foreach p in "2007-2012" "2013-2016" {

    foreach z in D_Z_total_cupos D_Z_vacantes_1sem {

        if "`z'" == "D_Z_total_cupos" {
            local zname "Total cupos"
        }
        else {
            local zname "Vacantes 1sem"
        }

        ****************************************************
        * First stage
        ****************************************************

        use `both', clear
        keep if period == "`p'"
        keep if !missing(D_N_enter, `z', avg_N_enter)

        reg D_N_enter `z' i.ao_proceso [aw = avg_N_enter], ///
            vce(cluster program_id)

        local N        = e(N)
        local clusters = e(N_clust)
        local beta     = _b[`z']
        local se       = _se[`z']
        local t        = `beta' / `se'
        local pval     = 2 * ttail(e(df_r), abs(`t'))
        local Fstat    = `t'^2

        post `handle' ("`p'") ("`zname'") ("D_N_enter") ("First stage") ///
            (`N') (`clusters') (`beta') (`se') (`pval') (`Fstat')


        ****************************************************
        * Reduced form
        ****************************************************

        foreach y in ///
            D_grad_target_rate_8y ///
            D_grad_uni_rate_8y ///
            D_grad_he_rate_8y {

            use `both', clear
            keep if period == "`p'"
            keep if !missing(`y', `z', avg_N_enter)

            reg `y' `z' i.ao_proceso [aw = avg_N_enter], ///
                vce(cluster program_id)

            local N        = e(N)
            local clusters = e(N_clust)
            local beta     = _b[`z']
            local se       = _se[`z']
            local t        = `beta' / `se'
            local pval     = 2 * ttail(e(df_r), abs(`t'))

            post `handle' ("`p'") ("`zname'") ("`y'") ("Reduced form") ///
                (`N') (`clusters') (`beta') (`se') (`pval') (.)
        }


        ****************************************************
        * 2SLS
        ****************************************************

        foreach y in ///
            D_grad_target_rate_8y ///
            D_grad_uni_rate_8y ///
            D_grad_he_rate_8y {

            use `both', clear
            keep if period == "`p'"
            keep if !missing(`y', D_N_enter, `z', avg_N_enter)

            ivregress 2sls `y' i.ao_proceso ///
                (D_N_enter = `z') [aw = avg_N_enter], ///
                vce(cluster program_id)

            local N        = e(N)
            local clusters = e(N_clust)
            local beta     = _b[D_N_enter]
            local se       = _se[D_N_enter]
            local zstat    = `beta' / `se'
            local pval     = 2 * normal(-abs(`zstat'))

            post `handle' ("`p'") ("`zname'") ("`y'") ("2SLS") ///
                (`N') (`clusters') (`beta') (`se') (`pval') (.)
        }
    }
}

postclose `handle'


****************************************************
* 4. Display results
****************************************************

use `results', clear

gen beta_se = string(beta, "%9.4f") + " (" + string(se, "%9.4f") + ")"
gen p_fmt   = string(pval, "%9.3f")
gen F_fmt   = string(Fstat, "%9.2f")

di as text "=================================================="
di as result "FULL RESULTS: FIRST STAGE, REDUCED FORM, 2SLS"
di as text "=================================================="

sort period instrument model outcome
list period instrument model outcome N clusters beta_se p_fmt F_fmt, ///
    noobs abbreviate(28)

save "$processed/inframarginal_two_instruments_full_results.dta", replace


****************************************************
* 5. Residualized first-stage graphs
****************************************************

foreach p in "2007-2012" "2013-2016" {

    foreach z in D_Z_total_cupos D_Z_vacantes_1sem {

        use `both', clear
        keep if period == "`p'"
        keep if !missing(D_N_enter, `z', avg_N_enter)

        reg D_N_enter i.ao_proceso [aw = avg_N_enter]
        predict r_D_N_enter, resid

        reg `z' i.ao_proceso [aw = avg_N_enter]
        predict r_Z, resid

        reg D_N_enter `z' i.ao_proceso [aw = avg_N_enter], ///
            vce(cluster program_id)

        local beta_txt = string(_b[`z'], "%9.3f")
        local se_txt   = string(_se[`z'], "%9.3f")
        local t        = _b[`z'] / _se[`z']
        local F_txt    = string(`t'^2, "%9.2f")

        if "`z'" == "D_Z_total_cupos" {
            local title_z "Total cupos"
            local zfile "total_cupos"
        }
        else {
            local title_z "Vacantes 1st semester"
            local zfile "vacantes_1sem"
        }

        xtile bin = r_Z [aw = avg_N_enter], nq(40)

        preserve

            collapse ///
                (mean) r_D_N_enter r_Z [aw = avg_N_enter], ///
                by(bin)

            twoway ///
                (scatter r_D_N_enter r_Z, msize(small)) ///
                (lfit r_D_N_enter r_Z, lwidth(medthick)), ///
                yline(0, lpattern(dash) lcolor(gs10)) ///
                xline(0, lpattern(dash) lcolor(gs10)) ///
                xtitle("Residualized change in `title_z'") ///
                ytitle("Residualized change in inframarginal entrants") ///
                title("First stage: `p'") ///
                subtitle("Coef. = `beta_txt' (`se_txt'); robust F = `F_txt'") ///
                legend(off) ///
                graphregion(color(white)) ///
                plotregion(color(white))

            local pname = subinstr("`p'", "-", "_", .)

            graph export "$output/figures/first_stage_`zfile'_`pname'.pdf", replace
            graph save   "$output/figures/first_stage_`zfile'_`pname'.gph", replace

        restore
    }
}


****************************************************
* 6. Combine graphs
****************************************************

graph combine ///
    "$output/figures/first_stage_total_cupos_2007_2012.gph" ///
    "$output/figures/first_stage_total_cupos_2013_2016.gph", ///
    cols(2) ///
    graphregion(color(white)) ///
    title("First stage comparison: total cupos")

graph export "$output/figures/first_stage_total_cupos_comparison.pdf", replace


graph combine ///
    "$output/figures/first_stage_vacantes_1sem_2007_2012.gph" ///
    "$output/figures/first_stage_vacantes_1sem_2013_2016.gph", ///
    cols(2) ///
    graphregion(color(white)) ///
    title("First stage comparison: first-semester vacancies")

graph export "$output/figures/first_stage_vacantes_1sem_comparison.pdf", replace


****************************************************
* End
****************************************************

di as text "=================================================="
di as result "Saved:"
di as result "$processed/inframarginal_two_instruments_full_results.dta"
di as result "$output/figures/first_stage_total_cupos_comparison.pdf"
di as result "$output/figures/first_stage_vacantes_1sem_comparison.pdf"
di as text "=================================================="