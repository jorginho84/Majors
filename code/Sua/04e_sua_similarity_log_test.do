/*******************************************************************************
04e_sua_similarity_log_test.do

PURPOSE

Estimate the logarithmic conditional-similarity first stage within exposed
SUA markets.

DECOMPOSITION

    E_p^k = M_m * Q_p^k

where:

    M_m   = entrant share of total market enrollment
    Q_p^k = PSU similarity with entrants, conditional on entrant presence


MEASURES

    1. Triangular conditional similarity
    2. Gaussian conditional similarity


SAMPLE

    - Broad-field definition
    - Markets with positive entrant presence: M_m > 0
    - Positive first-year enrollment: N_firstyear > 0
    - Economically meaningful Q = 0 observations are retained


LOG TRANSFORMATION

    log_tilde(Q_p^k) =
        log(Q_p^k)     if Q_p^k > 0
        0              if Q_p^k = 0

A separate indicator

    D_p^k = 1(Q_p^k > 0)

is interacted with Post_t and included in the regression.


MODEL

    log(N_firstyear_pt)

        = beta_k [log_tilde(Q_p^k) x Post_t]
        + theta_k [D_p^k x Post_t]
        + program FE
        + Broad-field x year FE
        + pre-treatment region x year FE
        + error_pt


INTERPRETATION

beta_k captures the post-2012 enrollment-similarity elasticity associated
with variation in similarity intensity among programs with positive Q,
while retaining Q = 0 programs in exposed markets.

Standard errors are clustered by the pre-treatment market.

No external results file is created.
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
0. CHECK REQUIRED COMMAND
*******************************************************************************/

capture which reghdfe

if _rc {

    display as error ///
        "reghdfe is not installed."

    display as error ///
        "Run: ssc install reghdfe, replace"

    exit 199
}


/*******************************************************************************
1. INPUT
*******************************************************************************/

local input_panel ///
    "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta"


/*******************************************************************************
2. COMMON PANEL
*******************************************************************************/

use "`input_panel'", clear

keep if ///
    inrange(ao_proceso, 2007, 2016)

drop if missing( ///
    program_id, ///
    ao_proceso, ///
    field_pre, ///
    geo_pre, ///
    market_pre, ///
    N_firstyear_incumbent, ///
    exp_unw, ///
    exp_tri50, ///
    exp_gau50 ///
)

isid ///
    program_id ///
    ao_proceso

assert ///
    N_firstyear_incumbent >= 0

assert ///
    exp_unw >= 0

assert ///
    exp_tri50 >= 0

assert ///
    exp_gau50 >= 0


/*******************************************************************************
3. EXPOSED MARKETS AND CONDITIONAL SIMILARITY
*******************************************************************************/

/*
M_m is the entrant share of total market enrollment.

Q is defined only when M_m > 0.
*/

gen double entrant_share = ///
    exp_unw

keep if ///
    entrant_share > 0

assert ///
    entrant_share > 0


/*
Conditional similarity.
*/

gen double q_tri = ///
    exp_tri50 / entrant_share

gen double q_gau = ///
    exp_gau50 / entrant_share


label variable q_tri ///
    "Triangular similarity conditional on entrants"

label variable q_gau ///
    "Gaussian similarity conditional on entrants"


assert inrange( ///
    q_tri, ///
    0, ///
    1.0000001 ///
)

assert inrange( ///
    q_gau, ///
    0, ///
    1.0000001 ///
)


/*
Verify exact decomposition.
*/

assert ///
    reldif( ///
        exp_tri50, ///
        entrant_share * q_tri ///
    ) < 1e-8

assert ///
    reldif( ///
        exp_gau50, ///
        entrant_share * q_gau ///
    ) < 1e-8


/*
Q must be fixed over time within program.
*/

foreach q_variable in ///
    q_tri ///
    q_gau {

    tempvar q_min q_max

    bysort program_id: ///
        egen double `q_min' = ///
            min(`q_variable')

    bysort program_id: ///
        egen double `q_max' = ///
            max(`q_variable')

    assert ///
        abs( ///
            `q_max' - ///
            `q_min' ///
        ) < 1e-10

    drop ///
        `q_min' ///
        `q_max'
}


/*******************************************************************************
4. LOG OUTCOME SAMPLE
*******************************************************************************/

/*
log(N) requires N > 0.

Q = 0 is NOT removed.
*/

keep if ///
    N_firstyear_incumbent > 0

assert ///
    N_firstyear_incumbent > 0


/*
Require positive-outcome observations before and after 2012.
*/

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

assert _N > 0


/*******************************************************************************
5. POST INDICATOR
*******************************************************************************/

capture confirm variable post2012

if _rc {

    gen byte post2012 = ///
        inrange(ao_proceso, 2012, 2016)
}

assert ///
    post2012 == inrange(ao_proceso, 2012, 2016)

assert ///
    inlist(post2012, 0, 1)


/*******************************************************************************
6. LOG OUTCOME
*******************************************************************************/

gen double ln_enrollment = ///
    ln(N_firstyear_incumbent)

assert ///
    !missing(ln_enrollment)


/*******************************************************************************
7. ZERO-PRESERVING LOG Q
*******************************************************************************/

/*
Positive-Q indicators.
*/

gen byte D_q_tri = ///
    q_tri > 0

gen byte D_q_gau = ///
    q_gau > 0


assert ///
    inlist(D_q_tri, 0, 1)

assert ///
    inlist(D_q_gau, 0, 1)


/*
log_tilde(Q):

    log(Q) if Q > 0
    0      if Q = 0
*/

gen double ln_q_tri = 0

replace ln_q_tri = ///
    ln(q_tri) ///
    if q_tri > 0


gen double ln_q_gau = 0

replace ln_q_gau = ///
    ln(q_gau) ///
    if q_gau > 0


assert ///
    ln_q_tri == 0 ///
    if q_tri == 0

assert ///
    ln_q_gau == 0 ///
    if q_gau == 0


/*******************************************************************************
8. POST INTERACTIONS
*******************************************************************************/

gen double ln_q_tri_post = ///
    ln_q_tri * post2012

gen double ln_q_gau_post = ///
    ln_q_gau * post2012


gen byte D_q_tri_post = ///
    D_q_tri * post2012

gen byte D_q_gau_post = ///
    D_q_gau * post2012


/*
Checks.
*/

assert ///
    ln_q_tri_post == 0 ///
    if ao_proceso <= 2011

assert ///
    ln_q_gau_post == 0 ///
    if ao_proceso <= 2011

assert ///
    D_q_tri_post == 0 ///
    if ao_proceso <= 2011

assert ///
    D_q_gau_post == 0 ///
    if ao_proceso <= 2011


assert ///
    ln_q_tri_post == 0 ///
    if q_tri == 0

assert ///
    ln_q_gau_post == 0 ///
    if q_gau == 0


/*******************************************************************************
9. FIXED-EFFECT IDENTIFIERS
*******************************************************************************/

egen long sim_field_year = ///
    group( ///
        field_pre ///
        ao_proceso ///
    )

egen long sim_region_year = ///
    group( ///
        geo_pre ///
        ao_proceso ///
    )


/*******************************************************************************
10. SAMPLE DIAGNOSTICS
*******************************************************************************/

egen byte tag_program = ///
    tag(program_id)

egen byte tag_market = ///
    tag(market_pre)


display ""
display "============================================================"
display " LOG CONDITIONAL-SIMILARITY SAMPLE"
display "============================================================"


count

display ///
    "Program-year observations = " ///
    %9.0fc r(N)


count if ///
    tag_program == 1

display ///
    "Programs                  = " ///
    %9.0fc r(N)


count if ///
    tag_market == 1

display ///
    "Exposed markets           = " ///
    %9.0fc r(N)


count if ///
    tag_program == 1 & ///
    q_tri == 0

display ///
    "Programs with Q_tri = 0   = " ///
    %9.0fc r(N)


count if ///
    tag_program == 1 & ///
    q_gau == 0

display ///
    "Programs with Q_gau = 0   = " ///
    %9.0fc r(N)


drop ///
    tag_program ///
    tag_market


/*******************************************************************************
11. TEMPORARY RESULTS
*******************************************************************************/

tempfile similarity_log_results
tempname results_handle

postfile `results_handle' ///
    str12 measure ///
    double beta ///
    double se ///
    double F_stat ///
    double p_value ///
    double lower_95 ///
    double upper_95 ///
    double D_beta ///
    double D_se ///
    double D_p ///
    long observations ///
    long programs ///
    long markets ///
    using `similarity_log_results', ///
    replace


/*******************************************************************************
12. LOG Q FIRST STAGES
*******************************************************************************/

foreach measure in ///
    tri ///
    gau {


    if "`measure'" == "tri" {

        local log_post ///
            ln_q_tri_post

        local D_post ///
            D_q_tri_post

        local measure_label ///
            "Triangular"
    }


    if "`measure'" == "gau" {

        local log_post ///
            ln_q_gau_post

        local D_post ///
            D_q_gau_post

        local measure_label ///
            "Gaussian"
    }


    display ""
    display "============================================================"
    display " LOG CONDITIONAL-SIMILARITY FIRST STAGE"
    display "============================================================"

    display ///
        "Measure       = `measure_label'"

    display ///
        "Sample        = Exposed markets; Q = 0 retained"

    display ///
        "Fixed effects = Program + Broad-field x year + region x year"

    display "============================================================"


    reghdfe ///
        ln_enrollment ///
        `log_post' ///
        `D_post', ///
        absorb( ///
            program_id ///
            sim_field_year ///
            sim_region_year ///
        ) ///
        vce(cluster market_pre)


    /*
    Save estimation sample.
    */

    tempvar estimation_sample

    gen byte `estimation_sample' = ///
        e(sample)


    /*
    Main coefficient.
    */

    local beta = ///
        _b[`log_post']

    local se = ///
        _se[`log_post']

    local residual_df = ///
        e(df_r)

    local observations = ///
        e(N)

    local critical_value = ///
        invttail( ///
            `residual_df', ///
            0.025 ///
        )

    local lower_95 = ///
        `beta' - ///
        `critical_value' * `se'

    local upper_95 = ///
        `beta' + ///
        `critical_value' * `se'


    test `log_post'

    local F_stat = ///
        r(F)

    local p_value = ///
        r(p)


    /*
    D x Post control.
    */

    local D_beta = ///
        _b[`D_post']

    local D_se = ///
        _se[`D_post']

    test `D_post'

    local D_p = ///
        r(p)


    /*
    Effective programs and markets.
    */

    tempvar tag_est_program tag_est_market

    egen byte `tag_est_program' = ///
        tag(program_id) ///
        if `estimation_sample' == 1

    quietly count if ///
        `tag_est_program' == 1

    local programs = ///
        r(N)


    egen byte `tag_est_market' = ///
        tag(market_pre) ///
        if `estimation_sample' == 1

    quietly count if ///
        `tag_est_market' == 1

    local markets = ///
        r(N)


    /*
    Store.
    */

    post `results_handle' ///
        ("`measure_label'") ///
        (`beta') ///
        (`se') ///
        (`F_stat') ///
        (`p_value') ///
        (`lower_95') ///
        (`upper_95') ///
        (`D_beta') ///
        (`D_se') ///
        (`D_p') ///
        (`observations') ///
        (`programs') ///
        (`markets')


    /*
    Compact output.
    */

    display ""
    display "MAIN LOG-Q TERM"

    display ///
        "Beta log(Q)xPost = " ///
        %9.4f `beta'

    display ///
        "SE                = " ///
        %9.4f `se'

    display ///
        "F                 = " ///
        %9.4f `F_stat'

    display ///
        "p-value           = " ///
        %9.4f `p_value'


    display ""
    display "POSITIVE-Q DUMMY CONTROL"

    display ///
        "Beta D x Post     = " ///
        %9.4f `D_beta'

    display ///
        "SE                = " ///
        %9.4f `D_se'

    display ///
        "p-value           = " ///
        %9.4f `D_p'


    display ""
    display "SAMPLE"

    display ///
        "Observations      = " ///
        %9.0fc `observations'

    display ///
        "Programs          = " ///
        %9.0fc `programs'

    display ///
        "Markets           = " ///
        %9.0fc `markets'


    drop ///
        `estimation_sample' ///
        `tag_est_program' ///
        `tag_est_market'
}


postclose `results_handle'


/*******************************************************************************
13. DISPLAY RESULTS
*******************************************************************************/

use `similarity_log_results', clear

count
assert r(N) == 2

isid measure


format ///
    beta ///
    se ///
    F_stat ///
    p_value ///
    lower_95 ///
    upper_95 ///
    D_beta ///
    D_se ///
    D_p ///
    %9.4f

format ///
    observations ///
    programs ///
    markets ///
    %12.0fc


display ""
display "============================================================"
display " LOG CONDITIONAL-SIMILARITY RESULTS"
display " Q = 0 RETAINED"
display "============================================================"

list ///
    measure ///
    beta ///
    se ///
    F_stat ///
    p_value ///
    observations ///
    programs ///
    markets, ///
    noobs clean


display ""
display "============================================================"
display " POSITIVE-Q DUMMY x POST"
display "============================================================"

list ///
    measure ///
    D_beta ///
    D_se ///
    D_p, ///
    noobs clean


display ""
display "04h_sua_similarity_log_test.do completed successfully."