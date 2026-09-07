/*******************************************************************************
04_sua_levels_first_stages.do

PURPOSE

Estimate the SUA first stage in levels for:

    EXPOSURE MEASURES
        1. Total
        2. Triangular
        3. Gaussian

    FIELD DEFINITIONS
        1. Broad
        2. ISCED-97
        3. Generic

    FIXED-EFFECT SPECIFICATIONS
        1. Program + year FE
        2. Program + field x year FE
        3. Program + field x year + region x year FE

MODEL

    N_firstyear_pt
        = beta_k [10 x E_p^k x D_pt^k]
        + fixed effects
        + error_pt

where:

    D_pt^k = 1(E_p^k > 0) x Post_t.

Because exposure equals zero for non-exposed programs:

    E_p^k x D_pt^k = E_p^k x Post_t.

Therefore, the explicit treatment indicator reproduces the original
Exposure x Post regressor.

One unit of the regressor corresponds to a 10 percentage-point increase
in exposure after 2012.

Each regression is:

    1. Displayed separately in the Stata console.
    2. Stored individually with estimates store.
    3. Added to a compact summary displayed at the end.

Standard errors are clustered by the corresponding pre-treatment market.

No graph or permanent results file is created.
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"

estimates clear


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
    programyear ///
    fieldyear ///
    regionyear


/*******************************************************************************
2. TEMPORARY RESULTS STORAGE
*******************************************************************************/

tempfile level_results
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
    long exposed_programs ///
    long markets ///
    using `level_results', ///
    replace


/*******************************************************************************
3. ESTIMATION BY FIELD DEFINITION
*******************************************************************************/

foreach market_definition of local market_definitions {


    /***************************************************************************
    3.1 FIELD-DEFINITION LABEL AND CODE
    ***************************************************************************/

    if "`market_definition'" == "broad_area" {

        local field_label ///
            "Broad"

        local field_code ///
            "broad"
    }

    if "`market_definition'" == "cine_subarea" {

        local field_label ///
            "ISCED-97"

        local field_code ///
            "isced"
    }

    if "`market_definition'" == "generic_area" {

        local field_label ///
            "Generic"

        local field_code ///
            "generic"
    }


    /***************************************************************************
    3.2 LOAD CORRESPONDING PROGRAM PANEL
    ***************************************************************************/

    local input_panel ///
        "$processed/sua_incumbent_panel_w_`market_definition'_region_2007_2016.dta"

    use "`input_panel'", clear

    keep if ///
        inrange(ao_proceso, 2007, 2016)

    display ""
    display "============================================================"
    display " FIELD DEFINITION: `field_label'"
    display "============================================================"


    /***************************************************************************
    3.3 COMMON ANALYTICAL SAMPLE

    Undefined exposures are excluded.

    Economically defined exposure values equal to zero are retained.
    ***************************************************************************/

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

    assert ///
        N_firstyear_incumbent > 0

    assert ///
        exp_unw >= 0

    assert ///
        exp_tri50 >= 0

    assert ///
        exp_gau50 >= 0

    isid ///
        program_id ///
        ao_proceso


    /***************************************************************************
    3.4 REQUIRE PRE- AND POST-2012 OBSERVATIONS
    ***************************************************************************/

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

    isid ///
        program_id ///
        ao_proceso


    /***************************************************************************
    3.5 POST INDICATOR
    ***************************************************************************/

    capture confirm variable post2012

    if _rc {

        gen byte post2012 = ///
            inrange(ao_proceso, 2012, 2016)
    }

    assert ///
        post2012 == ///
        inrange(ao_proceso, 2012, 2016)

    assert ///
        inlist(post2012, 0, 1)


    /***************************************************************************
    3.6 FIXED-EFFECT IDENTIFIERS
    ***************************************************************************/

    capture confirm variable ///
        level_field_year

    if _rc {

        egen long level_field_year = ///
            group( ///
                field_pre ///
                ao_proceso ///
            )
    }


    capture confirm variable ///
        level_region_year

    if _rc {

        egen long level_region_year = ///
            group( ///
                geo_pre ///
                ao_proceso ///
            )
    }


    /***************************************************************************
    3.7 VERIFY THAT EXPOSURE IS FIXED WITHIN PROGRAM
    ***************************************************************************/

    foreach raw_exposure in ///
        exp_unw ///
        exp_tri50 ///
        exp_gau50 {

        bysort program_id (ao_proceso): ///
            assert ///
            `raw_exposure' == ///
            `raw_exposure'[1]
    }


    /***************************************************************************
    3.8 CONSTRUCT EXPOSURE x POST REGRESSORS
    ***************************************************************************/

    foreach exposure_measure of local exposure_measures {


        /*
        Select the corresponding raw exposure.
        */

        if "`exposure_measure'" == "total" {

            local raw_exposure ///
                exp_unw

            local previous_regressor ///
                z_unw10
        }

        if "`exposure_measure'" == "triangular" {

            local raw_exposure ///
                exp_tri50

            local previous_regressor ///
                z_tri10
        }

        if "`exposure_measure'" == "gaussian" {

            local raw_exposure ///
                exp_gau50

            local previous_regressor ///
                z_gau10
        }


        /*
        Indicator for programs with positive exposure.
        */

        gen byte positive_`exposure_measure' = ///
            `raw_exposure' > 0

        label variable ///
            positive_`exposure_measure' ///
            "Exposure is positive"


        /*
        D_pt = 1(E_p > 0) x Post_t.
        */

        gen byte treatment_`exposure_measure' = ///
            positive_`exposure_measure' * ///
            post2012

        label variable ///
            treatment_`exposure_measure' ///
            "Positive exposure x post-2012"


        /*
        First-stage regressor.

        One unit represents 10 percentage points of exposure after 2012.
        */

        gen double fs_`exposure_measure' = ///
            10 * ///
            `raw_exposure' * ///
            treatment_`exposure_measure'

        label variable ///
            fs_`exposure_measure' ///
            "10 percentage-point exposure x post"


        /*
        Verify treatment-variable construction.
        */

        assert ///
            fs_`exposure_measure' == 0 ///
            if post2012 == 0

        assert ///
            fs_`exposure_measure' == 0 ///
            if `raw_exposure' == 0

        assert ///
            !missing( ///
                fs_`exposure_measure' ///
            )


        /*
        Verify equivalence with the exposure x post variable already stored
        in the input panel, when that variable is available.
        */

        capture confirm variable ///
            `previous_regressor'

        if !_rc {

            assert abs( ///
                fs_`exposure_measure' - ///
                `previous_regressor' ///
            ) < 1e-10
        }
    }


    /***************************************************************************
    3.9 SAMPLE DIAGNOSTICS
    ***************************************************************************/

    egen byte tag_program_input = ///
        tag(program_id)

    quietly count if ///
        tag_program_input == 1

    display ///
        "Programs in common sample = " ///
        %9.0fc r(N)


    foreach exposure_measure of local exposure_measures {

        quietly count if ///
            tag_program_input == 1 & ///
            positive_`exposure_measure' == 1

        display ///
            "Programs with positive `exposure_measure' exposure = " ///
            %9.0fc r(N)
    }

    drop tag_program_input


    /***************************************************************************
    4. FIXED-EFFECT SPECIFICATIONS
    ***************************************************************************/

    foreach fe_specification of local fe_specifications {


        /*
        Column 1: Program + year fixed effects.
        */

        if "`fe_specification'" == "programyear" {

            local absorbed_effects ///
                program_id ///
                ao_proceso

            local specification_label ///
                "Program FE + year FE"

            local specification_code ///
                "py"
        }


        /*
        Column 2: Program + field x year fixed effects.

        Common year fixed effects are contained in field x year FE.
        */

        if "`fe_specification'" == "fieldyear" {

            local absorbed_effects ///
                program_id ///
                level_field_year

            local specification_label ///
                "Program FE + field x year FE"

            local specification_code ///
                "fy"
        }


        /*
        Column 3: Program + field x year + region x year fixed effects.

        Common year effects are contained in the interacted fixed effects.
        */

        if "`fe_specification'" == "regionyear" {

            local absorbed_effects ///
                program_id ///
                level_field_year ///
                level_region_year

            local specification_label ///
                "Program FE + field x year FE + region x year FE"

            local specification_code ///
                "ry"
        }


        /***********************************************************************
        5. EXPOSURE MEASURES
        ***********************************************************************/

        foreach exposure_measure of local exposure_measures {


            if "`exposure_measure'" == "total" {

                local regressor ///
                    fs_total

                local exposure_label ///
                    "Total"

                local exposure_code ///
                    "tot"
            }

            if "`exposure_measure'" == "triangular" {

                local regressor ///
                    fs_triangular

                local exposure_label ///
                    "Triangular"

                local exposure_code ///
                    "tri"
            }

            if "`exposure_measure'" == "gaussian" {

                local regressor ///
                    fs_gaussian

                local exposure_label ///
                    "Gaussian"

                local exposure_code ///
                    "gau"
            }


            /*******************************************************************
            6. DISPLAY REGRESSION DESCRIPTION
            *******************************************************************/

            display ""
            display "============================================================"
            display " SUA FIRST STAGE IN LEVELS"
            display "============================================================"

            display ///
                "Field definition = `field_label'"

            display ///
                "Exposure measure = `exposure_label'"

            display ///
                "Fixed effects    = `specification_label'"

            display ///
                "Outcome          = First-year enrollment"

            display ///
                "Exposure scale   = 10 percentage points"

            display "============================================================"


            /*******************************************************************
            7. INDIVIDUAL FIRST-STAGE REGRESSION

            The regression is displayed in full in the Stata console.
            *******************************************************************/

            reghdfe ///
                N_firstyear_incumbent ///
                `regressor', ///
                absorb( ///
                    `absorbed_effects' ///
                ) ///
                vce(cluster market_pre)


            /*
            Store the regression individually.

            Examples:

                lvl_broad_tot_py
                lvl_broad_tri_fy
                lvl_generic_gau_ry
            */

            estimates store ///
                lvl_`field_code'_`exposure_code'_`specification_code'


            /*******************************************************************
            8. COEFFICIENT AND INFERENCE
            *******************************************************************/

            local beta = ///
                _b[`regressor']

            local standard_error = ///
                _se[`regressor']

            local observations = ///
                e(N)

            local residual_df = ///
                e(df_r)

            local critical_value = ///
                invttail( ///
                    `residual_df', ///
                    0.025 ///
                )

            local lower_95 = ///
                `beta' - ///
                `critical_value' * ///
                `standard_error'

            local upper_95 = ///
                `beta' + ///
                `critical_value' * ///
                `standard_error'


            /*
            Cluster-robust Wald test of the exposure coefficient.
            */

            quietly test ///
                `regressor'

            local F_statistic = ///
                r(F)

            local p_value = ///
                r(p)


            /*******************************************************************
            9. ESTIMATION-SAMPLE COUNTS
            *******************************************************************/

            tempvar ///
                estimation_sample ///
                tag_program ///
                tag_exposed_program ///
                tag_market

            gen byte `estimation_sample' = ///
                e(sample)

            egen byte `tag_program' = ///
                tag(program_id) ///
                if `estimation_sample' == 1

            quietly count if ///
                `tag_program' == 1

            local programs = ///
                r(N)


            egen byte `tag_exposed_program' = ///
                tag(program_id) ///
                if ///
                `estimation_sample' == 1 & ///
                positive_`exposure_measure' == 1

            quietly count if ///
                `tag_exposed_program' == 1

            local exposed_programs = ///
                r(N)


            egen byte `tag_market' = ///
                tag(market_pre) ///
                if `estimation_sample' == 1

            quietly count if ///
                `tag_market' == 1

            local markets = ///
                r(N)


            /*******************************************************************
            10. STORE RESULT IN COMPACT SUMMARY
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
                (`exposed_programs') ///
                (`markets')


            /*******************************************************************
            11. DISPLAY COMPACT REGRESSION RESULT
            *******************************************************************/

            display ""
            display "Compact result"

            display ///
                "Coefficient       = " ///
                %9.4f `beta'

            display ///
                "Standard error    = " ///
                %9.4f `standard_error'

            display ///
                "Wald F            = " ///
                %9.4f `F_statistic'

            display ///
                "p-value           = " ///
                %9.4f `p_value'

            display ///
                "Observations      = " ///
                %9.0fc `observations'

            display ///
                "Programs          = " ///
                %9.0fc `programs'

            display ///
                "Exposed programs  = " ///
                %9.0fc `exposed_programs'

            display ///
                "Markets           = " ///
                %9.0fc `markets'


            drop ///
                `estimation_sample' ///
                `tag_program' ///
                `tag_exposed_program' ///
                `tag_market'
        }
    }
}

postclose `results_handle'


/*******************************************************************************
12. LOAD AND VALIDATE SUMMARY RESULTS
*******************************************************************************/

use `level_results', clear

count

/*
Three fields x three exposures x three FE specifications = 27 regressions.
*/

assert r(N) == 27

isid ///
    fe_specification ///
    field_definition ///
    exposure_measure


/*
Confirm nine results for each fixed-effect specification.
*/

count if ///
    fe_specification == "programyear"

assert r(N) == 9


count if ///
    fe_specification == "fieldyear"

assert r(N) == 9


count if ///
    fe_specification == "regionyear"

assert r(N) == 9


/*******************************************************************************
13. FORMAT AND ORDER SUMMARY RESULTS
*******************************************************************************/

gen byte field_order = .

replace field_order = 1 ///
    if field_definition == "Broad"

replace field_order = 2 ///
    if field_definition == "ISCED-97"

replace field_order = 3 ///
    if field_definition == "Generic"


gen byte exposure_order = .

replace exposure_order = 1 ///
    if exposure_measure == "Total"

replace exposure_order = 2 ///
    if exposure_measure == "Triangular"

replace exposure_order = 3 ///
    if exposure_measure == "Gaussian"


gen byte specification_order = .

replace specification_order = 1 ///
    if fe_specification == "programyear"

replace specification_order = 2 ///
    if fe_specification == "fieldyear"

replace specification_order = 3 ///
    if fe_specification == "regionyear"


sort ///
    field_order ///
    exposure_order ///
    specification_order


format ///
    beta ///
    standard_error ///
    lower_95 ///
    upper_95 ///
    %9.4f

format ///
    F_statistic ///
    %9.2f

format ///
    p_value ///
    %9.4f

format ///
    observations ///
    programs ///
    exposed_programs ///
    markets ///
    %12.0fc


label variable ///
    fe_specification ///
    "Fixed-effect specification"

label variable ///
    field_definition ///
    "Field definition"

label variable ///
    exposure_measure ///
    "Exposure measure"

label variable ///
    beta ///
    "Exposure coefficient"

label variable ///
    standard_error ///
    "Clustered standard error"

label variable ///
    F_statistic ///
    "Cluster-robust Wald F"

label variable ///
    p_value ///
    "p-value"

label variable ///
    lower_95 ///
    "95% CI lower bound"

label variable ///
    upper_95 ///
    "95% CI upper bound"

label variable ///
    observations ///
    "Observations"

label variable ///
    programs ///
    "Programs"

label variable ///
    exposed_programs ///
    "Exposed programs"

label variable ///
    markets ///
    "Markets"


/*******************************************************************************
14. DISPLAY COMPACT SUMMARY
*******************************************************************************/

display ""
display "============================================================"
display " SUA FIRST-STAGE RESULTS: LEVELS"
display "============================================================"
display "One unit represents a 10 percentage-point exposure increase."
display ""

list ///
    field_definition ///
    exposure_measure ///
    fe_specification ///
    beta ///
    standard_error ///
    F_statistic ///
    p_value ///
    observations ///
    programs ///
    exposed_programs ///
    markets, ///
    sepby( ///
        field_definition ///
        exposure_measure ///
    ) ///
    noobs clean





/*******************************************************************************
15. END
*******************************************************************************/

display ""
display "============================================================"
display " LEVEL ESTIMATIONS COMPLETED"
display "============================================================"