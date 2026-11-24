/**********************************************************************
* 54_design5_income_rank_rolctrl.do
*
* Design V with the income rank of the program of graduation (as 46,
* issue #13) under the three candidate main ROL FE, with the
* program-year controls and time FE of the results slide (50). Deck
* slide "Design V: income rank of the program of graduation" (issue #10).
*
*   n_pt = a Z_pt + x_i'a2 + [c_pt] + psi_p + [psi_t | psi_u(p)t +
*          psi_f(p)t] + psi_ROL(i) + nu
*   Y_i  = b n_pt + ...                                       (2SLS)
*
*   ROL FE : 1st preference + set of universities (main), first three
*            preferences, set of programs; each on its own non-singleton
*            sample
*   specifications, per ROL:
*     (a) program + year FE
*     (b) + demand in t-1 (log applicants, log first-preference
*         applicants, log waiting list, mean score of first-preference
*         applicants) and accreditation and tuition in t (shares in
*         accredited program and institution, years of institutional
*         accreditation, log median tuition, share in day programs,
*         formal duration); missing -> 0 plus indicator
*     (c) (b) with university x year and field x year FE
*   x    : PSU, NEM, female, private-paid, municipal, missing indicators
*   Y    : ir   income rank (1-100) of the program of i's first title
*               within 8 years, any program and institution; 0 if no
*               title (Step 0, ProgramVA/01b)
*          ga   any title within 8 years (pp)
*          irg  income rank among graduates (selected; descriptive)
*          prog graduation from the enrolled program, 8y (pp), reference
*   units: first stage, entrants per seat; 2SLS per ten entrants (rank
*          points or pp)
*   SE   : clustered by program-year; KP F
*
* Outputs (output/inframarginal/tables/):
*   im_d5_incrank_rolctrl.tex / .csv
*
* Inputs: $processed/design5_individual_2007_2016.dta (02_build/16)
*         $processed/pva_students_2007_2016.dta (ProgramVA/01b)
*         $processed/program_year_controls_2007_2016.dta (02_build/20)
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

/**********************************************************************
* 1. Sample (as 46 and 50b)
**********************************************************************/

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
isid mrun

merge 1:1 mrun ao_proceso using "$processed/pva_students_2007_2016.dta", ///
    keepusing(inc_rank grad_any_8y) keep(master match)
tab _merge
drop _merge
merge m:1 codigo_carrera_harmonized ao_proceso ///
    using "$processed/program_year_controls_2007_2016.dta", ///
    keep(master match) gen(_m_ctrl)

egen long pt         = group(program_id_rank_analysis ao_proceso)
egen long programs   = group(program_id_rank_analysis)
egen long uni_year   = group(sigla_universidad ao_proceso)
egen long field_year = group(field ao_proceso)

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
local b_dem "ld_apps_l1 ld_apps1_l1 ld_wait_l1 d_score1_l1"
local b_acc "m_acred_carr m_acred_inst m_acred_inst_years m_ltuition m_diurno m_duration"
local cpt ""
foreach b in dem acc {
    foreach v of local b_`b' {
        gen byte mi_`v' = missing(`v')
        quietly summarize mi_`v'
        replace `v' = 0 if mi_`v'
        local cpt "`cpt' `v'"
        if r(max) > 0 local cpt "`cpt' mi_`v'"
    }
}

local fe1 "programs ao_proceso"
local fe2 "programs ao_proceso"
local fe3 "programs uni_year field_year"
local ct1 "`ctrl'"
local ct2 "`ctrl' `cpt'"
local ct3 "`ctrl' `cpt'"

/**********************************************************************
* 2. Estimation
**********************************************************************/

tempname P
tempfile res
postfile `P' str6 rol byte spec str4 outcome ///
    double(fs fsse fsp iv ivse ivp F ym) long(N npt) using `res', replace
foreach r in top1u top3 set {
    forvalues s = 1/3 {
        local fe "`fe`s'' rol_`r'"
        quietly reghdfe N_total_enter Z_total_cupos `ct`s'' if !missing(y_ir), ///
            absorb(`fe') vce(cluster pt)
        local fs   = _b[Z_total_cupos]
        local fsse = _se[Z_total_cupos]
        local fsp  = 2 * ttail(e(df_r), abs(`fs' / `fsse'))
        foreach y in ir ga irg prog {
            quietly ivreghdfe y_`y' (N_total_enter = Z_total_cupos) `ct`s'', ///
                absorb(`fe') cluster(pt)
            local iv   = _b[N_total_enter]
            local ivse = _se[N_total_enter]
            local F    = e(widstat)
            local N    = e(N)
            tempvar es
            gen byte `es' = e(sample)
            quietly summarize y_`y' if `es'
            local ym = r(mean)
            quietly distinct pt if `es'
            local npt = r(ndistinct)
            drop `es'
            post `P' ("`r'") (`s') ("`y'") (`fs') (`fsse') (`fsp') ///
                (`iv') (`ivse') (2 * normal(-abs(`iv' / `ivse'))) (`F') (`ym') (`N') (`npt')
            di as result "`r' s`s' `y': FS " %6.3f `fs' "  2SLS x10 " %8.4f 10*`iv' ///
                " (" %7.4f 10*`ivse' ")  F=" %7.1f `F' "  N=" `N' "  mean " %6.2f `ym'
        }
    }
}
postclose `P'

use `res', clear
* per ten entrants
replace iv   = 10 * iv
replace ivse = 10 * ivse
gen byte k = 3 * (cond(rol == "top1u", 1, cond(rol == "top3", 2, 3)) - 1) + spec
sort outcome k
export delimited using "$im_out/tables/im_d5_incrank_rolctrl.csv", replace

/**********************************************************************
* 3. Table
**********************************************************************/

capture program drop cell
program define cell
    args v o k
    quietly summarize `v' if outcome == "`o'" & k == `k'
    c_local val = r(mean)
end

local lab_ir   "Income rank (0 if no title)"
local lab_ga   "Any title, 8y (pp)"
local lab_irg  "Income rank, graduates"
local lab_prog "Program graduation, 8y (pp)"

file open T using "$im_out/tables/im_d5_incrank_rolctrl.tex", write replace
file write T "\begin{tabular}{l*{9}{c}}" _n "\toprule" _n
file write T "ROL FE & \multicolumn{3}{c}{Top 1 + univ. (main)} & \multicolumn{3}{c}{First three pref.} & \multicolumn{3}{c}{Program set} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}\cmidrule(lr){8-10}" _n
file write T _dup(3) " & (a) & (b) & (c)" " \\" _n
file write T "Program-year controls" _dup(3) " & -- & Yes & Yes" " \\" _n
file write T "Time FE" _dup(3) " & Year & Year & U, F \(\times\) yr" " \\" _n "\midrule" _n
file write T "First stage: \(n_{pt}\) on \(Z_{pt}\)"
forvalues k = 1/9 {
    cell fs ir `k'
    local b = `val'
    cell fsp ir `k'
    stars `val' st
    file write T " & " %5.3f (`b') "`st'"
}
file write T " \\" _n
forvalues k = 1/9 {
    cell fsse ir `k'
    file write T " & (" %5.3f (`val') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
forvalues k = 1/9 {
    cell F ir `k'
    file write T " & " %6.0fc (`val')
}
file write T " \\" _n "\addlinespace" _n
file write T "\multicolumn{10}{l}{2SLS, per ten entrants} \\" _n
foreach o in ir ga irg prog {
    file write T "\quad `lab_`o''"
    forvalues k = 1/9 {
        cell iv `o' `k'
        local b = `val'
        cell ivp `o' `k'
        stars `val' st
        file write T " & " %6.3f (`b') "`st'"
    }
    file write T " \\" _n
    forvalues k = 1/9 {
        cell ivse `o' `k'
        file write T " & (" %5.3f (`val') ")"
    }
    file write T " \\" _n "\quad \quad Mean"
    forvalues k = 1/9 {
        cell ym `o' `k'
        file write T " & " %5.1f (`val')
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Students (income rank)"
forvalues k = 1/9 {
    cell N ir `k'
    file write T " & " %9.0fc (`val')
}
file write T " \\" _n "Program-years"
forvalues k = 1/9 {
    cell npt ir `k'
    file write T " & " %6.0fc (`val')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

list rol spec outcome fs F iv ivse N ym, sepby(outcome) noobs abbreviate(8)
di as result "54_design5_income_rank_rolctrl.do finished."
