/**********************************************************************
* 37b_design5_logs.do
*
* Design V (issue #8) in logs: same as 37_design5_main.do with the
* endogenous variable and the instrument in logs. Y_i is binary and
* stays in levels.
*
*   ln n_pt = a ln Z_pt + x_i'a2 + psi_p + psi_t + psi_ROL(i) + nu
*   Y_i     = b ln n_pt + x_i'b2 + phi_p + phi_t + phi_ROL(i) + e   (2SLS)
*
*   b/10 = change in the probability of graduating per 10% more entrants
*   Columns as in im_d5_main.tex: program+year, + controls,
*   + top1u ROL (main), + exact ROL. SE clustered by program-year.
*
* Output: output/inframarginal/tables/im_d5_logs.tex
* Input : $processed/design5_individual_2007_2016.dta (02_build/16)
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
* 0. Sample (identical to 37_design5_main.do)
**********************************************************************/

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
isid mrun

egen long pt       = group(program_id_rank_analysis ao_proceso)
egen long programs = group(program_id_rank_analysis)

foreach v in program uni he {
    local src = cond("`v'" == "program", "graduates_enrolled_program_8y", "graduates_`v'_8y")
    gen double y_`v' = `src'
}

local ctrl ""
foreach v in psu_lm nem female priv mun {
    gen byte m_`v' = missing(`v')
    replace `v' = 0 if missing(`v')
    local ctrl "`ctrl' `v' m_`v'"
}

count if N_total_enter <= 0 | Z_total_cupos <= 0
gen double ln_n = ln(N_total_enter)
gen double ln_z = ln(Z_total_cupos)

local fe1 "programs ao_proceso"
local ct1 ""
local fe2 "programs ao_proceso"
local ct2 "`ctrl'"
local fe3 "programs ao_proceso rol_top1u"
local ct3 "`ctrl'"
local fe4 "programs ao_proceso rol_exact"
local ct4 "`ctrl'"

/**********************************************************************
* 1. Estimation
**********************************************************************/

forvalues c = 1/4 {
    quietly reghdfe ln_n ln_z `ct`c'', absorb(`fe`c'') vce(cluster pt)
    local fs`c'   = _b[ln_z]
    local fsse`c' = _se[ln_z]
    local fsp`c'  = 2 * ttail(e(df_r), abs(_b[ln_z] / _se[ln_z]))
    foreach y in program uni he {
        quietly reghdfe y_`y' ln_z `ct`c'', absorb(`fe`c'') vce(cluster pt)
        local rf`c'`y'   = _b[ln_z]
        local rfse`c'`y' = _se[ln_z]
        local rfp`c'`y'  = 2 * ttail(e(df_r), abs(_b[ln_z] / _se[ln_z]))
        quietly ivreghdfe y_`y' (ln_n = ln_z) `ct`c'', absorb(`fe`c'') cluster(pt)
        local iv`c'`y'   = _b[ln_n]
        local ivse`c'`y' = _se[ln_n]
        local ivp`c'`y'  = 2 * normal(-abs(_b[ln_n] / _se[ln_n]))
        if "`y'" == "program" {
            local F`c' = e(widstat)
            local N`c' = e(N)
            tempvar s
            gen byte `s' = e(sample)
            quietly distinct pt if `s'
            local npt`c' = r(ndistinct)
            drop `s'
        }
        di as result "col `c' `y': FS=" %6.3f `fs`c'' " RF=" %7.3f `rf`c'`y'' ///
            " 2SLS=" %7.3f `iv`c'`y'' " (" %6.3f `ivse`c'`y'' ") F=" %7.1f `F`c''
    }
}

/**********************************************************************
* 2. Table
**********************************************************************/

file open T using "$im_out/tables/im_d5_logs.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & (1) & (2) & (3) & (4) \\" _n
file write T "ROL FE & -- & -- & Top 1 + univ. & Exact \\" _n
file write T "Controls & No & Yes & Yes & Yes \\" _n "\midrule" _n
file write T "First stage: \(\ln n_{pt}\) on \(\ln Z_{pt}\)"
forvalues c = 1/4 {
    stars `fsp`c'' s
    file write T " & " %6.3f (`fs`c'') "`s'"
}
file write T " \\" _n
forvalues c = 1/4 {
    file write T " & (" %5.3f (`fsse`c'') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
forvalues c = 1/4 {
    file write T " & " %6.0f (`F`c'')
}
file write T " \\" _n "\addlinespace" _n
file write T "\multicolumn{5}{l}{2SLS (change in probability per log point of \(n_{pt}\))} \\" _n
foreach y in program uni he {
    local yl = cond("`y'" == "program", "Graduation, enrolled program, 8y", cond("`y'" == "uni", "Graduation, any university, 8y", "Graduation, any higher education, 8y"))
    file write T "\quad `yl'"
    forvalues c = 1/4 {
        stars `ivp`c'`y'' s
        file write T " & " %7.4f (`iv`c'`y'') "`s'"
    }
    file write T " \\" _n
    forvalues c = 1/4 {
        file write T " & (" %7.4f (`ivse`c'`y'') ")"
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Students"
forvalues c = 1/4 {
    file write T " & " %9.0fc (`N`c'')
}
file write T " \\" _n "Program-years (clusters)"
forvalues c = 1/4 {
    file write T " & " %6.0fc (`npt`c'')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "37b_design5_logs.do finished."
