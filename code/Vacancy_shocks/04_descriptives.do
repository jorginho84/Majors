/**********************************************************************
* 04_descriptives.do
*
* Design III — where are the vacancy shocks?
*
* Figures (output/vacancy_shocks/figures/):
*   vs_dlogV_hist.pdf        distribution of dlogV, with the top-20% threshold
*   vs_dV_hist.pdf           distribution of level changes dV
*   vs_shocks_by_year.pdf    number of shocks per year, main vs. no-sudden
*
* Tables (output/vacancy_shocks/tables/, booktabs fragments):
*   vs_shock_location.tex    shock rate and share by pre-period selectivity
*                            quintile, field, CRUCH status, and year
*   vs_shocks_per_program.tex number of shocks per program
*   vs_shock_definitions.tex  count and size of shocks under each definition
*
* Input: $processed/vs_panel_exposure.dta
**********************************************************************/

do "code/config.do"

global vs_out "$output/vacancy_shocks"
cap mkdir "$vs_out"
cap mkdir "$vs_out/tables"
cap mkdir "$vs_out/figures"

set scheme s2color

use "$processed/vs_panel_exposure.dta", clear
xtset pid ao_proceso

* candidate program-years: incumbents with a vacancy change, 2010-2016
gen byte cand = !missing(dlogV) & entrant_2012 != 1 & inrange(ao_proceso, 2010, 2016)
gen double dV = V_dem - L.V_dem

_pctile dlogV if dlogV > 0 & entrant_2012 != 1 & inrange(ao_proceso, 2008, 2016), p(80)
local thr = r(r1)
local thrs = string(`thr', "%4.2f")


/**********************************************************************
* 1. Figures
**********************************************************************/

quietly count if cand
local ncand = r(N)
quietly count if cand & dlogV > 0
local npos = r(N)
quietly count if cand & dlogV == 0
local pzero = string(100 * r(N) / `ncand', "%3.0f")
local ppos  = string(100 * `npos' / `ncand', "%3.0f")

* most program-years have no change in vacancies: plot the increases only
twoway (histogram dlogV if cand & dlogV > 0 & dlogV <= 1.5, ///
            width(0.05) fraction fcolor(navy%60) lcolor(navy%80)), ///
    xline(`thr', lcolor(cranberry) lpattern(dash) lwidth(medthick)) ///
    xtitle("Increase in log vacancies, t-1 to t") ytitle("Fraction of increases") ///
    text(0.15 `thr' " top 20% of increases" " (dlogV {&ge} `thrs')", ///
        place(e) color(cranberry) size(small)) ///
    note("Program-years 2010-2016 with vacancies in t-1 and t: N = `ncand'. `pzero'% have no change," ///
         "`ppos'% increase (`npos', shown; trimmed at 1.5). Threshold: 80th percentile of positive changes, pooled 2008-2016.", ///
         size(vsmall)) ///
    graphregion(color(white)) plotregion(color(white))
graph export "$vs_out/figures/vs_dlogV_hist.pdf", replace

twoway (histogram dV if cand & inrange(dV, -100, 200), ///
            width(5) fraction fcolor(navy%60) lcolor(navy%80)), ///
    xline(0, lcolor(gs8)) ///
    xtitle("Change in vacancies (seats), t-1 to t") ytitle("Fraction of program-years") ///
    note("Program-years 2010-2016. Trimmed to [-100, 200] seats.", size(vsmall)) ///
    graphregion(color(white)) plotregion(color(white))
graph export "$vs_out/figures/vs_dV_hist.pdf", replace

preserve
collapse (sum) shock_main shock_nosud if inrange(ao_proceso, 2010, 2016), by(ao_proceso)
graph bar shock_nosud shock_main, over(ao_proceso) ///
    bar(1, color(navy%35)) bar(2, color(navy)) ///
    legend(order(1 "Top 20% increase" 2 "Top 20% and sudden (main)") rows(1) size(small)) ///
    ytitle("Number of program shocks") ///
    graphregion(color(white)) plotregion(color(white))
graph export "$vs_out/figures/vs_shocks_by_year.pdf", replace
restore


/**********************************************************************
* 2. Where do shocks happen?
**********************************************************************/

* pre-period selectivity quintile, across programs
preserve
bys pid: keep if _n == 1
xtile selq = psu_first_pre if !missing(psu_first_pre), nq(5)
keep pid selq
tempfile q
save `q'
restore
merge m:1 pid using `q', nogen

gen str40 grp_sel = "Q" + string(selq) if !missing(selq)
replace grp_sel = "No PSU data" if missing(selq)
replace grp_sel = "Q1 (least selective)" if selq == 1
replace grp_sel = "Q5 (most selective)"  if selq == 5

* before 2012 only CRUCH universities were in DEMRE: split state vs. private CRUCH
gen str40 grp_uni = cond(state == 1, "State (CRUCH)", "Private (CRUCH)")
gen str60 grp_fld = field
replace grp_fld = "Unknown" if grp_fld == ""
gen str10 grp_yr  = string(ao_proceso)

quietly count if cand & shock_main
local ntot = r(N)

file open T using "$vs_out/tables/vs_shock_location.tex", write replace
file write T "\begin{tabular}{lrrrr}" _n "\toprule" _n
file write T " & Program-years & Shocks & Shock rate (\%) & Share of shocks (\%) \\" _n
file write T "\midrule" _n

foreach dim in sel fld uni yr {
    local head : word `=cond("`dim'"=="sel",1,cond("`dim'"=="fld",2,cond("`dim'"=="uni",3,4)))' of ///
        "Pre-period selectivity (entrant PSU quintile)" "Field of study" "University" "Year"
    file write T "\multicolumn{5}{l}{\textit{`head'}} \\" _n
    preserve
    keep if cand
    gen byte one = 1
    collapse (sum) n = one s = shock_main, by(grp_`dim')
    gen double rate = 100 * s / n
    gen double share = 100 * s / `ntot'
    if "`dim'" == "fld" gsort -s
    else sort grp_`dim'
    forvalues i = 1/`=_N' {
        local lab = subinstr(grp_`dim'[`i'], "&", "\&", .)
        file write T "\quad `lab' & " %9.0fc (n[`i']) " & " %9.0fc (s[`i']) ///
            " & " %5.1f (rate[`i']) " & " %5.1f (share[`i']) " \\" _n
    }
    restore
    if "`dim'" != "yr" file write T "\addlinespace" _n
}
quietly count if cand
file write T "\midrule" _n "Total & " %9.0fc (r(N)) " & " %9.0fc (`ntot') ///
    " & " %5.1f (100*`ntot'/r(N)) " & 100.0 \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 3. Shocks per program
**********************************************************************/

preserve
keep if entrant_2012 != 1 & !missing(V_dem)
collapse (sum) ns = shock_main, by(pid)
gen int nsc = min(ns, 3)
gen byte one = 1
collapse (sum) n = one, by(nsc)
egen double tot = total(n)
gen double pct = 100 * n / tot
file open T using "$vs_out/tables/vs_shocks_per_program.tex", write replace
file write T "\begin{tabular}{lrr}" _n "\toprule" _n
file write T "Shocks per program, 2010--2016 & Programs & \% \\" _n "\midrule" _n
forvalues i = 1/`=_N' {
    local lab = cond(nsc[`i'] == 3, "3 or more", string(nsc[`i']))
    file write T "`lab' & " %9.0fc (n[`i']) " & " %5.1f (pct[`i']) " \\" _n
}
file write T "\midrule" _n "Total & " %9.0fc (tot[1]) " & 100.0 \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T
restore


/**********************************************************************
* 4. Shock definitions compared
**********************************************************************/

file open T using "$vs_out/tables/vs_shock_definitions.tex", write replace
file write T "\begin{tabular}{llrrr}" _n "\toprule" _n
file write T "Definition & & Shocks & Mean \(\Delta\log V\) & Mean seats added \\" _n "\midrule" _n
foreach t in main p90 p75 within nosud lev ind adm {
    local alltags main p90 p75 within nosud lev ind adm
    local pos : list posof "`t'" in alltags
    local d1 : word `pos' of ///
        "Main" "Top 10\%" "Top 25\%" "Within-year p80" "No sudden conditions" "Level change" "INDICES vacancies" "Admissions as vacancies"
    local d2 : word `pos' of ///
        "top 20\%, sudden" "sudden" "sudden" "sudden" "top 20\%" "top 20\% of \(\Delta V\)" "top 20\%, sudden" "top 20\%, sudden"
    local dl = cond("`t'" == "adm", "dlogV_adm", cond("`t'" == "ind", "dlogV_ind", "dlogV"))
    quietly summarize `dl' if shock_`t'
    local n = r(N)
    local m = r(mean)
    quietly summarize seats_`t' if shock_`t'
    file write T "`d1' & `d2' & " %9.0fc (`n') " & " %5.2f (`m') " & " %6.1f (r(mean)) " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "Design III descriptives written to $vs_out."
