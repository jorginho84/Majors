/**********************************************************************
* 03b_selective_diagnostic.do
*
* Design IV, selective vs selective (issue #3): why is the continuous
* TWFE of oe_sel_fs_N_first.tex negative (triangular, about -12) while
* the Callaway-Sant'Anna ATT of the event study is positive (+8.7)?
*
* Same outcome (N_first), same panel (oe_selective_panel.dta, from 03).
* The two differ in (i) treatment: kernel-weighted cumulative exposure
* vs. a binary first-shock-in-market indicator; (ii) FE: field-year
* vs. program and year only; (iii) estimator: TWFE vs. CS
* (robust to heterogeneous effects under staggered adoption).
*
* Ladder, changing one thing at a time:
*   R1 continuous triangular, FE full, own control      (slide spec)
*   R2 continuous Total,      FE full, own control
*   R3 binary Post,           FE full, own control
*   R4 binary Post,           program + year FE, own control
*   R5 binary Post,           program + year FE, balanced, no control
*   R6 CS never treated       (program + year, balanced, no control)
*   R7 CS not yet treated
*   R8 imputation (BJS),      program + year FE, balanced, no control
*   R9 imputation (BJS),      FE full, own control
*   R10 binary Post split by 2016 triangular exposure (high / low),
*       FE full, own control (dose)
*   R11 continuous triangular, program + year FE, own control
*   R12 binary Post and continuous triangular together, FE full, own
*   FE full = program, broad field x year. SE clustered
*   by broad market.
*
* Output: output/own_expansion/tables/oe_sel_diag.tex
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"

use "$processed/oe_selective_panel.dta", clear
gen byte post_sel = g_sel > 0 & ao_proceso >= g_sel
gen int Ei = g_sel if g_sel > 0
local full "pid fy_broad"

tab g_sel if ao_proceso == 2016
quietly summarize N_first if g_sel > 0 & post_sel == 0
local ym = r(mean)

capture program drop keep_b
program define keep_b
    args name x
    c_local b_`name'  = _b[`x']
    c_local se_`name' = _se[`x']
    c_local p_`name'  = 2 * normal(-abs(_b[`x'] / _se[`x']))
    c_local N_`name'  = e(N)
end

reghdfe N_first x_tri_broad, absorb(`full') cluster(mkt_broad)
keep_b R1 x_tri_broad
reghdfe N_first x_tot_broad, absorb(`full') cluster(mkt_broad)
keep_b R2 x_tot_broad
reghdfe N_first post_sel, absorb(`full') cluster(mkt_broad)
keep_b R3 post_sel
reghdfe N_first post_sel, absorb(pid ao_proceso) cluster(mkt_broad)
keep_b R4 post_sel
reghdfe N_first post_sel if balanced, absorb(pid ao_proceso) cluster(mkt_broad)
keep_b R5 post_sel

foreach cg in never notyet {
    local opt = cond("`cg'" == "notyet", "notyet", "")
    local r   = cond("`cg'" == "notyet", "R7", "R6")
    csdid N_first if balanced, ivar(pid) time(ao_proceso) gvar(g_sel) `opt'
    estat simple
    matrix bb = r(b)
    matrix VV = r(V)
    local b_`r'  = bb[1, 1]
    local se_`r' = sqrt(VV[1, 1])
    local p_`r'  = 2 * normal(-abs(`b_`r'' / `se_`r''))
    local N_`r'  = .
}

did_imputation N_first pid ao_proceso Ei if balanced, fe(pid ao_proceso) ///
    cluster(mkt_broad) autosample
keep_b R8 tau
did_imputation N_first pid ao_proceso Ei, fe(`full') ///
    cluster(mkt_broad) autosample
keep_b R9 tau

* dose: split treated programs by 2016 triangular exposure
bys pid: egen double tri16 = max(cond(ao_proceso == 2016, sE_tri_broad, .))
quietly summarize tri16 if g_sel > 0 & ao_proceso == 2016, detail
local med = r(p50)
di as text "Median 2016 triangular exposure among treated: " as result %6.2f `med'
gen byte post_hi = post_sel & tri16 >  `med'
gen byte post_lo = post_sel & tri16 <= `med'
reghdfe N_first post_hi post_lo, absorb(`full') cluster(mkt_broad)
keep_b R10h post_hi
keep_b R10l post_lo
test post_hi = post_lo
local p_eq = r(p)

* also: continuous triangular with program + year FE only
reghdfe N_first x_tri_broad, absorb(pid ao_proceso) cluster(mkt_broad)
keep_b R11 x_tri_broad

* level (exposed market) and dose (closeness) together
reghdfe N_first post_sel x_tri_broad, absorb(`full') cluster(mkt_broad)
keep_b R12p post_sel
keep_b R12x x_tri_broad


/**********************************************************************
* Table
**********************************************************************/

file open T using "$oe_out/tables/oe_sel_diag.tex", write replace
file write T "\begin{tabular}{llllc}" _n "\toprule" _n
file write T " & Treatment & Estimator & Fixed effects & Coefficient \\" _n "\midrule" _n
local rows R1 R11 R2 R3 R4 R5 R6 R7 R8 R9 R10h R10l R12p R12x
local t_R1   "Cum. exposure, triangular (10 pp)"
local t_R11  "Cum. exposure, triangular (10 pp)"
local t_R2   "Cum. exposure, Total (10 pp)"
local t_R3   "Post first shock in market"
local t_R4   "Post first shock in market"
local t_R5   "Post first shock in market"
local t_R6   "Post first shock in market"
local t_R7   "Post first shock in market"
local t_R8   "Post first shock in market"
local t_R9   "Post first shock in market"
local t_R10h "Post $\times$ high triangular exposure"
local t_R10l "Post $\times$ low triangular exposure"
local t_R12p "Joint: Post first shock in market"
local t_R12x "Joint: cum. exposure, triangular (10 pp)"
local e_R12p "TWFE"
local e_R12x "TWFE"
local e_R1 "TWFE"
local e_R11 "TWFE"
local e_R2 "TWFE"
local e_R3 "TWFE"
local e_R4 "TWFE"
local e_R5 "TWFE, balanced"
local e_R6 "CS, never treated"
local e_R7 "CS, not yet treated"
local e_R8 "Imputation (BJS), balanced"
local e_R9 "Imputation (BJS)"
local e_R10h "TWFE"
local e_R10l "TWFE"
foreach r in R1 R2 R3 R9 R10h R10l R12p R12x {
    local f_`r' "Program, field-year"
}
local f_R11 "Program, year"
local f_R4 "Program, year"
foreach r in R5 R6 R7 R8 {
    local f_`r' "Program, year"
}
local i = 0
foreach r of local rows {
    local ++i
    oe_stars `p_`r''
    file write T "(`i') & `t_`r'' & `e_`r'' & `f_`r'' & " %7.2f (`b_`r'') "`r(stars)'" " \\" _n
    file write T " & & & & (" %6.2f (`se_`r'') ") \\" _n
}
file write T "\midrule" _n "\multicolumn{4}{l}{Pre-shock mean of first-year enrollment, treated} & " %6.1f (`ym') " \\" _n
file write T "\multicolumn{4}{l}{\(p\)-value, high = low exposure} & " %5.3f (`p_eq') " \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

foreach r of local rows {
    di as text "`r' `t_`r'' | `e_`r'' | `f_`r'': " as result %7.2f `b_`r'' " (" %6.2f `se_`r'' ") N " `N_`r''
}
di as result "Selective diagnostic written."
