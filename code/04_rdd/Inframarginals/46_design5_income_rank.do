/**********************************************************************
* 46_design5_income_rank.do
*
* Issue #13: Design V (37_design5_main.do) with the income rank of the
* program of graduation as the outcome.
*
*   n_pt = a Z_pt + x_i'a2 + FE + nu
*   Y_i  = b n_pt + x_i'b2 + FE + e   (2SLS)
*
*   Y : ir    income rank (1-100) of the program of i's first title
*             within 8 years, any program and institution; 0 if no title
*             (Step 0, ProgramVA/01b)
*       ga    any title within 8 years (pp), same title definition
*       irg   income rank among graduates (selected; descriptive)
*       prog  graduation from the enrolled program, 8y (pp), reference:
*             reproduces the deck
*   Columns: (1) program + year; (2) + controls; (3) + ROL top1u (main);
*            (4) program + university x year + ROL top1u, controls
*   Sample, controls, clustering (program-year) as in 37.
*
* Outputs (output/inframarginal/tables/):
*   im_d5_incrank.tex, im_d5_incrank.csv
*
* Inputs: $processed/design5_individual_2007_2016.dta (02_build/16)
*         $processed/pva_students_2007_2016.dta (ProgramVA/01b)
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out/tables"

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
isid mrun

merge 1:1 mrun ao_proceso using "$processed/pva_students_2007_2016.dta", ///
    keepusing(inc_rank grad_any_8y) keep(master match)
tab _merge
drop _merge

egen long pt       = group(program_id_rank_analysis ao_proceso)
egen long programs = group(program_id_rank_analysis)
egen long uni_year = group(sigla_universidad ao_proceso)

gen double y_ir   = inc_rank
gen double y_ga   = 100 * grad_any_8y
gen double y_irg  = inc_rank if grad_any_8y == 1
gen double y_prog = 100 * graduates_enrolled_program_8y

local ctrl ""
foreach v in psu_lm nem female priv mun {
    gen byte m_`v' = missing(`v')
    replace `v' = 0 if missing(`v')
    local ctrl "`ctrl' `v' m_`v'"
}

local fe1 "programs ao_proceso"
local ct1 ""
local fe2 "programs ao_proceso"
local ct2 "`ctrl'"
local fe3 "programs ao_proceso rol_top1u"
local ct3 "`ctrl'"
local fe4 "programs uni_year rol_top1u"
local ct4 "`ctrl'"

capture postclose R
postfile R str4 y byte col double fs fsse F rf rfse rfp iv ivse ivp N ym ///
    using "`c(tmpdir)'/d5_ir.dta", replace

foreach y in ir ga irg prog {
    forvalues c = 1/4 {
        quietly reghdfe N_total_enter Z_total_cupos `ct`c'' if !missing(y_`y'), ///
            absorb(`fe`c'') vce(cluster pt)
        local fs = _b[Z_total_cupos]
        local fsse = _se[Z_total_cupos]
        quietly reghdfe y_`y' Z_total_cupos `ct`c'', absorb(`fe`c'') vce(cluster pt)
        local rf = _b[Z_total_cupos]
        local rfse = _se[Z_total_cupos]
        local rfp = 2 * ttail(e(df_r), abs(`rf' / `rfse'))
        quietly ivreghdfe y_`y' (N_total_enter = Z_total_cupos) `ct`c'', ///
            absorb(`fe`c'') cluster(pt)
        local iv = _b[N_total_enter]
        local ivse = _se[N_total_enter]
        local ivp = 2 * normal(-abs(`iv' / `ivse'))
        local F = e(widstat)
        local N = e(N)
        tempvar s
        gen byte `s' = e(sample)
        quietly summarize y_`y' if `s'
        local ym = r(mean)
        drop `s'
        post R ("`y'") (`c') (`fs') (`fsse') (`F') (`rf') (`rfse') (`rfp') ///
            (`iv') (`ivse') (`ivp') (`N') (`ym')
        foreach k in fs fsse F rf rfse rfp iv ivse ivp N ym {
            local `y'`c'_`k' = ``k''
        }
        di as text "`y' col `c': FS " as result %6.3f `fs' ///
            as text "  RF " as result %8.4f `rf' " (" %7.4f `rfse' ")" ///
            as text "  2SLS " as result %8.4f `iv' " (" %7.4f `ivse' ")" ///
            as text "  F " as result %7.1f `F' as text "  N " as result %9.0fc `N' ///
            as text "  mean " as result %6.2f `ym'
    }
}
postclose R

/**********************************************************************
* Table: 2SLS per 10 entrants
**********************************************************************/

local lab_ir   "Income rank of program of graduation (0 if no title)"
local lab_ga   "Any title, 8y (pp)"
local lab_irg  "Income rank among graduates"
local lab_prog "Graduation from the enrolled program, 8y (pp)"

file open T using "$im_out/tables/im_d5_incrank.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & (1) & (2) & (3) & (4) \\" _n
file write T "Controls & No & Yes & Yes & Yes \\" _n
file write T "ROL FE (top 1 + univ.) & No & No & Yes & Yes \\" _n
file write T "Year FE & Yes & Yes & Yes & -- \\" _n
file write T "University \(\times\) year FE & No & No & No & Yes \\" _n "\midrule" _n
file write T "First stage: \(n_{pt}\) on \(Z_{pt}\)"
forvalues c = 1/4 {
    file write T " & " %6.3f (`ir`c'_fs')
}
file write T " \\" _n
forvalues c = 1/4 {
    file write T " & (" %5.3f (`ir`c'_fsse') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
forvalues c = 1/4 {
    file write T " & " %6.0f (`ir`c'_F')
}
file write T " \\" _n "\addlinespace" _n
file write T "\multicolumn{5}{l}{2SLS, per 10 entrants} \\" _n
foreach y in ir ga irg prog {
    file write T "\quad `lab_`y''"
    forvalues c = 1/4 {
        stars ``y'`c'_ivp' s
        file write T " & " %7.3f (10 * ``y'`c'_iv') "`s'"
    }
    file write T " \\" _n
    forvalues c = 1/4 {
        file write T " & (" %6.3f (10 * ``y'`c'_ivse') ")"
    }
    file write T " \\" _n "\quad \quad Mean"
    forvalues c = 1/4 {
        file write T " & " %6.1f (``y'`c'_ym')
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Students (income rank)"
forvalues c = 1/4 {
    file write T " & " %9.0fc (`ir`c'_N')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

use "`c(tmpdir)'/d5_ir.dta", clear
export delimited using "$im_out/tables/im_d5_incrank.csv", replace
list y col fs F rf rfse iv ivse N ym, sepby(y) noobs abbreviate(8)
di as result "46_design5_income_rank.do finished."
