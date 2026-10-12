/*******************************************************************************
04c_sua_exposure_decomposition_test.do

PURPOSE

Decompose the existing non-cosine SUA exposure into:

    1. Market size:
           M_m = entrant enrollment / total market enrollment

    2. Conditional similarity:
           Q_p = average similarity to entrants within the market

The existing weighted exposures satisfy:

    Triangular exposure = M_m x Q_p_triangular
    Gaussian exposure   = M_m x Q_p_gaussian

This is an exploratory diagnostic. Existing exposure variables and main
regressions are not modified.

MARKET

    Broad academic field x pre-treatment region

OUTCOME

    First-year enrollment in incumbent programs
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
1. INPUT
*******************************************************************************/

local input_panel ///
    "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta"


/*******************************************************************************
2. LOAD COMMON ANALYTICAL SAMPLE
*******************************************************************************/

use "`input_panel'", clear

keep if inrange(ao_proceso, 2007, 2016)

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

isid program_id ao_proceso


/*
Require each program to have observations before and after SUA entry.
*/

bysort program_id: ///
    egen byte sample_has_pre = ///
        max(ao_proceso <= 2011)

bysort program_id: ///
    egen byte sample_has_post = ///
        max(ao_proceso >= 2012)

keep if ///
    sample_has_pre == 1 & ///
    sample_has_post == 1

drop ///
    sample_has_pre ///
    sample_has_post


/*******************************************************************************
3. VERIFY THAT EXPOSURES ARE PREDETERMINED
*******************************************************************************/

foreach variable in ///
    exp_unw ///
    exp_tri50 ///
    exp_gau50 {

    bysort program_id (ao_proceso): ///
        assert ///
        `variable' == `variable'[1]
}


/*******************************************************************************
4. POST INDICATOR AND FIXED-EFFECT IDENTIFIERS
*******************************************************************************/

gen byte post_sua = ///
    inrange(ao_proceso, 2012, 2016)

label variable post_sua ///
    "SUA post period: 2012-2016"


egen long fe_field_year_decomp = ///
    group( ///
        field_pre ///
        ao_proceso ///
    )

egen long fe_region_year_decomp = ///
    group( ///
        geo_pre ///
        ao_proceso ///
    )

egen long fe_market_year_decomp = ///
    group( ///
        market_pre ///
        ao_proceso ///
    )


/*******************************************************************************
5. DECOMPOSE EXISTING EXPOSURES
*******************************************************************************/

/*
Market size:

    M_m = entrant enrollment / total market enrollment

This is exactly the existing Total exposure.
*/

gen double market_entrant_share = ///
    exp_unw

label variable market_entrant_share ///
    "Entrant share of market enrollment"


/*
Indicator for markets with entrant universities.
*/

gen byte market_has_entrants = ///
    market_entrant_share > 0

label variable market_has_entrants ///
    "Market has positive entrant exposure"


/*
Conditional similarity is defined only when the market has entrants:

    Q_tri = triangular exposure / total exposure
    Q_gau = gaussian exposure / total exposure
*/

gen double similarity_triangular = .

replace similarity_triangular = ///
    exp_tri50 / market_entrant_share ///
    if market_has_entrants == 1


gen double similarity_gaussian = .

replace similarity_gaussian = ///
    exp_gau50 / market_entrant_share ///
    if market_has_entrants == 1


label variable similarity_triangular ///
    "Triangular similarity conditional on entrant market"

label variable similarity_gaussian ///
    "Gaussian similarity conditional on entrant market"


/*******************************************************************************
6. VERIFY THE ALGEBRAIC DECOMPOSITION
*******************************************************************************/

/*
For positive-exposure markets:

    weighted exposure = market size x conditional similarity
*/

assert ///
    reldif( ///
        exp_tri50, ///
        market_entrant_share * similarity_triangular ///
    ) < 1e-8 ///
    if market_has_entrants == 1


assert ///
    reldif( ///
        exp_gau50, ///
        market_entrant_share * similarity_gaussian ///
    ) < 1e-8 ///
    if market_has_entrants == 1


/*
When there are no entrants, all weighted exposures must equal zero.
*/

assert exp_tri50 == 0 ///
    if market_has_entrants == 0

assert exp_gau50 == 0 ///
    if market_has_entrants == 0


display ""
display "============================================================"
display " DECOMPOSITION VERIFIED"
display "============================================================"
display "Triangular = market size x triangular similarity"
display "Gaussian   = market size x gaussian similarity"


/*******************************************************************************
7. DESCRIPTIVE DIAGNOSTICS
*******************************************************************************/

/*
Count each program and market once.
*/

egen byte tag_program_decomp = ///
    tag(program_id)

egen byte tag_market_decomp = ///
    tag(market_pre)


count if tag_program_decomp == 1
local total_programs = r(N)

count if ///
    tag_program_decomp == 1 & ///
    market_has_entrants == 1
local exposed_programs = r(N)

count if tag_market_decomp == 1
local total_markets = r(N)

count if ///
    tag_market_decomp == 1 & ///
    market_has_entrants == 1
local exposed_markets = r(N)


display ""
display "============================================================"
display " EXPOSURE SUPPORT"
display "============================================================"

display ///
    "Programs, total            = " ///
    %9.0fc `total_programs'

display ///
    "Programs in exposed market = " ///
    %9.0fc `exposed_programs'

display ///
    "Markets, total             = " ///
    %9.0fc `total_markets'

display ///
    "Markets with entrants      = " ///
    %9.0fc `exposed_markets'


display ""
display "PROGRAM-LEVEL DISTRIBUTIONS IN EXPOSED MARKETS"

summarize ///
    market_entrant_share ///
    similarity_triangular ///
    similarity_gaussian ///
    exp_tri50 ///
    exp_gau50 ///
    if ///
        tag_program_decomp == 1 & ///
        market_has_entrants == 1, ///
    detail


display ""
display "PROGRAM-LEVEL CORRELATIONS IN EXPOSED MARKETS"

pwcorr ///
    market_entrant_share ///
    similarity_triangular ///
    similarity_gaussian ///
    exp_tri50 ///
    exp_gau50 ///
    if ///
        tag_program_decomp == 1 & ///
        market_has_entrants == 1, ///
    sig obs


/*******************************************************************************
8. CENTER SIZE AND SIMILARITY AMONG EXPOSED PROGRAMS
*******************************************************************************/

/*
Program-weighted means are used. Centering makes the exposed-market dummy
interpretable as the post-2012 difference for an exposed program with average
market size and average similarity.
*/

quietly summarize ///
    market_entrant_share ///
    if ///
        tag_program_decomp == 1 & ///
        market_has_entrants == 1

local mean_market_share = r(mean)


quietly summarize ///
    similarity_triangular ///
    if ///
        tag_program_decomp == 1 & ///
        market_has_entrants == 1

local mean_triangular_similarity = r(mean)


quietly summarize ///
    similarity_gaussian ///
    if ///
        tag_program_decomp == 1 & ///
        market_has_entrants == 1

local mean_gaussian_similarity = r(mean)


gen double centered_market_share = 0

replace centered_market_share = ///
    market_entrant_share - `mean_market_share' ///
    if market_has_entrants == 1


gen double centered_triangular_similarity = 0

replace centered_triangular_similarity = ///
    similarity_triangular - ///
    `mean_triangular_similarity' ///
    if market_has_entrants == 1


gen double centered_gaussian_similarity = 0

replace centered_gaussian_similarity = ///
    similarity_gaussian - ///
    `mean_gaussian_similarity' ///
    if market_has_entrants == 1


/*******************************************************************************
9. CONSTRUCT FIRST-STAGE REGRESSORS
*******************************************************************************/

/*
Original combined exposures.

One unit corresponds to a 10-percentage-point increase in the existing
weighted exposure.
*/

gen double x_combined_triangular = ///
    10 * exp_tri50 * post_sua

gen double x_combined_gaussian = ///
    10 * exp_gau50 * post_sua


/*
Extensive margin:

    exposed market x Post
*/

gen double x_exposed_market = ///
    market_has_entrants * post_sua


/*
Market-size margin.

One unit corresponds to a 10-percentage-point increase relative to the
average exposed program.
*/

gen double x_market_size = ///
    10 * centered_market_share * post_sua


/*
Similarity margin.

One unit corresponds to a 0.10 increase in conditional similarity relative
to the average exposed program.
*/

gen double x_triangular_similarity = ///
    10 * centered_triangular_similarity * post_sua

gen double x_gaussian_similarity = ///
    10 * centered_gaussian_similarity * post_sua


/*
Uncentered similarity interactions for the within-market regressions.
Centering is unnecessary there because market x year FE absorb the common
market-level Post component.
*/

gen double x_triangular_within_market = ///
    10 * similarity_triangular * post_sua ///
    if market_has_entrants == 1

gen double x_gaussian_within_market = ///
    10 * similarity_gaussian * post_sua ///
    if market_has_entrants == 1


/*******************************************************************************
10. ORIGINAL COMBINED FIRST STAGES
*
* These reproduce the logic of the existing weighted-exposure regressions.
*******************************************************************************/

display ""
display "============================================================"
display " A. ORIGINAL COMBINED EXPOSURES"
display " Program FE + Broad-field x year FE"
display "============================================================"


reghdfe ///
    N_firstyear_incumbent ///
    x_combined_triangular, ///
    absorb( ///
        program_id ///
        fe_field_year_decomp ///
    ) ///
    vce(cluster market_pre)

estimates store orig_tri

test x_combined_triangular

display ///
    "Triangular first-stage F = " ///
    %9.3f r(F)


reghdfe ///
    N_firstyear_incumbent ///
    x_combined_gaussian, ///
    absorb( ///
        program_id ///
        fe_field_year_decomp ///
    ) ///
    vce(cluster market_pre)

estimates store orig_gau

test x_combined_gaussian

display ///
    "Gaussian first-stage F = " ///
    %9.3f r(F)


/*******************************************************************************
11. DECOMPOSED FIRST STAGES: BASELINE
*
* The regressions distinguish:
*
*     1. Positive versus zero exposure
*     2. Market size among exposed programs
*     3. Similarity among exposed programs
*******************************************************************************/

display ""
display "============================================================"
display " B. DECOMPOSED EXPOSURE: BASELINE"
display " Program FE + Broad-field x year FE"
display "============================================================"


reghdfe ///
    N_firstyear_incumbent ///
    x_exposed_market ///
    x_market_size ///
    x_triangular_similarity, ///
    absorb( ///
        program_id ///
        fe_field_year_decomp ///
    ) ///
    vce(cluster market_pre)

estimates store dec_tri_base

test ///
    x_exposed_market ///
    x_market_size ///
    x_triangular_similarity

display ///
    "Triangular decomposition: joint F = " ///
    %9.3f r(F)


reghdfe ///
    N_firstyear_incumbent ///
    x_exposed_market ///
    x_market_size ///
    x_gaussian_similarity, ///
    absorb( ///
        program_id ///
        fe_field_year_decomp ///
    ) ///
    vce(cluster market_pre)

estimates store dec_gau_base

test ///
    x_exposed_market ///
    x_market_size ///
    x_gaussian_similarity

display ///
    "Gaussian decomposition: joint F = " ///
    %9.3f r(F)


/*******************************************************************************
12. DECOMPOSED FIRST STAGES: REGION x YEAR
*******************************************************************************/

display ""
display "============================================================"
display " C. DECOMPOSED EXPOSURE: REGION x YEAR"
display " Program FE + Broad-field x year FE + region x year FE"
display "============================================================"


reghdfe ///
    N_firstyear_incumbent ///
    x_exposed_market ///
    x_market_size ///
    x_triangular_similarity, ///
    absorb( ///
        program_id ///
        fe_field_year_decomp ///
        fe_region_year_decomp ///
    ) ///
    vce(cluster market_pre)

estimates store dec_tri_reg

test ///
    x_exposed_market ///
    x_market_size ///
    x_triangular_similarity

display ///
    "Triangular decomposition: joint F = " ///
    %9.3f r(F)


reghdfe ///
    N_firstyear_incumbent ///
    x_exposed_market ///
    x_market_size ///
    x_gaussian_similarity, ///
    absorb( ///
        program_id ///
        fe_field_year_decomp ///
        fe_region_year_decomp ///
    ) ///
    vce(cluster market_pre)

estimates store dec_gau_reg

test ///
    x_exposed_market ///
    x_market_size ///
    x_gaussian_similarity

display ///
    "Gaussian decomposition: joint F = " ///
    %9.3f r(F)


/*******************************************************************************
13. SIMILARITY WITHIN EXPOSED MARKETS
*
* Market x year FE absorb every annual shock common to programs in the same
* region x Broad-field market.
*
* Identification comes exclusively from differences in similarity between
* incumbent programs within the same exposed market.
*******************************************************************************/

display ""
display "============================================================"
display " D. SIMILARITY WITHIN EXPOSED MARKETS"
display " Program FE + market x year FE"
display "============================================================"


reghdfe ///
    N_firstyear_incumbent ///
    x_triangular_within_market ///
    if market_has_entrants == 1, ///
    absorb( ///
        program_id ///
        fe_market_year_decomp ///
    ) ///
    vce(cluster market_pre)

estimates store within_tri

test x_triangular_within_market

display ///
    "Within-market triangular F = " ///
    %9.3f r(F)


reghdfe ///
    N_firstyear_incumbent ///
    x_gaussian_within_market ///
    if market_has_entrants == 1, ///
    absorb( ///
        program_id ///
        fe_market_year_decomp ///
    ) ///
    vce(cluster market_pre)

estimates store within_gau

test x_gaussian_within_market

display ///
    "Within-market Gaussian F = " ///
    %9.3f r(F)


/*******************************************************************************
14. COMPACT RESULT TABLES
*******************************************************************************/

display ""
display "============================================================"
display " ORIGINAL COMBINED EXPOSURES"
display "============================================================"

estimates table ///
    orig_tri ///
    orig_gau, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N r2_a) ///
    keep( ///
        x_combined_triangular ///
        x_combined_gaussian ///
    )


display ""
display "============================================================"
display " DECOMPOSED EXPOSURES"
display "============================================================"

estimates table ///
    dec_tri_base ///
    dec_gau_base ///
    dec_tri_reg ///
    dec_gau_reg, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N r2_a) ///
    keep( ///
        x_exposed_market ///
        x_market_size ///
        x_triangular_similarity ///
        x_gaussian_similarity ///
    )


display ""
display "============================================================"
display " SIMILARITY WITHIN EXPOSED MARKETS"
display "============================================================"

estimates table ///
    within_tri ///
    within_gau, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N r2_a) ///
    keep( ///
        x_triangular_within_market ///
        x_gaussian_within_market ///
    )


display ""
display "============================================================"
display " INTERPRETATION"
display "============================================================"

display ///
    "x_exposed_market: exposed market at average size and similarity."

display ///
    "x_market_size: 10 percentage points more entrant market share."

display ///
    "x_*_similarity: 0.10 more conditional similarity."

display ///
    "Within-market models compare incumbent programs in the same exposed market."

display ""
display "04g_sua_exposure_decomposition_test.do completed."