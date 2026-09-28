/**********************************************************************
* 05d_sua_kernelden_log_event_studies.do
*
* Objective:
*   Estimate log event studies for the exposure measures with
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
*   log(N_pt) =
*
*       sum_{s != 2011}
*           beta_s [log_tilde(E_p) x 1(year=s)]
*
*       + sum_{s != 2011}
*           theta_s [D(E_p>0) x 1(year=s)]
*
*       + Program FE
*       + Field x Year FE
*       + Region x Year FE
*       + error
*
* Omitted year:
*   2011
*
* Outcome:
*   Only N_firstyear_incumbent > 0.
*
* Pretrend test:
*   Only the beta coefficients associated with log_tilde(E):
*
*       beta_2007 =
*       beta_2008 =
*       beta_2009 =
*       beta_2010 = 0
*
* The D(E>0) x year controls are not plotted.
*
* Outputs:
*   One PNG event-study figure for each field definition.
*
* No combined figure is created or saved.
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

local years ///
    2007 ///
    2008 ///
    2009 ///
    2010 ///
    2012 ///
    2013 ///
    2014 ///
    2015 ///
    2016


/**********************************************************************
* 1. Loop over field definitions
**********************************************************************/

forvalues i = 1/3 {

    local markettype : word `i' of `markettypes'

    di as text ///
        "============================================================"

    di as result ///
        "KD LOG EVENT STUDY: `markettype' x region"

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
    Positive enrollment is required for the log outcome.
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
    * 1.3 Validations
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
    * 1.4 Log outcome
    ******************************************************************/

    gen double ln_enrollment = ///
        ln(N_firstyear_incumbent)


    /******************************************************************
    * 1.5 Construct log_tilde(E) and D(E>0)
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
    * 1.7 Create year interactions
    *
    * beta_s:
    *   log_tilde(E) x year
    *
    * theta_s:
    *   D(E>0) x year
    *
    * 2011 is omitted.
    ******************************************************************/

    foreach y of local years {

        gen double ltri_`y' = ///
            ln_tri_kd * ///
            (ao_proceso == `y')

        gen double dtri_`y' = ///
            D_tri_kd * ///
            (ao_proceso == `y')


        gen double lgau_`y' = ///
            ln_gau_kd * ///
            (ao_proceso == `y')

        gen double dgau_`y' = ///
            D_gau_kd * ///
            (ao_proceso == `y')

    }


    /******************************************************************
    * 1.8 Sample descriptives
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
    * 2. TRIANGULAR
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "TRIANGULAR KD LOG EVENT STUDY"


    reghdfe ///
        ln_enrollment ///
        ltri_2007 ///
        ltri_2008 ///
        ltri_2009 ///
        ltri_2010 ///
        ltri_2012 ///
        ltri_2013 ///
        ltri_2014 ///
        ltri_2015 ///
        ltri_2016 ///
        dtri_2007 ///
        dtri_2008 ///
        dtri_2009 ///
        dtri_2010 ///
        dtri_2012 ///
        dtri_2013 ///
        dtri_2014 ///
        dtri_2015 ///
        dtri_2016, ///
        absorb( ///
            program_id ///
            field_year ///
            region_year ///
        ) ///
        vce(cluster market_pre)


    /******************************************************************
    * 2.1 Joint pretrend test
    *
    * Only beta_s coefficients for log exposure intensity.
    ******************************************************************/

    test ///
        ltri_2007 ///
        ltri_2008 ///
        ltri_2009 ///
        ltri_2010

    local Fpre_tri = r(F)
    local ppre_tri = r(p)

    local ppre_tri_txt : ///
        display %5.3f `ppre_tri'


    di as result ///
        "Triangular pretrend F = " ///
        %9.4f `Fpre_tri'

    di as result ///
        "Triangular pretrend p = " ///
        %9.4f `ppre_tri'


    /******************************************************************
    * 2.2 Store beta_s coefficients temporarily
    ******************************************************************/

    tempfile tri_results

    tempname posttri

    postfile `posttri' ///
        int year ///
        double beta ///
        double se ///
        double low ///
        double high ///
        using `tri_results', ///
        replace


    foreach y of local years {

        local b = ///
            _b[ltri_`y']

        local se = ///
            _se[ltri_`y']

        local lo = ///
            `b' - 1.96 * `se'

        local hi = ///
            `b' + 1.96 * `se'

        post `posttri' ///
            (`y') ///
            (`b') ///
            (`se') ///
            (`lo') ///
            (`hi')

    }


    /*
    Omitted year: 2011.
    */

    post `posttri' ///
        (2011) ///
        (0) ///
        (0) ///
        (0) ///
        (0)

    postclose `posttri'


    /******************************************************************
    * 3. GAUSSIAN
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "GAUSSIAN KD LOG EVENT STUDY"


    reghdfe ///
        ln_enrollment ///
        lgau_2007 ///
        lgau_2008 ///
        lgau_2009 ///
        lgau_2010 ///
        lgau_2012 ///
        lgau_2013 ///
        lgau_2014 ///
        lgau_2015 ///
        lgau_2016 ///
        dgau_2007 ///
        dgau_2008 ///
        dgau_2009 ///
        dgau_2010 ///
        dgau_2012 ///
        dgau_2013 ///
        dgau_2014 ///
        dgau_2015 ///
        dgau_2016, ///
        absorb( ///
            program_id ///
            field_year ///
            region_year ///
        ) ///
        vce(cluster market_pre)


    /******************************************************************
    * 3.1 Joint pretrend test
    ******************************************************************/

    test ///
        lgau_2007 ///
        lgau_2008 ///
        lgau_2009 ///
        lgau_2010

    local Fpre_gau = r(F)
    local ppre_gau = r(p)

    local ppre_gau_txt : ///
        display %5.3f `ppre_gau'


    di as result ///
        "Gaussian pretrend F = " ///
        %9.4f `Fpre_gau'

    di as result ///
        "Gaussian pretrend p = " ///
        %9.4f `ppre_gau'


    /******************************************************************
    * 3.2 Store beta_s coefficients temporarily
    ******************************************************************/

    tempfile gau_results

    tempname postgau

    postfile `postgau' ///
        int year ///
        double beta ///
        double se ///
        double low ///
        double high ///
        using `gau_results', ///
        replace


    foreach y of local years {

        local b = ///
            _b[lgau_`y']

        local se = ///
            _se[lgau_`y']

        local lo = ///
            `b' - 1.96 * `se'

        local hi = ///
            `b' + 1.96 * `se'

        post `postgau' ///
            (`y') ///
            (`b') ///
            (`se') ///
            (`lo') ///
            (`hi')

    }


    post `postgau' ///
        (2011) ///
        (0) ///
        (0) ///
        (0) ///
        (0)

    postclose `postgau'


    /******************************************************************
    * 4. Build temporary dataset for graph
    ******************************************************************/

    use `tri_results', clear

    gen byte measure = 1

    append using `gau_results'

    replace measure = 2 ///
        if missing(measure)


    label define measure_lbl ///
        1 "Triangular" ///
        2 "Gaussian"

    label values ///
        measure ///
        measure_lbl


    /******************************************************************
    * 4.1 Small visual offset
    ******************************************************************/

    gen double year_plot = year

    replace year_plot = ///
        year - 0.08 ///
        if measure == 1

    replace year_plot = ///
        year + 0.08 ///
        if measure == 2


    /******************************************************************
    * 4.2 Event-study graph
    *
    * The graph remains open in Stata and is also exported as PNG.
    * No combined graph is created.
    ******************************************************************/

    twoway ///
        (rcap low high year_plot ///
            if measure == 1) ///
        (scatter beta year_plot ///
            if measure == 1, ///
            msymbol(triangle)) ///
        (rcap low high year_plot ///
            if measure == 2) ///
        (scatter beta year_plot ///
            if measure == 2, ///
            msymbol(diamond)), ///
        xline( ///
            2011, ///
            lpattern(dash) ///
        ) ///
        yline( ///
            0, ///
            lpattern(solid) ///
        ) ///
        xlabel( ///
            2007(1)2016, ///
            angle(45) ///
        ) ///
        xtitle("Year") ///
        ytitle( ///
            "Enrollment elasticity with respect to exposure" ///
        ) ///
        title( ///
            "Kernel-denominator log exposure event study" ///
        ) ///
        subtitle( ///
            "`markettype' x region" ///
        ) ///
        legend( ///
            order( ///
                2 "Triangular" ///
                4 "Gaussian" ///
            ) ///
            rows(1) ///
        ) ///
        note( ///
            "2011 omitted. Program, field x year, and region x year FE." ///
            "Zero exposure retained; D(E>0) x year controls included but not plotted." ///
            "Pretrend p: Tri=`ppre_tri_txt'; Gau=`ppre_gau_txt'" ///
        ) ///
        name( ///
            kd_log_es_`markettype', ///
            replace ///
        )


    /******************************************************************
    * 4.3 Export graph
    *
    * PNG only.
    ******************************************************************/

    graph export ///
        "$output/sua_kernelden_log_event_study_`markettype'.png", ///
        replace ///
        width(2400)


    /******************************************************************
    * 4.4 Display plotted coefficients
    ******************************************************************/

    sort ///
        measure ///
        year

    list ///
        measure ///
        year ///
        beta ///
        se ///
        low ///
        high, ///
        noobs ///
        sepby(measure)


    /******************************************************************
    * 4.5 Pretrend summary
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "PRETRENDS: `markettype' x region"

    di as result ///
        "Triangular: F=" ///
        %8.3f `Fpre_tri' ///
        "  p=" ///
        %8.4f `ppre_tri'

    di as result ///
        "Gaussian:   F=" ///
        %8.3f `Fpre_gau' ///
        "  p=" ///
        %8.4f `ppre_gau'

}


di as result ///
    "KD log event studies completed."

di as result ///
    "Individual figures exported to $output."