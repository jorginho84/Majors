/**********************************************************************
* 05c_sua_kernelden_event_studies.do
*
* Objective:
*   Estimate level event studies for the new exposure measures
*   with kernel-weighted denominators.
*
* Measures:
*   exp_tri50kd
*   exp_gau50kd
*
* Specification:
*
*   N_firstyear_pt =
*       sum_s beta_s [10 * E_p x 1(year=s)]
*       + Program FE
*       + Field x Year FE
*       + Region x Year FE
*       + error
*
* Omitted year:
*   2011
*
* Cluster:
*   market_pre
*
* Pretrend test:
*   H0:
*       beta_2007 =
*       beta_2008 =
*       beta_2009 =
*       beta_2010 = 0
*
* Outputs:
*   Individual event-study figures for Broad, CINE97, and Generic
*   field definitions, plus a combined figure.
*
* Figures are exported as PNG only.
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
        "KD EVENT STUDY: `markettype' x region"

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
    * 1.4 Fixed effects
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
    * 1.5 Create exposure-by-year interactions
    *
    * Scale:
    *   One unit = 10 percentage points of exposure.
    ******************************************************************/

    foreach y of local years {

        gen double tri_`y' = ///
            10 * exp_tri50kd * ///
            (ao_proceso == `y')

        gen double gau_`y' = ///
            10 * exp_gau50kd * ///
            (ao_proceso == `y')

    }


    /******************************************************************
    * 1.6 TRIANGULAR
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "TRIANGULAR KD EVENT STUDY"


    reghdfe ///
        N_firstyear_incumbent ///
        tri_2007 ///
        tri_2008 ///
        tri_2009 ///
        tri_2010 ///
        tri_2012 ///
        tri_2013 ///
        tri_2014 ///
        tri_2015 ///
        tri_2016, ///
        absorb( ///
            program_id ///
            field_year ///
            region_year ///
        ) ///
        vce(cluster market_pre)


    /******************************************************************
    * 1.7 Joint pretrend test - Triangular
    ******************************************************************/

    test ///
        tri_2007 ///
        tri_2008 ///
        tri_2009 ///
        tri_2010

    local Fpre_tri = ///
        r(F)

    local ppre_tri = ///
        r(p)

    local ppre_tri_txt : ///
        display %5.3f `ppre_tri'


    di as result ///
        "Triangular pretrend F = " ///
        %9.4f `Fpre_tri'

    di as result ///
        "Triangular pretrend p = " ///
        %9.4f `ppre_tri'


    /******************************************************************
    * 1.8 Store Triangular coefficients temporarily
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
            _b[tri_`y']

        local se = ///
            _se[tri_`y']

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
    * 1.9 GAUSSIAN
    ******************************************************************/

    di as text ///
        "------------------------------------------------------------"

    di as result ///
        "GAUSSIAN KD EVENT STUDY"


    reghdfe ///
        N_firstyear_incumbent ///
        gau_2007 ///
        gau_2008 ///
        gau_2009 ///
        gau_2010 ///
        gau_2012 ///
        gau_2013 ///
        gau_2014 ///
        gau_2015 ///
        gau_2016, ///
        absorb( ///
            program_id ///
            field_year ///
            region_year ///
        ) ///
        vce(cluster market_pre)


    /******************************************************************
    * 1.10 Joint pretrend test - Gaussian
    ******************************************************************/

    test ///
        gau_2007 ///
        gau_2008 ///
        gau_2009 ///
        gau_2010

    local Fpre_gau = ///
        r(F)

    local ppre_gau = ///
        r(p)

    local ppre_gau_txt : ///
        display %5.3f `ppre_gau'


    di as result ///
        "Gaussian pretrend F = " ///
        %9.4f `Fpre_gau'

    di as result ///
        "Gaussian pretrend p = " ///
        %9.4f `ppre_gau'


    /******************************************************************
    * 1.11 Store Gaussian coefficients temporarily
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
            _b[gau_`y']

        local se = ///
            _se[gau_`y']

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
    * 1.12 Build temporary dataset for graph
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
    * 1.13 Small visual offset
    ******************************************************************/

    gen double year_plot = year

    replace year_plot = ///
        year - 0.08 ///
        if measure == 1

    replace year_plot = ///
        year + 0.08 ///
        if measure == 2


    /******************************************************************
    * 1.14 Event-study graph
    *
    * Each graph is kept in memory and exported at the end of the file.
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
            "Enrollment coefficient for a 0.10 increase in exposure" ///
        ) ///
        title( ///
            "Kernel-denominator exposure event study" ///
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
            "Pretrend p: Tri=`ppre_tri_txt'; Gau=`ppre_gau_txt'" ///
        ) ///
        name( ///
            kd_es_`markettype', ///
            replace ///
        )


    /******************************************************************
    * 1.15 Display coefficients
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



/**********************************************************************
* 3. Export figures
*
* PNG only. No .gph or PDF files are created.
**********************************************************************/

graph display ///
    kd_es_broad_area

graph export ///
    "$output/sua_kernelden_event_study_broad_area.png", ///
    replace ///
    width(2400)


graph display ///
    kd_es_cine_subarea

graph export ///
    "$output/sua_kernelden_event_study_cine_subarea.png", ///
    replace ///
    width(2400)


graph display ///
    kd_es_generic_area

graph export ///
    "$output/sua_kernelden_event_study_generic_area.png", ///
    replace ///
    width(2400)




di as result ///
    "KD level event studies completed."

di as result ///
    "Figures exported to $output."