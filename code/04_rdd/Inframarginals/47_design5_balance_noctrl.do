/**********************************************************************
* 47_design5_balance_noctrl.do
*
* Design V (issues #8, #10): how much of the raw correlation between
* the instrument and predetermined characteristics do the controls
* absorb? Same rows as 40b/42, ROL FE = unordered set of programs.
*
*   x_i = g Z_pt + controls + u_i,   Z per 10 seats
*
*   columns:
*     (1) no controls, full sample
*     (2) no controls, program-set sample (non-singletons of col 4)
*     (3) program + year FE, program-set sample
*     (4) program + year + ROL (program set) FE
*   (2)-(4) share one sample, so differences come from the controls,
*   not from the sample. (1) vs (2) shows the sample change alone.
*
*   x   : as 40b (binary covariates 0-100, so g is pp per ten seats);
*         joint tests: predicted graduation from all covariates and
*         from all but PSU
*   SE  : clustered by program-year
*   Sample: as 37/40 (most preferred inframarginal application in the
*         student's first inframarginal year), cohorts <= last - 8
*
* Inputs:  $processed/design5_individual_2007_2016.dta (02_build/16)
*          $psu_raw/A_INSCRITOS_PUNTAJES_PSU_YYYY_PRIV_MRUN.csv (BEA)
* Outputs: output/inframarginal/tables/im_d5_balance_noctrl.tex
*          output/inframarginal/tables/im_d5_balance_noctrl.csv
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

foreach x in female priv mun subv bea {
    replace `x' = 100 * `x'
}
quietly reg y_program psu_lm nem female priv mun subv bea n_apps
predict double yhat if e(sample)
quietly reg y_program nem female priv mun subv bea n_apps
predict double yhat_np if e(sample)

* program-set sample: non-singletons under the col-4 FE
quietly reghdfe Z10, absorb(programs ao_proceso rol_set)
gen byte s_set = e(sample)
count if s_set
di as result "Students: all " _N ", program-set sample " r(N)

/**********************************************************************
* 3. Balance regressions
**********************************************************************/

local rows "priv mun subv psu_lm nem bea female n_apps yhat yhat_np"
capture postclose R
postfile R str8 x byte col double(b se p N) ///
    using "`c(tmpdir)'/d5_balance_noctrl.dta", replace
foreach x of local rows {
    quietly summarize `x'
    local m_`x' = r(mean)
    forvalues c = 1/4 {
        if `c' == 1 quietly reg `x' Z10, vce(cluster pt)
        if `c' == 2 quietly reg `x' Z10 if s_set, vce(cluster pt)
        if `c' == 3 quietly reghdfe `x' Z10 if s_set, absorb(programs ao_proceso) vce(cluster pt)
        if `c' == 4 quietly reghdfe `x' Z10 if s_set, absorb(programs ao_proceso rol_set) vce(cluster pt)
        local b_`x'_`c'  = _b[Z10]
        local se_`x'_`c' = _se[Z10]
        local p_`x'_`c'  = 2 * ttail(e(df_r), abs(_b[Z10] / _se[Z10]))
        if "`x'" == "nem" local N_`c' = e(N)
        post R ("`x'") (`c') (`b_`x'_`c'') (`se_`x'_`c'') (`p_`x'_`c'') (e(N))
        di as result "`x' col `c': " %9.4f `b_`x'_`c'' " (" %7.4f `se_`x'_`c'' ")  p=" %5.3f `p_`x'_`c'' "  N=" e(N)
    }
}
postclose R
preserve
use "`c(tmpdir)'/d5_balance_noctrl.dta", clear
export delimited using "$im_out/tables/im_d5_balance_noctrl.csv", replace
restore

/**********************************************************************
* 4. Table
**********************************************************************/

local lab_priv    "Private-paid school (\%)"
local lab_mun     "Municipal school (\%)"
local lab_subv    "Private-subsidized school (\%)"
local lab_psu_lm  "PSU language+math (points)"
local lab_nem     "NEM (points)"
local lab_bea     "BEA, top 10\% of own school (\%)"
local lab_female  "Female (\%)"
local lab_n_apps  "Applications in the ROL (number)"
local lab_yhat    "Predicted graduation, all covariates (\%)"
local lab_yhat_np "Predicted graduation, all but PSU (\%)"

file open T using "$im_out/tables/im_d5_balance_noctrl.tex", write replace
file write T "\begin{tabular}{lccccc}" _n "\toprule" _n
file write T " & Mean & (1) & (2) & (3) & (4) \\" _n "\midrule" _n
foreach x of local rows {
    if "`x'" == "priv"   file write T "\multicolumn{6}{l}{\textit{Panel A. Socioeconomic proxies}} \\" _n
    if "`x'" == "psu_lm" file write T "\addlinespace" _n "\multicolumn{6}{l}{\textit{Panel B. Achievement and other predetermined}} \\" _n
    if "`x'" == "yhat"   file write T "\addlinespace" _n "\multicolumn{6}{l}{\textit{Joint tests}} \\" _n
    file write T "`lab_`x''" " & " %6.2f (`m_`x'')
    forvalues c = 1/4 {
        stars `p_`x'_`c'' s
        file write T " & " %7.3f (`b_`x'_`c'') "`s'"
    }
    file write T " \\" _n " &"
    forvalues c = 1/4 {
        file write T " & (" %6.3f (`se_`x'_`c'') ")"
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Students & "
forvalues c = 1/4 {
    file write T " & " %9.0fc (`N_`c'')
}
file write T " \\" _n
file write T "Sample & & All & Program set & Program set & Program set \\" _n
file write T "Program + year FE & & No & No & Yes & Yes \\" _n
file write T "ROL FE (program set) & & No & No & No & Yes \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "47_design5_balance_noctrl.do finished."
