/**********************************************************************
* 40c_design5_leadlag_uniyear.do
*
* Design V (issues #8, #10): is the positive T-1 graduation coefficient
* of the distributed lag (40, panel B2) a university-wide shock, such as
* a revenue effect (2026-11-10 meeting)? Same distributed lag, replacing
* the year FE with university x year FE (or field x year FE), which
* absorb anything common to the university (field) in a year: revenue,
* spending, staff.
*
*   y_i = sum_{k=-3..3} g_k Z_p,t+k + x_i'd + phi_p + [phi_t |
*         phi_u(p)t | phi_f(p)t] + phi_ROL(i) + e_i
*
*   unit : as 37/40 (most preferred inframarginal application in the
*          student's first inframarginal year), cohorts <= last 8y cohort
*   Z    : TOTAL_CUPOS from the Oferta Academica 2007-2019, per ten
*          seats (same series as 40)
*   y    : graduation from the enrolled program within 8 years (x100);
*          entrants of the program-year (N_total_enter); and two
*          composition outcomes without controls: PSU language+math and
*          predicted graduation (fitted value of graduation on PSU, NEM,
*          female, private-paid, municipal), x100
*   x    : PSU, NEM, female, private-paid, municipal, with missing
*          indicators (graduation and entrants only)
*   FE   : program + ROL top1u, and (1) year (= 40, B2 main),
*          (2) university x year, (3) field x year
*   SE   : clustered by program-year
*
* Outputs (output/inframarginal/tables/):
*   im_d5_leadlag_uniyear.tex   t-1 (and t) coefficients, three FE
*   im_d5_leadlag_uniyear.csv   every coefficient, k = -3..3
*
* Inputs: $processed/design5_individual_2007_2016.dta (02_build/16)
*         $demre_raw/Postulacion/OfertaAcadémica_AdmisiónYYYY.xlsx
*         $processed/check_06b_titulados_all.dta
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out"
cap mkdir "$im_out/tables"

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args b se name
    local z = abs(`b' / `se')
    c_local `name' = cond(`z' > 2.576, "\sym{***}", cond(`z' > 1.96, "\sym{**}", cond(`z' > 1.645, "\sym{*}", "")))
end

/**********************************************************************
* 1. Seats t-3..t+3 (as 40, section 2)
**********************************************************************/

capture program drop harmonize_code
program define harmonize_code
    args in out
    tempvar s
    gen `s' = strtrim(string(`in', "%12.0f"))
    gen long `out' = `in'
    replace `out' = real(substr(`s', 1, length(`s')-2) + "0" + ///
        substr(`s', length(`s')-1, 2)) if length(`s') == 4
end

tempfile zx
forvalues y = 2007/2019 {
    import excel using "$demre_raw/Postulacion/OfertaAcadémica_Admisión`y'.xlsx", ///
        firstrow clear allstring
    rename *, upper
    capture rename CODIGO_CARRERA CODIGO
    keep CODIGO TOTAL_CUPOS
    destring CODIGO TOTAL_CUPOS, replace force
    drop if missing(CODIGO)
    gen int ao_proceso = `y'
    if `y' > 2007 append using `zx'
    save `zx', replace
}
harmonize_code CODIGO codigo_carrera_harmonized
collapse (max) zx = TOTAL_CUPOS, by(codigo_carrera_harmonized ao_proceso)
replace zx = . if zx <= 0
xtset codigo_carrera_harmonized ao_proceso
foreach k in 1 2 3 {
    gen double Zm`k' = L`k'.zx / 10
    gen double Zp`k' = F`k'.zx / 10
}
keep codigo_carrera_harmonized ao_proceso Zm? Zp?
tempfile zll
save `zll'

/**********************************************************************
* 2. Sample (as 37/40)
**********************************************************************/

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
merge m:1 codigo_carrera_harmonized ao_proceso using `zll', keep(master match) nogen
egen long pt         = group(program_id_rank_analysis ao_proceso)
egen long programs   = group(program_id_rank_analysis)
egen long uni_year   = group(sigla_universidad ao_proceso)
egen long field_year = group(field ao_proceso)
gen double y_program = 100 * graduates_enrolled_program_8y
gen double Z10 = Z_total_cupos / 10

* composition index: graduation predicted by predetermined traits
quietly reg y_program psu_lm nem female priv mun
predict double yhat if e(sample)

local ctrl ""
foreach v in psu_lm nem female priv mun {
    gen double c_`v' = cond(missing(`v'), 0, `v')
    gen byte   m_`v' = missing(`v')
    local ctrl "`ctrl' c_`v' m_`v'"
}

/**********************************************************************
* 3. Distributed lag under three sets of time FE
**********************************************************************/

local terms "Zm3 Zm2 Zm1 Z10 Zp1 Zp2 Zp3"
local fe1 "programs ao_proceso rol_top1u"
local fe2 "programs uni_year rol_top1u"
local fe3 "programs field_year rol_top1u"

tempname P
tempfile res
postfile `P' str16 dv byte fe int k double(b se p) long N using `res', replace
foreach dv in y_program N_total_enter psu_lm yhat {
    local cc = cond(inlist("`dv'", "psu_lm", "yhat"), "", "`ctrl'")
    foreach f in 1 2 3 {
        quietly reghdfe `dv' `terms' `cc', absorb(`fe`f'') vce(cluster pt)
        local df = e(df_r)
        local N = e(N)
        * sample means for the table (column 1 sample = all columns)
        if `f' == 1 {
            tempvar es
            gen byte `es' = e(sample)
            quietly summarize `dv' if `es'
            local mean_`dv' = r(mean)
            if "`dv'" == "y_program" {
                quietly summarize Z_total_cupos if `es'
                local mean_seats = r(mean)
            }
            drop `es'
        }
        di as result _n "`dv' fe`f', N = " `N'
        local k = -3
        foreach v of local terms {
            local p = 2 * ttail(`df', abs(_b[`v'] / _se[`v']))
            post `P' ("`dv'") (`f') (`k') (_b[`v']) (_se[`v']) (`p') (`N')
            di as text "  k=" %2.0f `k' ": " %8.3f _b[`v'] " (" %6.3f _se[`v'] ")  p=" %5.3f `p'
            local ++k
        }
    }
}
postclose `P'

use `res', clear
export delimited using "$im_out/tables/im_d5_leadlag_uniyear.csv", replace

/**********************************************************************
* 4. Table: t-1 (and t) coefficients
**********************************************************************/

local r1 "y_program -1 Graduation (pp): seats in \(t-1\)"
local r2 "y_program 0 Graduation (pp): seats in \(t\)"
local r3 "N_total_enter -1 Entrants in \(t\): seats in \(t-1\)"
local r4 "psu_lm -1 PSU of the cohort: seats in \(t-1\)"
local r5 "yhat -1 Predicted graduation (pp): seats in \(t-1\)"

file open T using "$im_out/tables/im_d5_leadlag_uniyear.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & Mean & (1) Year FE & (2) University \(\times\) year FE & (3) Field \(\times\) year FE \\" _n
file write T " & & (as in the deck) & & \\" _n "\midrule" _n
forvalues r = 1/5 {
    gettoken dv lab : r`r'
    gettoken kk lab : lab
    if `r' == 3 file write T "\addlinespace" _n
    file write T "`lab'"
    if "`dv'" == "N_total_en" file write T " & " %5.1f (`mean_N_total_enter')
    else file write T " & " %5.1f (`mean_`dv'')
    foreach f in 1 2 3 {
        quietly summarize b if dv == "`dv'" & k == `kk' & fe == `f'
        local b = r(mean)
        quietly summarize se if dv == "`dv'" & k == `kk' & fe == `f'
        stars `b' `r(mean)' st
        file write T " & " %6.2f (`b') "`st'"
    }
    file write T " \\" _n " &"
    foreach f in 1 2 3 {
        quietly summarize se if dv == "`dv'" & k == `kk' & fe == `f'
        file write T " & (" %4.2f (r(mean)) ")"
    }
    file write T " \\" _n
}
quietly summarize N if dv == "y_program" & fe == 1
file write T "\midrule" _n "Students & \multicolumn{4}{c}{" %9.0fc (r(mean)) "} \\" _n
file write T "Seats of the program (mean) & \multicolumn{4}{c}{" %5.1f (`mean_seats') "} \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "40c_design5_leadlag_uniyear.do finished."
