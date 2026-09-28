/**********************************************************************
* 03_build_shocks_exposure.do
*
* Design III — vacancy shocks at source programs j and exposure of
* incumbent programs k.
*
* Shock (main definition, agreed in issue #2):
*   dlogV_jt = log V_jt - log V_j,t-1 is in the top 20% of the pooled
*   distribution of positive changes, and the increase is "sudden":
*     (a) j existed two years before (V_j,t-2 observed),
*     (b) j was not in the top 20% in t-1,
*     (c) the increase is not reversed in t+1 (dlogV_j,t+1 > -0.5 dlogV_jt).
*   SUA entrants are never shock sources. Shocks are dated 2010-2016,
*   after the 2007-2009 window used to measure similarity.
*
* Vacancies: regular-admission vacancies from DEMRE Oferta Académica
* (VACANTES_1SEM), the seats DEMRE fills in the regular process.
*
* Robustness definitions (tag):
*   main    DEMRE vacancies, p80, sudden
*   p90     top 10%
*   p75     top 25%
*   within  p80 computed within year
*   nosud   p80, without the sudden conditions
*   lev     p80 of level changes dV instead of dlogV
*   ind     vacancies from CNED INDICES (all admission routes)
*   adm     vacancies proxied by regular admissions (status 24)
*
* Exposure of k (seats added by close competitors, per own seat):
*
*   E_kt = sum_j s(k<-j) * seats_jt / N_first_pre_k,
*   seats_jt = (V_jt - V_j,t-1) * shock_jt
*
*   Similarity s: ROL measures from 02 (s_rol main; s_adj, s_top2,
*   s_colist), plus a market benchmark: s = 1 for j in k's field x region.
*
* Event-study treatment: first year in which E_kt (main) is in the top
* quartile of positive exposures -> cohort g_k (0 = never).
*
* Inputs:  $processed/vs_program_year_2007_2016.dta
*          $processed/vs_rol_similarity.dta
* Output:  $processed/vs_panel_exposure.dta
**********************************************************************/

do "code/config.do"

local shock_y0 = 2010

capture program drop make_shock
program define make_shock
    syntax, v(varname) tag(name) [pct(real 80) within sudden levels]

    tempvar ch pos thr top
    if "`levels'" != "" gen double `ch' = `v' - L.`v'
    else                gen double `ch' = ln(`v') - ln(L.`v')

    gen byte `pos' = `ch' > 0 & !missing(`ch') & entrant_2012 != 1

    gen double `thr' = .
    if "`within'" == "" {
        _pctile `ch' if `pos' & inrange(ao_proceso, 2008, 2016), p(`pct')
        replace `thr' = r(r1)
        di as text "  [`tag'] threshold (pooled p`pct') = " as result %6.3f r(r1)
    }
    else {
        forvalues y = 2008/2016 {
            quietly _pctile `ch' if `pos' & ao_proceso == `y', p(`pct')
            quietly replace `thr' = r(r1) if ao_proceso == `y'
        }
        di as text "  [`tag'] threshold computed within year (p`pct')"
    }

    gen byte `top' = `pos' & `ch' >= `thr'
    gen byte shock_`tag' = `top'

    if "`sudden'" != "" {
        replace shock_`tag' = 0 if missing(L2.`v')
        replace shock_`tag' = 0 if L.`top' == 1
        replace shock_`tag' = 0 if !missing(F.`ch') & F.`ch' <= -0.5 * `ch'
    }

    replace shock_`tag' = 0 if ao_proceso < $shock_y0
    gen double seats_`tag' = (`v' - L.`v') * shock_`tag'
    replace seats_`tag' = 0 if missing(seats_`tag')

    label var shock_`tag' "Vacancy shock at program (`tag')"
    label var seats_`tag' "Seats added in shock (`tag')"

    quietly count if shock_`tag'
    di as text "  [`tag'] shocks, `=$shock_y0'-2016: " as result r(N)
end


/**********************************************************************
* 1. Shocks at every program (all are potential sources j)
**********************************************************************/

use "$processed/vs_program_year_2007_2016.dta", clear
xtset pid ao_proceso

global shock_y0 = `shock_y0'

gen double V_dem = vac_demre   if vac_demre   > 0
gen double V_ind = vac_indices if vac_indices > 0
gen double V_adm = n_admitted  if n_admitted  > 0
gen double dlogV     = ln(V_dem) - ln(L.V_dem)
gen double dlogV_ind = ln(V_ind) - ln(L.V_ind)
gen double dlogV_adm = ln(V_adm) - ln(L.V_adm)
label var dlogV     "Change in log regular vacancies (DEMRE)"
label var dlogV_ind "Change in log vacancies (INDICES)"
label var dlogV_adm "Change in log regular admissions"

make_shock, v(V_dem) tag(main)   pct(80) sudden
make_shock, v(V_dem) tag(p90)    pct(90) sudden
make_shock, v(V_dem) tag(p75)    pct(75) sudden
make_shock, v(V_dem) tag(within) pct(80) sudden within
make_shock, v(V_dem) tag(nosud)  pct(80)
make_shock, v(V_dem) tag(lev)    pct(80) sudden levels
make_shock, v(V_ind) tag(ind)    pct(80) sudden
make_shock, v(V_adm) tag(adm)    pct(80) sudden

local tags main p90 p75 within nosud lev ind adm

tempfile panel shocks
save `panel'


/**********************************************************************
* 2. ROL exposure: sum over sources j of s(k<-j) * seats_jt
**********************************************************************/

keep code_h ao_proceso seats_*
egen double any = rowtotal(seats_*)
keep if any > 0
drop any
rename code_h j
save `shocks'

use "$processed/vs_rol_similarity.dta", clear
joinby j using `shocks'

* main shock definition across similarity variants
foreach s in rol adj top2 colist {
    gen double num_`s'_main = s_`s' * seats_main
}
* ROL similarity across shock definitions
foreach t of local tags {
    if "`t'" != "main" gen double num_rol_`t' = s_rol * seats_`t'
}
collapse (sum) num_*, by(k ao_proceso)
rename k code_h
tempfile rolexp
save `rolexp'


/**********************************************************************
* 3. Market benchmark: seats added elsewhere in k's field x region
**********************************************************************/

use `panel', clear
keep code_h ao_proceso field region seats_main
drop if missing(field) | missing(region)
bys field region ao_proceso: egen double mkt_seats = total(seats_main)
gen double num_mkt_main = mkt_seats - seats_main
keep code_h ao_proceso num_mkt_main
tempfile mktexp
save `mktexp'


/**********************************************************************
* 4. Exposure of each k, normalized by pre-period size
**********************************************************************/

use `panel', clear
merge 1:1 code_h ao_proceso using `rolexp', keep(master match) nogen
merge 1:1 code_h ao_proceso using `mktexp', keep(master match) nogen

* k must have been in the 2007-2009 lists to carry ROL similarity
preserve
use k n_list using "$processed/vs_rol_similarity.dta", clear
bys k: keep if _n == 1
rename k code_h
tempfile inlists
save `inlists'
restore
merge m:1 code_h using `inlists', keep(master match) gen(_inl)
gen byte in_lists = _inl == 3
drop _inl

foreach v of varlist num_* {
    replace `v' = 0 if missing(`v')
    local e = subinstr("`v'", "num_", "E_", 1)
    gen double `e' = `v' / N_first_pre if N_first_pre > 0
    bys pid (ao_proceso): gen double cum`e' = sum(`e')
    replace cum`e' = . if missing(`e')
}
drop num_*

label var E_rol_main    "ROL exposure: competitor seats added per own seat"
label var cumE_rol_main "Cumulative ROL exposure since 2010"

* own shocks are a confounder for k's enrollment: control for them
bys pid (ao_proceso): gen int own_cumshock = sum(shock_main)
label var own_cumshock "Own vacancy shocks to date"


/**********************************************************************
* 5. Event-study cohorts: first high-exposure year
**********************************************************************/

* Similarity is dense (hundreds of neighbors per k), so almost every k has
* some positive exposure every year. Three treatment definitions, from
* loose to strict, all reported:
*   g        E_rol_main in the top quartile of positive exposures (p75)
*   g_p90    E_rol_main in the top decile of positive exposures
*   g_nbr5   a main shock at one of k's five most ROL-similar programs

foreach p in 75 90 {
    _pctile E_rol_main if E_rol_main > 0 & in_lists, p(`p')
    local hi`p' = r(r1)
    di as text "High-exposure threshold (p`p' of positive E): " as result %8.4f `hi`p''
}

gen byte high = E_rol_main >= `hi75' & E_rol_main < . & in_lists
gen byte high_p90 = E_rol_main >= `hi90' & E_rol_main < . & in_lists

* top-5 neighbor shock
preserve
use k j s_rol using "$processed/vs_rol_similarity.dta", clear
gsort k -s_rol
by k: keep if _n <= 5
keep k j
tempfile top5
save `top5'
use `shocks', clear
keep j ao_proceso seats_main
keep if seats_main > 0
joinby j using `top5'
gen byte high_nbr5 = 1
collapse (max) high_nbr5, by(k ao_proceso)
rename k code_h
tempfile nbr5
save `nbr5'
restore
merge 1:1 code_h ao_proceso using `nbr5', keep(master match) nogen
replace high_nbr5 = 0 if missing(high_nbr5) | !in_lists

foreach t in "" _p90 _nbr5 {
    local h = cond("`t'" == "", "high", "high`t'")
    bys pid: egen int g`t' = min(cond(`h', ao_proceso, .))
    replace g`t' = 0 if missing(g`t')
    gen int rel`t' = ao_proceso - g`t' if g`t' > 0
}
label var high      "High ROL exposure this year (p75)"
label var high_p90  "High ROL exposure this year (p90)"
label var high_nbr5 "Shock at one of k's top-5 ROL neighbors this year"
label var g         "First high-exposure year, p75 (0 = never)"
label var g_p90     "First high-exposure year, p90 (0 = never)"
label var g_nbr5    "First top-5-neighbor shock year (0 = never)"
label var rel       "Years since first high exposure (p75)"


/**********************************************************************
* 6. Outcomes and estimation sample
**********************************************************************/

gen double lnN = ln(N_first) if N_first > 0
label var lnN "Log first-year enrollment"

gen byte est_sample = in_lists & N_first_pre > 0 & entrant_2012 != 1 ///
    & !missing(field, region)
label var est_sample "Incumbent k in 2007-2009 lists with pre-period enrollment"

foreach t in g g_p90 g_nbr5 {
    di as text _n "Cohorts, `t'"
    tab `t' if est_sample & ao_proceso == 2016
}

compress
save "$processed/vs_panel_exposure.dta", replace
di as result "vs_panel_exposure.dta saved."
