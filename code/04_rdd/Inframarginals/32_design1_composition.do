/**********************************************************************
* 32_design1_composition.do
*
* Design I composition effects, pooled 2008-2016 (issue #5). Replaces
* the period-split Design I block of Own_expansion/04.
*
*   d y_pt = b d Z_pt + FE + e,  Z = total cupos in tens (b = 10 seats)
*   FE: (1) year; (2) year + university x year
*   y : mean characteristics of Formulario D entrants
*       (01_build_composition.do); first-year enrollment as reference.
*   SE clustered by program.
*
* University = first two digits of the 5-digit harmonized DEMRE code.
*
* Output: output/own_expansion/tables/oe_comp_design1.tex
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"

local cvars c_psu_mean c_psu_last c_psu_sd c_nem_mean c_female c_priv c_mun

capture program drop harmonize_code
program define harmonize_code
    syntax varname, Generate(name)
    tempvar s
    gen str12 `s' = strtrim(string(`varlist', "%12.0f"))
    gen long `generate' = `varlist'
    replace `generate' = real(substr(`s', 1, 2) + "0" + substr(`s', 3, 2)) ///
        if length(`s') == 4
end

capture program drop oe_coef
program define oe_coef
    args x prefix
    c_local `prefix'b  = _b[`x']
    c_local `prefix'se = _se[`x']
    c_local `prefix'p  = 2 * ttail(e(df_r), abs(_b[`x'] / _se[`x']))
    c_local `prefix'N  = e(N)
end

use "$processed/oe_composition_program_year.dta", clear
foreach y of local cvars {
    local lab_`y' : variable label `y'
}
local lab_N "First-year enrollment"

use t_codigo_carrera ao_proceso Z_total_cupos ///
    using "$processed/program_year_vacancies_2007_2016.dta", clear
harmonize_code t_codigo_carrera, generate(code_h)
collapse (sum) Z_total_cupos, by(code_h ao_proceso)
tempfile z
save `z'

* N as in Design I: distinct enrollees with enrolls_target == 1
use mrun ao_proceso t_codigo_carrera enrolls_target ///
    using "$processed/analysis_sample_with_fields_final.dta", clear
keep if enrolls_target == 1
harmonize_code t_codigo_carrera, generate(code_h)
bys mrun code_h ao_proceso: keep if _n == 1
gen byte one = 1
collapse (sum) N = one, by(code_h ao_proceso)

merge 1:1 code_h ao_proceso using `z', keep(match) nogen
merge 1:1 code_h ao_proceso using "$processed/oe_composition_program_year.dta", ///
    keep(master match) nogen
egen long pid = group(code_h)
gen int univ = floor(code_h / 1000)
xtset pid ao_proceso
replace Z_total_cupos = Z_total_cupos / 10
foreach v in N Z_total_cupos `cvars' {
    gen double D_`v' = D.`v'
}

local fe1 "ao_proceso"
local fe2 "ao_proceso univ#ao_proceso"
foreach k in 1 2 {
    foreach y in N `cvars' {
        quietly reghdfe D_`y' D_Z_total_cupos if inrange(ao_proceso, 2008, 2016), ///
            absorb(`fe`k'') cluster(pid)
        oe_coef D_Z_total_cupos c`k'_`y'_
    }
}

file open T using "$oe_out/tables/oe_comp_design1.tex", write replace
file write T "\begin{tabular}{lcc}" _n "\toprule" _n
file write T "Outcome (\(\Delta\)) & (1) & (2) \\" _n "\midrule" _n
foreach y in N `cvars' {
    local ylab = cond("`y'" == "N", "`lab_N'", "`lab_`y''")
    file write T "`ylab'"
    foreach k in 1 2 {
        oe_stars `c`k'_`y'_p'
        file write T " & " %7.3f (`c`k'_`y'_b') "`r(stars)'"
    }
    file write T " \\" _n
    foreach k in 1 2 {
        file write T " & (" %6.3f (`c`k'_`y'_se') ")"
    }
    file write T " \\" _n
    if "`y'" == "N" file write T "\addlinespace" _n
}
file write T "\midrule" _n "Observations (FD)"
foreach k in 1 2 {
    file write T " & " %6.0fc (`c`k'_c_psu_mean_N')
}
file write T " \\" _n "Year FE & \checkmark & \checkmark \\" _n
file write T "University \(\times\) year FE & & \checkmark \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "Design I composition table written."
