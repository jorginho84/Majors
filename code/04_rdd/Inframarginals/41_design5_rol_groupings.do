/**********************************************************************
* 41_design5_rol_groupings.do
*
* Design V (issue #8): main 2SLS of 37 under every ROL definition of the
* sparsity slide (36). The field-based groupings agreed on 2026-10-27
* (02_build/16b: OECD fields, ISCED sub-areas, field x selectivity,
* university x field) gave the same answer and are not reported.
*
*   n_pt = a Z_pt + x_i'a2 + psi_p + psi_t + psi_ROL(i) + nu
*   Y_i  = b n_pt + x_i'b2 + phi_p + phi_t + phi_ROL(i) + e   (2SLS)
*
*   columns (ROL FE, coarse to fine by number of groups):
*     (1) none (controls only)        (2) top1, first preference
*     (3) set of universities         (4) top2, first two preferences
*     (5) top1 + set of universities (main)
*     (6) top3, first three preferences
*     (7) unordered set of programs   (8) exact ordered list
*   unit, n, Z, Y, x, SE: as in 37 (one row per inframarginal student,
*     most preferred inframarginal application in the first year;
*     x = PSU, NEM, female, private-paid, municipal with missing dummies;
*     SE clustered by program-year). Full sample: each column keeps its
*     own non-singleton sample.
*
*   Argument "trend" (run through 41b): every column adds program-
*     specific linear trends, programs##c.ao_proceso, as in 39.
*
* Inputs:  $processed/design5_individual_2007_2016.dta (02_build/16)
* Outputs: output/inframarginal/tables/im_d5_rolgroups.tex
*          output/inframarginal/tables/im_d5_rolgroups.csv
*          with "trend": im_d5_rolgroups_trends.tex / .csv
**********************************************************************/

args trend
local sfx    = cond("`trend'" == "trend", "_trends", "")
local progfe = cond("`trend'" == "trend", "programs##c.ao_proceso", "programs")

clear all
set more off
do "code/config.do"
di as result "41: trend = `trend'  absorb program part = `progfe'"

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

/**********************************************************************
* 0. Sample (as 37)
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

local rols "top1 univ top2 top1u top3 set exact"
local ncol = 1 + `: word count `rols''
local fe1 "`progfe' ao_proceso"
local lab1 "none"
local c 1
foreach r of local rols {
    local ++c
    local fe`c' "`progfe' ao_proceso rol_`r'"
    local lab`c' "`r'"
}

* identifying share and number of groups
quietly count
local Nall = r(N)
foreach r of local rols {
    bysort rol_`r' programs ao_proceso: gen byte f = _n == 1
    bysort rol_`r' programs: egen int ny = total(f)
    quietly count if ny >= 2
    local idsh_`r' = 100 * r(N) / `Nall'
    drop f ny
    quietly distinct rol_`r'
    local ng_`r' = r(ndistinct)
    di as result "rol_`r': " `ng_`r'' " groups, identifying share " %5.1f `idsh_`r''
}

/**********************************************************************
* 1. Estimation
**********************************************************************/

capture program drop d5_est
program define d5_est
    args yv fe ctrl pfx
    quietly reghdfe N_total_enter Z_total_cupos `ctrl', absorb(`fe') vce(cluster pt)
    c_local `pfx'fs   = _b[Z_total_cupos]
    c_local `pfx'fsse = _se[Z_total_cupos]
    c_local `pfx'fsp  = 2 * ttail(e(df_r), abs(_b[Z_total_cupos] / _se[Z_total_cupos]))
    quietly reghdfe y_`yv' Z_total_cupos `ctrl', absorb(`fe') vce(cluster pt)
    c_local `pfx'rf   = _b[Z_total_cupos]
    c_local `pfx'rfse = _se[Z_total_cupos]
    c_local `pfx'rfp  = 2 * ttail(e(df_r), abs(_b[Z_total_cupos] / _se[Z_total_cupos]))
    quietly ivreghdfe y_`yv' (N_total_enter = Z_total_cupos) `ctrl', ///
        absorb(`fe') cluster(pt)
    c_local `pfx'iv   = _b[N_total_enter]
    c_local `pfx'ivse = _se[N_total_enter]
    c_local `pfx'ivp  = 2 * normal(-abs(_b[N_total_enter] / _se[N_total_enter]))
    c_local `pfx'F    = e(widstat)
    c_local `pfx'N    = e(N)
    tempvar s
    gen byte `s' = e(sample)
    quietly summarize y_`yv' if `s'
    c_local `pfx'ym   = r(mean)
end

capture postclose R
postfile R str8 outcome byte col str10 rol double(fs fsse F rf rfse iv ivse N ym) ///
    using "`c(tmpdir)'/d5_rolgroups`sfx'.dta", replace

foreach y in program uni he {
    forvalues c = 1/`ncol' {
        d5_est `y' "`fe`c''" "`ctrl'" C`c'`y'_
        post R ("`y'") (`c') ("`lab`c''") ///
            (`C`c'`y'_fs') (`C`c'`y'_fsse') (`C`c'`y'_F') ///
            (`C`c'`y'_rf') (`C`c'`y'_rfse') (`C`c'`y'_iv') (`C`c'`y'_ivse') ///
            (`C`c'`y'_N') (`C`c'`y'_ym')
        di as result "`y' col `c' (`lab`c''): FS=" %6.3f `C`c'`y'_fs' ///
            " 2SLS=" %8.5f `C`c'`y'_iv' " (" %7.5f `C`c'`y'_ivse' ///
            ")  F=" %6.0f `C`c'`y'_F' "  N=" %9.0fc `C`c'`y'_N'
    }
}
postclose R

preserve
use "`c(tmpdir)'/d5_rolgroups`sfx'.dta", clear
export delimited using "$im_out/tables/im_d5_rolgroups`sfx'.csv", replace
restore

/**********************************************************************
* 2. Table
**********************************************************************/

local rname_none      "--"
local rname_top1      "Top 1"
local rname_univ      "Univ.\ set"
local rname_top2      "Top 2"
local rname_top3      "Top 3"
local rname_set       "Program set"
local rname_top1u     "Top 1 + univ."
local rname_exact     "Exact"

file open T using "$im_out/tables/im_d5_rolgroups`sfx'.tex", write replace
file write T "\begin{tabular}{l*{`ncol'}{c}}" _n "\toprule" _n " "
forvalues c = 1/`ncol' {
    file write T " & (`c')"
}
file write T " \\" _n "ROL FE"
forvalues c = 1/`ncol' {
    file write T " & `rname_`lab`c'''"
}
file write T " \\" _n "\midrule" _n
file write T "First stage (entrants per seat)"
forvalues c = 1/`ncol' {
    stars `C`c'program_fsp' s
    file write T " & " %6.3f (`C`c'program_fs') "`s'"
}
file write T " \\" _n
forvalues c = 1/`ncol' {
    file write T " & (" %5.3f (`C`c'program_fsse') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
forvalues c = 1/`ncol' {
    file write T " & " %6.0f (`C`c'program_F')
}
file write T " \\" _n "\addlinespace" _n "\multicolumn{`=`ncol'+1'}{l}{2SLS: effect of one more entrant (probability; 0.001 = 0.1 pp)} \\" _n
foreach y in program uni he {
    local yl = cond("`y'" == "program", "Graduation, enrolled program, 8y", ///
        cond("`y'" == "uni", "Graduation, any university, 8y", "Graduation, any higher education, 8y"))
    file write T "\quad `yl'"
    forvalues c = 1/`ncol' {
        stars `C`c'`y'_ivp' s
        file write T " & " %8.5f (`C`c'`y'_iv') "`s'"
    }
    file write T " \\" _n
    forvalues c = 1/`ncol' {
        file write T " & (" %7.5f (`C`c'`y'_ivse') ")"
    }
    file write T " \\" _n
}
file write T "\addlinespace" _n "Mean of outcome (program, share 0--1)"
forvalues c = 1/`ncol' {
    file write T " & " %5.3f (`C`c'program_ym')
}
file write T " \\" _n "Students"
forvalues c = 1/`ncol' {
    file write T " & " %9.0fc (`C`c'program_N')
}
file write T " \\" _n "ROL groups"
forvalues c = 1/`ncol' {
    if `c' == 1 file write T " & --"
    else file write T " & " %9.0fc (`ng_`lab`c''')
}
file write T " \\" _n "ROL\(\times\)program spans \(\geq\)2 years (\% students)"
forvalues c = 1/`ncol' {
    if `c' == 1 file write T " & --"
    else file write T " & " %5.1f (`idsh_`lab`c''')
}
file write T " \\" _n "\midrule" _n
if "`trend'" == "trend" {
    file write T "\multicolumn{`=`ncol'+1'}{l}{Program and year FE, program trends and controls in every column; SE by program-year.} \\" _n
}
else {
    file write T "\multicolumn{`=`ncol'+1'}{l}{Program and year FE and controls in every column; SE clustered by program-year.} \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "41_design5_rol_groupings.do finished."
