/*******************************************************************************
04b_sua_weighted_first_stages.do

PURPOSE

Estimate the relevant selectivity-weighted SUA first stages.

SECTION A: MARKET-DEFINITION COMPARISON

    Field definitions:
        1. Broad area
        2. ISCED subarea
        3. Generic career area

    Exposures:
        1. Triangular kernel, h = 50 PSU points
        2. Gaussian kernel, h = 50 PSU points

    Fixed effects:
        Program FE
        Corresponding field x year FE

SECTION B: REGION-YEAR SENSITIVITY

    Field definition:
        Broad area only

    Exposures:
        1. Triangular
        2. Gaussian

    Fixed effects:
        Program FE
        Broad-field x year FE
        Pre-treatment region x year FE

OUTCOME

    N_firstyear_incumbent

INSTRUMENT

    Selectivity-weighted exposure x Post2012

SCALING

    One unit equals 10 percentage points of exposure.

INFERENCE

    Standard errors clustered by pre-treatment market.

ANALYTICAL SAMPLE

The original weighted first-stage sample is preserved so that the estimates
remain comparable with the previously reported results. In particular, the
sample requires nonmissing first-year enrollment, mean PSU, and all three
previously constructed exposure instruments.

The unweighted exposure is not estimated in this file. It remains in
04_sua_first_stage.do.

OUTPUT

Eight regression rows:

    baseline   x broad  x triangular
    baseline   x broad  x gaussian
    baseline   x ISCED  x triangular
    baseline   x ISCED  x gaussian
    baseline   x generic x triangular
    baseline   x generic x gaussian
    regionyear x broad  x triangular
    regionyear x broad  x gaussian
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

local kernels ///
    tri ///
    gau


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

tempfile weighted_results

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
    using `weighted_results', ///
    replace


/*******************************************************************************
4. ESTIMATION LOOP
*
* For every field definition:
*
*     baseline:
*         Program FE
*         Corresponding field x year FE
*
* For Broad area only:
*
*     regionyear:
*         Program FE
*         Broad-field x year FE
*         Pre-treatment region x year FE
*******************************************************************************/

foreach markettype of local markettypes {

    /***************************************************************************
    4.1 MAP FIELD-DEFINITION NAMES
    ***************************************************************************/

    if "`markettype'" == "broad_area" {

        local field_label ///
            "broad"
    }

    if "`markettype'" == "cine_subarea" {

        local field_label ///
            "isced"
    }

    if "`markettype'" == "generic_area" {

        local field_label ///
            "generic"
    }


    /***************************************************************************
    4.2 LOAD REGION-LEVEL WEIGHTED PANEL
    ***************************************************************************/

    local input ///
        "$processed/sua_incumbent_panel_w_`markettype'_region_2007_2016.dta"

    use "`input'", clear


    display ""
    display "============================================================"
    display " FIELD DEFINITION: `field_label'"
    display " GEOGRAPHY: REGION"
    display "============================================================"


    /***************************************************************************
    4.3 PRESERVE ORIGINAL ANALYTICAL SAMPLE
    *
    * These conditions reproduce the sample used by the original 04b.
    *
    * mean_psu_lm_firstyear and z_unw10 are retained only as common-sample
    * requirements. They are not outcomes or regressors in this file.
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


    /***************************************************************************
    4.4 REQUIRE PRE- AND POST-2012 SUPPORT
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

    assert _N > 0


    /***************************************************************************
    4.5 VERIFY THE PANEL
    ***************************************************************************/

    isid ///
        program_id ///
        ao_proceso


    /*
    The instruments should be zero before 2012.
    */

    assert z_tri10 == 0 ///
        if ao_proceso <= 2011

    assert z_gau10 == 0 ///
        if ao_proceso <= 2011


    /***************************************************************************
    4.6 CONSTRUCT FIXED-EFFECT IDENTIFIERS
    ***************************************************************************/

    /*
    Corresponding field x year FE.
    */

    egen long field_year = ///
        group( ///
            field_pre ///
            ao_proceso ///
        )


    /*
    Pre-treatment region x year FE.

    This is used only for Broad area.
    */

    egen long region_year = ///
        group( ///
            geo_pre ///
            ao_proceso ///
        )


    /***************************************************************************
    4.7 SPECIFICATIONS TO ESTIMATE
    *
    * All field definitions receive the baseline specification.
    *
    * Broad area additionally receives region x year FE.
    ***************************************************************************/

    local specifications ///
        baseline

    if "`markettype'" == "broad_area" {

        local specifications ///
            baseline ///
            regionyear
    }


    /***************************************************************************
    4.8 ESTIMATE RELEVANT SPECIFICATIONS
    ***************************************************************************/

    foreach specification of local specifications {

        /*
        Choose the fixed-effect structure.
        */

        if "`specification'" == "baseline" {

            local absorbed_fe ///
                program_id ///
                field_year

            local specification_title ///
                "PROGRAM FE + FIELD x YEAR FE"
        }


        if "`specification'" == "regionyear" {

            local absorbed_fe ///
                program_id ///
                field_year ///
                region_year

            local specification_title ///
                "PROGRAM FE + FIELD x YEAR FE + REGION x YEAR FE"
        }


        foreach kernel of local kernels {

            /*
            Select weighted exposure.
            */

            if "`kernel'" == "tri" {

                local instrument ///
                    z_tri10

                local exposure_label ///
                    "TRIANGULAR"
            }


            if "`kernel'" == "gau" {

                local instrument ///
                    z_gau10

                local exposure_label ///
                    "GAUSSIAN"
            }


            display ""
            display "------------------------------------------------------------"
            display "Field          = `field_label'"
            display "Exposure       = `exposure_label'"
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


            /*
            Coefficient and standard error.
            */

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
            Confidence interval.
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
            Cluster-robust Wald F test.
            */

            test `instrument'

            local first_stage_F = ///
                r(F)

            local p = ///
                r(p)


            /*
            Counts in the actual reghdfe sample.
            */

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


            /*
            Store one result row.
            */

            post `post_results' ///
                ("`specification'") ///
                ("`field_label'") ///
                ("`kernel'") ///
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


            /*
            Display compact results.
            */

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

use `weighted_results', clear


/*
Expected rows:

    6 baseline rows:
        3 field definitions x 2 exposures

    2 region-year rows:
        Broad x 2 exposures
*/

count
assert r(N) == 8


isid ///
    specification ///
    field_definition ///
    exposure


/*
Confirm that region-year is only estimated for Broad area.
*/

assert field_definition == "broad" ///
    if specification == "regionyear"


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
    if exposure == "tri"

replace exposure_order = 2 ///
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
9. DISPLAY BASELINE MARKET COMPARISON
*******************************************************************************/

display ""
display "============================================================"
display " BASELINE: MARKET-DEFINITION COMPARISON"
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
10. DISPLAY REGION-YEAR SENSITIVITY
*******************************************************************************/

display ""
display "============================================================"
display " BROAD AREA: SENSITIVITY TO REGION x YEAR FE"
display "============================================================"


list ///
    specification ///
    exposure_label ///
    beta ///
    se ///
    first_stage_F ///
    p ///
    N ///
    programs ///
    markets ///
    if field_definition == "broad", ///
    sepby(specification) ///
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