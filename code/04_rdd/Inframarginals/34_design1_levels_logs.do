/**********************************************************************
* 34_design1_levels_logs.do
*
* Design I re-estimated in LEVELS with program FE (issue #7). Panel A of
* the "Design I: results" table (First Cohort threshold, 8-year
* graduation of inframarginal applicants), but instead of first
* differences:
*
*   (A) levels:   N_pt = pi Z_pt + FE + v ;  y_pt = beta N^_pt + FE + e
*   (B) log-log:  lnN_pt = pi lnZ_pt + FE + v ;  y_pt = beta lnN^_pt + FE + e
*                 y stays in levels; no zeros assumed (N, Z > 0 is
*                 checked and the rows dropped are counted).
*
*   FE : (1) program + year; (2) program + university x year
*   Weights avg_N_infra_enter (as in 31), SE clustered by program.
*   RF and 2SLS reported x 100.
*
* Output: output/inframarginal/tables/im_d1_levels_logs.tex
* Input : 21b First Cohort panel, check_06b_titulados_all.dta
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out"
cap mkdir "$im_out/tables"

local P21b "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016"

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

use "`P21b'_first_enroll.dta", clear
egen long univ = group(sigla_universidad)
count if N_total_enter <= 0 | Z_total_cupos <= 0
local n_zero = r(N)
di as result "Program-years with N or Z <= 0 (dropped in logs): `n_zero'"
gen double lnN = ln(N_total_enter) if N_total_enter > 0
gen double lnZ = ln(Z_total_cupos) if Z_total_cupos > 0

* levels sample: programs in the Design I estimation sample, cohorts with observed 8y outcomes
bys program_id_rank_analysis: egen byte inprog = max(sample_iv == 1 & ao_proceso <= `last_cohort')
gen byte samp = inprog == 1 & ao_proceso <= `last_cohort' & !missing(avg_N_infra_enter, lnN, lnZ)
quietly count if samp
di as result "Levels sample: " r(N) " program-years"

local W "[aw = avg_N_infra_enter]"
local fe1 "program_id_rank_analysis ao_proceso"
local fe2 "program_id_rank_analysis univ#ao_proceso"

foreach sp in lev log {
    local nv = cond("`sp'" == "lev", "N_total_enter", "lnN")
    local zv = cond("`sp'" == "lev", "Z_total_cupos", "lnZ")
    foreach k in 1 2 {
        quietly reghdfe `nv' `zv' `W' if samp, absorb(`fe`k'') cluster(program_id_rank_analysis)
        local `sp'`k'_fs   = _b[`zv']
        local `sp'`k'_fsse = _se[`zv']
        local `sp'`k'_fsp  = 2 * ttail(e(df_r), abs(_b[`zv'] / _se[`zv']))
        local `sp'`k'_N    = e(N)
        quietly distinct program_id_rank_analysis if e(sample)
        local `sp'`k'_np   = r(ndistinct)
        foreach y in program uni he {
            local yv = cond("`y'" == "program", "grad_enrolled_program_rate_8y", "grad_`y'_rate_8y")
            quietly reghdfe `yv' `zv' `W' if samp, absorb(`fe`k'') cluster(program_id_rank_analysis)
            local `sp'`k'_rf_`y'   = _b[`zv']
            local `sp'`k'_rfse_`y' = _se[`zv']
            local `sp'`k'_rfp_`y'  = 2 * ttail(e(df_r), abs(_b[`zv'] / _se[`zv']))
            quietly ivreghdfe `yv' (`nv' = `zv') `W' if samp, absorb(`fe`k'') cluster(program_id_rank_analysis)
            local `sp'`k'_iv_`y'   = _b[`nv']
            local `sp'`k'_ivse_`y' = _se[`nv']
            local `sp'`k'_ivp_`y'  = 2 * normal(-abs(_b[`nv'] / _se[`nv']))
            if "`y'" == "program" local `sp'`k'_F = e(widstat)
        }
    }
}
quietly summarize grad_enrolled_program_rate_8y `W' if samp
local ymean = r(mean)

local cols "lev1 lev2 log1 log2"
file open T using "$im_out/tables/im_d1_levels_logs.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{Levels} & \multicolumn{2}{c}{Log--log} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write T " & (1) & (2) & (3) & (4) \\" _n "\midrule" _n
file write T "First stage: \(N\) on \(Z\) (levels), \(\ln N\) on \(\ln Z\) (logs)"
foreach c of local cols {
    stars ``c'_fsp' s
    file write T " & " %6.3f (``c'_fs') "`s'"
}
file write T " \\" _n
foreach c of local cols {
    file write T " & (" %5.3f (``c'_fsse') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
foreach c of local cols {
    file write T " & " %6.1f (``c'_F')
}
file write T " \\" _n "\addlinespace" _n
file write T "\multicolumn{5}{l}{Graduation from the program, 8y (\(\times 100\))} \\" _n
foreach e in rf iv {
    local elab = cond("`e'" == "rf", "\quad Reduced form", "\quad \textbf{2SLS}")
    file write T "`elab'"
    foreach c of local cols {
        stars ``c'_`e'p_program' s
        file write T " & " %7.3f (100 * ``c'_`e'_program') "`s'"
    }
    file write T " \\" _n
    foreach c of local cols {
        file write T " & (" %6.3f (100 * ``c'_`e'se_program') ")"
    }
    file write T " \\" _n
}
file write T "\addlinespace" _n "\multicolumn{5}{l}{Secondary outcomes, 2SLS (\(\times 100\))} \\" _n
foreach y in uni he {
    local ylab = cond("`y'" == "uni", "\quad Graduation from any university, 8y", "\quad Graduation from any HE, 8y")
    file write T "`ylab'"
    foreach c of local cols {
        stars ``c'_ivp_`y'' s
        file write T " & " %7.3f (100 * ``c'_iv_`y'') "`s'"
    }
    file write T " \\" _n
    foreach c of local cols {
        file write T " & (" %6.3f (100 * ``c'_ivse_`y'') ")"
    }
    file write T " \\" _n
}
file write T "\addlinespace" _n "Observations (program-years)"
foreach c of local cols {
    file write T " & " %6.0fc (``c'_N')
}
file write T " \\" _n "Programs"
foreach c of local cols {
    file write T " & " %6.0fc (``c'_np')
}
file write T " \\" _n "Mean program graduation, 8y (\%) & \multicolumn{4}{c}{" %5.1f (100 * `ymean') "} \\" _n
file write T "\midrule" _n "Program FE & X & X & X & X \\" _n "Year FE & X & & X & \\" _n "University \(\times\) year FE & & X & & X \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T
di as result "written"
