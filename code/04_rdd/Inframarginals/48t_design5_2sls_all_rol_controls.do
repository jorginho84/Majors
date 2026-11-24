/**********************************************************************
* 48t_design5_2sls_all_rol_controls.do
*
* Design V (issue #10): the Design V 2SLS (37) under every ROL FE
* definition of 37, with the program-year controls and time FE of the
* results slide (specs. (b), (c)). Extends 48s (main,
* first three, set of programs) to the other ROL FE.
*
*   Y_i = b n_pt + x_i'b2 + [c_pt] + phi_p + [phi_t | phi_u(p)t +
*         phi_f(p)t] + phi_ROL(i) + e_i,   n_pt instrumented by Z_pt
*
*   ROL FE (rows): none; 1st preference; set of universities; first two
*     preferences; 1st preference + set of universities (main); first
*     three preferences; set of programs; exact ordered list; each on
*     its own non-singleton sample
*   specifications (columns):
*     (1) program + year FE (= 37, Panel A)
*     (2) + demand in t-1 and accreditation and tuition in t; missing
*         -> 0 plus indicator (results slide, spec. (b))
*     (3) (2) with university x year and field x year FE (results slide, spec. (c))
*   x    : PSU, NEM, female, private-paid, municipal, missing indicators
*   Y    : graduation within 8 years, enrolled program / any university
*          / any higher-education institution; pp per ten entrants
*   SE   : clustered by program-year; KP F
*
*   Estimated here: columns 2-3 for none, 1st preference, set of
*   universities, first two preferences and exact list. Read: column 1
*   from 37 (im_d5_results.csv); columns 2-3 for main, first three and
*   set of programs from 48s (im_d5_fs_rf_2sls_rol_controls.csv).
*
* Outputs (output/inframarginal/tables/):
*   im_d5_2sls_all_rol_controls.tex / .csv
*
* Inputs: as 48s; im_d5_results.csv (37); im_d5_fs_rf_2sls_rol_controls.csv
*         (48s)
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
* 1. Sample (as 37 and 48s)
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
* 2. Estimation: columns 2-3, ROL FE not in 48s
**********************************************************************/

tempname P
tempfile res
postfile `P' str6 rol byte spec str8 outcome ///
    double(fs fsse fsp rf rfse rfp iv ivse ivp F ym) long(N npt) using `res', replace
foreach r in none top1 univ top2 exact {
    forvalues s = 2/3 {
        local fe "`fe`s''"
        if "`r'" != "none" local fe "`fe' rol_`r'"
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
            di as result "`r' s`s' `y': FS " %6.3f `fs' "  2SLS " %8.5f `iv' ///
                " (" %7.5f `ivse' ")  F=" %6.1f `F' "  N=" `N'
        }
    }
}
postclose `P'

* column 1: 37, Panel A (no ROL FE = column 2 of 37, with individual controls)
import delimited using "$im_out/tables/im_d5_results.csv", clear asdouble case(preserve)
keep if panel == "A" & col >= 2
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
tempfile all
save `all'

* columns 2-3 for main, first three, set of programs: 48s (already scaled)
import delimited using "$im_out/tables/im_d5_fs_rf_2sls_rol_controls.csv", clear asdouble case(preserve)
keep if spec >= 2
keep rol spec outcome fs fsse fsp rf rfse rfp iv ivse ivp F ym N npt
gen byte src_48s = 1
append using `all'
replace src_48s = 0 if missing(src_48s)
gen byte r = 1 * (rol == "none") + 2 * (rol == "top1") + 3 * (rol == "univ") + ///
    4 * (rol == "top2") + 5 * (rol == "top1u") + 6 * (rol == "top3") + ///
    7 * (rol == "set") + 8 * (rol == "exact")
assert r > 0
isid outcome r spec
sort outcome r spec
list outcome rol spec fs F iv ivse N src_48s, sepby(outcome rol) noobs
export delimited using "$im_out/tables/im_d5_2sls_all_rol_controls.csv", replace

/**********************************************************************
* 3. Table
**********************************************************************/

local l1 "None"
local l2 "1st preference"
local l3 "Set of universities"
local l4 "First two preferences"
local l5 "1st pref. + set of univ. (main)"
local l6 "First three preferences"
local l7 "Set of programs"
local l8 "Exact ordered list"

file open T using "$im_out/tables/im_d5_2sls_all_rol_controls.tex", write replace
file write T "\begin{tabular}{l*{4}{c}}" _n "\toprule" _n
file write T "ROL FE & (1) & (2) & (3) & Students \\" _n
file write T "Demand \(t-1\), accred., tuition & -- & Yes & Yes & (col. 1) \\" _n
file write T "Time FE & Year & Year & U\(\times\)y, F\(\times\)y & \\" _n
foreach o in program uni he fs {
    if "`o'" == "program" local pl "Panel A. 2SLS, graduation within 8 years, enrolled program (pp per ten entrants)"
    if "`o'" == "uni"     local pl "Panel B. 2SLS, graduation within 8 years, any university (pp per ten entrants)"
    if "`o'" == "he"      local pl "Panel C. 2SLS, graduation within 8 years, any higher education (pp per ten entrants)"
    if "`o'" == "fs"      local pl "Panel D. First stage, entrants per seat [Kleibergen--Paap F]"
    local oo = cond("`o'" == "fs", "program", "`o'")
    local b  = cond("`o'" == "fs", "fs", "iv")
    file write T "\midrule" _n "\multicolumn{5}{l}{\textit{`pl'}} \\" _n
    forvalues r = 1/8 {
        file write T "`l`r''"
        forvalues s = 1/3 {
            quietly summarize `b' if outcome == "`oo'" & r == `r' & spec == `s'
            local v = r(mean)
            quietly summarize `b'p if outcome == "`oo'" & r == `r' & spec == `s'
            stars `r(mean)' st
            file write T " & " %6.3f (`v') "`st'"
        }
        quietly summarize N if outcome == "`oo'" & r == `r' & spec == 1
        file write T " & " %9.0fc (r(mean)) " \\" _n
        forvalues s = 1/3 {
            quietly summarize `b'se if outcome == "`oo'" & r == `r' & spec == `s'
            local v = r(mean)
            if "`o'" == "fs" {
                quietly summarize F if outcome == "`oo'" & r == `r' & spec == `s'
                file write T " & (" %5.3f (`v') ") [" %4.0f (r(mean)) "]"
            }
            else file write T " & (" %5.3f (`v') ")"
        }
        file write T " & \\" _n
    }
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "48t_design5_2sls_all_rol_controls.do finished."
