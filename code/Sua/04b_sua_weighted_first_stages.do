/*******************************************************************************
04b_sua_weighted_first_stages.do

PURPOSE

Compare the three SUA exposure measures across alternative definitions of the
academic market and two fixed-effect specifications.

FIELD DEFINITIONS

    1. Broad area
    2. ISCED subarea
    3. Generic career area

EXPOSURES

    1. Total exposure
    2. Triangular exposure
    3. Gaussian exposure

SPECIFICATIONS

    baseline:
        Program FE
        Field x year FE

    regionyear:
        Program FE
        Field x year FE
        Region x year FE

OUTCOME

    N_firstyear_incumbent

SCALING

    One unit of z_unw10, z_tri10, or z_gau10 corresponds to
    10 percentage points of the respective exposure.

INFERENCE

    Standard errors clustered by pre-treatment market.

TOTAL REGRESSIONS

    3 field definitions
    x 3 exposure measures
    x 2 FE specifications
    = 18 regressions
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

local markettypes ///
    broad_area ///
    cine_subarea ///
    generic_area

local exposures ///
    unw ///
    tri ///
    gau

local specifications ///
    baseline ///
    regionyear


/*******************************************************************************
2. OUTPUTS
*******************************************************************************/

local results_dta ///
    "$processed/sua_weighted_first_stage_results.dta"

local results_xlsx ///
    "$output/sua_weighted_first_stage_results.xlsx"


/*******************************************************************************
3. RESULTS STORAGE
*******************************************************************************/

tempfile first_stage_results
tempname post_results

postfile `post_results' ///
    str12 specification ///
    str16 field_definition ///
    str12 exposure ///
    double beta ///
    double se ///
    double t ///
    double first_stage_F ///
    double p ///
    double lb ///
    double ub ///
    long N ///
    long programs ///
    long markets ///
    using `first_stage_results', ///
    replace


/*******************************************************************************
4. ESTIMATION
*******************************************************************************/

foreach markettype of local markettypes {

    /***************************************************************************
    4.1 FIELD-DEFINITION LABEL
    ***************************************************************************/

    if "`markettype'" == "broad_area" {
        local field_definition "broad"
    }

    if "`markettype'" == "cine_subarea" {
        local field_definition "isced"
    }

    if "`markettype'" == "generic_area" {
        local field_definition "generic"
    }


    /***************************************************************************
    4.2 LOAD CORRESPONDING REGION-LEVEL PANEL
    ***************************************************************************/

    local input ///
        "$processed/sua_incumbent_panel_w_`markettype'_region_2007_2016.dta"

    use "`input'", clear

    display ""
    display "============================================================"
    display " FIELD DEFINITION: `field_definition'"
    display " GEOGRAPHY: REGION"
    display "============================================================"


    /***************************************************************************
    4.3 COMMON ANALYTICAL SAMPLE
    *
    * Requiring all three instruments keeps Total, Triangular and Gaussian
    * directly comparable within each field definition.
    ***************************************************************************/

    drop if missing( ///
        program_id, ///
        ao_proceso, ///
        field_pre, ///
        geo_pre, ///
        market_pre, ///
        N_firstyear_incumbent, ///
        mean_psu_lm_firstyear, ///
        z_unw10, ///
        z_tri10, ///
        z_gau10 ///
    )

    assert _N > 0


    /*
    Require each program to have observations before and after the reform.
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


    /***************************************************************************
    4.4 VERIFY PANEL AND EXPOSURES
    ***************************************************************************/

    isid ///
        program_id ///
        ao_proceso

    foreach instrument in ///
        z_unw10 ///
        z_tri10 ///
        z_gau10 {

        assert `instrument' == 0 ///
            if ao_proceso <= 2011
    }


    /***************************************************************************
    4.5 FIXED-EFFECT IDENTIFIERS
    ***************************************************************************/

    /*
    Field definition x year FE.

    Since each input panel corresponds to a different field definition,
    field_pre represents Broad, ISCED or Generic as appropriate.
    */

    egen long field_year = ///
        group( ///
            field_pre ///
            ao_proceso ///
        )


    /*
    Pre-treatment region x year FE.
    */

    egen long region_year = ///
        group( ///
            geo_pre ///
            ao_proceso ///
        )


    /***************************************************************************
    4.6 SPECIFICATIONS
    ***************************************************************************/

    foreach specification of local specifications {

        /*
        Baseline:
            Program FE
            Field x year FE
        */

        if "`specification'" == "baseline" {

            local absorbed_fe ///
                program_id ///
                field_year

            local specification_title ///
                "PROGRAM FE + FIELD x YEAR FE"
        }


        /*
        Region-year:
            Program FE
            Field x year FE
            Region x year FE
        */

        if "`specification'" == "regionyear" {

            local absorbed_fe ///
                program_id ///
                field_year ///
                region_year

            local specification_title ///
                "PROGRAM FE + FIELD x YEAR FE + REGION x YEAR FE"
        }


        /***********************************************************************
        4.7 EXPOSURE MEASURES
        ***********************************************************************/

        foreach exposure of local exposures {

            /*
            Total exposure.
            */

            if "`exposure'" == "unw" {

                local instrument ///
                    z_unw10

                local exposure_title ///
                    "TOTAL EXPOSURE"
            }


            /*
            Triangular exposure.
            */

            if "`exposure'" == "tri" {

                local instrument ///
                    z_tri10

                local exposure_title ///
                    "TRIANGULAR"
            }


            /*
            Gaussian exposure.
            */

            if "`exposure'" == "gau" {

                local instrument ///
                    z_gau10

                local exposure_title ///
                    "GAUSSIAN"
            }


            display ""
            display "------------------------------------------------------------"
            display "Field          = `field_definition'"
            display "Exposure       = `exposure_title'"
            display "Specification  = `specification'"
            display "`specification_title'"
            display "------------------------------------------------------------"


            /*******************************************************************
            FIRST-STAGE REGRESSION
            *******************************************************************/

            reghdfe ///
                N_firstyear_incumbent ///
                `instrument', ///
                absorb( ///
                    `absorbed_fe' ///
                ) ///
                vce(cluster market_pre)


            /*******************************************************************
            COEFFICIENT AND INFERENCE
            *******************************************************************/

            local beta = ///
                _b[`instrument']

            local se = ///
                _se[`instrument']

            local t = ///
                `beta' / `se'

            local df_r = ///
                e(df_r)

            local N_estimation = ///
                e(N)


            /*
            95% confidence interval.
            */

            local critical_value = ///
                invttail(`df_r', 0.025)

            local lb = ///
                `beta' - ///
                `critical_value' * `se'

            local ub = ///
                `beta' + ///
                `critical_value' * `se'


            /*
            Cluster-robust Wald F statistic.
            */

            test `instrument'

            local first_stage_F = ///
                r(F)

            local p = ///
                r(p)


            /*******************************************************************
            SAMPLE COUNTS
            *******************************************************************/

            quietly levelsof ///
                program_id ///
                if e(sample), ///
                local(sample_programs)

            local N_programs : ///
                word count `sample_programs'


            quietly levelsof ///
                market_pre ///
                if e(sample), ///
                local(sample_markets)

            local N_markets : ///
                word count `sample_markets'


            /*******************************************************************
            STORE RESULTS
            *******************************************************************/

            post `post_results' ///
                ("`specification'") ///
                ("`field_definition'") ///
                ("`exposure'") ///
                (`beta') ///
                (`se') ///
                (`t') ///
                (`first_stage_F') ///
                (`p') ///
                (`lb') ///
                (`ub') ///
                (`N_estimation') ///
                (`N_programs') ///
                (`N_markets')


            /*******************************************************************
            DISPLAY COMPACT RESULT
            *******************************************************************/

            display ///
                "Beta          = " ///
                %9.4f `beta'

            display ///
                "SE            = " ///
                %9.4f `se'

            display ///
                "First-stage F = " ///
                %9.4f `first_stage_F'

            display ///
                "p             = " ///
                %9.4f `p'

            display ///
                "N             = " ///
                %9.0fc `N_estimation'

            display ///
                "Programs      = " ///
                %9.0fc `N_programs'

            display ///
                "Markets       = " ///
                %9.0fc `N_markets'
        }
    }
}

postclose `post_results'


/*******************************************************************************
5. LOAD AND VALIDATE RESULTS
*******************************************************************************/

use `first_stage_results', clear


/*
There must be:

    3 field definitions
    x 3 exposures
    x 2 specifications
    = 18 rows
*/

count
assert r(N) == 18


/*
Each row must identify a unique regression.
*/

isid ///
    specification ///
    field_definition ///
    exposure


/*
There must be nine baseline and nine region-year regressions.
*/

count if specification == "baseline"
assert r(N) == 9

count if specification == "regionyear"
assert r(N) == 9


/*
There must be six regressions for each field definition.
*/

foreach field in ///
    broad ///
    isced ///
    generic {

    count if field_definition == "`field'"
    assert r(N) == 6
}


/*******************************************************************************
6. LABEL RESULTS
*******************************************************************************/

gen str20 field_label = ""

replace field_label = ///
    "Broad area" ///
    if field_definition == "broad"

replace field_label = ///
    "ISCED subarea" ///
    if field_definition == "isced"

replace field_label = ///
    "Generic area" ///
    if field_definition == "generic"


gen str20 exposure_label = ""

replace exposure_label = ///
    "Total exposure" ///
    if exposure == "unw"

replace exposure_label = ///
    "Triangular" ///
    if exposure == "tri"

replace exposure_label = ///
    "Gaussian" ///
    if exposure == "gau"


assert field_label != ""
assert exposure_label != ""


/*******************************************************************************
7. ORDER RESULTS
*******************************************************************************/

gen byte specification_order = .

replace specification_order = 1 ///
    if specification == "baseline"

replace specification_order = 2 ///
    if specification == "regionyear"


gen byte field_order = .

replace field_order = 1 ///
    if field_definition == "broad"

replace field_order = 2 ///
    if field_definition == "isced"

replace field_order = 3 ///
    if field_definition == "generic"


gen byte exposure_order = .

replace exposure_order = 1 ///
    if exposure == "unw"

replace exposure_order = 2 ///
    if exposure == "tri"

replace exposure_order = 3 ///
    if exposure == "gau"


sort ///
    specification_order ///
    field_order ///
    exposure_order


/*******************************************************************************
8. FORMATS
*******************************************************************************/

format ///
    beta ///
    se ///
    t ///
    first_stage_F ///
    p ///
    lb ///
    ub ///
    %9.4f


order ///
    specification ///
    field_definition ///
    field_label ///
    exposure ///
    exposure_label ///
    beta ///
    se ///
    t ///
    first_stage_F ///
    p ///
    lb ///
    ub ///
    N ///
    programs ///
    markets ///
    specification_order ///
    field_order ///
    exposure_order


/*******************************************************************************
9. DISPLAY BASELINE RESULTS
*******************************************************************************/

display ""
display "============================================================"
display " BASELINE: MARKET-DEFINITION COMPARISON"
display " Program FE + field x year FE"
display "============================================================"


list ///
    field_label ///
    exposure_label ///
    beta ///
    se ///
    first_stage_F ///
    p ///
    N ///
    programs ///
    markets ///
    if specification == "baseline", ///
    sepby(field_definition) ///
    noobs clean


/*******************************************************************************
10. DISPLAY REGION-YEAR RESULTS
*******************************************************************************/

display ""
display "============================================================"
display " REGION x YEAR: MARKET-DEFINITION COMPARISON"
display " Program FE + field x year FE + region x year FE"
display "============================================================"


list ///
    field_label ///
    exposure_label ///
    beta ///
    se ///
    first_stage_F ///
    p ///
    N ///
    programs ///
    markets ///
    if specification == "regionyear", ///
    sepby(field_definition) ///
    noobs clean


/*******************************************************************************
11. SAVE RESULTS
*******************************************************************************/

save ///
    "`results_dta'", ///
    replace


export excel ///
    using "`results_xlsx'", ///
    firstrow(variables) ///
    replace


display ""
display "============================================================"
display " OUTPUTS"
display "============================================================"

display ///
    "Saved: `results_dta'"

display ///
    "Exported: `results_xlsx'"

display ""
display "04b_sua_weighted_first_stages.do completed successfully."