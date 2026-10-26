/**********************************************************************
* 39_design5_trends.do
*
* Design V (issues #8, #10): main 2SLS with and without program-specific
* linear trends. The lead placebo in 38 shows that Z_p,t+1 predicts this
* year's graduation as much as Z_pt does, consistent with programs that
* expand also having improving graduation. Program trends absorb that.
*
*   columns: (1) ROL top1            (2) ROL top1  + program trends
*            (3) ROL exact           (4) ROL exact + program trends
*   FE     : program and year always; controls as in 37
*   trends : programs##c.ao_proceso (program FE and program slopes)
*   SE     : clustered by program-year
*
* Output: output/inframarginal/tables/im_d5_trends.tex
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

* sample: same as 37
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

local fe1 "programs ao_proceso rol_top1"
local fe2 "programs##c.ao_proceso ao_proceso rol_top1"
local fe3 "programs ao_proceso rol_exact"
local fe4 "programs##c.ao_proceso ao_proceso rol_exact"

forvalues c = 1/4 {
    quietly reghdfe N_total_enter Z_total_cupos `ctrl', absorb(`fe`c'') vce(cluster pt)
    local fs`c'   = _b[Z_total_cupos]
    local fsse`c' = _se[Z_total_cupos]
    local fsp`c'  = 2 * ttail(e(df_r), abs(_b[Z_total_cupos] / _se[Z_total_cupos]))
    foreach y in program uni he {
        quietly reghdfe y_`y' Z_total_cupos `ctrl', absorb(`fe`c'') vce(cluster pt)
        local rf`c'`y'   = _b[Z_total_cupos]
        local rfse`c'`y' = _se[Z_total_cupos]
        local rfp`c'`y'  = 2 * ttail(e(df_r), abs(_b[Z_total_cupos] / _se[Z_total_cupos]))
        quietly ivreghdfe y_`y' (N_total_enter = Z_total_cupos) `ctrl', absorb(`fe`c'') cluster(pt)
        local iv`c'`y'   = _b[N_total_enter]
        local ivse`c'`y' = _se[N_total_enter]
        local ivp`c'`y'  = 2 * normal(-abs(_b[N_total_enter] / _se[N_total_enter]))
        if "`y'" == "program" {
            local F`c' = e(widstat)
            local N`c' = e(N)
            tempvar s
            gen byte `s' = e(sample)
            quietly distinct pt if `s'
            local npt`c' = r(ndistinct)
            quietly summarize y_program if `s'
            local ym`c' = r(mean)
            drop `s'
        }
        di as result "col `c' `y': FS=" %6.3f `fs`c'' " RF=" %8.5f `rf`c'`y'' " (" %7.5f `rfse`c'`y'' ///
            ")  2SLS=" %8.5f `iv`c'`y'' " (" %7.5f `ivse`c'`y'' ")"
    }
    di as result "col `c': F=" %7.1f `F`c'' "  N=" %9.0fc `N`c''
}

* table
file open T using "$im_out/tables/im_d5_trends.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & (1) & (2) & (3) & (4) \\" _n "\midrule" _n
file write T "First stage: \(n_{pt}\) on \(Z_{pt}\)"
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
foreach y in program uni he {
    local yl = cond("`y'" == "program", "Graduation, enrolled program, 8y", cond("`y'" == "uni", "Graduation, any university, 8y", "Graduation, any higher education, 8y"))
    file write T "\multicolumn{5}{l}{`yl'} \\" _n
    foreach e in rf iv {
        local elab = cond("`e'" == "rf", "\quad Reduced form", "\quad \textbf{2SLS}")
        file write T "`elab'"
        forvalues c = 1/4 {
            stars ``e'p`c'`y'' s
            file write T " & " %8.5f (``e'`c'`y'') "`s'"
        }
        file write T " \\" _n
        forvalues c = 1/4 {
            file write T " & (" %8.5f (``e'se`c'`y'') ")"
        }
        file write T " \\" _n
    }
}
file write T "\midrule" _n "Mean of program graduation"
forvalues c = 1/4 {
    file write T " & " %5.3f (`ym`c'')
}
file write T " \\" _n "Students"
forvalues c = 1/4 {
    file write T " & " %9.0fc (`N`c'')
}
file write T " \\" _n "Program-years (clusters)"
forvalues c = 1/4 {
    file write T " & " %6.0fc (`npt`c'')
}
file write T " \\" _n "\midrule" _n
file write T "Program FE & Yes & Yes & Yes & Yes \\" _n
file write T "Year FE & Yes & Yes & Yes & Yes \\" _n
file write T "ROL FE & Top 1 & Top 1 & Exact & Exact \\" _n
file write T "Program-specific linear trends & No & Yes & No & Yes \\" _n
file write T "Controls & Yes & Yes & Yes & Yes \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "39_design5_trends.do finished."
