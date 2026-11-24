/**********************************************************************
* 49_finance_seats_levels.do
*
* University finances and seats in levels (2026-11-17 meeting, issue
* #10). 45 is in first differences, which constrains the coefficient on
* lagged Y to 1 (Emilio). Here: log levels with university and year FE,
* adding the seat lags one at a time.
*
*   ln Y_ut = b0 ln V_ut [+ b1 ln V_u,t-1 [+ b2 ln V_u,t-2]]
*             + (field shares)_ut' theta + phi_u + phi_t + e_ut
*
*   unit : university x fiscal year (= admission year), FY 2013-2022
*   V    : regular vacancies of the university's programs (as 45)
*   Y    : as 45 (entrants, undergraduate stock, tuition revenue,
*          expenses, capital; per undergraduate: expenses, academic
*          salaries, overhead, capital), plus enrollment at all levels
*          and the per-student rows divided by it (expenses also cover
*          graduate and postitulo students)
*   controls: share of each knowledge area in undergraduate enrollment
*          (levels, one omitted)
*   FE   : university, year
*   SE   : clustered by university
*   columns: (1) seats in t; (2) + t-1; (3) + t-2. Same sample in all
*          three (seats observed in t, t-1, t-2), so differences across
*          columns come from the lags, not the sample. Exclusions as 45:
*          tuition jump (flag_jump) in t or t-1; for capital also an
*          asset jump (flag_nc) in t or t-1.
*   Units: the .tex reports 10 x the elasticities (% change in Y when
*          seats rise by 10%); the csv keeps the elasticities.
*
* Outputs (output/inframarginal/tables/):
*   im_fin_seats_levels.tex, im_fin_seats_levels.csv
*
* Inputs: $processed/university_finance_panel.dta (02_build/17)
*         $processed/university_entrants_fields.dta (02_build/18)
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out"
cap mkdir "$im_out/tables"

capture program drop stars
program define stars
    args b se name
    local z = abs(`b' / `se')
    c_local `name' = cond(`z' > 2.576, "\sym{***}", cond(`z' > 1.96, "\sym{**}", cond(`z' > 1.645, "\sym{*}", "")))
end

/**********************************************************************
* 1. Panel (as 45, in levels)
**********************************************************************/

use "$processed/university_entrants_fields.dta", clear
merge 1:1 cod_inst fy using "$processed/university_finance_panel.dta", ///
    keep(master match) nogen
xtset cod_inst fy

gen double l_V = ln(V) if V > 0
gen double l_E = ln(E) if E > 0
gen double overhead = rem_adm + rem_dir + g_adm
local fin "aranceles ing_total gasto_total rem_total rem_acad overhead g_otrop act_nc"
foreach v in `fin' enr_total {
    gen double l_`v' = ln(`v') if `v' > 0
}
foreach v of local fin {
    gen double l_pc_`v' = ln(`v' / enr_total) if `v' > 0
    gen double l_pca_`v' = ln(`v' / enr_all) if `v' > 0
}
gen double l_enr_all = ln(enr_all) if enr_all > 0
gen double gshare = 100 * (1 - enr_total / enr_all)
summarize gshare, detail
unab shs : sh*
local nsh : word count `shs'
local ctl ""
forvalues j = 2/`nsh' {
    local ctl "`ctl' sh`j'"
}

gen byte s = E > 0 & !missing(l_V, L.l_V, L2.l_V, l_pc_gasto_total, sh2) ///
    & !flag_jump & !L.flag_jump
gen byte s_nc = s & !flag_nc & !L.flag_nc
count if s
count if s_nc
distinct cod_inst if s
tab fy if s

/**********************************************************************
* 2. Estimation
**********************************************************************/

tempname P
tempfile res
postfile `P' str20 y byte col double(b0 se0 b1 se1 b2 se2) long(N nu) using `res', replace
local ys "E enr_total enr_all aranceles ing_total gasto_total rem_total rem_acad overhead g_otrop act_nc pc_aranceles pc_ing_total pc_gasto_total pc_rem_total pc_rem_acad pc_overhead pc_g_otrop pc_act_nc pca_aranceles pca_ing_total pca_gasto_total pca_rem_total pca_rem_acad pca_overhead pca_g_otrop pca_act_nc"
local x1 "l_V"
local x2 "l_V L.l_V"
local x3 "l_V L.l_V L2.l_V"
foreach y of local ys {
    local ss = cond(strpos("`y'", "act_nc"), "s_nc", "s")
    forvalues c = 1/3 {
        quietly reghdfe l_`y' `x`c'' `ctl' if `ss', absorb(cod_inst fy) cluster(cod_inst)
        local b0 = _b[l_V]
        local s0 = _se[l_V]
        local b1 = .
        local s1 = .
        local b2 = .
        local s2 = .
        if `c' >= 2 {
            local b1 = _b[L.l_V]
            local s1 = _se[L.l_V]
        }
        if `c' == 3 {
            local b2 = _b[L2.l_V]
            local s2 = _se[L2.l_V]
        }
        post `P' ("`y'") (`c') (`b0') (`s0') (`b1') (`s1') (`b2') (`s2') (e(N)) (e(N_clust))
        di as result "`y' c`c': " %7.3f `b0' " (" %6.3f `s0' ")  N=" e(N)
    }
}
postclose `P'

use `res', clear
export delimited using "$im_out/tables/im_fin_seats_levels.csv", replace

/**********************************************************************
* 3. Table: 10 x elasticities
**********************************************************************/

local l_E              "First-year entrants"
local l_enr_total      "All undergraduate students"
local l_aranceles      "Tuition revenue"
local l_gasto_total    "Expenses"
local l_act_nc         "Capital (non-current assets)"
local l_pc_gasto_total "\textbf{Expenses}"
local l_pc_rem_acad    "\quad Teaching: academic salaries"
local l_pc_overhead    "\quad Fixed costs: overhead"
local l_pc_act_nc      "Capital"
local l_enr_all        "All students (all levels)"
foreach v in gasto_total rem_acad overhead act_nc {
    local l_pca_`v' "`l_pc_`v''"
}
local rows "E enr_total enr_all aranceles gasto_total act_nc pc_gasto_total pc_rem_acad pc_overhead pc_act_nc pca_gasto_total pca_rem_acad pca_overhead pca_act_nc"
local h_E              "\textit{Students}"
local h_aranceles      "\textit{University totals}"
local h_pc_gasto_total "\textit{Per undergraduate student}"
local h_pca_gasto_total "\textit{Per student, all levels (undergraduate, graduate, postitulo)}"

quietly summarize nu if y == "pc_gasto_total" & col == 1
local nu = r(mean)
quietly summarize N if y == "pc_gasto_total" & col == 1
local N = r(mean)
quietly summarize N if y == "pc_act_nc" & col == 1
local Nnc = r(mean)

foreach v in b0 se0 b1 se1 b2 se2 {
    replace `v' = 10 * `v'
}

* cells: (col, lag) pairs in table order
local cells "1:0 2:0 2:1 3:0 3:1 3:2"
file open T using "$im_out/tables/im_fin_seats_levels.tex", write replace
file write T "\begin{tabular}{l*{6}{c}}" _n "\toprule" _n
file write T " & (1) & \multicolumn{2}{c}{(2)} & \multicolumn{3}{c}{(3)} \\" _n
file write T "\cmidrule(lr){2-2}\cmidrule(lr){3-4}\cmidrule(lr){5-7}" _n
file write T "\% change in \(Y_t\), seats in: & \(t\) & \(t\) & \(t-1\) & \(t\) & \(t-1\) & \(t-2\) \\" _n "\midrule" _n
foreach y of local rows {
    if "`h_`y''" != "" {
        if "`y'" != "E" file write T "\addlinespace" _n
        file write T "\multicolumn{7}{l}{`h_`y''} \\" _n
    }
    file write T "`l_`y''"
    foreach cl of local cells {
        gettoken c k : cl, parse(":")
        local k = subinstr("`k'", ":", "", 1)
        quietly summarize b`k' if y == "`y'" & col == `c'
        local b = r(mean)
        quietly summarize se`k' if y == "`y'" & col == `c'
        stars `b' `r(mean)' st
        file write T " & " %6.2f (`b') "`st'"
    }
    file write T " \\" _n
    foreach cl of local cells {
        gettoken c k : cl, parse(":")
        local k = subinstr("`k'", ":", "", 1)
        quietly summarize se`k' if y == "`y'" & col == `c'
        file write T " & (" %5.2f (r(mean)) ")"
    }
    file write T " \\" _n
}
file write T "\midrule" _n "University-years (" %2.0f (`nu') " universities) & \multicolumn{6}{c}{" %4.0f (`N') " (capital rows: " %4.0f (`Nnc') ")} \\" _n
file write T "University and year FE & \multicolumn{6}{c}{Yes} \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "49_finance_seats_levels.do finished."
