/**********************************************************************
* 38_design5_balance.do
*
* Design V (issue #8): does Z predict who the inframarginal students are?
* Vacancies are published in DEMRE's Oferta Academica before students
* apply, so the "students do not know Z when they apply" timing argument
* cannot be assumed. Test it instead:
*
*   (a) balance: x_i = g Z_pt + FE + u, for each predetermined x
*       (PSU L+M, NEM, female, private-paid, municipal, ROL length)
*   (b) placebo: N_pt and Y_i on Z_pt and next year's Z_p,t+1
*
*   FE: program + year (col 1); program + year + ROL top1u (col 2, main)
*   SE clustered by program-year. Same sample as 37.
*
* Output: output/inframarginal/tables/im_d5_balance.tex
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

* next year's vacancies, from the Design I panel
use program_id_rank_analysis ao_proceso Z_total_cupos using ///
    "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_first_enroll.dta", clear
xtset program_id_rank_analysis ao_proceso
gen double F1Z = F.Z_total_cupos
keep program_id_rank_analysis ao_proceso F1Z
tempfile lead
save `lead'

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
merge m:1 program_id_rank_analysis ao_proceso using `lead', keep(master match) nogen
egen long pt       = group(program_id_rank_analysis ao_proceso)
egen long programs = group(program_id_rank_analysis)
gen double y_program = 100 * graduates_enrolled_program_8y

local fe1 "programs ao_proceso"
local fe2 "programs ao_proceso rol_top1u"

* (a) balance; Z scaled per 10 vacancies so coefficients are readable
gen double Z10 = Z_total_cupos / 10
local xs "psu_lm nem female priv mun n_apps"
foreach x of local xs {
    quietly summarize `x'
    local m_`x' = r(mean)
    foreach k in 1 2 {
        quietly reghdfe `x' Z10, absorb(`fe`k'') vce(cluster pt)
        local b_`x'_`k'  = _b[Z10]
        local se_`x'_`k' = _se[Z10]
        local p_`x'_`k'  = 2 * ttail(e(df_r), abs(_b[Z10] / _se[Z10]))
        local N_`x'_`k'  = e(N)
        di as result "`x' fe`k': " %8.4f `b_`x'_`k'' " (" %7.4f `se_`x'_`k'' ")  p=" %5.3f `p_`x'_`k''
    }
}

* joint test: predicted graduation from x on Z
quietly reg y_program psu_lm nem female priv mun n_apps
predict double yhat if e(sample)
foreach k in 1 2 {
    quietly reghdfe yhat Z10, absorb(`fe`k'') vce(cluster pt)
    local b_yhat_`k'  = _b[Z10]
    local se_yhat_`k' = _se[Z10]
    local p_yhat_`k'  = 2 * ttail(e(df_r), abs(_b[Z10] / _se[Z10]))
    di as result "yhat fe`k': " %8.4f `b_yhat_`k'' " (" %7.4f `se_yhat_`k'' ")  p=" %5.3f `p_yhat_`k''
}
quietly summarize yhat
local m_yhat = r(mean)

* (b) lead of Z, on cohorts with Z_{t+1} observed
foreach k in 1 2 {
    foreach dv in N_total_enter y_program {
        quietly reghdfe `dv' Z10 F1Z, absorb(`fe`k'') vce(cluster pt)
        local L_`dv'_`k'_b   = _b[F1Z] * 10
        local L_`dv'_`k'_se  = _se[F1Z] * 10
        local L_`dv'_`k'_p   = 2 * ttail(e(df_r), abs(_b[F1Z] / _se[F1Z]))
        local C_`dv'_`k'_b   = _b[Z10]
        local C_`dv'_`k'_se  = _se[Z10]
        local C_`dv'_`k'_p   = 2 * ttail(e(df_r), abs(_b[Z10] / _se[Z10]))
        local L_`dv'_`k'_N   = e(N)
        di as result "`dv' fe`k': Z_t " %8.4f `C_`dv'_`k'_b' " (" %7.4f `C_`dv'_`k'_se' ///
            ")   Z_t+1 " %8.4f `L_`dv'_`k'_b' " (" %7.4f `L_`dv'_`k'_se' ")  N=" e(N)
    }
}

* table
local lab_psu_lm "PSU language+math"
local lab_nem    "NEM"
local lab_female "Female"
local lab_priv   "Private-paid school"
local lab_mun    "Municipal school"
local lab_n_apps "Applications in the ROL"
local lab_yhat   "Predicted graduation (\(\times 100\))"

file open T using "$im_out/tables/im_d5_balance.tex", write replace
file write T "\begin{tabular}{lccc}" _n "\toprule" _n
file write T " & Mean & (1) & (2) \\" _n
file write T "ROL FE & & -- & Top 1 + univ. \\" _n "\midrule" _n
file write T "\multicolumn{4}{l}{\textit{Panel A. Balance: covariate on \(Z_{pt}\) (per 10 vacancies)}} \\" _n
foreach x in `xs' yhat {
    file write T "`lab_`x''" " & " %6.2f (`m_`x'')
    foreach k in 1 2 {
        stars `p_`x'_`k'' s
        file write T " & " %7.3f (`b_`x'_`k'') "`s'"
    }
    file write T " \\" _n " &"
    foreach k in 1 2 {
        file write T " & (" %6.3f (`se_`x'_`k'') ")"
    }
    file write T " \\" _n
}
file write T "\addlinespace" _n
file write T "\multicolumn{4}{l}{\textit{Panel B. Placebo: next year's vacancies \(Z_{p,t+1}\) (per 10)}} \\" _n
foreach dv in N_total_enter y_program {
    local dl = cond("`dv'" == "N_total_enter", "First stage, \(n_{pt}\)", "Graduation from the program (\(\times 100\))")
    file write T "`dl' & "
    foreach k in 1 2 {
        stars `L_`dv'_`k'_p' s
        file write T " & " %7.3f (`L_`dv'_`k'_b') "`s'"
    }
    file write T " \\" _n " &"
    foreach k in 1 2 {
        file write T " & (" %6.3f (`L_`dv'_`k'_se') ")"
    }
    file write T " \\" _n
}
file write T "Students (Panel B) & "
foreach k in 1 2 {
    file write T " & " %9.0fc (`L_y_program_`k'_N')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "38_design5_balance.do finished."
