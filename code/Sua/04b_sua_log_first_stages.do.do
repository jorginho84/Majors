/*******************************************************************************
04b_sua_log_first_stages.do

PURPOSE

Estimate log-log SUA first stages for:

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
        = beta_k [log(E_p^k) x D_pt^k]
        + fixed effects
        + error_pt

where:

    D_pt^k = 1(E_p^k > 0) x Post_t

Programs with zero exposure are excluded from the corresponding log
regression. The dummy is retained in the construction but is not included
separately because, within the positive-exposure sample, it equals Post_t.

The coefficient beta_k is the differential post-2012 enrollment elasticity
with respect to exposure among programs with positive exposure.

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
    log(N) requires strictly positive enrollment.
    */

    keep if ///
        N_firstyear_incumbent > 0

    assert _N > 0

    isid ///
        program_id ///
        ao_proceso


    /***************************************************************************
    3.4 REQUIRE POSITIVE ENROLLMENT OBSERVATIONS BEFORE AND AFTER 2012
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
    Exposure must be constant over time within each incumbent program.
    */

    foreach raw_exposure in ///
        exp_unw ///
        exp_tri50 ///
        exp_gau50 {

        tempvar minimum_exposure maximum_exposure

        bysort program_id: ///
            egen double `minimum_exposure' = ///
                min(`raw_exposure')

        bysort program_id: ///
            egen double `maximum_exposure' = ///
                max(`raw_exposure')

        assert ///
            abs( ///
                `maximum_exposure' - ///
                `minimum_exposure' ///
            ) < 1e-10

        drop ///
            `minimum_exposure' ///
            `maximum_exposure'
    }


    /***************************************************************************
    3.6 POST-TREATMENT INDICATOR
    *
    * Use the existing variable when available. Otherwise, construct it.
    ***************************************************************************/

    capture confirm variable post2012

    if _rc {

        gen byte post2012 = ///
            ao_proceso >= 2012
    }


    /*
    Validate the existing or newly created variable.
    */

    assert ///
        post2012 == (ao_proceso >= 2012)

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

    gen byte positive_total_exposure = ///
        exp_unw > 0

    gen byte exposed_post_total = ///
        positive_total_exposure * post2012

    gen double ln_total_exposure = ///
        ln(exp_unw) ///
        if positive_total_exposure == 1

    gen double log_total_post = ///
        ln_total_exposure * exposed_post_total ///
        if positive_total_exposure == 1

    assert ///
        log_total_post == 0 ///
        if positive_total_exposure == 1 & ///
           ao_proceso <= 2011

    assert ///
        !missing(log_total_post) ///
        if positive_total_exposure == 1


    /***************************************************************************
    3.9 TRIANGULAR EXPOSURE
    ***************************************************************************/

    gen byte positive_triangular_exposure = ///
        exp_tri50 > 0

    gen byte exposed_post_triangular = ///
        positive_triangular_exposure * post2012

    gen double ln_triangular_exposure = ///
        ln(exp_tri50) ///
        if positive_triangular_exposure == 1

    gen double log_triangular_post = ///
        ln_triangular_exposure * exposed_post_triangular ///
        if positive_triangular_exposure == 1

    assert ///
        log_triangular_post == 0 ///
        if positive_triangular_exposure == 1 & ///
           ao_proceso <= 2011

    assert ///
        !missing(log_triangular_post) ///
        if positive_triangular_exposure == 1


    /***************************************************************************
    3.10 GAUSSIAN EXPOSURE
    ***************************************************************************/

    gen byte positive_gaussian_exposure = ///
        exp_gau50 > 0

    gen byte exposed_post_gaussian = ///
        positive_gaussian_exposure * post2012

    gen double ln_gaussian_exposure = ///
        ln(exp_gau50) ///
        if positive_gaussian_exposure == 1

    gen double log_gaussian_post = ///
        ln_gaussian_exposure * exposed_post_gaussian ///
        if positive_gaussian_exposure == 1

    assert ///
        log_gaussian_post == 0 ///
        if positive_gaussian_exposure == 1 & ///
           ao_proceso <= 2011

    assert ///
        !missing(log_gaussian_post) ///
        if positive_gaussian_exposure == 1


    /***************************************************************************
    3.11 FIXED-EFFECT IDENTIFIERS
    *
    * Use specific names for the logarithmic exercise. Existing variables
    * are retained and not overwritten.
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
    display "POSITIVE-EXPOSURE PROGRAMS"

    count if ///
        tag_program == 1 & ///
        positive_total_exposure == 1

    display ///
        "Total exposure      = " ///
        %9.0fc r(N)

    count if ///
        tag_program == 1 & ///
        positive_triangular_exposure == 1

    display ///
        "Triangular exposure = " ///
        %9.0fc r(N)

    count if ///
        tag_program == 1 & ///
        positive_gaussian_exposure == 1

    display ///
        "Gaussian exposure   = " ///
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

                local positive_sample ///
                    positive_total_exposure

                local log_post_variable ///
                    log_total_post

                local exposure_label ///
                    "Total"
            }


            /*
            Triangular exposure.
            */

            if "`exposure_measure'" == "triangular" {

                local positive_sample ///
                    positive_triangular_exposure

                local log_post_variable ///
                    log_triangular_post

                local exposure_label ///
                    "Triangular"
            }


            /*
            Gaussian exposure.
            */

            if "`exposure_measure'" == "gaussian" {

                local positive_sample ///
                    positive_gaussian_exposure

                local log_post_variable ///
                    log_gaussian_post

                local exposure_label ///
                    "Gaussian"
            }


            display ""
            display "------------------------------------------------------------"
            display "Field          = `field_label'"
            display "Exposure       = `exposure_label'"
            display "Specification  = `fe_specification'"
            display "`specification_label'"
            display "Sample         = Positive exposure only"
            display "------------------------------------------------------------"


            /*******************************************************************
            6. LOG-LOG FIRST-STAGE REGRESSION
            *******************************************************************/

            reghdfe ///
                ln_firstyear_enrollment ///
                `log_post_variable' ///
                if `positive_sample' == 1, ///
                absorb( ///
                    `absorbed_effects' ///
                ) ///
                vce(cluster market_pre)


            /*******************************************************************
            7. COEFFICIENT AND INFERENCE
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
            Cluster-robust Wald F statistic.
            */

            test `log_post_variable'

            local F_statistic = ///
                r(F)

            local p_value = ///
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
                (`observations') ///
                (`programs') ///
                (`markets')


            /*******************************************************************
            10. DISPLAY COMPACT RESULT
            *******************************************************************/

            display ///
                "Beta elasticity = " ///
                %9.4f `beta'

            display ///
                "SE              = " ///
                %9.4f `standard_error'

            display ///
                "Wald F          = " ///
                %9.4f `F_statistic'

            display ///
                "p-value         = " ///
                %9.4f `p_value'

            display ///
                "Observations    = " ///
                %9.0fc `observations'

            display ///
                "Programs        = " ///
                %9.0fc `programs'

            display ///
                "Markets         = " ///
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
Three fields x three exposures x two FE specifications = 18 regressions.
*/

assert r(N) == 18

isid ///
    fe_specification ///
    field_definition ///
    exposure_measure


/*
Validate the expected number of results by specification.
*/

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
    %9.4f

format ///
    F_statistic ///
    p_value ///
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
    "Post-2012 exposure elasticity"

label variable standard_error ///
    "Clustered standard error"

label variable F_statistic ///
    "Cluster-robust Wald F"

label variable p_value ///
    "p-value"

label variable lower_95 ///
    "95% CI lower bound"

label variable upper_95 ///
    "95% CI upper bound"


/*******************************************************************************
13. DISPLAY RESULTS
*******************************************************************************/

sort ///
    fe_specification ///
    field_definition ///
    exposure_measure

display ""
display "============================================================"
display " SUA LOG-LOG FIRST-STAGE RESULTS"
display " POSITIVE-EXPOSURE PROGRAMS ONLY"
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
14. INTERPRETATION
*******************************************************************************/

display ""
display "============================================================"
display " INTERPRETATION"
display "============================================================"

display ""
display "Beta is the differential post-2012 enrollment elasticity"
display "with respect to exposure among programs with positive exposure."
display ""
display "A 1% higher exposure is associated with an approximately"
display "Beta% differential change in first-year enrollment after 2012."
display ""
display "Programs with zero exposure are excluded from the corresponding"
display "logarithmic regression."
display ""
display "The treatment dummy is retained in the construction but is not"
display "included separately because it equals Post within this sample."