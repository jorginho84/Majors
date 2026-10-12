/**********************************************************************
* 04g_sua_kernelden_first_stages.do
*
* Objective:
*   Estimate level first stages using the new exposure measures
*   with kernel-weighted denominators constructed in 03d.
*
* Measures:
*   exp_tri50kd
*   exp_gau50kd
*
* Main specification:
*
*   N_firstyear_incumbent_pt =
*       beta * [Exposure_p x Post_t]
*       + Program FE
*       + Field x Year FE
*       + Region x Year FE
*       + error
*
* Cluster:
*   market_pre
*
* Scale:
*   One unit of z_*kd10 = a 10 percentage point increase
*   in exposure.
*
* Inputs:
*   sua_incumbent_panel_kd_<market>_region_2007_2016.dta
*
* Does not modify previous outputs.
**********************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/**********************************************************************
* 0. Definitions
**********************************************************************/

local markettypes ///
    broad_area ///
    cine_subarea ///
    generic_area

local fieldvars ///
    field_pre ///
    field_pre ///
    field_pre


/**********************************************************************
* 1. Loop over field definitions
**********************************************************************/

forvalues i = 1/3 {

    local markettype : word `i' of `markettypes'

    di as text ///
        "============================================================"

    di as result ///
        "KERNEL-DENOMINATOR FIRST STAGE: `markettype' × region"

    di as text ///
        "============================================================"


    /******************************************************************
    * 1.1 Load panel
    ******************************************************************/

    use ///
        "$processed/sua_incumbent_panel_kd_`markettype'_region_2007_2016.dta", ///
        clear


    /******************************************************************
    * 1.2 Sample
    ******************************************************************/

    keep if ///
        !missing(program_id) & ///
        !missing(ao_proceso) & ///
        !missing(N_firstyear_incumbent) & ///
        !missing(field_pre) & ///
        !missing(geo_pre) & ///
        !missing(market_pre)

    /*
    KD exposure measures require pre-treatment PSU
    for the incumbent program.
    */

    keep if ///
        !missing(exp_tri50kd) & ///
        !missing(exp_gau50kd)


    /******************************************************************
    * 1.3 Basic validations
    ******************************************************************/

    isid ///
        program_id ///
        ao_proceso

    assert inrange( ///
        exp_tri50kd, ///
        0, ///
        1.0000001 ///
    )

    assert inrange( ///
        exp_gau50kd, ///
        0, ///
        1.0000001 ///
    )


    /******************************************************************
    * 1.4 Post interactions
    *
    * One unit = 10 percentage points of exposure.
    ******************************************************************/

    capture drop z_tri50kd10
    capture drop z_gau50kd10

    gen double z_tri50kd10 = ///
        10 * exp_tri50kd * post2012

    gen double z_gau50kd10 = ///
        10 * exp_gau50kd * post2012


    /******************************************************************
    * 1.5 Fixed effects
    ******************************************************************/

    egen long field_year = ///
        group( ///
            field_pre ///
            ao_proceso ///
        )

    egen long region_year = ///
        group( ///
            geo_pre ///
            ao_proceso ///
        )


    /******************************************************************
    * 1.6 Sample descriptives
    ******************************************************************/

    egen byte tag_program = ///
        tag(program_id)

    egen byte tag_market = ///
        tag(market_pre)

    quietly count
    local N = r(N)

    quietly count if tag_program == 1
    local P = r(N)

    quietly count if tag_market == 1
    local M = r(N)

    di as text ///
        "Observations = `N'"

    di as text ///
        "Programs     = `P'"

    di as text ///
        "Markets      = `M'"


    /******************************************************************
    * 1.7 TRIANGULAR
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "TRIANGULAR KD EXPOSURE"

    reghdfe ///
        N_firstyear_incumbent ///
        z_tri50kd10, ///
        absorb( ///
            program_id ///
            field_year ///
            region_year ///
        ) ///
        vce(cluster market_pre)

    local b_tri = ///
        _b[z_tri50kd10]

    local se_tri = ///
        _se[z_tri50kd10]

    test z_tri50kd10

    local F_tri = ///
        r(F)

    local p_tri = ///
        r(p)

    di as result ///
        "beta = " %9.4f `b_tri'

    di as result ///
        "SE   = " %9.4f `se_tri'

    di as result ///
        "F    = " %9.4f `F_tri'

    di as result ///
        "p    = " %9.4f `p_tri'


    /******************************************************************
    * 1.8 GAUSSIAN
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "GAUSSIAN KD EXPOSURE"

    reghdfe ///
        N_firstyear_incumbent ///
        z_gau50kd10, ///
        absorb( ///
            program_id ///
            field_year ///
            region_year ///
        ) ///
        vce(cluster market_pre)

    local b_gau = ///
        _b[z_gau50kd10]

    local se_gau = ///
        _se[z_gau50kd10]

    test z_gau50kd10

    local F_gau = ///
        r(F)

    local p_gau = ///
        r(p)

    di as result ///
        "beta = " %9.4f `b_gau'

    di as result ///
        "SE   = " %9.4f `se_gau'

    di as result ///
        "F    = " %9.4f `F_gau'

    di as result ///
        "p    = " %9.4f `p_gau'


    /******************************************************************
    * 1.9 Quick comparison
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "SUMMARY: `markettype' × region"

    di as text ///
        "Triangular: beta=" ///
        %9.4f `b_tri' ///
        "  SE=" ///
        %9.4f `se_tri' ///
        "  F=" ///
        %9.3f `F_tri' ///
        "  p=" ///
        %9.4f `p_tri'

    di as text ///
        "Gaussian:   beta=" ///
        %9.4f `b_gau' ///
        "  SE=" ///
        %9.4f `se_gau' ///
        "  F=" ///
        %9.3f `F_gau' ///
        "  p=" ///
        %9.4f `p_gau'


    drop ///
        tag_program ///
        tag_market ///
        field_year ///
        region_year

}


di as result ///
    "Kernel-denominator level first stages completed."