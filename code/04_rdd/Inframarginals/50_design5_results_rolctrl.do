/**********************************************************************
* 50_design5_results_rolctrl.do
*
* Deck slide "Design V: results" (issue #10): Design V 2SLS under the
* three candidate main ROL FE (1st preference + set of universities,
* first three preferences, set of programs), each with (a) program +
* year FE, (b) + demand in t-1, accreditation and tuition, (c) (b) with
* university x year and field x year FE. No estimation: reads 48t.
*
*   units: first stage, entrants per seat; 2SLS, pp per ten entrants;
*          means in %
*
* Output: output/inframarginal/tables/im_d5_main_rolctrl.tex
* Input : output/inframarginal/tables/im_d5_2sls_all_rol_controls.csv (48t)
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

import delimited using "$im_out/tables/im_d5_2sls_all_rol_controls.csv", clear asdouble case(preserve)
keep if inlist(rol, "top1u", "top3", "set")
gen byte k = 3 * (cond(rol == "top1u", 1, cond(rol == "top3", 2, 3)) - 1) + spec
isid outcome k

capture program drop cell
program define cell
    args v o k
    quietly summarize `v' if outcome == "`o'" & k == `k'
    c_local val = r(mean)
end

file open T using "$im_out/tables/im_d5_main_rolctrl.tex", write replace
file write T "\begin{tabular}{l*{9}{c}}" _n "\toprule" _n
file write T "ROL FE & \multicolumn{3}{c}{Top 1 + univ. (main)} & \multicolumn{3}{c}{First three pref.} & \multicolumn{3}{c}{Program set} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}\cmidrule(lr){8-10}" _n
forvalues k = 1/9 {
    file write T " & (`k')"
}
file write T " \\" _n
file write T "Program-year controls" _dup(3) " & -- & Yes & Yes" " \\" _n
file write T "Time FE" _dup(3) " & Year & Year & U, F \(\times\) yr" " \\" _n "\midrule" _n
file write T "First stage: \(n_{pt}\) on \(Z_{pt}\)"
forvalues k = 1/9 {
    cell fs program `k'
    local b = `val'
    cell fsp program `k'
    stars `val' st
    file write T " & " %5.3f (`b') "`st'"
}
file write T " \\" _n
forvalues k = 1/9 {
    cell fsse program `k'
    file write T " & (" %5.3f (`val') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
forvalues k = 1/9 {
    cell F program `k'
    file write T " & " %5.0f (`val')
}
file write T " \\" _n "\addlinespace" _n
file write T "\multicolumn{10}{l}{2SLS (pp per ten entrants)} \\" _n
foreach o in program uni he {
    local ol = cond("`o'" == "program", "Graduation, enrolled program, 8y", cond("`o'" == "uni", "Graduation, any university, 8y", "Graduation, any higher education, 8y"))
    file write T "\quad `ol'"
    forvalues k = 1/9 {
        cell iv `o' `k'
        local b = `val'
        cell ivp `o' `k'
        stars `val' st
        file write T " & " %6.3f (`b') "`st'"
    }
    file write T " \\" _n
    forvalues k = 1/9 {
        cell ivse `o' `k'
        file write T " & (" %5.3f (`val') ")"
    }
    file write T " \\" _n "\quad \quad Mean (\%)"
    forvalues k = 1/9 {
        cell ym `o' `k'
        file write T " & " %4.1f (`val')
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Students"
forvalues k = 1/9 {
    cell N program `k'
    file write T " & " %9.0fc (`val')
}
file write T " \\" _n "Program-years (clusters)"
forvalues k = 1/9 {
    cell npt program `k'
    file write T " & " %6.0fc (`val')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "50_design5_results_rolctrl.do finished."
