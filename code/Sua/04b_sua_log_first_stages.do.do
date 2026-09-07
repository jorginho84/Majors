/*******************************************************************************
04b_sua_log_first_stages.do

PURPOSE

Estimate log SUA first stages for:

    FIELD DEFINITIONS
        1. Broad area
        2. CINE97 / ISCED subarea
        3. Generic career area

    EXPOSURE MEASURES
        1. Total
        2. Triangular
        3. Gaussian

    FIXED-EFFECT SPECIFICATIONS
        1. Baseline:
               Program FE
               Field x year FE

        2. Region-year:
               Program FE
               Field x year FE
               Region x year FE


MODEL

    log(N_firstyear_pt)
        = beta_k [log_tilde(E_p^k) x Post_t]
        + theta_k [1(E_p^k > 0) x Post_t]
        + fixed effects
        + error_pt

where

    log_tilde(E_p^k) =
        0                if E_p^k = 0
        log(E_p^k)       if E_p^k > 0

Programs with zero exposure are retained.

The dummy 1(E_p^k > 0) x Post_t distinguishes zero exposure from
positive exposure after 2012.

The coefficient beta_k on log_tilde(E_p^k) x Post_t is the main
coefficient reported in the table.

Because the dependent variable is log enrollment, observations with
zero first-year enrollment are excluded.

No external results files are created.
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
1. DEFINITIONS
*******************************************************************************/

local market_definitions ///
    broad_area ///
    cine_subarea ///
    generic_area

local exposure_measures ///
    total ///
    triangular ///
    gaussian

local fe_specifications ///
    baseline ///
    regionyear


/*******************************************************************************
2. RESULTS STORAGE
*******************************************************************************/

tempfile log_first_stage_results
tempname results_handle

postfile `results_handle' ///
    str12 fe_specification ///
    str12 field_definition ///
    str12 exposure_measure ///
    double beta ///
    double standard_error ///
    double F_statistic ///
    double p_value ///
    double lower_95 ///
    double upper_95 ///
    double D_beta ///
    double D_standard_error ///
    double D_p_value ///
    long observations ///
    long programs ///
    long markets ///
    using `log_first_stage_results', ///
    replace


/*******************************************************************************
3. ESTIMATION BY FIELD DEFINITION
*******************************************************************************/

foreach market_definition of local market_definitions {


    /***************************************************************************
    3.1 FIELD-DEFINITION LABEL
    ***************************************************************************/

    if "`market_definition'" == "broad_area" {

        local field_label ///
            "Broad"
    }

    if "`market_definition'" == "cine_subarea" {

        local field_label ///
            "CINE97"
    }

    if "`market_definition'" == "generic_area" {

        local field_label ///
            "Generic"
    }


    /***************************************************************************
    3.2 LOAD CORRESPONDING PROGRAM PANEL
    ***************************************************************************/

    local input_panel ///
        "$processed/sua_incumbent_panel_w_`market_definition'_region_2007_2016.dta"

    use "`input_panel'", clear

    display ""
    display "============================================================"
    display " FIELD DEFINITION: `field_label'"
    display "============================================================"


    /***************************************************************************
    3.3 INITIAL ANALYTICAL SAMPLE
    ***************************************************************************/

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


    /*
    The dependent variable is log enrollment.
    Therefore N_firstyear_incumbent must be strictly positive.

    IMPORTANT:
    Zero exposure is NOT excluded.
    */

    keep if ///
        N_firstyear_incumbent > 0

    assert _N > 0

    isid ///
        program_id ///
        ao_proceso


    /***************************************************************************
    3.4 REQUIRE POSITIVE OUTCOME OBSERVATIONS BEFORE AND AFTER 2012
    ***************************************************************************/

    bysort program_id: ///
        egen byte has_positive_pre = ///
            max(ao_proceso <= 2011)

    bysort program_id: ///
        egen byte has_positive_post = ///
            max(ao_proceso >= 2012)

    keep if ///
        has_positive_pre == 1 & ///
        has_positive_post == 1

    drop ///
        has_positive_pre ///
        has_positive_post

    assert _N > 0


    /***************************************************************************
    3.5 VERIFY RAW EXPOSURES
    ***************************************************************************/

    foreach raw_exposure in ///
        exp_unw ///
        exp_tri50 ///
        exp_gau50 {

        assert ///
            `raw_exposure' >= 0 ///
            if !missing(`raw_exposure')
    }


    /*
    Exposure must be fixed over time within program.
    */

    foreach raw_exposure in ///
        exp_unw ///
        exp_tri50 ///
        exp_gau50 {

        tempvar min_exp max_exp

        bysort program_id: ///
            egen double `min_exp' = ///
                min(`raw_exposure')

        bysort program_id: ///
            egen double `max_exp' = ///
                max(`raw_exposure')

        assert ///
            abs( ///
                `max_exp' - ///
                `min_exp' ///
            ) < 1e-10

        drop ///
            `min_exp' ///
            `max_exp'
    }


    /***************************************************************************
    3.6 POST-TREATMENT INDICATOR
    ***************************************************************************/

    capture confirm variable post2012

    if _rc {

        gen byte post2012 = ///
            inrange(ao_proceso, 2012, 2016)
    }

    assert ///
        post2012 == inrange(ao_proceso, 2012, 2016)

    assert ///
        inlist(post2012, 0, 1)


    /***************************************************************************
    3.7 LOG OUTCOME
    ***************************************************************************/

    gen double ln_firstyear_enrollment = ///
        ln(N_firstyear_incumbent)

    assert ///
        !missing(ln_firstyear_enrollment)


    /***************************************************************************
    3.8 TOTAL EXPOSURE
    ***************************************************************************/

    /*
    Dummy for positive exposure.
    */

    gen byte positive_total_exposure = ///
        exp_unw > 0

    assert ///
        inlist(positive_total_exposure, 0, 1)


    /*
    Construct log-tilde exposure:

        = log(E) if E > 0
        = 0      if E = 0
    */

    gen double ln_total_exposure = 0

    replace ln_total_exposure = ///
        ln(exp_unw) ///
        if exp_unw > 0


    /*
    Post interaction of log-tilde exposure.
    */

    gen double log_total_post = ///
        ln_total_exposure * post2012


    /*
    Positive-exposure dummy x Post.
    */

    gen byte D_total_post = ///
        positive_total_exposure * post2012


    /*
    Checks.
    */

    assert ///
        ln_total_exposure == 0 ///
        if exp_unw == 0

    assert ///
        log_total_post == 0 ///
        if exp_unw == 0

    assert ///
        D_total_post == 0 ///
        if exp_unw == 0

    assert ///
        log_total_post == 0 ///
        if ao_proceso <= 2011

    assert ///
        D_total_post == 0 ///
        if ao_proceso <= 2011


    /***************************************************************************
    3.9 TRIANGULAR EXPOSURE
    ***************************************************************************/

    gen byte positive_triangular_exposure = ///
        exp_tri50 > 0

    assert ///
        inlist(positive_triangular_exposure, 0, 1)


    gen double ln_triangular_exposure = 0

    replace ln_triangular_exposure = ///
        ln(exp_tri50) ///
        if exp_tri50 > 0


    gen double log_triangular_post = ///
        ln_triangular_exposure * post2012

    gen byte D_triangular_post = ///
        positive_triangular_exposure * post2012


    assert ///
        ln_triangular_exposure == 0 ///
        if exp_tri50 == 0

    assert ///
        log_triangular_post == 0 ///
        if exp_tri50 == 0

    assert ///
        D_triangular_post == 0 ///
        if exp_tri50 == 0

    assert ///
        log_triangular_post == 0 ///
        if ao_proceso <= 2011

    assert ///
        D_triangular_post == 0 ///
        if ao_proceso <= 2011


    /***************************************************************************
    3.10 GAUSSIAN EXPOSURE
    ***************************************************************************/

    gen byte positive_gaussian_exposure = ///
        exp_gau50 > 0

    assert ///
        inlist(positive_gaussian_exposure, 0, 1)


    gen double ln_gaussian_exposure = 0

    replace ln_gaussian_exposure = ///
        ln(exp_gau50) ///
        if exp_gau50 > 0


    gen double log_gaussian_post = ///
        ln_gaussian_exposure * post2012

    gen byte D_gaussian_post = ///
        positive_gaussian_exposure * post2012


    assert ///
        ln_gaussian_exposure == 0 ///
        if exp_gau50 == 0

    assert ///
        log_gaussian_post == 0 ///
        if exp_gau50 == 0

    assert ///
        D_gaussian_post == 0 ///
        if exp_gau50 == 0

    assert ///
        log_gaussian_post == 0 ///
        if ao_proceso <= 2011

    assert ///
        D_gaussian_post == 0 ///
        if ao_proceso <= 2011


    /***************************************************************************
    3.11 FIXED-EFFECT IDENTIFIERS
    ***************************************************************************/

    capture confirm variable log_field_year

    if _rc {

        egen long log_field_year = ///
            group( ///
                field_pre ///
                ao_proceso ///
            )
    }


    capture confirm variable log_region_year

    if _rc {

        egen long log_region_year = ///
            group( ///
                geo_pre ///
                ao_proceso ///
            )
    }


    /***************************************************************************
    3.12 SAMPLE DIAGNOSTICS
    ***************************************************************************/

    egen byte tag_program = ///
        tag(program_id)

    display ""
    display "============================================================"
    display " EXPOSURE SUPPORT"
    display "============================================================"

    count if ///
        tag_program == 1

    display ///
        "Programs in log-outcome sample = " ///
        %9.0fc r(N)


    count if ///
        tag_program == 1 & ///
        positive_total_exposure == 1

    display ///
        "Positive total exposure        = " ///
        %9.0fc r(N)


    count if ///
        tag_program == 1 & ///
        positive_triangular_exposure == 1

    display ///
        "Positive triangular exposure   = " ///
        %9.0fc r(N)


    count if ///
        tag_program == 1 & ///
        positive_gaussian_exposure == 1

    display ///
        "Positive Gaussian exposure     = " ///
        %9.0fc r(N)

    drop tag_program


    /***************************************************************************
    4. FIXED-EFFECT SPECIFICATIONS
    ***************************************************************************/

    foreach fe_specification of local fe_specifications {


        /*
        Baseline:
            Program FE
            Field x year FE
        */

        if "`fe_specification'" == "baseline" {

            local absorbed_effects ///
                program_id ///
                log_field_year

            local specification_label ///
                "Program FE + field x year FE"
        }


        /*
        Region-year:
            Program FE
            Field x year FE
            Region x year FE
        */

        if "`fe_specification'" == "regionyear" {

            local absorbed_effects ///
                program_id ///
                log_field_year ///
                log_region_year

            local specification_label ///
                "Program FE + field x year FE + region x year FE"
        }


        /***********************************************************************
        5. EXPOSURE MEASURES
        ***********************************************************************/

        foreach exposure_measure of local exposure_measures {


            /*
            Total exposure.
            */

            if "`exposure_measure'" == "total" {

                local log_post_variable ///
                    log_total_post

                local D_post_variable ///
                    D_total_post

                local exposure_label ///
                    "Total"
            }


            /*
            Triangular exposure.
            */

            if "`exposure_measure'" == "triangular" {

                local log_post_variable ///
                    log_triangular_post

                local D_post_variable ///
                    D_triangular_post

                local exposure_label ///
                    "Triangular"
            }


            /*
            Gaussian exposure.
            */

            if "`exposure_measure'" == "gaussian" {

                local log_post_variable ///
                    log_gaussian_post

                local D_post_variable ///
                    D_gaussian_post

                local exposure_label ///
                    "Gaussian"
            }


            display ""
            display "------------------------------------------------------------"
            display "Field          = `field_label'"
            display "Exposure       = `exposure_label'"
            display "Specification  = `fe_specification'"
            display "`specification_label'"
            display "Zero exposure  = RETAINED"
            display "------------------------------------------------------------"


            /*******************************************************************
            6. LOG FIRST-STAGE REGRESSION

            Both terms enter:

                log-tilde(E) x Post
                1(E>0) x Post

            No positive-exposure sample restriction.
            *******************************************************************/

            reghdfe ///
                ln_firstyear_enrollment ///
                `log_post_variable' ///
                `D_post_variable', ///
                absorb( ///
                    `absorbed_effects' ///
                ) ///
                vce(cluster market_pre)


            /*******************************************************************
            7. MAIN LOG-EXPOSURE COEFFICIENT
            *******************************************************************/

            local beta = ///
                _b[`log_post_variable']

            local standard_error = ///
                _se[`log_post_variable']

            local residual_df = ///
                e(df_r)

            local observations = ///
                e(N)

            local critical_value = ///
                invttail(`residual_df', 0.025)

            local lower_95 = ///
                `beta' - ///
                `critical_value' * `standard_error'

            local upper_95 = ///
                `beta' + ///
                `critical_value' * `standard_error'


            /*
            Wald F for main log-exposure coefficient.
            */

            test `log_post_variable'

            local F_statistic = ///
                r(F)

            local p_value = ///
                r(p)


            /*******************************************************************
            7.1 DUMMY x POST COEFFICIENT
            *******************************************************************/

            local D_beta = ///
                _b[`D_post_variable']

            local D_standard_error = ///
                _se[`D_post_variable']

            test `D_post_variable'

            local D_p_value = ///
                r(p)


            /*******************************************************************
            8. NUMBER OF PROGRAMS AND MARKETS
            *******************************************************************/

            tempvar tag_estimation_program tag_estimation_market

            egen byte `tag_estimation_program' = ///
                tag(program_id) ///
                if e(sample)

            quietly count if ///
                `tag_estimation_program' == 1

            local programs = ///
                r(N)


            egen byte `tag_estimation_market' = ///
                tag(market_pre) ///
                if e(sample)

            quietly count if ///
                `tag_estimation_market' == 1

            local markets = ///
                r(N)


            drop ///
                `tag_estimation_program' ///
                `tag_estimation_market'


            /*******************************************************************
            9. STORE RESULT
            *******************************************************************/

            post `results_handle' ///
                ("`fe_specification'") ///
                ("`field_label'") ///
                ("`exposure_label'") ///
                (`beta') ///
                (`standard_error') ///
                (`F_statistic') ///
                (`p_value') ///
                (`lower_95') ///
                (`upper_95') ///
                (`D_beta') ///
                (`D_standard_error') ///
                (`D_p_value') ///
                (`observations') ///
                (`programs') ///
                (`markets')


            /*******************************************************************
            10. DISPLAY COMPACT RESULT
            *******************************************************************/

            display ""
            display "MAIN LOG-EXPOSURE TERM"

            display ///
                "Beta log(E)xPost = " ///
                %9.4f `beta'

            display ///
                "SE                = " ///
                %9.4f `standard_error'

            display ///
                "Wald F            = " ///
                %9.4f `F_statistic'

            display ///
                "p-value           = " ///
                %9.4f `p_value'


            display ""
            display "POSITIVE-EXPOSURE DUMMY CONTROL"

            display ///
                "Beta D x Post     = " ///
                %9.4f `D_beta'

            display ///
                "SE                = " ///
                %9.4f `D_standard_error'

            display ///
                "p-value           = " ///
                %9.4f `D_p_value'


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
        }
    }
}

postclose `results_handle'


/*******************************************************************************
11. LOAD AND VALIDATE RESULTS
*******************************************************************************/

use `log_first_stage_results', clear

count

/*
Three field definitions
x three exposure measures
x two FE specifications
= 18 regressions.
*/

assert r(N) == 18

isid ///
    fe_specification ///
    field_definition ///
    exposure_measure


count if ///
    fe_specification == "baseline"

assert r(N) == 9


count if ///
    fe_specification == "regionyear"

assert r(N) == 9


/*******************************************************************************
12. FORMATS AND LABELS
*******************************************************************************/

format ///
    beta ///
    standard_error ///
    lower_95 ///
    upper_95 ///
    D_beta ///
    D_standard_error ///
    %9.4f

format ///
    F_statistic ///
    p_value ///
    D_p_value ///
    %9.4f

format ///
    observations ///
    programs ///
    markets ///
    %12.0fc


label variable fe_specification ///
    "Fixed-effect specification"

label variable field_definition ///
    "Field definition"

label variable exposure_measure ///
    "Exposure measure"

label variable beta ///
    "Coefficient on log(E) x Post"

label variable standard_error ///
    "Clustered standard error"

label variable F_statistic ///
    "Cluster-robust Wald F for log(E) x Post"

label variable p_value ///
    "p-value for log(E) x Post"

label variable lower_95 ///
    "95% CI lower bound"

label variable upper_95 ///
    "95% CI upper bound"

label variable D_beta ///
    "Coefficient on 1(E>0) x Post"

label variable D_standard_error ///
    "SE for 1(E>0) x Post"

label variable D_p_value ///
    "p-value for 1(E>0) x Post"


/*******************************************************************************
13. DISPLAY MAIN RESULTS
*******************************************************************************/

sort ///
    fe_specification ///
    field_definition ///
    exposure_measure

display ""
display "============================================================"
display " SUA LOG FIRST-STAGE RESULTS"
display " ZERO-EXPOSURE PROGRAMS RETAINED"
display "============================================================"

list ///
    fe_specification ///
    field_definition ///
    exposure_measure ///
    beta ///
    standard_error ///
    F_statistic ///
    p_value ///
    observations ///
    programs ///
    markets, ///
    sepby( ///
        fe_specification ///
        field_definition ///
    ) ///
    noobs clean


/*******************************************************************************
14. DISPLAY DUMMY-CONTROL RESULTS
*******************************************************************************/

display ""
display "============================================================"
display " POSITIVE-EXPOSURE DUMMY x POST"
display "============================================================"

list ///
    fe_specification ///
    field_definition ///
    exposure_measure ///
    D_beta ///
    D_standard_error ///
    D_p_value, ///
    sepby( ///
        fe_specification ///
        field_definition ///
    ) ///
    noobs clean


/*******************************************************************************
15. INTERPRETATION
*******************************************************************************/

display ""
display "============================================================"
display " INTERPRETATION"
display "============================================================"

display ""
display "Zero-exposure programs are retained."
display ""
display "The constructed exposure variable equals:"
display "    log(E) if E > 0"
display "    0      if E = 0"
display ""
display "The regression includes both:"
display "    log-tilde(E) x Post"
display "    1(E>0) x Post"
display ""
display "The dummy interaction separates the difference between"
display "zero and positive exposure from variation in exposure intensity."
display ""
display "The main reported beta is the coefficient on"
display "log-tilde(E) x Post."
display ""
display "Zero first-year enrollment observations are excluded because"
display "the dependent variable is log enrollment."
display ""
display "============================================================"