/**********************************************************************
* 40b_design5_balance_psu.do
*
* Design V (issue #10): balance of the instrument controlling for PSU,
* agreed at the 2026-11-10 meeting. Hypothesis: once PSU is held fixed,
* the remaining variation in Z_pt is unrelated to the other
* characteristics of inframarginal students.
*
*   x_i = g Z_pt + h(PSU_i) + program FE + year FE + ROL FE + u_i
*   h(PSU): (a) none (= 40, panel A-B), (b) linear PSU language+math
*           with a missing indicator, (c) PSU deciles within admission
*           year as FE (missing = own category)
*   x     : school type (private-paid, municipal, private-subsidized;
*           0-100; the rest, 2%, is delegated administration, which works
*           like a municipal school and is not shown), PSU (only without h),
*           NEM, BEA (0-100), female (0-100), ROL length; joint tests:
*           predicted graduation from all covariates, and from all but
*           PSU (the index that is meaningful when PSU is controlled)
*   ROL FE: top 1 + set of universities (main) and exact ordered list
*   Z     : per 10 seats; coefficients are changes per ten seats
*   SE    : clustered by program-year
*   Sample: as 37/40 (most preferred inframarginal application in the
*           student's first inframarginal year), cohorts <= last - 8
*
* Input:  $processed/design5_individual_2007_2016.dta (02_build/16)
*         $psu_raw/A_INSCRITOS_PUNTAJES_PSU_YYYY_PRIV_MRUN.csv (BEA)
* Output: output/inframarginal/tables/im_d5_balance_psu.tex
*         output/inframarginal/tables/im_d5_balance_psu.csv
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
gen byte subv  = dep == 3 if !missing(dep)

foreach x in female priv mun subv bea {
    replace `x' = 100 * `x'
}

* joint-test indices (as 40; yhat_np leaves PSU out)
quietly reg y_program psu_lm nem female priv mun subv bea n_apps
predict double yhat if e(sample)
quietly reg y_program nem female priv mun subv bea n_apps
predict double yhat_np if e(sample)

* PSU controls: linear with missing indicator; deciles within year
gen byte   psu_m = missing(psu_lm)
gen double psu_c = cond(psu_m, 0, psu_lm)
gen byte   psu_d = .
levelsof ao_proceso, local(yrs)
foreach y of local yrs {
    tempvar d
    xtile `d' = psu_lm if ao_proceso == `y', nq(10)
    replace psu_d = `d' if ao_proceso == `y'
    drop `d'
}
replace psu_d = 11 if psu_m

/**********************************************************************
* 3. Balance regressions
*    columns: 1-3 ROL top1u (none, linear, deciles); 4-6 ROL exact
**********************************************************************/

local xs "priv mun subv psu_lm nem bea female n_apps yhat yhat_np"

tempname P
postfile `P' str10 x byte col double(b se p mean) long N ///
    using "$im_out/tables/im_d5_balance_psu.dta", replace

forvalues c = 1/6 {
    local rol = cond(`c' <= 3, "rol_top1u", "rol_exact")
    local h   = mod(`c' - 1, 3) + 1
    foreach x of local xs {
        if "`x'" == "psu_lm" & `h' > 1 continue
        quietly summarize `x'
        local m_`x' = r(mean)
        if `h' == 1 quietly reghdfe `x' Z10, absorb(programs ao_proceso `rol') vce(cluster pt)
        if `h' == 2 quietly reghdfe `x' Z10 psu_c psu_m, absorb(programs ao_proceso `rol') vce(cluster pt)
        if `h' == 3 quietly reghdfe `x' Z10, absorb(programs ao_proceso `rol' psu_d) vce(cluster pt)
        local b_`x'_`c'  = _b[Z10]
        local se_`x'_`c' = _se[Z10]
        local p_`x'_`c'  = 2 * ttail(e(df_r), abs(_b[Z10] / _se[Z10]))
        local N_`x'_`c'  = e(N)
        post `P' ("`x'") (`c') (`b_`x'_`c'') (`se_`x'_`c'') (`p_`x'_`c'') (`m_`x'') (e(N))
        di as result "`x' col `c': " %8.4f `b_`x'_`c'' " (" %7.4f `se_`x'_`c'' ")  p=" %5.3f `p_`x'_`c''
    }
}
postclose `P'

* students in the sample of each ROL definition (non-singletons), as in
* 40; rows with missing values of x use slightly fewer students
foreach rol in rol_top1u rol_exact {
    quietly reghdfe Z10, absorb(programs ao_proceso `rol')
    local Ns_`rol' = e(N)
}

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

file open T using "$im_out/tables/im_d5_balance_psu.tex", write replace
file write T "\begin{tabular}{lccccccc}" _n "\toprule" _n
file write T " & & \multicolumn{3}{c}{ROL FE: Top 1 + univ.} & \multicolumn{3}{c}{ROL FE: Exact} \\" _n
file write T "\cmidrule(lr){3-5}\cmidrule(lr){6-8}" _n
file write T " & Mean & (1) & (2) & (3) & (4) & (5) & (6) \\" _n
file write T "PSU control & & -- & Linear & Deciles & -- & Linear & Deciles \\" _n "\midrule" _n
foreach x of local xs {
    if "`x'" == "priv"   file write T "\multicolumn{8}{l}{\textit{Panel A. Socioeconomic proxies}} \\" _n
    if "`x'" == "psu_lm" file write T "\addlinespace" _n "\multicolumn{8}{l}{\textit{Panel B. Achievement and other predetermined}} \\" _n
    if "`x'" == "yhat"   file write T "\addlinespace" _n "\multicolumn{8}{l}{\textit{Joint tests}} \\" _n
    file write T "`lab_`x''" " & " %6.2f (`m_`x'')
    forvalues c = 1/6 {
        if "`b_`x'_`c''" == "" {
            file write T " & "
        }
        else {
            stars `p_`x'_`c'' s
            file write T " & " %7.3f (`b_`x'_`c'') "`s'"
        }
    }
    file write T " \\" _n " &"
    forvalues c = 1/6 {
        if "`b_`x'_`c''" == "" {
            file write T " & "
        }
        else {
            file write T " & (" %6.3f (`se_`x'_`c'') ")"
        }
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Students &"
forvalues c = 1/6 {
    local rol = cond(`c' <= 3, "rol_top1u", "rol_exact")
    file write T " & " %9.0fc (`Ns_`rol'')
}
file write T " \\" _n
file write T "Program FE & & Yes & Yes & Yes & Yes & Yes & Yes \\" _n
file write T "Year FE & & Yes & Yes & Yes & Yes & Yes & Yes \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

use "$im_out/tables/im_d5_balance_psu.dta", clear
export delimited using "$im_out/tables/im_d5_balance_psu.csv", replace
erase "$im_out/tables/im_d5_balance_psu.dta"

di as result "40b_design5_balance_psu.do finished."
