/**********************************************************************
* 04h_sua_kernelden_log_first_stages.do
*
* Objective:
*   Estimate log first stages using the exposure measures with
*   kernel-weighted denominators constructed in 03d.
*
* Zero correction:
*
*   log_tilde(E) = log(E) if E > 0
*                  0      if E = 0
*
*   D(E>0) = 1 if E > 0
*            0 if E = 0
*
* Specification:
*
*   log(N_firstyear_pt) =
*       beta  * [log_tilde(E_p) x Post_t]
*       + theta * [D(E_p>0) x Post_t]
*       + Program FE
*       + Field x Year FE
*       + Region x Year FE
*       + error
*
* Outcome:
*   Only N_firstyear_incumbent > 0.
*
* Cluster:
*   market_pre
*
* IMPORTANT:
*   Programs with E = 0 are NOT dropped.
*
* Does not save any output.
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


/**********************************************************************
* 1. Loop over field definitions
**********************************************************************/

forvalues i = 1/3 {

    local markettype : word `i' of `markettypes'

    di as text ///
        "============================================================"

    di as result ///
        "KD LOG FIRST STAGE: `markettype' x region"

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
        !missing(field_pre) & ///
        !missing(geo_pre) & ///
        !missing(market_pre)

    /*
    Log outcome:
    positive enrollment is required.
    */

    keep if ///
        N_firstyear_incumbent > 0 & ///
        !missing(N_firstyear_incumbent)

    /*
    E = 0 observations are retained.
    Only genuine missing exposure values are dropped.
    */

    keep if ///
        !missing(exp_tri50kd) & ///
        !missing(exp_gau50kd)


    /******************************************************************
    * 1.3 Log outcome
    ******************************************************************/

    gen double ln_enrollment = ///
        ln(N_firstyear_incumbent)


    /******************************************************************
    * 1.4 Zero-coded log and positive-exposure indicator
    ******************************************************************/

    gen double ln_tri_kd = 0

    replace ln_tri_kd = ///
        ln(exp_tri50kd) ///
        if exp_tri50kd > 0


    gen byte D_tri_kd = ///
        exp_tri50kd > 0


    gen double ln_gau_kd = 0

    replace ln_gau_kd = ///
        ln(exp_gau50kd) ///
        if exp_gau50kd > 0


    gen byte D_gau_kd = ///
        exp_gau50kd > 0


    /******************************************************************
    * 1.5 Post interactions
    ******************************************************************/

    gen double ln_tri_post = ///
        ln_tri_kd * post2012

    gen double D_tri_post = ///
        D_tri_kd * post2012


    gen double ln_gau_post = ///
        ln_gau_kd * post2012

    gen double D_gau_post = ///
        D_gau_kd * post2012


    /******************************************************************
    * 1.6 Fixed effects
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
    * 1.7 Sample descriptives
    ******************************************************************/

    egen byte tag_program = ///
        tag(program_id)

    egen byte tag_market = ///
        tag(market_pre)

    quietly count
    local N = r(N)

    quietly count if ///
        tag_program == 1

    local P = r(N)

    quietly count if ///
        tag_market == 1

    local M = r(N)


    quietly count if ///
        tag_program == 1 & ///
        exp_tri50kd == 0

    local Ztri = r(N)


    quietly count if ///
        tag_program == 1 & ///
        exp_gau50kd == 0

    local Zgau = r(N)


    di as text ///
        "Observations       = `N'"

    di as text ///
        "Programs           = `P'"

    di as text ///
        "Markets            = `M'"

    di as text ///
        "Programs Tri E=0   = `Ztri'"

    di as text ///
        "Programs Gau E=0   = `Zgau'"


    /******************************************************************
    * 1.8 TRIANGULAR
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "TRIANGULAR KD - LOG"

    reghdfe ///
        ln_enrollment ///
        ln_tri_post ///
        D_tri_post, ///
        absorb( ///
            program_id ///
            field_year ///
            region_year ///
        ) ///
        vce(cluster market_pre)


    local b_tri = ///
        _b[ln_tri_post]

    local se_tri = ///
        _se[ln_tri_post]


    test ln_tri_post

    local F_tri = ///
        r(F)

    local p_tri = ///
        r(p)


    capture local b_Dtri = ///
        _b[D_tri_post]

    capture local se_Dtri = ///
        _se[D_tri_post]


    di as result ///
        "beta log intensity = " ///
        %9.4f `b_tri'

    di as result ///
        "SE                 = " ///
        %9.4f `se_tri'

    di as result ///
        "F                  = " ///
        %9.4f `F_tri'

    di as result ///
        "p                  = " ///
        %9.4f `p_tri'


    /******************************************************************
    * 1.9 GAUSSIAN
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "GAUSSIAN KD - LOG"

    reghdfe ///
        ln_enrollment ///
        ln_gau_post ///
        D_gau_post, ///
        absorb( ///
            program_id ///
            field_year ///
            region_year ///
        ) ///
        vce(cluster market_pre)


    local b_gau = ///
        _b[ln_gau_post]

    local se_gau = ///
        _se[ln_gau_post]


    test ln_gau_post

    local F_gau = ///
        r(F)

    local p_gau = ///
        r(p)


    di as result ///
        "beta log intensity = " ///
        %9.4f `b_gau'

    di as result ///
        "SE                 = " ///
        %9.4f `se_gau'

    di as result ///
        "F                  = " ///
        %9.4f `F_gau'

    di as result ///
        "p                  = " ///
        %9.4f `p_gau'


    /******************************************************************
    * 1.10 Summary
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "SUMMARY: `markettype' x region"

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

}


di as result ///
    "KD log first stages completed."