/**********************************************************************
* 45_finance_seats_rf.do
*
* Revenue channel behind the positive T-1 graduation coefficient of the
* Design V distributed lag (40, 2026-11-10 meeting): do universities that
* raise their seats get more resources per student, in that year or the
* next ones? University-level reduced form in first differences:
*
*   Dln Y_ut = b0 Dln V_ut + b1 Dln V_u,t-1 + b2 Dln V_u,t-2
*              + D(field shares)_ut' theta + phi_t + e_ut
*
*   unit : university x fiscal year (= admission year), FY 2014-2022
*          (first differences of FY 2013-2022 statements)
*   V    : regular vacancies of the university's programs in the
*          centralized admission
*   Y    : first-year entrants (DEMRE); undergraduate stock (MINEDUC);
*          from the SES statements, in total and per undergraduate:
*          tuition revenue, total income, total expenses, salaries,
*          and, to separate variable from fixed costs (2026-11-12
*          meeting): academic salaries (variable, ~31% of expenses);
*          overhead = administrative and executive salaries +
*          administration and sales expenses (fixed, ~48%); other
*          operating expenses (mixed, csv only); non-current assets
*          (capital stock; its change is net investment, as there is no
*          capex line)
*   controls: changes in the share of each knowledge area (11
*          categories from 02_build/18, one omitted) in undergraduate
*          enrollment, so that expanding cheaper fields is not read as
*          dilution
*   FE   : year
*   SE   : clustered by university
*   Sample: universities with entrants in t, t-1 and t-2; years with a
*          tuition jump (flag_jump, 01_clean/08) in t or t-1 excluded;
*          for non-current assets, also years with an asset jump
*          (flag_nc: factor > 2.5, e.g. UNAB FY 2018-19) in t or t-1.
*   Sum : b0 + b1 + b2 (lincom).
*   The .tex table reports 10 x the elasticities: % change in the
*   outcome when seats rise by 10% (the csv keeps the elasticities).
*
* Outputs (output/inframarginal/tables/):
*   im_fin_seats_rf.tex   deck table
*   im_fin_seats_rf.csv   every estimate
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
* 1. Panel
**********************************************************************/

use "$processed/university_entrants_fields.dta", clear
merge 1:1 cod_inst fy using "$processed/university_finance_panel.dta", ///
    keep(master match) nogen
xtset cod_inst fy

gen double l_V  = ln(V) if V > 0
gen double dl_V = D.l_V
gen double l_E  = ln(E) if E > 0
gen double dl_E = D.l_E
* fixed-cost block: administrative + executive salaries + administration
* and sales expenses (FY <= 2022 classification)
gen double overhead = rem_adm + rem_dir + g_adm
local fin "aranceles ing_total gasto_total rem_total rem_acad overhead g_otrop act_nc"
foreach v in `fin' enr_total {
    gen double l_`v' = ln(`v') if `v' > 0
    gen double dl_`v' = D.l_`v'
}
foreach v of local fin {
    gen double lpc_`v' = ln(`v' / enr_total) if `v' > 0
    gen double dl_pc_`v' = D.lpc_`v'
}
unab shs : sh*
local nsh : word count `shs'
local ctl ""
forvalues j = 2/`nsh' {
    gen double dsh`j' = D.sh`j'
    local ctl "`ctl' dsh`j'"
}

gen byte s = E > 0 & L.E > 0 & L2.E > 0 & !flag_jump & !L.flag_jump ///
    & !missing(dl_V, L.dl_V, L2.dl_V, dl_pc_gasto_total, dsh2)
* non-current assets: also drop years with an asset jump in t or t-1
gen byte s_nc = s & !flag_nc & !L.flag_nc
count if s
count if s_nc
distinct cod_inst if s
tab fy if s

* sample means of the outcome levels, for the table (nominal pesos:
* totals in CLP billions = M$ / 1e6; per student in CLP millions =
* M$ / 1e3), and the typical annual change in seats
foreach v in aranceles gasto_total act_nc {
    gen double lv_`v' = `v' / 1e6
}
foreach v in gasto_total rem_acad overhead act_nc {
    gen double lv_pc_`v' = `v' / enr_total / 1e3
}
gen double lv_E = E
gen double lv_enr_total = enr_total
foreach v in E enr_total aranceles gasto_total act_nc pc_gasto_total pc_rem_acad pc_overhead pc_act_nc {
    local ss = cond(strpos("`v'", "act_nc"), "s_nc", "s")
    quietly summarize lv_`v' if `ss'
    local mean_`v' = r(mean)
}
quietly summarize dl_V if s
local dV_mean = 100 * r(mean)
local dV_sd   = 100 * r(sd)
di as result "Annual change in seats: mean " %5.1f `dV_mean' "%, SD " %5.1f `dV_sd' "%"

/**********************************************************************
* 2. Estimation
**********************************************************************/

tempname P
tempfile res
postfile `P' str14 y double(b0 se0 b1 se1 b2 se2 bs ses) long(N nu) using `res', replace
local ys "E enr_total aranceles ing_total gasto_total rem_total rem_acad overhead g_otrop act_nc pc_aranceles pc_ing_total pc_gasto_total pc_rem_total pc_rem_acad pc_overhead pc_g_otrop pc_act_nc"
foreach y of local ys {
    local ss = cond(strpos("`y'", "act_nc"), "s_nc", "s")
    quietly reghdfe dl_`y' dl_V L.dl_V L2.dl_V `ctl' if `ss', absorb(fy) cluster(cod_inst)
    local N = e(N)
    local nu = e(N_clust)
    local b0 = _b[dl_V]
    local s0 = _se[dl_V]
    local b1 = _b[L.dl_V]
    local s1 = _se[L.dl_V]
    local b2 = _b[L2.dl_V]
    local s2 = _se[L2.dl_V]
    quietly lincom dl_V + L.dl_V + L2.dl_V
    post `P' ("`y'") (`b0') (`s0') (`b1') (`s1') (`b2') (`s2') (r(estimate)) (r(se)) (`N') (`nu')
}
postclose `P'

use `res', clear
export delimited using "$im_out/tables/im_fin_seats_rf.csv", replace
format b0 se0 b1 se1 b2 se2 bs ses %7.3f
list y b0 se0 b1 se1 b2 se2 bs ses N nu, noobs clean

/**********************************************************************
* 3. Table
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
local rows "E enr_total aranceles gasto_total act_nc pc_gasto_total pc_rem_acad pc_overhead pc_act_nc"
* panel headers before these rows
local h_E              "\textit{Students} (mean: number)"
local h_aranceles      "\textit{University totals} (mean: CLP billion)"
local h_pc_gasto_total "\textit{Per student} (mean: CLP million)"

quietly summarize nu if y == "pc_gasto_total"
local nu = r(mean)
quietly summarize N if y == "pc_gasto_total"
local N = r(mean)
quietly summarize N if y == "pc_act_nc"
local Nnc = r(mean)

* table in percent per 10% more seats (elasticity x 10)
foreach v in b0 se0 b1 se1 b2 se2 bs ses {
    replace `v' = 10 * `v'
}
file open T using "$im_out/tables/im_fin_seats_rf.tex", write replace
* the sum b0 + b1 + b2 stays in the csv only
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T "\% change in year \(t\) & Mean & \(t\) & \(t-1\) & \(t-2\) \\" _n "\midrule" _n
foreach y of local rows {
    if "`h_`y''" != "" {
        if "`y'" != "E" file write T "\addlinespace" _n
        file write T "\multicolumn{5}{l}{`h_`y''} \\" _n
    }
    file write T "`l_`y''"
    if inlist("`y'", "E", "enr_total") file write T " & " %9.0fc (`mean_`y'')
    else file write T " & " %6.1f (`mean_`y'')
    foreach k in 0 1 2 {
        quietly summarize b`k' if y == "`y'"
        local b = r(mean)
        quietly summarize se`k' if y == "`y'"
        stars `b' `r(mean)' st
        file write T " & " %6.2f (`b') "`st'"
    }
    file write T " \\" _n " &"
    foreach k in 0 1 2 {
        quietly summarize se`k' if y == "`y'"
        file write T " & (" %5.2f (r(mean)) ")"
    }
    file write T " \\" _n
}
file write T "\midrule" _n "University-years (" %2.0f (`nu') " universities) & \multicolumn{4}{c}{" %4.0f (`N') " (capital rows: " %4.0f (`Nnc') ")} \\" _n
file write T "Annual change in seats & \multicolumn{4}{c}{mean " %3.1f (`dV_mean') "\%, SD " %3.1f (`dV_sd') "\%} \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "45_finance_seats_rf.do finished."
