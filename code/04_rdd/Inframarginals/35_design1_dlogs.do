/**********************************************************************
* 35_design1_dlogs.do
*
* Design I in first differences of logs: dlnN_pt = ln N_pt - ln N_p,t-1
* instrumented by dlnZ_pt = ln Z_pt - ln Z_p,t-1. Outcome y in first
* differences of LOGS too: dln y = ln y_pt - ln y_p,t-1 (observations with y = 0
* in t or t-1 are lost; counted below). Same sample (sample_iv, cohorts with
* observed 8-year outcomes), weights avg_N_infra_enter, SE clustered by
* program, FE: (1) year; (2) year + university x year. Coefficients are elasticities (not x 100).
*
* Output: output/inframarginal/tables/im_d1_dlogs.tex
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

use "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_first_enroll.dta", clear
xtset program_id_rank_analysis ao_proceso
foreach y in grad_enrolled_program_rate_8y grad_uni_rate_8y grad_he_rate_8y {
    replace D_`y' = . if ao_proceso > `last_cohort'
}
egen long univ = group(sigla_universidad)
gen double lnN = ln(N_total_enter)
gen double lnZ = ln(Z_total_cupos)
gen double dlnN = lnN - L.lnN
gen double dlnZ = lnZ - L.lnZ
gen byte samp = sample_iv == 1 & ao_proceso <= `last_cohort' & !missing(dlnN, dlnZ)
quietly count if samp
di as result "dlog sample: " r(N)
quietly summarize dlnZ if samp
di as result "sd dlnZ = " r(sd)

foreach y in program uni he {
    local yv = cond("`y'" == "program", "grad_enrolled_program_rate_8y", "grad_`y'_rate_8y")
    gen double ln_`y' = ln(`yv') if `yv' > 0
    gen double dl_`y' = ln_`y' - L.ln_`y'
    quietly count if samp
    local n0 = r(N)
    quietly count if samp & !missing(dl_`y')
    local n1 = r(N)
    di as result "`y': dln y defined for `n1' of `n0' sample obs"
    local nlost_`y' = `n0' - `n1'
}

local W "[aw = avg_N_infra_enter]"
local fe1 "ao_proceso"
local fe2 "ao_proceso univ#ao_proceso"

foreach k in 1 2 {
    quietly reghdfe dlnN dlnZ `W' if samp, absorb(`fe`k'') cluster(program_id_rank_analysis)
    local c`k'_fs = _b[dlnZ]
    local c`k'_fsse = _se[dlnZ]
    local c`k'_fsp = 2 * ttail(e(df_r), abs(_b[dlnZ] / _se[dlnZ]))
    local c`k'_N = e(N)
    local c`k'_F = (_b[dlnZ] / _se[dlnZ])^2
    quietly distinct program_id_rank_analysis if e(sample)
    local c`k'_np = r(ndistinct)
    foreach y in program uni he {
        local yv = cond("`y'" == "program", "grad_enrolled_program_rate_8y", "grad_`y'_rate_8y")
        quietly reghdfe dl_`y' dlnZ `W' if samp, absorb(`fe`k'') cluster(program_id_rank_analysis)
        if "`y'" == "program" local c`k'_Ny = e(N)
        local c`k'_rf_`y' = _b[dlnZ]
        local c`k'_rfse_`y' = _se[dlnZ]
        local c`k'_rfp_`y' = 2 * ttail(e(df_r), abs(_b[dlnZ] / _se[dlnZ]))
        quietly ivreghdfe dl_`y' (dlnN = dlnZ) `W' if samp, absorb(`fe`k'') cluster(program_id_rank_analysis)
        local c`k'_iv_`y' = _b[dlnN]
        local c`k'_ivse_`y' = _se[dlnN]
        local c`k'_ivp_`y' = 2 * normal(-abs(_b[dlnN] / _se[dlnN]))
    }
}
quietly summarize grad_enrolled_program_rate_8y if samp `W'
local ymean = r(mean)

file open T using "$im_out/tables/im_d1_dlogs.tex", write replace
file write T "\begin{tabular}{lcc}" _n "\toprule" _n " & (1) & (2) \\" _n "\midrule" _n
file write T "First stage: \(\Delta\ln N\) on \(\Delta\ln Z\)"
foreach k in 1 2 {
    stars `c`k'_fsp' s
    file write T " & " %6.3f (`c`k'_fs') "`s'"
}
file write T " \\" _n
foreach k in 1 2 {
    file write T " & (" %5.3f (`c`k'_fsse') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
foreach k in 1 2 {
    file write T " & " %6.1f (`c`k'_F')
}
file write T " \\" _n "\addlinespace" _n "\multicolumn{3}{l}{\(\Delta\ln\) graduation from the program, 8y} \\" _n
foreach e in rf iv {
    local elab = cond("`e'" == "rf", "\quad Reduced form", "\quad \textbf{2SLS}")
    file write T "`elab'"
    foreach k in 1 2 {
        stars `c`k'_`e'p_program' s
        file write T " & " %7.3f (`c`k'_`e'_program') "`s'"
    }
    file write T " \\" _n
    foreach k in 1 2 {
        file write T " & (" %6.3f (`c`k'_`e'se_program') ")"
    }
    file write T " \\" _n
}
file write T "\addlinespace" _n "\multicolumn{3}{l}{Secondary outcomes, 2SLS, \(\Delta\ln y\)} \\" _n
foreach y in uni he {
    local ylab = cond("`y'" == "uni", "\quad Graduation from any university, 8y", "\quad Graduation from any HE, 8y")
    file write T "`ylab'"
    foreach k in 1 2 {
        stars `c`k'_ivp_`y'' s
        file write T " & " %7.3f (`c`k'_iv_`y'') "`s'"
    }
    file write T " \\" _n
    foreach k in 1 2 {
        file write T " & (" %6.3f (`c`k'_ivse_`y'') ")"
    }
    file write T " \\" _n
}
file write T "\addlinespace" _n "Observations, program outcome"
foreach k in 1 2 {
    file write T " & " %6.0fc (`c`k'_Ny')
}
file write T " \\" _n "Programs"
foreach k in 1 2 {
    file write T " & " %6.0fc (`c`k'_np')
}
file write T " \\" _n "Observations lost to \(y=0\), program outcome & \multicolumn{2}{c}{" %5.0fc (`nlost_program') "} \\" _n
file write T "\midrule" _n "Year FE & X & X \\" _n "University \(\times\) year FE & & X \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T
