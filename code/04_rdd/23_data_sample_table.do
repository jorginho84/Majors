/**********************************************************************
* 23_data_sample_table.do
*
* "Data and sample" table of the deck as a .tex fragment, so the slide
* \inputs it instead of hardcoding numbers.
*
*   Full sample : applications with a running variable (02_build/02,
*                 applications_rd.dta): applications, unique students,
*                 program-years
*   BW25        : RD sample, |score_rd| <= $bandwidth (analysis_sample,
*                 02_build/03, as 04_rdd/01): running variable, above
*                 cutoff, enrollment outcomes
*   Grad. sample: same bandwidth on the graduation file (02_build/06,
*                 analysis_sample_with_fields_graduation_8y, as 04_rdd/05):
*                 graduation within 8 years
*
* Inputs:  $processed/applications_rd.dta, analysis_sample.dta,
*          analysis_sample_with_fields_final.dta (02_build/05),
*          analysis_sample_with_fields_graduation_8y.dta,
*          pva_program_names.dta (ProgramVA/01c, names with accents)
* Outputs: output/tables/data_sample_overview.tex
*          output/tables/data_nonharmonized_fields.tex (appendix: RD
*          observations without a harmonized field)
**********************************************************************/

clear all
set more off
do "code/config.do"

* full sample
use "$processed/applications_rd.dta", clear
local Napp = _N
quietly distinct mrun
local Nstu = r(ndistinct)
capture confirm variable codigo_carrera
local pv = cond(_rc == 0, "codigo_carrera", "t_codigo_carrera")
quietly distinct ao_proceso `pv', joint
local Npy = r(ndistinct)
di as result "Full sample: `Napp' applications, `Nstu' students, `Npy' program-years (`pv')"

* BW25
use score_rd above_cutoff enrolls_target enrolls_uni enrolls_he ///
    using "$processed/analysis_sample.dta", clear
keep if abs(score_rd) <= $bandwidth
local Nbw = _N
foreach v in score_rd above_cutoff enrolls_target enrolls_uni enrolls_he {
    quietly summarize `v'
    local m_`v' = r(mean)
}

* graduation sample
use score_rd graduates_target_8y graduates_uni_8y graduates_he_8y ///
    using "$processed/analysis_sample_with_fields_graduation_8y.dta", clear
keep if abs(score_rd) <= $bandwidth
local Ngr = _N
foreach v in graduates_target_8y graduates_uni_8y graduates_he_8y {
    quietly summarize `v'
    local m_`v' = r(mean)
}

local l_score_rd       "Running variable"
local l_above_cutoff   "Above cutoff"
local l_enrolls_target "Enrolls target"
local l_enrolls_uni    "Enrolls university"
local l_enrolls_he     "Enrolls HE"
local l_graduates_target_8y "Graduates target (8y)"
local l_graduates_uni_8y    "Graduates university (8y)"
local l_graduates_he_8y     "Graduates HE (8y)"

file open T using "$output/tables/data_sample_overview.tex", write replace
file write T "\begin{tabular}{lccc}" _n "\toprule" _n "Statistic & Sample & N & Mean \\" _n "\midrule" _n
file write T "Applications & Full sample & " %9.0fc (`Napp') " & -- \\" _n
file write T "Unique students & Full sample & " %9.0fc (`Nstu') " & -- \\" _n
file write T "Program-years & Full sample & " %9.0fc (`Npy') " & -- \\" _n "\midrule" _n
foreach v in score_rd above_cutoff enrolls_target enrolls_uni enrolls_he {
    file write T "`l_`v'' & BW$bandwidth & " %9.0fc (`Nbw') " & " %6.3f (`m_`v'') " \\" _n
}
file write T "\midrule" _n
foreach v in graduates_target_8y graduates_uni_8y graduates_he_8y {
    file write T "`l_`v'' & Grad. sample & " %9.0fc (`Ngr') " & " %6.3f (`m_`v'') " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

/**********************************************************************
* Appendix: RD observations without a harmonized field (in the BW25
* sample, not in the field-enriched sample of 02_build/05)
**********************************************************************/

use mrun ao_proceso t_codigo_carrera using ///
    "$processed/analysis_sample_with_fields_final.dta", clear
keep if !missing(t_codigo_carrera)
duplicates drop
tempfile withfield
save `withfield'

use mrun ao_proceso t_codigo_carrera sigla_universidad nombre_carrera score_rd ///
    using "$processed/analysis_sample.dta", clear
keep if abs(score_rd) <= $bandwidth
local Nall = _N
merge m:1 mrun ao_proceso t_codigo_carrera using `withfield', keep(master) nogen
local Nnf = _N
di as result "Without field: `Nnf' of `Nall'"
gen n = 1
replace sigla_universidad = upper(strtrim(sigla_universidad))
collapse (min) y0 = ao_proceso (max) y1 = ao_proceso (sum) n, ///
    by(sigla_universidad t_codigo_carrera)
* program names with accents (ProgramVA/01c), 4-digit codes -> XX0YY
gen str6 s = strtrim(string(t_codigo_carrera, "%12.0f"))
gen long code_h = cond(length(s) == 4, real(substr(s, 1, 2) + "0" + substr(s, 3, 2)), t_codigo_carrera)
merge m:1 code_h using "$processed/pva_program_names.dta", keep(master match) keepusing(prog_name) nogen
gen nombre_carrera = substr(prog_name, 1, 1) + lower(substr(prog_name, 2, .))
gsort -n
quietly summarize y0
local Y0 = r(min)
quietly summarize y1
local Y1 = r(max)

file open T using "$output/tables/data_nonharmonized_fields.tex", write replace
file write T "\begin{tabularx}{\textwidth}{lXccc}" _n "\toprule" _n
file write T "Institution & Program & Years & Code & Obs. \\" _n "\midrule" _n
forvalues i = 1/`=_N' {
    local yr = cond(y0[`i'] == y1[`i'], string(y0[`i']), string(y0[`i']) + "--" + string(y1[`i']))
    file write T "`=strtrim(sigla_universidad[`i'])' & `=nombre_carrera[`i']' & `yr' & " ///
        %5.0f (t_codigo_carrera[`i']) " & " %6.0fc (n[`i']) " \\" _n
}
file write T "\midrule" _n "Total & & `Y0'--`Y1' & & " %6.0fc (`Nnf') " \\" _n
file write T "\bottomrule" _n "\end{tabularx}" _n
file close T
di as result "Share of BW25 sample: " %6.3f 100 * `Nnf' / `Nall' "%"

di as result "23_data_sample_table.do finished."
