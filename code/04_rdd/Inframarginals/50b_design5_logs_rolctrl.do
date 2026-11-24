/**********************************************************************
* 50b_design5_logs_rolctrl.do
*
* Design V in logs (as 37b) under the three candidate main ROL FE, with
* the program-year controls and time FE of the results slide (50). Deck
* slide "Design V: results in logs" (issue #10).
*
*   ln n_pt = a ln Z_pt + x_i'a2 + [c_pt] + psi_p + [psi_t | psi_u(p)t +
*             psi_f(p)t] + psi_ROL(i) + nu
*   Y_i     = b ln n_pt + ...                                  (2SLS)
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
*   Y    : graduation within 8 years, enrolled program / any university
*          / any higher-education institution (0/1, in levels)
*   units: b/10 = change in the probability per 10% more entrants; the
*          table reports b/10 in pp (= 10 b)
*   SE   : clustered by program-year; KP F
*
* Outputs (output/inframarginal/tables/):
*   im_d5_logs_rolctrl.tex / .csv
*
* Inputs: $processed/design5_individual_2007_2016.dta (02_build/16),
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
* 1. Sample (as 37b and 48s)
**********************************************************************/

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
merge m:1 codigo_carrera_harmonized ao_proceso ///
    using "$processed/program_year_controls_2007_2016.dta", ///
    keep(master match) gen(_m_ctrl)

egen long pt         = group(program_id_rank_analysis ao_proceso)
egen long programs   = group(program_id_rank_analysis)
egen long uni_year   = group(sigla_universidad ao_proceso)
egen long field_year = group(field ao_proceso)
foreach v in program uni he {
    local src = cond("`v'" == "program", "graduates_enrolled_program_8y", "graduates_`v'_8y")
    gen double y_`v' = `src'
}
gen double ln_n = ln(N_total_enter)
gen double ln_z = ln(Z_total_cupos)
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
postfile `P' str6 rol byte spec str8 outcome ///
    double(fs fsse fsp iv ivse ivp F ym) long(N npt) using `res', replace
foreach r in top1u top3 set {
    forvalues s = 1/3 {
        local fe "`fe`s'' rol_`r'"
        quietly reghdfe ln_n ln_z `ct`s'', absorb(`fe') vce(cluster pt)
        local fs   = _b[ln_z]
        local fsse = _se[ln_z]
        local fsp  = 2 * ttail(e(df_r), abs(`fs' / `fsse'))
        foreach y in program uni he {
            quietly ivreghdfe y_`y' (ln_n = ln_z) `ct`s'', absorb(`fe') cluster(pt)
            local iv   = _b[ln_n]
            local ivse = _se[ln_n]
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
            di as result "`r' s`s' `y': FS " %6.3f `fs' "  2SLS " %8.4f `iv' ///
                " (" %7.4f `ivse' ")  F=" %7.1f `F' "  N=" `N'
        }
    }
}
postclose `P'

use `res', clear
* per 10% more entrants, in pp: b/10 x 100
replace iv   = 10 * iv
replace ivse = 10 * ivse
replace ym   = 100 * ym
gen byte k = 3 * (cond(rol == "top1u", 1, cond(rol == "top3", 2, 3)) - 1) + spec
sort outcome k
export delimited using "$im_out/tables/im_d5_logs_rolctrl.csv", replace

/**********************************************************************
* 3. Table
**********************************************************************/

capture program drop cell
program define cell
    args v o k
    quietly summarize `v' if outcome == "`o'" & k == `k'
    c_local val = r(mean)
end

file open T using "$im_out/tables/im_d5_logs_rolctrl.tex", write replace
file write T "\begin{tabular}{l*{9}{c}}" _n "\toprule" _n
file write T "ROL FE & \multicolumn{3}{c}{Top 1 + univ. (main)} & \multicolumn{3}{c}{First three pref.} & \multicolumn{3}{c}{Program set} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}\cmidrule(lr){8-10}" _n
forvalues k = 1/9 {
    file write T " & (`k')"
}
file write T " \\" _n
file write T "Program-year controls" _dup(3) " & -- & Yes & Yes" " \\" _n
file write T "Time FE" _dup(3) " & Year & Year & U, F \(\times\) yr" " \\" _n "\midrule" _n
file write T "First stage: \(\ln n_{pt}\) on \(\ln Z_{pt}\)"
forvalues k = 1/9 {
    cell fs program `k'
    local b = `val'
    cell fsp program `k'
    stars `val' st
    file write T " & " %5.3f (`b') "`st'"
}
file write T " \\" _n
forvalues k = 1/9 {
    cell fsse program `k'
    file write T " & (" %5.3f (`val') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
forvalues k = 1/9 {
    cell F program `k'
    file write T " & " %6.0fc (`val')
}
file write T " \\" _n "\addlinespace" _n
file write T "\multicolumn{10}{l}{2SLS (pp per 10\% more entrants)} \\" _n
foreach o in program uni he {
    local ol = cond("`o'" == "program", "Graduation, enrolled program, 8y", cond("`o'" == "uni", "Graduation, any university, 8y", "Graduation, any higher education, 8y"))
    file write T "\quad `ol'"
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
    file write T " \\" _n
}
file write T "\midrule" _n "Students"
forvalues k = 1/9 {
    cell N program `k'
    file write T " & " %9.0fc (`val')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "50b_design5_logs_rolctrl.do finished."
