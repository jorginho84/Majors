/**********************************************************************
* 22_rdd_by_field_tables.do
*
* RDD by field of study: the four deck tables as .tex fragments, so the
* slides \input them instead of hardcoding numbers. Nothing is
* re-estimated; the RD estimates come from 03 (enrollment) and 07
* (graduation within 8 years).
*
*   RD   : y = b 1[score_rd >= 0] + score_rd + interaction + program-year
*          FE, SE clustered by program-year, |score_rd| <= $bandwidth
*          (as 03 and 07)
*   Baseline: mean of the outcome just below the cutoff, applicants with
*          -$bandwidth <= score_rd < 0 in the field (the outcome level
*          the RD jump is added to)
*
* Inputs:  output/tables/rdd_enrollment_by_field.dta (03)
*          output/tables/rdd_graduation_by_field.dta (07)
*          $processed/analysis_sample_with_fields_final.dta
*          $processed/analysis_sample_with_fields_graduation_8y.dta
* Outputs: output/tables/rdd_field_enroll_target.tex   target, univ., HE, N
*          output/tables/rdd_field_enroll_unihe.tex    univ. and HE, with baseline
*          output/tables/rdd_field_grad_target.tex     target graduation
*          output/tables/rdd_field_grad_unihe.tex      univ. and HE graduation, with baseline
**********************************************************************/

clear all
set more off
do "code/config.do"

global tab "$output/tables"

* baselines below the cutoff, by field
foreach s in enroll grad {
    if "`s'" == "enroll" {
        use field score_rd enrolls_uni enrolls_he using ///
            "$processed/analysis_sample_with_fields_final.dta", clear
        local ys "enrolls_uni enrolls_he"
    }
    else {
        use field score_rd graduates_uni_8y graduates_he_8y using ///
            "$processed/analysis_sample_with_fields_graduation_8y.dta", clear
        local ys "graduates_uni_8y graduates_he_8y"
    }
    keep if score_rd >= -$bandwidth & score_rd < 0
    drop if inlist(field, "", "Missing")
    collapse (mean) `ys', by(field)
    tempfile base_`s'
    save `base_`s''
}

capture program drop fieldtex
program define fieldtex
    * f: field label with & escaped
    args f
    c_local fl = subinstr("`f'", "&", "\&", .)
end

/**********************************************************************
* Enrollment
**********************************************************************/

use "$tab/rdd_enrollment_by_field.dta", clear
keep field outcome beta se N
replace outcome = subinstr(outcome, "enrolls_", "", .)
reshape wide beta se N, i(field) j(outcome) string
merge 1:1 field using `base_enroll', keep(1 3) nogen
replace field = "Arts and Architecture" if field == "Arts & Architecture"
sort field

file open T using "$tab/rdd_field_enroll_target.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T "Field & Target & University & HE & N \\" _n "\midrule" _n
forvalues i = 1/`=_N' {
    fieldtex "`=subinstr(field[`i'], " and ", " & ", .)'"
    file write T "`fl' & " %5.3f (betatarget[`i']) " & " %5.3f (betauni[`i']) ///
        " & " %5.3f (betahe[`i']) " & " %9.0fc (Ntarget[`i']) " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

file open T using "$tab/rdd_field_enroll_unihe.tex", write replace
file write T "\begin{tabular}{llcccc}" _n "\toprule" _n
file write T "Field & Outcome & Estimate & SE & N & Baseline \\" _n "\midrule" _n
forvalues i = 1/`=_N' {
    fieldtex "`=subinstr(field[`i'], " and ", " & ", .)'"
    if `i' > 1 file write T "\midrule" _n
    file write T "`fl' & University & " %5.3f (betauni[`i']) " & " %5.3f (seuni[`i']) ///
        " & " %9.0fc (Nuni[`i']) " & " %5.3f (enrolls_uni[`i']) " \\" _n
    file write T " & HE & " %5.3f (betahe[`i']) " & " %5.3f (sehe[`i']) ///
        " & " %9.0fc (Nhe[`i']) " & " %5.3f (enrolls_he[`i']) " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

/**********************************************************************
* Graduation within 8 years
**********************************************************************/

use "$tab/rdd_graduation_by_field.dta", clear
keep field outcome beta se N
replace outcome = subinstr(subinstr(outcome, "graduates_", "", .), "_8y", "", .)
reshape wide beta se N, i(field) j(outcome) string
merge 1:1 field using `base_grad', keep(1 3) nogen
sort field

file open T using "$tab/rdd_field_grad_target.tex", write replace
file write T "\begin{tabular}{lcc}" _n "\toprule" _n "Field & Estimate & SE \\" _n "\midrule" _n
forvalues i = 1/`=_N' {
    fieldtex "`=subinstr(field[`i'], " and ", " & ", .)'"
    file write T "`fl' & " %5.3f (betatarget[`i']) " & " %5.3f (setarget[`i']) " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

file open T using "$tab/rdd_field_grad_unihe.tex", write replace
file write T "\begin{tabular}{llcccc}" _n "\toprule" _n
file write T "Field & Outcome & Estimate & SE & N & Baseline \\" _n "\midrule" _n
forvalues i = 1/`=_N' {
    fieldtex "`=subinstr(field[`i'], " and ", " & ", .)'"
    if `i' > 1 file write T "\midrule" _n
    file write T "`fl' & University & " %6.3f (betauni[`i']) " & " %5.3f (seuni[`i']) ///
        " & " %9.0fc (Nuni[`i']) " & " %5.3f (graduates_uni_8y[`i']) " \\" _n
    file write T " & HE & " %6.3f (betahe[`i']) " & " %5.3f (sehe[`i']) ///
        " & " %9.0fc (Nhe[`i']) " & " %5.3f (graduates_he_8y[`i']) " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "22_rdd_by_field_tables.do finished."
