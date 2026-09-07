/*******************************************************************************
04f_sua_Exposure_Q_Selectivity_FirstStages.do

PURPOSE

Estimate first-stage heterogeneity by incumbent-program selectivity for:

    1. Triangular SUA exposure
    2. Gaussian SUA exposure
    3. Triangular conditional similarity Q
    4. Gaussian conditional similarity Q

Selectivity groups:

    Low:     PSU < 550
    Middle:  550 <= PSU < 650
    High:    PSU >= 650

EXPOSURE SPECIFICATIONS

A. Baseline:
       Program FE
     + Broad-field x year FE

B. Region controls:
       Program FE
     + Broad-field x year FE
     + Region x year FE

Q SPECIFICATION

C. Within-market:
       Program FE
     + Market x year FE

Q regressions are restricted to markets with positive entrant exposure.

Scaling:

    Exposure:
        one unit = 10 percentage points

    Q:
        one unit = 0.10 increase in conditional similarity

The output table reports:

    - coefficient
    - standard error
    - p-value
    - F-statistic
    - mean outcome in estimation sample
    - observations
    - programs
    - markets/clusters

INPUT

    $processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta

OUTPUT

    $output/sua_selectivity_first_stages.csv
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
1. LOAD COMMON ANALYTICAL PANEL
*******************************************************************************/

local panel ///
    "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta"

use "`panel'", clear

keep if inrange(ao_proceso, 2007, 2016)

drop if missing( ///
    program_id, ///
    ao_proceso, ///
    field_pre, ///
    geo_pre, ///
    market_pre, ///
    N_firstyear_incumbent, ///
    inc_psu_pre, ///
    exp_unw, ///
    exp_tri50, ///
    exp_gau50 ///
)

isid ///
    program_id ///
    ao_proceso


/*******************************************************************************
2. REQUIRE PRE AND POST OBSERVATIONS
*******************************************************************************/

bysort program_id: ///
    egen byte has_pre = ///
        max(ao_proceso <= 2011)

bysort program_id: ///
    egen byte has_post = ///
        max(ao_proceso >= 2012)

keep if ///
    has_pre == 1 & ///
    has_post == 1

drop ///
    has_pre ///
    has_post


/*******************************************************************************
3. VERIFY PREDETERMINED CHARACTERISTICS
*******************************************************************************/

foreach v in ///
    exp_unw ///
    exp_tri50 ///
    exp_gau50 ///
    inc_psu_pre ///
    field_pre ///
    geo_pre ///
    market_pre {

    bysort program_id (ao_proceso): ///
        assert `v' == `v'[1]
}


/*******************************************************************************
4. SELECTIVITY GROUPS
*******************************************************************************/

gen byte sel_group = .

replace sel_group = 1 ///
    if inc_psu_pre < 550

replace sel_group = 2 ///
    if ///
        inc_psu_pre >= 550 & ///
        inc_psu_pre < 650

replace sel_group = 3 ///
    if inc_psu_pre >= 650

assert !missing(sel_group)


label define sel_lbl ///
    1 "PSU < 550" ///
    2 "PSU 550-649" ///
    3 "PSU >= 650"

label values sel_group sel_lbl


display ""
display "============================================================"
display " SELECTIVITY GROUPS"
display "============================================================"

preserve

    bysort program_id (ao_proceso): ///
        keep if _n == 1

    tabulate sel_group

    summarize inc_psu_pre, detail

restore


/*******************************************************************************
5. POST INDICATOR
*******************************************************************************/

gen byte post_sua = ///
    inrange(ao_proceso, 2012, 2016)


/*******************************************************************************
6. FIXED-EFFECT IDENTIFIERS
*******************************************************************************/

egen long fe_fldyr = ///
    group( ///
        field_pre ///
        ao_proceso ///
    )

egen long fe_regyr = ///
    group( ///
        geo_pre ///
        ao_proceso ///
    )

egen long fe_mktyr = ///
    group( ///
        market_pre ///
        ao_proceso ///
    )


/*******************************************************************************
7. CONDITIONAL SIMILARITY Q
*******************************************************************************/

gen byte has_entry = ///
    exp_unw > 0


gen double q_tri = .

replace q_tri = ///
    exp_tri50 / exp_unw ///
    if has_entry == 1


gen double q_gau = .

replace q_gau = ///
    exp_gau50 / exp_unw ///
    if has_entry == 1


label variable q_tri ///
    "Triangular conditional similarity"

label variable q_gau ///
    "Gaussian conditional similarity"


/*******************************************************************************
8. VERIFY EXPOSURE DECOMPOSITION
*******************************************************************************/

assert ///
    reldif( ///
        exp_tri50, ///
        exp_unw * q_tri ///
    ) < 1e-8 ///
    if has_entry == 1


assert ///
    reldif( ///
        exp_gau50, ///
        exp_unw * q_gau ///
    ) < 1e-8 ///
    if has_entry == 1


assert exp_tri50 == 0 ///
    if has_entry == 0

assert exp_gau50 == 0 ///
    if has_entry == 0


/*******************************************************************************
9. FIRST-STAGE REGRESSORS
*******************************************************************************/

/*
Exposure:
one unit = 10 percentage points.
*/

gen double x_exp_tri = ///
    10 * exp_tri50 * post_sua

gen double x_exp_gau = ///
    10 * exp_gau50 * post_sua


/*
Conditional similarity Q:
one unit = 0.10 increase in Q.
*/

gen double x_q_tri = ///
    10 * q_tri * post_sua ///
    if has_entry == 1

gen double x_q_gau = ///
    10 * q_gau * post_sua ///
    if has_entry == 1


/*******************************************************************************
10. RESULT FILE
*******************************************************************************/

tempfile results
tempname handle

postfile `handle' ///
    byte sel_group ///
    str15 sel_label ///
    str12 family ///
    str12 spec ///
    str12 measure ///
    double beta ///
    double se ///
    double pvalue ///
    double fst_F ///
    double ymean ///
    long obs ///
    long programs ///
    long markets ///
    using `results', ///
    replace


/*******************************************************************************
11. LOOP OVER SELECTIVITY GROUPS
*******************************************************************************/

forvalues g = 1/3 {


    /***************************************************************************
    GROUP LABEL
    ***************************************************************************/

    if `g' == 1 {
        local grp_lbl "PSU < 550"
    }

    if `g' == 2 {
        local grp_lbl "PSU 550-649"
    }

    if `g' == 3 {
        local grp_lbl "PSU >= 650"
    }


    display ""
    display "============================================================"
    display " SELECTIVITY: `grp_lbl'"
    display "============================================================"


    /***************************************************************************
    A1. TRIANGULAR EXPOSURE — BASELINE
    ***************************************************************************/

    reghdfe ///
        N_firstyear_incumbent ///
        x_exp_tri ///
        if sel_group == `g', ///
        absorb( ///
            program_id ///
            fe_fldyr ///
        ) ///
        vce(cluster market_pre)

    local b = _b[x_exp_tri]
    local s = _se[x_exp_tri]

    test x_exp_tri

    local F = r(F)
    local p = r(p)
    local N = e(N)

    quietly summarize ///
        N_firstyear_incumbent ///
        if e(sample), ///
        meanonly

    local ybar = r(mean)

    capture drop tag_prog tag_mkt

    egen byte tag_prog = ///
        tag(program_id) ///
        if e(sample)

    quietly count if tag_prog == 1
    local P = r(N)

    egen byte tag_mkt = ///
        tag(market_pre) ///
        if e(sample)

    quietly count if tag_mkt == 1
    local M = r(N)

    drop tag_prog tag_mkt

    post `handle' ///
        (`g') ///
        ("`grp_lbl'") ///
        ("Exposure") ///
        ("Baseline") ///
        ("Triangular") ///
        (`b') ///
        (`s') ///
        (`p') ///
        (`F') ///
        (`ybar') ///
        (`N') ///
        (`P') ///
        (`M')


    /***************************************************************************
    A2. GAUSSIAN EXPOSURE — BASELINE
    ***************************************************************************/

    reghdfe ///
        N_firstyear_incumbent ///
        x_exp_gau ///
        if sel_group == `g', ///
        absorb( ///
            program_id ///
            fe_fldyr ///
        ) ///
        vce(cluster market_pre)

    local b = _b[x_exp_gau]
    local s = _se[x_exp_gau]

    test x_exp_gau

    local F = r(F)
    local p = r(p)
    local N = e(N)

    quietly summarize ///
        N_firstyear_incumbent ///
        if e(sample), ///
        meanonly

    local ybar = r(mean)

    capture drop tag_prog tag_mkt

    egen byte tag_prog = ///
        tag(program_id) ///
        if e(sample)

    quietly count if tag_prog == 1
    local P = r(N)

    egen byte tag_mkt = ///
        tag(market_pre) ///
        if e(sample)

    quietly count if tag_mkt == 1
    local M = r(N)

    drop tag_prog tag_mkt

    post `handle' ///
        (`g') ///
        ("`grp_lbl'") ///
        ("Exposure") ///
        ("Baseline") ///
        ("Gaussian") ///
        (`b') ///
        (`s') ///
        (`p') ///
        (`F') ///
        (`ybar') ///
        (`N') ///
        (`P') ///
        (`M')


    /***************************************************************************
    B1. TRIANGULAR EXPOSURE — REGION x YEAR
    ***************************************************************************/

    reghdfe ///
        N_firstyear_incumbent ///
        x_exp_tri ///
        if sel_group == `g', ///
        absorb( ///
            program_id ///
            fe_fldyr ///
            fe_regyr ///
        ) ///
        vce(cluster market_pre)

    local b = _b[x_exp_tri]
    local s = _se[x_exp_tri]

    test x_exp_tri

    local F = r(F)
    local p = r(p)
    local N = e(N)

    quietly summarize ///
        N_firstyear_incumbent ///
        if e(sample), ///
        meanonly

    local ybar = r(mean)

    capture drop tag_prog tag_mkt

    egen byte tag_prog = ///
        tag(program_id) ///
        if e(sample)

    quietly count if tag_prog == 1
    local P = r(N)

    egen byte tag_mkt = ///
        tag(market_pre) ///
        if e(sample)

    quietly count if tag_mkt == 1
    local M = r(N)

    drop tag_prog tag_mkt

    post `handle' ///
        (`g') ///
        ("`grp_lbl'") ///
        ("Exposure") ///
        ("Region-year") ///
        ("Triangular") ///
        (`b') ///
        (`s') ///
        (`p') ///
        (`F') ///
        (`ybar') ///
        (`N') ///
        (`P') ///
        (`M')


    /***************************************************************************
    B2. GAUSSIAN EXPOSURE — REGION x YEAR
    ***************************************************************************/

    reghdfe ///
        N_firstyear_incumbent ///
        x_exp_gau ///
        if sel_group == `g', ///
        absorb( ///
            program_id ///
            fe_fldyr ///
            fe_regyr ///
        ) ///
        vce(cluster market_pre)

    local b = _b[x_exp_gau]
    local s = _se[x_exp_gau]

    test x_exp_gau

    local F = r(F)
    local p = r(p)
    local N = e(N)

    quietly summarize ///
        N_firstyear_incumbent ///
        if e(sample), ///
        meanonly

    local ybar = r(mean)

    capture drop tag_prog tag_mkt

    egen byte tag_prog = ///
        tag(program_id) ///
        if e(sample)

    quietly count if tag_prog == 1
    local P = r(N)

    egen byte tag_mkt = ///
        tag(market_pre) ///
        if e(sample)

    quietly count if tag_mkt == 1
    local M = r(N)

    drop tag_prog tag_mkt

    post `handle' ///
        (`g') ///
        ("`grp_lbl'") ///
        ("Exposure") ///
        ("Region-year") ///
        ("Gaussian") ///
        (`b') ///
        (`s') ///
        (`p') ///
        (`F') ///
        (`ybar') ///
        (`N') ///
        (`P') ///
        (`M')


    /***************************************************************************
    C1. TRIANGULAR Q — WITHIN MARKET
    ***************************************************************************/

    reghdfe ///
        N_firstyear_incumbent ///
        x_q_tri ///
        if ///
            sel_group == `g' & ///
            has_entry == 1, ///
        absorb( ///
            program_id ///
            fe_mktyr ///
        ) ///
        vce(cluster market_pre)

    local b = _b[x_q_tri]
    local s = _se[x_q_tri]

    test x_q_tri

    local F = r(F)
    local p = r(p)
    local N = e(N)

    quietly summarize ///
        N_firstyear_incumbent ///
        if e(sample), ///
        meanonly

    local ybar = r(mean)

    capture drop tag_prog tag_mkt

    egen byte tag_prog = ///
        tag(program_id) ///
        if e(sample)

    quietly count if tag_prog == 1
    local P = r(N)

    egen byte tag_mkt = ///
        tag(market_pre) ///
        if e(sample)

    quietly count if tag_mkt == 1
    local M = r(N)

    drop tag_prog tag_mkt

    post `handle' ///
        (`g') ///
        ("`grp_lbl'") ///
        ("Q") ///
        ("Within-mkt") ///
        ("Triangular") ///
        (`b') ///
        (`s') ///
        (`p') ///
        (`F') ///
        (`ybar') ///
        (`N') ///
        (`P') ///
        (`M')


    /***************************************************************************
    C2. GAUSSIAN Q — WITHIN MARKET
    ***************************************************************************/

    reghdfe ///
        N_firstyear_incumbent ///
        x_q_gau ///
        if ///
            sel_group == `g' & ///
            has_entry == 1, ///
        absorb( ///
            program_id ///
            fe_mktyr ///
        ) ///
        vce(cluster market_pre)

    local b = _b[x_q_gau]
    local s = _se[x_q_gau]

    test x_q_gau

    local F = r(F)
    local p = r(p)
    local N = e(N)

    quietly summarize ///
        N_firstyear_incumbent ///
        if e(sample), ///
        meanonly

    local ybar = r(mean)

    capture drop tag_prog tag_mkt

    egen byte tag_prog = ///
        tag(program_id) ///
        if e(sample)

    quietly count if tag_prog == 1
    local P = r(N)

    egen byte tag_mkt = ///
        tag(market_pre) ///
        if e(sample)

    quietly count if tag_mkt == 1
    local M = r(N)

    drop tag_prog tag_mkt

    post `handle' ///
        (`g') ///
        ("`grp_lbl'") ///
        ("Q") ///
        ("Within-mkt") ///
        ("Gaussian") ///
        (`b') ///
        (`s') ///
        (`p') ///
        (`F') ///
        (`ybar') ///
        (`N') ///
        (`P') ///
        (`M')
}


/*******************************************************************************
12. CLOSE RESULT FILE
*******************************************************************************/

postclose `handle'


/*******************************************************************************
13. SUMMARY TABLE
*******************************************************************************/

use `results', clear

sort ///
    sel_group ///
    family ///
    spec ///
    measure


format ///
    beta ///
    se ///
    %9.4f

format ///
    pvalue ///
    %9.4f

format ///
    fst_F ///
    %9.2f

format ///
    ymean ///
    %9.2f

format ///
    obs ///
    programs ///
    markets ///
    %9.0fc


display ""
display "============================================================"
display " SELECTIVITY FIRST-STAGE SUMMARY"
display "============================================================"
display ""

list ///
    sel_label ///
    family ///
    spec ///
    measure ///
    beta ///
    se ///
    pvalue ///
    fst_F ///
    ymean ///
    obs ///
    programs ///
    markets, ///
    noobs clean


/*******************************************************************************
14. MAIN-SPECIFICATION TABLE FOR PRESENTATION
*******************************************************************************/

/*
For the presentation:

    Exposure:
        Region-year specification

    Q:
        Within-market specification

Baseline exposure regressions remain in the complete results file but are
not needed in the main presentation table.
*/

display ""
display "============================================================"
display " MAIN SPECIFICATIONS FOR PRESENTATION"
display "============================================================"
display ""

list ///
    sel_label ///
    family ///
    measure ///
    beta ///
    se ///
    pvalue ///
    fst_F ///
    ymean ///
    obs ///
    programs ///
    markets ///
    if ///
        (family == "Exposure" & spec == "Region-year") | ///
        (family == "Q" & spec == "Within-mkt"), ///
    noobs clean

