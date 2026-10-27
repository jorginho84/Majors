/**********************************************************************
* 03_va_correlates.do
*
* Program value-added (issue #9): correlates of program VA.
*   1. Selectivity: average PSU (L-M) of the program's enrollees
*   2. Field of study (SIES area de conocimiento, 11 fields and 5 groups)
*   3. Vacancies: level (mean log total cupos) and growth 2007-2016,
*      and the evolution of vacancies by VA tercile
*
* VA: main specification (portfolio FE + controls), EB-shrunk, outcome
* inc_rank (Mi Futuro income rank of the program graduated from, 0 if no
* title; rank points), versions itt (headline) and enr. Program-level
* statistics are weighted by the program's students in the identifying
* sample. Correlations with precisely measured characteristics are also
* reported corrected for estimation error in VA (MH fn. 41):
* corr(v, x) = corr(v_hat, x) * SD(v_hat) / SD_signal(v).
*
* Inputs:  $processed/pva_program_va.dta, pva_students_2007_2016.dta,
*          analysis_sample_with_fields_final.dta,
*          program_year_vacancies_2007_2016.dta
* Output:  output/tables/pva_correlates*.csv, output/figures/pva_*.pdf
**********************************************************************/

clear all
set more off
do "code/config.do"

capture log close
log using "$logs/pva_03_va_correlates.log", replace text

capture program drop harmonize_code
program define harmonize_code
    args in out
    tempvar s
    gen `s' = strtrim(string(`in', "%12.0f"))
    gen long `out' = `in'
    replace `out' = real(substr(`s', 1, length(`s')-2) + "0" + ///
        substr(`s', length(`s')-1, 2)) if length(`s') == 4
end

/**********************************************************************
* 1. Program characteristics
**********************************************************************/

* 1a. average PSU of enrollees (all enrollees, 2007-2016 pooled)
use S_enr psu_lm using "$processed/pva_students_2007_2016.dta", clear
keep if !missing(S_enr, psu_lm)
collapse (mean) psu_mean = psu_lm (count) n_enr_psu = psu_lm, by(S_enr)
rename S_enr code_h
tempfile psu
save `psu'

* 1b. field: most frequent SIES field of the program code
use t_codigo_carrera field using "$processed/analysis_sample_with_fields_final.dta", clear
keep if !inlist(field, "", "Missing", "Undefined")
harmonize_code t_codigo_carrera code_h
contract code_h field, freq(nf)
gsort code_h -nf
bysort code_h: keep if _n == 1
keep code_h field
gen byte field_group = .
replace field_group = 1 if inlist(field, "Business", "Law")
replace field_group = 2 if field == "Health"
replace field_group = 3 if inlist(field, "Basic Sciences", "Technology")
replace field_group = 4 if inlist(field, "Education", "Humanities", "Social Sciences")
replace field_group = 5 if inlist(field, "Agriculture", "Arts and Architecture")
label define field_group_lbl 1 "Business and Law" 2 "Health" 3 "STEM" ///
    4 "Education and Humanities" 5 "Arts, Agriculture and Other", replace
label values field_group field_group_lbl
tempfile fld
save `fld'

* 1c. vacancies (total cupos), program-year
use "$processed/program_year_vacancies_2007_2016.dta", clear
harmonize_code t_codigo_carrera code_h
collapse (sum) cupos = total_cupos, by(code_h ao_proceso)
replace cupos = . if cupos <= 0
gen double lcupos = ln(cupos)
tempfile vac_py
save `vac_py'
bysort code_h: egen byte n_years = count(cupos)
gen double l07 = lcupos if ao_proceso == 2007
gen double l16 = lcupos if ao_proceso == 2016
collapse (mean) lcupos_mean = lcupos cupos_mean = cupos ///
         (max) l07 l16 n_years, by(code_h)
gen double dlcupos_0716 = l16 - l07
label var lcupos_mean  "Mean log total cupos, 2007-2016"
label var dlcupos_0716 "Log change in total cupos, 2007-2016"
tempfile vac
save `vac'

/**********************************************************************
* 2. Merge with VA
**********************************************************************/

use "$processed/pva_program_va.dta", clear
merge m:1 code_h using `psu', keep(1 3) nogen
merge m:1 code_h using `fld', keep(1 3) nogen
merge m:1 code_h using `vac', keep(1 3) nogen

di as result _n "=== Coverage of characteristics (programs with main VA) ==="
foreach v in psu_mean field lcupos_mean dlcupos_0716 {
    count if !missing(v_inc_eb) & !missing(`v')
}

save "$processed/pva_program_va_correlates.dta", replace

/**********************************************************************
* 3. Correlations: PSU, vacancies (levels and growth)
**********************************************************************/

tempname post
postfile `post' str4 version str16 x str10 y double(corr corr_signal slope se_slope) ///
    long K using "$processed/pva_correlates.dta", replace

foreach version in itt enr {
    use "$processed/pva_program_va_correlates.dta", clear
    keep if version == "`version'" & !missing(v_inc_main)

    * SD of the estimates and of the signal (for the correction)
    quietly summarize v_inc_main [aw = n_obs]
    local var_hat = r(Var) * (r(sum_w) - 1) / r(sum_w)
    gen double se2 = se_inc_main^2
    quietly summarize se2 [aw = n_obs]
    local ratio = sqrt(`var_hat' / max(`var_hat' - r(mean), 1e-12))

    foreach x in psu_mean lcupos_mean dlcupos_0716 {
        foreach y in mean_inc v_inc_main v_inc_eb {
            quietly corr `y' `x' [aw = n_obs]
            local r = r(rho)
            local rs = cond("`y'" == "v_inc_main", `r' * `ratio', `r')
            * regress EB VA on x (EB as dependent variable is fine; as in MH
            * we use EB only to correct regressors)
            quietly reg `y' `x' [aw = n_obs], robust
            post `post' ("`version'") ("`x'") ("`y'") (`r') (`rs') ///
                (_b[`x']) (_se[`x']) (e(N))
        }
    }

    * conditional associations (MH Fig. 10 spirit): VA on PSU, vacancies,
    * field FE jointly
    di as result _n "=== `version': VA (main) on PSU, log cupos, growth, field FE ==="
    reg v_inc_main psu_mean lcupos_mean dlcupos_0716 i.field_group [aw = n_obs], robust
    reg v_inc_main psu_mean lcupos_mean dlcupos_0716 i.field_group ///
        [aw = 1 / (se_inc_main^2)], robust
}
postclose `post'
use "$processed/pva_correlates.dta", clear
format corr* slope se_slope %9.4f
list, noobs sepby(version x) abbrev(12)
export delimited using "$output/tables/pva_correlates.csv", replace

/**********************************************************************
* 4. Field of study
**********************************************************************/

use "$processed/pva_program_va_correlates.dta", clear
keep if version == "itt" & !missing(v_inc_main, field_group)

* weighted means by field (raw graduation, VA, EB VA) with SEs
tempname pf
postfile `pf' str30 field str12 y double(b se) long K ///
    using "$processed/pva_field.dta", replace
levelsof field, local(fs)
foreach f of local fs {
    foreach y in mean_inc v_inc_main v_inc_eb v_grad_eb psu_mean {
        quietly reg `y' [aw = n_obs] if field == "`f'", robust
        post `pf' ("`f'") ("`y'") (_b[_cons]) (_se[_cons]) (e(N))
    }
}
postclose `pf'

* share of signal variance explained by field (between-field variance of
* EB VA over signal variance)
quietly summarize v_inc_main [aw = n_obs]
local var_hat = r(Var) * (r(sum_w) - 1) / r(sum_w)
gen double se2 = se_inc_main^2
quietly summarize se2 [aw = n_obs]
local var_sig = `var_hat' - r(mean)
gen double wv = v_inc_main * n_obs
bysort field: egen double swv = total(wv)
bysort field: egen double sw  = total(n_obs)
gen double fmean = swv / sw
quietly summarize fmean [aw = n_obs]
local var_btw = r(Var) * (r(sum_w) - 1) / r(sum_w)
di as result _n "Signal variance of VA: " %9.6f `var_sig' ///
    "   between-field variance: " %9.6f `var_btw' ///
    "   share: " %6.3f `var_btw' / `var_sig'
di as text "(between-field variance includes noise in field means; small for large fields)"

* VA terciles by field
xtile va_t = v_inc_eb [aw = n_obs], n(3)
tab field va_t [aw = n_obs], row nofreq

use "$processed/pva_field.dta", clear
list, noobs sepby(field) abbrev(12)
export delimited using "$output/tables/pva_field.csv", replace

/**********************************************************************
* 5. Figures: VA vs PSU (raw vs VA), VA by field
**********************************************************************/

use "$processed/pva_program_va_correlates.dta", clear
keep if version == "itt" & !missing(v_inc_main, psu_mean)
quietly summarize mean_inc [aw = n_obs]
gen double mean_inc_c = mean_inc - r(mean)

foreach y in mean_inc_c v_inc_eb {
    quietly corr `y' psu_mean [aw = n_obs]
    local r = string(r(rho), "%5.2f")
    quietly reg `y' psu_mean [aw = n_obs]
    local b = string(_b[psu_mean] * 100, "%6.3f")
    local ttl = cond("`y'" == "mean_inc_c", "Raw income rank (centered)", ///
        "Value-added on income rank (EB)")
    twoway (scatter `y' psu_mean [aw = n_obs], msymbol(Oh) msize(vsmall) ///
               mcolor(navy%40)) ///
           (lfit `y' psu_mean [aw = n_obs], lcolor(maroon)), ///
        ytitle("`ttl'") xtitle("Average PSU (L-M) of enrollees") ///
        legend(off) ///
        note("Corr = `r'; slope per 100 PSU points = `b'") ///
        name(g_`y', replace) nodraw
}
graph combine g_mean_inc_c g_v_inc_eb, cols(1) xcommon ysize(8) ///
    title("Income rank: raw vs value-added, by selectivity")
graph export "$output/figures/pva_va_vs_psu.pdf", replace

use "$processed/pva_program_va_correlates.dta", clear
keep if version == "itt" & !missing(v_inc_main, field)
graph hbox v_inc_eb [aw = n_obs], over(field, sort(1)) ///
    ytitle("Value-added on income rank (EB, relative to weighted mean)") ///
    note("Programs weighted by students in the identifying sample")
graph export "$output/figures/pva_va_by_field.pdf", replace

/**********************************************************************
* 6. Evolution of vacancies by VA tercile
**********************************************************************/

use "$processed/pva_program_va_correlates.dta", clear
keep if version == "itt" & !missing(v_inc_eb)
xtile va_t = v_inc_eb [aw = n_obs], n(3)
keep code_h va_t field_group n_obs
tempfile terc
save `terc'

use `vac_py', clear
merge m:1 code_h using `terc', keep(3) nogen

* (a) balanced panel of programs observed every year: total cupos by
*     tercile, indexed to 2007 = 100
preserve
    bysort code_h: egen byte ny = count(cupos)
    keep if ny == 10
    collapse (sum) cupos (count) nprog = cupos, by(va_t ao_proceso)
    bysort va_t (ao_proceso): gen double idx = 100 * cupos / cupos[1]
    list, noobs sepby(va_t)
    export delimited using "$output/tables/pva_vacancies_by_tercile_balanced.csv", replace
    twoway (connected idx ao_proceso if va_t == 1, lcolor(maroon) mcolor(maroon)) ///
           (connected idx ao_proceso if va_t == 2, lcolor(gs8) mcolor(gs8)) ///
           (connected idx ao_proceso if va_t == 3, lcolor(navy) mcolor(navy)), ///
        legend(order(1 "Low VA" 2 "Middle VA" 3 "High VA") rows(1)) ///
        ytitle("Total cupos (2007 = 100)") xtitle("Application year") ///
        xlabel(2007(1)2016) title("Vacancies by VA tercile, balanced programs")
    graph export "$output/figures/pva_vacancies_by_tercile.pdf", replace
restore

* (b) all programs: sum of cupos and number of programs by tercile (entry
*     and exit included), and the within-program log change via program FE
preserve
    collapse (sum) cupos (count) nprog = cupos, by(va_t ao_proceso)
    list, noobs sepby(va_t)
    export delimited using "$output/tables/pva_vacancies_by_tercile_all.csv", replace
restore

* within-program growth by tercile: lcupos on tercile x year, program FE
reghdfe lcupos ib2007.ao_proceso#i.va_t, absorb(code_h) vce(cluster code_h)
* same, net of field-specific trends
reghdfe lcupos ib2007.ao_proceso#i.va_t, absorb(code_h field_group#ao_proceso) ///
    vce(cluster code_h)

log close
