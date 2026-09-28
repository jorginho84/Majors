/**********************************************************************
* 03_build_shocks_exposure.do
*
* Design III — vacancy shocks at source programs j and exposure of
* incumbent programs k, with the similarity measures of Design II.
*
* Shock (main definition, agreed in issue #2):
*   dlogV_jt = log V_jt - log V_j,t-1 is in the top 20% of the pooled
*   distribution of positive changes, and the increase is "sudden":
*     (a) j existed two years before (V_j,t-2 observed),
*     (b) j was not in the top 20% in t-1,
*     (c) the increase is not reversed in t+1 (dlogV_j,t+1 > -0.5 dlogV_jt).
*   SUA entrants are never shock sources. Shocks are dated 2010-2016.
*   Vacancies: DEMRE Oferta Académica, regular admission (VACANTES_1SEM).
*
* Robustness definitions (tag): main, p90, p75, within, nosud, lev,
*   ind (CNED INDICES vacancies), adm (regular admissions).
*
* Exposure of k in year t (seats_jt = (V_jt - V_j,t-1) * shock_jt):
*
*   Market kernels, field definition f, kernel w in {tot, tri, gau}:
*     E^{w,f}_kt = 100 * sum_{j in m_f(k), j != k} w(k,j) seats_jt / T_{m_f(k)}
*     T_m = market first-year enrollment, 2007-2009  -> percentage points
*
*   Decomposition (as in Design II): cumE^{w} = cumM * Q^{w},
*     M = cumE^{tot} (seats added in the market, share of market size)
*     Q^{w} = cumE^{w} / cumE^{tot}   (seat-weighted similarity, in [0,1])
*
*   Cosine, d in {psu, psuR, psuRF, psu_pR, psu_pRF}:
*     E^{d}_kt = sum_{j != k} cos^d(k,j) * seats_jt / sum_{j,s} seats_js
*     (weights sum to one over all main shocks 2010-2016, as the entrant
*      enrollment weights of Design II sum to one over entrants)
*
*   cum* = cumulative sum since 2010: the time-varying analogue of E x Post.
*
* Event-study cohorts (first year of treatment, 0 = never):
*   g_mkt    first main shock at another program in k's broad market
*   g_close  first such shock with |S_k - S_j| < 50 (triangular support)
*   g_cos    first main shock at one of k's five highest-cosine programs
*
* Inputs:  vs_program_year_2007_2016.dta, vs_similarity_pairs.dta, vs_markets.dta
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

merge m:1 code_h using "$processed/vs_markets.dta", keep(master match) nogen

tempfile panel shocks
save `panel'

keep code_h ao_proceso seats_*
egen double any = rowtotal(seats_*)
keep if any > 0
drop any
rename code_h j
save `shocks'

* total seats added by main shocks, 2010-2016 (cosine weights)
quietly summarize seats_main
local seats_total = r(sum)
di as text "Total seats added by main shocks: " as result `seats_total'


/**********************************************************************
* 2. Pairwise exposure: sum over sources j of w(k,j) * seats_jt
**********************************************************************/

use "$processed/vs_similarity_pairs.dta", clear
joinby j using `shocks'

* market kernels x field definitions, main shock definition
foreach f in broad isced generic {
    foreach w in tot tri gau {
        gen double num_`w'_`f' = s_`w'_`f' * seats_main
    }
}
* cosine measures, main shock definition
foreach d in psu psuR psuRF psu_pR psu_pRF {
    gen double num_cos_`d' = cos_`d' * seats_main
}
* Total and Gaussian broad-market exposure across shock definitions
foreach t of local tags {
    if "`t'" == "main" continue
    gen double num_tot_broad_`t' = s_tot_broad * seats_`t'
    gen double num_gau_broad_`t' = s_gau_broad * seats_`t'
}
* close-competitor shock indicator (triangular support, broad market)
gen byte close_shock = s_tri_broad > 0 & seats_main > 0
gen byte mkt_shock   = s_tot_broad > 0 & seats_main > 0

collapse (sum) num_* (max) close_shock mkt_shock, by(k ao_proceso)
rename k code_h
tempfile pairexp
save `pairexp'


/**********************************************************************
* 3. Exposure of each k
**********************************************************************/

use `panel', clear
merge 1:1 code_h ao_proceso using `pairexp', keep(master match) nogen

foreach v of varlist num_* {
    replace `v' = 0 if missing(`v')
}
foreach v in close_shock mkt_shock {
    replace `v' = 0 if missing(`v')
}

* market-based measures: percentage points of market pre-period enrollment
foreach v of varlist num_tot_* num_tri_* num_gau_* {
    local f = cond(strpos("`v'", "_isced"), "isced", cond(strpos("`v'", "_generic"), "generic", "broad"))
    local e = subinstr("`v'", "num_", "E_", 1)
    gen double `e' = 100 * `v' / T_`f' if T_`f' > 0
}
* cosine: weights sum to one over all main-shock seats
foreach d in psu psuR psuRF psu_pR psu_pRF {
    gen double E_cos_`d' = num_cos_`d' / `seats_total'
}
drop num_*

foreach v of varlist E_* {
    bys pid (ao_proceso): gen double cum`v' = sum(`v')
    replace cum`v' = . if missing(`v')
}

* conditional similarity Q = cumE^w / cumE^tot, market measures
foreach f in broad isced generic {
    foreach w in tri gau {
        gen double Q_`w'_`f' = cumE_`w'_`f' / cumE_tot_`f' if cumE_tot_`f' > 0
    }
    gen byte D_mkt_`f' = cumE_tot_`f' > 0 if !missing(cumE_tot_`f')
    bys pid: egen double M_`f'_2016 = max(cumE_tot_`f')
}

label var cumE_tot_broad "Cumulative seats added in market (pp of market size)"
label var cumE_tri_broad "Cumulative triangular-weighted seats (pp)"
label var cumE_gau_broad "Cumulative Gaussian-weighted seats (pp)"

* own shocks are a confounder for k's enrollment: control for them
bys pid (ao_proceso): gen int own_cumshock = sum(shock_main)
label var own_cumshock "Own vacancy shocks to date"


/**********************************************************************
* 4. Event-study cohorts
**********************************************************************/

* top-5 cosine neighbors (PSU bins) of each k
preserve
use k j cos_psu using "$processed/vs_similarity_pairs.dta", clear
gsort k -cos_psu
by k: keep if _n <= 5
keep k j
tempfile top5
save `top5'
use `shocks', clear
keep j ao_proceso seats_main
keep if seats_main > 0
joinby j using `top5'
gen byte cos_shock = 1
collapse (max) cos_shock, by(k ao_proceso)
rename k code_h
tempfile nbr
save `nbr'
restore
merge 1:1 code_h ao_proceso using `nbr', keep(master match) nogen
replace cos_shock = 0 if missing(cos_shock)

foreach t in mkt close cos {
    bys pid: egen int g_`t' = min(cond(`t'_shock == 1, ao_proceso, .))
    replace g_`t' = 0 if missing(g_`t')
    gen int rel_`t' = ao_proceso - g_`t' if g_`t' > 0
}
label var g_mkt   "First shock at another program in k's broad market (0 = never)"
label var g_close "First shock in market with |S_k - S_j| < 50 (0 = never)"
label var g_cos   "First shock at one of k's top-5 cosine programs (0 = never)"


/**********************************************************************
* 5. Outcomes and samples
**********************************************************************/

gen double lnN = ln(N_first) if N_first > 0
label var lnN "Log first-year enrollment"

gen byte est_sample = N_first_pre > 0 & !missing(psu_first_pre) ///
    & entrant_2012 != 1 & !missing(mkt_broad)
label var est_sample "Incumbent k with 2007-2009 enrollment and PSU"

gen byte min10 = N_first_pre >= 10
label var min10 "Mean first-year enrollment 2007-2009 >= 10"

gen byte psu_group = cond(psu_first_pre < 550, 1, cond(psu_first_pre < 650, 2, 3)) ///
    if !missing(psu_first_pre)
label define psug 1 "PSU < 550" 2 "PSU 550-649" 3 "PSU >= 650"
label values psu_group psug

foreach t in mkt close cos {
    di as text _n "Cohorts, g_`t'"
    tab g_`t' if est_sample & ao_proceso == 2016
}

compress
save "$processed/vs_panel_exposure.dta", replace
di as result "vs_panel_exposure.dta saved."
