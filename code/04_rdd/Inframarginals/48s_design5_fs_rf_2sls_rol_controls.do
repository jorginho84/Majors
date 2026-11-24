/**********************************************************************
* 48s_design5_fs_rf_2sls_rol_controls.do
*
* Design V (issue #10): the standard Design V table (first stage,
* reduced form, 2SLS; 37) for the three ROL FE discussed as the main
* one, extended with the program-year controls and time FE of the
* results slide (specs. (b), (c)).
*
*   n_pt = a Z_pt + x_i'a2 + [c_pt] + psi_p + [psi_t | psi_u(p)t +
*          psi_f(p)t] + psi_ROL(i) + nu                    (first stage)
*   Y_i  = r Z_pt + ...                                    (reduced form)
*   Y_i  = b n_pt + ...                                    (2SLS)
*
*   ROL FE: 1st preference + set of universities (main), first three
*     preferences, set of programs; each on its own non-singleton sample
*   specifications, per ROL:
*     (a) program + year FE (= 37, read from im_d5_results.csv)
*     (b) + demand in t-1 (log applicants, log first-preference
*         applicants, log waiting list, mean score of first-preference
*         applicants) and accreditation and tuition in t (shares in
*         accredited program and institution, years of institutional
*         accreditation, log median tuition, share in day programs,
*         formal duration); missing -> 0 plus indicator (results slide, spec. (b))
*     (c) (b) with university x year and field x year FE (results slide, spec. (c))
*   unit : inframarginal student, most preferred inframarginal
*          application in the first year (as 37)
*   x    : PSU, NEM, female, private-paid, municipal, missing indicators
*   Y    : graduation within 8 years, enrolled program / any university
*          / any higher-education institution
*   units: first stage, entrants per seat; reduced form, pp per ten
*          seats; 2SLS, pp per ten entrants
*   SE   : clustered by program-year; KP F
*
* Outputs (output/inframarginal/tables/):
*   im_d5_fs_rf_2sls_rol_controls.tex / .csv
*
* Inputs: $processed/design5_individual_2007_2016.dta (02_build/16),
*         $processed/program_year_controls_2007_2016.dta (02_build/20),
*         output/inframarginal/tables/im_d5_results.csv (37)
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
* 1. Sample (as 37)
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

local fe2 "programs ao_proceso"
local fe3 "programs uni_year field_year"

/**********************************************************************
* 2. Estimation: specifications (b) and (c)
**********************************************************************/

tempname P
tempfile res
postfile `P' str6 rol byte spec str8 outcome ///
    double(fs fsse fsp rf rfse rfp iv ivse ivp F ym) long(N npt) using `res', replace
foreach r in top1u top3 set {
    forvalues s = 2/3 {
        local fe "`fe`s'' rol_`r'"
        quietly reghdfe N_total_enter Z_total_cupos `ctrl' `cpt', absorb(`fe') vce(cluster pt)
        local fs   = _b[Z_total_cupos]
        local fsse = _se[Z_total_cupos]
        local fsp  = 2 * ttail(e(df_r), abs(`fs' / `fsse'))
        foreach y in program uni he {
            quietly reghdfe y_`y' Z_total_cupos `ctrl' `cpt', absorb(`fe') vce(cluster pt)
            local rf   = _b[Z_total_cupos]
            local rfse = _se[Z_total_cupos]
            local rfp  = 2 * ttail(e(df_r), abs(`rf' / `rfse'))
            quietly ivreghdfe y_`y' (N_total_enter = Z_total_cupos) `ctrl' `cpt', ///
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
                (`rf') (`rfse') (`rfp') (`iv') (`ivse') ///
                (2 * normal(-abs(`iv' / `ivse'))) (`F') (`ym') (`N') (`npt')
            di as result "`r' s`s' `y': FS " %6.3f `fs' "  RF " %8.5f `rf' ///
                "  2SLS " %8.5f `iv' " (" %7.5f `ivse' ")  F=" %6.1f `F' "  N=" `N'
        }
    }
}
postclose `P'

* specification (a): 37, Panel A
import delimited using "$im_out/tables/im_d5_results.csv", clear asdouble case(preserve)
keep if panel == "A" & inlist(rol, "top1u", "top3", "set")
gen double fsp = 2 * normal(-abs(fs / fsse))
gen double rfp = 2 * normal(-abs(rf / rfse))
gen double ivp = 2 * normal(-abs(iv / ivse))
gen byte spec = 1
keep rol spec outcome fs fsse fsp rf rfse rfp iv ivse ivp F ym N npt
append using `res'
replace rf   = 1000 * rf
replace rfse = 1000 * rfse
replace iv   = 1000 * iv
replace ivse = 1000 * ivse
replace ym   = 100 * ym
gen byte k = 3 * (cond(rol == "top1u", 1, cond(rol == "top3", 2, 3)) - 1) + spec
sort outcome k
list outcome rol spec fs F rf rfse iv ivse N, sepby(outcome) noobs
export delimited using "$im_out/tables/im_d5_fs_rf_2sls_rol_controls.csv", replace

/**********************************************************************
* 3. Table
**********************************************************************/

capture program drop cell
program define cell
    args v o k
    quietly summarize `v' if outcome == "`o'" & k == `k'
    c_local val = r(mean)
end

file open T using "$im_out/tables/im_d5_fs_rf_2sls_rol_controls.tex", write replace
file write T "\begin{tabular}{l*{9}{c}}" _n "\toprule" _n
file write T " & \multicolumn{3}{c}{1st pref. + set of univ. (main)} & \multicolumn{3}{c}{First three preferences} & \multicolumn{3}{c}{Set of programs} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}\cmidrule(lr){8-10}" _n
forvalues k = 1/9 {
    file write T " & (`k')"
}
file write T " \\" _n
file write T "Demand \(t-1\), accred., tuition" _dup(3) " & -- & Yes & Yes" " \\" _n
file write T "Time FE" _dup(3) " & Year & Year & U\(\times\)y, F\(\times\)y" " \\" _n "\midrule" _n
file write T "First stage: entrants per seat"
forvalues k = 1/9 {
    cell fs program `k'
    local b = `val'
    cell fsp program `k'
    stars `val' st
    file write T " & " %6.3f (`b') "`st'"
}
file write T " \\" _n
forvalues k = 1/9 {
    cell fsse program `k'
    file write T " & (" %5.3f (`val') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
forvalues k = 1/9 {
    cell F program `k'
    file write T " & " %5.0f (`val')
}
file write T " \\" _n
foreach o in program uni he {
    if "`o'" == "program" local ol "Graduation within 8 years, enrolled program"
    if "`o'" == "uni"     local ol "Graduation within 8 years, any university"
    if "`o'" == "he"      local ol "Graduation within 8 years, any higher education"
    file write T "\addlinespace" _n "\multicolumn{10}{l}{\textit{`ol'}} \\" _n
    foreach s in rf iv {
        local sl = cond("`s'" == "rf", "\quad Reduced form (pp per ten seats)", "\quad \textbf{2SLS} (pp per ten entrants)")
        file write T "`sl'"
        forvalues k = 1/9 {
            cell `s' `o' `k'
            local b = `val'
            cell `s'p `o' `k'
            stars `val' st
            file write T " & " %6.3f (`b') "`st'"
        }
        file write T " \\" _n
        forvalues k = 1/9 {
            cell `s'se `o' `k'
            file write T " & (" %5.3f (`val') ")"
        }
        file write T " \\" _n
    }
    file write T "\quad Mean of outcome (\%)"
    forvalues k = 1/9 {
        cell ym `o' `k'
        file write T " & " %4.1f (`val')
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Students"
forvalues k = 1/9 {
    cell N program `k'
    file write T " & " %9.0fc (`val')
}
file write T " \\" _n "Program-years (clusters)"
forvalues k = 1/9 {
    cell npt program `k'
    file write T " & " %6.0fc (`val')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "48s_design5_fs_rf_2sls_rol_controls.do finished."
