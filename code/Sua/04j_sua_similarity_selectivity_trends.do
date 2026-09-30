/*******************************************************************************
04j_sua_similarity_selectivity_trends.do

PURPOSE

Test whether the conditional-similarity first stage (04e) separates
proximity to entrants from selectivity-specific enrollment trends.

Within a market, entrants sit in a given PSU range, so conditional
similarity Q_p^k is a non-monotonic function of the incumbent's own
pre-treatment selectivity S_p. Program FE absorb the level of S_p but not
post-2012 trends that differ by S_p. If mid-selectivity programs lost
enrollment after 2012 for other reasons, Q would pick that up.

SAMPLE (as in 04e)

    Broad field x pre-treatment region markets with entrant presence
    (M_m > 0), N_firstyear > 0, programs observed before and after 2012.

MODELS

    Levels:  N_pt      = beta [10 x Q_p^k x Post_t] + controls + FE + e_pt
    Logs:    log N_pt  = beta [log_tilde(Q_p^k) x Post_t]
                       + theta [1(Q_p^k > 0) x Post_t] + controls + FE + e_pt

SPECIFICATIONS

    1  base   Program + field x year + region x year FE (04e, deck table)
    2  dec    (1) + S_p decile x year FE
    3  poly   (1) + S_p x year and S_p^2 x year
    4  mkt    Program + market x year FE (absorbs M_m x year entirely)
    5  mktdec (4) + S_p decile x year FE

Event studies (Q x year, 2011 omitted) for specifications 1, 2, 4 and 5
report the joint pretrend p-value for 2007-2010.

Standard errors clustered by pre-treatment market. S_p is inc_psu_pre,
the incumbent's 2009-2011 mean PSU score.

OUTPUTS

    $output/tables/sua_q_selectivity_trends.tex
    $output/sua_q_event_study_selectivity_trends.png
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"

capture which reghdfe
if _rc {
    display as error "reghdfe is not installed."
    exit 199
}


/*******************************************************************************
1. SAMPLE (as in 04e)
*******************************************************************************/

use "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta", clear

keep if inrange(ao_proceso, 2007, 2016)

drop if missing( ///
    program_id, ao_proceso, field_pre, geo_pre, market_pre, ///
    N_firstyear_incumbent, exp_unw, exp_tri50, exp_gau50)

keep if exp_unw > 0

gen double q_tri = exp_tri50 / exp_unw
gen double q_gau = exp_gau50 / exp_unw

keep if N_firstyear_incumbent > 0

bysort program_id: egen byte has_pre  = max(ao_proceso <= 2011)
bysort program_id: egen byte has_post = max(ao_proceso >= 2012)
keep if has_pre == 1 & has_post == 1
drop has_pre has_post

isid program_id ao_proceso
assert post2012 == inrange(ao_proceso, 2012, 2016)

gen double ln_N = ln(N_firstyear_incumbent)


/*******************************************************************************
2. SELECTIVITY CONTROLS
*******************************************************************************/

assert !missing(inc_psu_pre)
bysort program_id (ao_proceso): assert inc_psu_pre == inc_psu_pre[1]

/*
Deciles of S_p across programs (one observation per program).
*/

egen byte tag_program = tag(program_id)
xtile sel_decile_p = inc_psu_pre if tag_program, nquantiles(10)
bysort program_id (sel_decile_p): replace sel_decile_p = sel_decile_p[1]
rename sel_decile_p sel_decile
assert !missing(sel_decile)

tabstat inc_psu_pre if tag_program, by(sel_decile) statistics(n min max)

/*
Q as a function of S_p: shows how far the two are from orthogonal.
*/

foreach k in tri gau {
    correlate q_`k' inc_psu_pre if tag_program
    reg q_`k' c.inc_psu_pre##c.inc_psu_pre if tag_program
    display "R2 of Q_`k' on S_p, S_p^2 = " %6.3f e(r2)
    areg q_`k' c.inc_psu_pre##c.inc_psu_pre if tag_program, absorb(market_pre)
    display "R2 of Q_`k' on S_p, S_p^2 + market FE = " %6.3f e(r2)
}

tabstat q_tri q_gau if tag_program, by(sel_decile) statistics(mean)

egen long field_year  = group(field_pre ao_proceso)
egen long region_year = group(geo_pre ao_proceso)
egen long mkt_year    = group(market_pre ao_proceso)
egen long decile_year = group(sel_decile ao_proceso)

summarize inc_psu_pre if tag_program, meanonly
gen double s_c  = (inc_psu_pre - r(mean)) / 100
gen double s_c2 = s_c^2

local poly_controls ""
forvalues y = 2007/2016 {
    if `y' != 2011 {
        gen double s1_`y' = s_c  * (ao_proceso == `y')
        gen double s2_`y' = s_c2 * (ao_proceso == `y')
        local poly_controls "`poly_controls' s1_`y' s2_`y'"
    }
}

local fe_base   "program_id field_year region_year"
local fe_dec    "program_id field_year region_year decile_year"
local fe_poly   "program_id field_year region_year"
local fe_mkt    "program_id mkt_year"
local fe_mktdec "program_id mkt_year decile_year"

local x_base   ""
local x_dec    ""
local x_poly   "`poly_controls'"
local x_mkt    ""
local x_mktdec ""


/*******************************************************************************
3. REGRESSORS
*******************************************************************************/

foreach k in tri gau {

    gen byte   pos_`k'   = q_`k' > 0
    gen double lvl_`k'   = 10 * q_`k' * post2012
    gen double log_`k'   = cond(pos_`k', ln(q_`k'), 0) * post2012
    gen byte   Dpost_`k' = pos_`k' * post2012

    local es_`k' ""
    forvalues y = 2007/2016 {
        if `y' != 2011 {
            gen double es_`k'_`y' = 10 * q_`k' * (ao_proceso == `y')
            local es_`k' "`es_`k'' es_`k'_`y'"
        }
    }
}


/*******************************************************************************
4. STATIC FIRST STAGES
*******************************************************************************/

tempfile results
tempname handle

postfile `handle' str6 model str8 spec str4 q ///
    double beta double se double p long N long programs ///
    using `results', replace

foreach model in lvl log {

    local outcome = cond("`model'" == "lvl", "N_firstyear_incumbent", "ln_N")

    foreach spec in base dec poly mkt mktdec {

        foreach k in tri gau {

            local regressors "lvl_`k'"
            if "`model'" == "log" local regressors "log_`k' Dpost_`k'"

            display ""
            display "=== `model' | `spec' | Q_`k' ==="

            reghdfe `outcome' `regressors' `x_`spec'', ///
                absorb(`fe_`spec'') vce(cluster market_pre)

            quietly test `model'_`k'
            local p = r(p)

            quietly levelsof program_id if e(sample), local(pl)
            local np : word count `pl'

            post `handle' ("`model'") ("`spec'") ("`k'") ///
                (_b[`model'_`k']) (_se[`model'_`k']) (`p') (e(N)) (`np')
        }
    }
}


/*******************************************************************************
5. EVENT STUDIES (LEVELS): PRETREND TESTS
*******************************************************************************/

tempfile es_coefs
tempname es_handle

postfile `es_handle' str8 spec str4 q int year ///
    double b double lb double ub using `es_coefs', replace

foreach spec in base dec mkt mktdec {

    foreach k in tri gau {

        display ""
        display "=== event study | `spec' | Q_`k' ==="

        reghdfe N_firstyear_incumbent `es_`k'' `x_`spec'', ///
            absorb(`fe_`spec'') vce(cluster market_pre)

        test es_`k'_2007 es_`k'_2008 es_`k'_2009 es_`k'_2010
        local p = r(p)

        local post_mean = (_b[es_`k'_2012] + _b[es_`k'_2013] + ///
            _b[es_`k'_2014] + _b[es_`k'_2015] + _b[es_`k'_2016]) / 5

        post `handle' ("es") ("`spec'") ("`k'") ///
            (`post_mean') (.) (`p') (e(N)) (.)

        local cv = invttail(e(df_r), 0.025)

        forvalues y = 2007/2016 {
            if `y' == 2011 {
                post `es_handle' ("`spec'") ("`k'") (`y') (0) (.) (.)
            }
            else {
                post `es_handle' ("`spec'") ("`k'") (`y') ///
                    (_b[es_`k'_`y']) ///
                    (_b[es_`k'_`y'] - `cv' * _se[es_`k'_`y']) ///
                    (_b[es_`k'_`y'] + `cv' * _se[es_`k'_`y'])
            }
        }
    }
}

postclose `handle'
postclose `es_handle'


/*******************************************************************************
6. SUMMARY
*******************************************************************************/

use `results', clear

format beta se %9.3f
format p %9.4f

display ""
display "Static first stages: beta, SE, p. Event studies: mean 2012-16 coefficient"
display "(beta) and joint pretrend p-value (p)."

list model spec q beta se p N programs, sepby(model spec) noobs clean


/*******************************************************************************
7. LATEX TABLE
*******************************************************************************/

capture program drop stars
program define stars
    args p name
    local s ""
    if `p' < 0.10 local s "\sym{*}"
    if `p' < 0.05 local s "\sym{**}"
    if `p' < 0.01 local s "\sym{***}"
    c_local `name' "`s'"
end

forvalues r = 1/`=_N' {
    local key = model[`r'] + "_" + spec[`r'] + "_" + q[`r']
    local b_`key'  = beta[`r']
    local se_`key' = se[`r']
    local p_`key'  = p[`r']
}

file open T using "$output/tables/sua_q_selectivity_trends.tex", write replace
file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{Levels} & \multicolumn{2}{c}{Logs} & \multicolumn{2}{c}{Event study: pretrend \(p\)} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}\cmidrule(lr){6-7}" _n
file write T "Fixed effects & Triangular & Gaussian & Triangular & Gaussian & Triangular & Gaussian \\" _n "\midrule" _n

local lab_base   "Field \(\times\) year \(+\) region \(\times\) year"
local lab_dec    "\quad \(+\) selectivity decile \(\times\) year"
local lab_poly   "\quad \(+\) \(S_p, S_p^2\) \(\times\) year"
local lab_mkt    "Market \(\times\) year"
local lab_mktdec "\quad \(+\) selectivity decile \(\times\) year"

foreach spec in base dec poly mkt mktdec {
    if "`spec'" == "mkt" file write T "\addlinespace" _n
    file write T "`lab_`spec''"
    foreach model in lvl log {
        foreach k in tri gau {
            stars `p_`model'_`spec'_`k'' st
            file write T " & " %6.3f (`b_`model'_`spec'_`k'') "`st'"
        }
    }
    foreach k in tri gau {
        if "`spec'" == "poly" file write T " & --"
        else file write T " & " %5.3f (`p_es_`spec'_`k'')
    }
    file write T " \\" _n
    foreach model in lvl log {
        foreach k in tri gau {
            file write T " & (" %5.3f (`se_`model'_`spec'_`k'') ")"
        }
    }
    file write T " & & \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/*******************************************************************************
8. EVENT-STUDY FIGURE: BASE VS SELECTIVITY-DECILE x YEAR
*******************************************************************************/

use `es_coefs', clear
keep if inlist(spec, "base", "dec")

gen double x = year + cond(spec == "base", -0.12, 0.12)

foreach k in tri gau {
    local ttl = cond("`k'" == "tri", "Triangular Q", "Gaussian Q")
    twoway ///
        (rcap lb ub x if q == "`k'" & spec == "base", lcolor(navy%55)) ///
        (rcap lb ub x if q == "`k'" & spec == "dec",  lcolor(maroon%55)) ///
        (scatter b x if q == "`k'" & spec == "base", mcolor(navy) msymbol(O)) ///
        (scatter b x if q == "`k'" & spec == "dec",  mcolor(maroon) msymbol(D)), ///
        xline(2011, lcolor(gs8) lpattern(dash)) yline(0, lcolor(gs7)) ///
        xlabel(2007(1)2016, labsize(small)) ylabel(, labsize(small) angle(horizontal) grid glcolor(gs14)) ///
        xtitle("Year", size(small)) ytitle("Effect of 0.10 of Q on first-year enrollment", size(small)) ///
        title("`ttl'", size(medium) color(black)) ///
        legend(order(3 "Field x year + region x year FE" 4 "+ selectivity decile x year FE") ///
            rows(2) position(6) size(small) region(lcolor(none))) ///
        graphregion(color(white)) plotregion(color(white)) scheme(s1color) ///
        name(g_`k', replace)
}

graph combine g_tri g_gau, rows(1) graphregion(color(white)) xsize(10) ysize(4.5)
graph export "$output/sua_q_event_study_selectivity_trends.png", width(2400) replace
