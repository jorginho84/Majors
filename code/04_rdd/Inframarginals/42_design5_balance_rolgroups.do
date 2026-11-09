/**********************************************************************
* 42_design5_balance_rolgroups.do
*
* Design V (issues #8, #10): balance of predetermined characteristics on
* the instrument under every ROL definition of the sparsity slide (36),
* to see whether the imbalance of 40 (panels A-B) shrinks as the ROL
* fixed effect gets finer.
*
*   x_i = g Z_pt + psi_p + psi_t + psi_ROL(i) + u_i,   Z per 10 seats
*
*   x   : SES proxies (private-paid, municipal, private-subsidized
*         school; GRUPO_DEPENDENCIA 4, 1-2 and 3), PSU L+M, NEM, BEA (top
*         10% of own school), female, ROL length, and predicted
*         graduation from all of them (joint test, as in 40). Binary
*         covariates in percent, so g reads as pp per ten seats.
*   columns (ROL FE, coarse to fine, as 41):
*     (1) none   (2) top1   (3) set of universities   (4) top2
*     (5) top1 + set of universities (main)   (6) top3
*     (7) unordered set of programs   (8) exact ordered list
*   FE  : program + year in every column, plus the ROL FE
*   SE  : clustered by program-year
*   Sample: as 37/40 (most preferred inframarginal application in the
*         student's first inframarginal year); each column keeps its own
*         non-singleton sample.
*
* Inputs:  $processed/design5_individual_2007_2016.dta (02_build/16)
*          $psu_raw/A_INSCRITOS_PUNTAJES_PSU_YYYY_PRIV_MRUN.csv (BEA)
* Outputs: output/inframarginal/tables/im_d5_balance_rolgroups.tex
*          output/inframarginal/tables/im_d5_balance_rolgroups.csv
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

/**********************************************************************
* 1. BEA from Formulario A (as 40)
**********************************************************************/

tempfile ses
forvalues y = 2007/2016 {
    import delimited "$psu_raw/A_INSCRITOS_PUNTAJES_PSU_`y'_PRIV_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(windows-1252) ///
        stringcols(_all)
    rename *, lower
    keep mrun bea
    destring mrun, replace force
    gen int ao_proceso = `y'
    if `y' > 2007 append using `ses'
    save `ses', replace
}
drop if missing(mrun)
duplicates drop mrun ao_proceso, force
gen byte bea_ = strtrim(bea) == "BEA"
drop bea
rename bea_ bea
save `ses', replace

/**********************************************************************
* 2. Sample (as 37/40)
**********************************************************************/

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
merge m:1 mrun ao_proceso using `ses', keep(master match) nogen
egen long pt       = group(program_id_rank_analysis ao_proceso)
egen long programs = group(program_id_rank_analysis)
gen double y_program = 100 * graduates_enrolled_program_8y
gen double Z10 = Z_total_cupos / 10
gen byte subv = dep == 3 if !missing(dep)

local xs "psu_lm nem female priv mun subv bea n_apps"
foreach x in female priv mun subv bea {
    replace `x' = 100 * `x'
}
quietly reg y_program `xs'
predict double yhat if e(sample)
di as result "Students: " _N

/**********************************************************************
* 3. Balance under each ROL definition
**********************************************************************/

local rols "top1 univ top2 top1u top3 set exact"
local fe1 "programs ao_proceso"
local lab1 "none"
local c 1
foreach r of local rols {
    local ++c
    local fe`c' "programs ao_proceso rol_`r'"
    local lab`c' "`r'"
}
local ncol `c'

local rows "priv mun subv psu_lm nem bea female n_apps yhat"
capture postclose R
postfile R str8 x byte col str6 rol double(b se p N) ///
    using "`c(tmpdir)'/d5_balance_rolgroups.dta", replace
foreach x of local rows {
    quietly summarize `x'
    local m_`x' = r(mean)
    forvalues c = 1/`ncol' {
        quietly reghdfe `x' Z10, absorb(`fe`c'') vce(cluster pt)
        local b_`x'_`c'  = _b[Z10]
        local se_`x'_`c' = _se[Z10]
        local p_`x'_`c'  = 2 * ttail(e(df_r), abs(_b[Z10] / _se[Z10]))
        if "`x'" == "psu_lm" local N_`c' = e(N)
        post R ("`x'") (`c') ("`lab`c''") (`b_`x'_`c'') (`se_`x'_`c'') (`p_`x'_`c'') (e(N))
        di as result "`x' col `c' (`lab`c''): " %8.4f `b_`x'_`c'' " (" %7.4f `se_`x'_`c'' ")  p=" %5.3f `p_`x'_`c''
    }
}
postclose R
preserve
use "`c(tmpdir)'/d5_balance_rolgroups.dta", clear
export delimited using "$im_out/tables/im_d5_balance_rolgroups.csv", replace
restore

/**********************************************************************
* 4. Table
**********************************************************************/

local rname_none  "--"
local rname_top1  "Top 1"
local rname_univ  "Univ.\ set"
local rname_top2  "Top 2"
local rname_top1u "Top 1 + univ."
local rname_top3  "Top 3"
local rname_set   "Program set"
local rname_exact "Exact"

local lab_priv   "Private-paid school (\%)"
local lab_mun    "Municipal school (\%)"
local lab_subv   "Private-subsidized school (\%)"
local lab_psu_lm "PSU language+math (points)"
local lab_nem    "NEM (points)"
local lab_bea    "BEA, top 10\% of own school (\%)"
local lab_female "Female (\%)"
local lab_n_apps "Applications in the ROL (number)"
local lab_yhat   "Predicted graduation, program, 8y (\%)"

local nc = `ncol' + 2
file open T using "$im_out/tables/im_d5_balance_rolgroups.tex", write replace
file write T "\begin{tabular}{lc*{`ncol'}{c}}" _n "\toprule" _n " & Mean"
forvalues c = 1/`ncol' {
    file write T " & (`c')"
}
file write T " \\" _n "ROL FE & "
forvalues c = 1/`ncol' {
    file write T " & `rname_`lab`c'''"
}
file write T " \\" _n "\midrule" _n
foreach x of local rows {
    if "`x'" == "priv"   file write T "\multicolumn{`nc'}{l}{\textit{Panel A. Socioeconomic proxies}} \\" _n
    if "`x'" == "psu_lm" file write T "\addlinespace" _n "\multicolumn{`nc'}{l}{\textit{Panel B. Achievement and other predetermined}} \\" _n
    if "`x'" == "yhat"   file write T "\addlinespace" _n "\multicolumn{`nc'}{l}{\textit{Joint test: all covariates above}} \\" _n
    file write T "`lab_`x''" " & " %6.2f (`m_`x'')
    forvalues c = 1/`ncol' {
        stars `p_`x'_`c'' s
        file write T " & " %6.3f (`b_`x'_`c'') "`s'"
    }
    file write T " \\" _n " &"
    forvalues c = 1/`ncol' {
        file write T " & (" %5.3f (`se_`x'_`c'') ")"
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Students & "
forvalues c = 1/`ncol' {
    file write T " & " %9.0fc (`N_`c'')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "42_design5_balance_rolgroups.do finished."
