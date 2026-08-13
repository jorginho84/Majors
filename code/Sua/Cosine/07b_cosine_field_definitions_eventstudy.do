/*******************************************************************************
07b_cosine_field_definitions_eventstudy.do

PURPOSE

Event-study comparison across three PSU-only cosine exposures.

Each exposure uses its corresponding academic field x year FE:

GENERAL:
    exposure = z_exp_psu_rf
    FE       = area_conocimiento_2011 x year

CINE97:
    exposure = z_exp_psu_rcine
    FE       = cine_f_13_subarea_2011 x year

GENERIC:
    exposure = z_exp_psu_rgen 
    FE       = area_carrera_generica_2011 x year

OUTCOME:
    N_firstyear

REFERENCE YEAR:
    2011

IMPORTANT:
    Exposure x year interactions are manually generated.
    2011 is explicitly omitted.

SPECIFICATIONS:

A. Baseline
       Program FE
       Corresponding field x year FE

B. Region-year
       Program FE
       Corresponding field x year FE
       Region x year FE

CLUSTER:
    Program
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
0. INPUTS
*******************************************************************************/

local panel ///
    "$processed/sua_exposure/sies_program_year_with_demre_2007_2016.dta"

local roster ///
    "$processed/sua_exposure/sua_university_sies_roster.dta"

local exp_general ///
    "$processed/cosine_exposure_incumbents_2011_same_region_field.dta"

local exp_cine ///
    "$processed/cosine_exposure_incumbents_2011_same_region_cine97.dta"

local exp_generic ///
    "$processed/cosine_exposure_incumbents_2011_same_region_generic.dta"


/*******************************************************************************
1. LOAD PANEL
*******************************************************************************/

use "`panel'", clear

keep if inrange(ao_proceso, 2007, 2016)

isid ///
    codigo_unico ///
    ao_proceso


/*******************************************************************************
2. SUA INCUMBENTS
*******************************************************************************/

preserve

    use "`roster'", clear

    keep ///
        cod_inst ///
        entrant_2012

    duplicates drop

    isid cod_inst

    tempfile sua_roster
    save `sua_roster', replace

restore


merge m:1 cod_inst ///
    using `sua_roster', ///
    keep(master match) ///
    gen(_m_roster)

keep if _m_roster == 3

drop _m_roster

keep if entrant_2012 == 0


/*******************************************************************************
3. GENERAL EXPOSURE
*******************************************************************************/

preserve

    use "`exp_general'", clear

    keep ///
        codigo_unico_2011 ///
        z_exp_psu_rf

    rename codigo_unico_2011 ///
        codigo_unico

    isid codigo_unico

    tempfile general_exp
    save `general_exp', replace

restore


merge m:1 codigo_unico ///
    using `general_exp', ///
    keep(master match) ///
    gen(_m_general)

keep if _m_general == 3

drop _m_general


/*******************************************************************************
4. CINE97 EXPOSURE
*******************************************************************************/

preserve

    use "`exp_cine'", clear

    keep ///
        codigo_unico_2011 ///
        z_exp_psu_rcine

    rename codigo_unico_2011 ///
        codigo_unico

    isid codigo_unico

    tempfile cine_exp
    save `cine_exp', replace

restore


merge m:1 codigo_unico ///
    using `cine_exp', ///
    keep(master match) ///
    gen(_m_cine)

keep if _m_cine == 3

drop _m_cine


/*******************************************************************************
5. GENERIC EXPOSURE
*******************************************************************************/

preserve

    use "`exp_generic'", clear

    keep ///
        codigo_unico_2011 ///
        z_exp_psu_rgen

    rename codigo_unico_2011 ///
        codigo_unico

    isid codigo_unico

    tempfile generic_exp
    save `generic_exp', replace

restore


merge m:1 codigo_unico ///
    using `generic_exp', ///
    keep(master match) ///
    gen(_m_generic)

keep if _m_generic == 3

drop _m_generic


/*******************************************************************************
6. COMMON RAW SAMPLE
*******************************************************************************/

drop if missing( ///
    N_firstyear, ///
    z_exp_psu_rf, ///
    z_exp_psu_rcine, ///
    z_exp_psu_rgen ///
)


/*******************************************************************************
7. FIX FIELD DEFINITIONS AT 2011
*******************************************************************************/

/*
General field.
*/

gen str40 field_gen_temp = ///
    area_conocimiento ///
    if ao_proceso == 2011

bysort codigo_unico: ///
    egen str40 field_gen = ///
        mode(field_gen_temp), ///
        minmode

drop field_gen_temp


/*
CINE97.
*/

gen str80 field_cine_temp = ///
    cine_f_13_subarea ///
    if ao_proceso == 2011

bysort codigo_unico: ///
    egen str80 field_cine = ///
        mode(field_cine_temp), ///
        minmode

drop field_cine_temp


/*
Generic career area.
*/

gen str100 field_rgen_temp = ///
    area_carrera_generica ///
    if ao_proceso == 2011

bysort codigo_unico: ///
    egen str100 field_rgen = ///
        mode(field_rgen_temp), ///
        minmode

drop field_rgen_temp


/*
Region.
*/

gen double region_temp = ///
    id_region ///
    if ao_proceso == 2011

bysort codigo_unico: ///
    egen double region_pre = ///
        max(region_temp)

drop region_temp


drop if ///
    missing(field_gen) | ///
    field_gen == ""

drop if ///
    missing(field_cine) | ///
    field_cine == ""

drop if ///
    missing(field_rgen) | ///
    field_rgen == ""

drop if missing(region_pre)


/*******************************************************************************
8. REQUIRE PRE + POST SUPPORT
*******************************************************************************/

bysort codigo_unico: ///
    egen byte has_pre = ///
        max(ao_proceso <= 2011)

bysort codigo_unico: ///
    egen byte has_post = ///
        max(ao_proceso >= 2012)


keep if ///
    has_pre == 1 & ///
    has_post == 1


drop ///
    has_pre ///
    has_post


/*******************************************************************************
9. FE IDS
*******************************************************************************/

egen long program_id = ///
    group(codigo_unico)


egen long fy_general = ///
    group( ///
        field_gen ///
        ao_proceso ///
    )


egen long fy_cine = ///
    group( ///
        field_cine ///
        ao_proceso ///
    )


egen long fy_generic = ///
    group( ///
        field_rgen ///
        ao_proceso ///
    )


egen long region_year_id = ///
    group( ///
        region_pre ///
        ao_proceso ///
    )


isid ///
    program_id ///
    ao_proceso


/*******************************************************************************
10. SAMPLE DIAGNOSTICS
*******************************************************************************/

display ""
display "============================================================"
display " COMMON RAW EVENT-STUDY SAMPLE"
display "============================================================"


count

display ///
    "Program-year observations = " ///
    %9.0fc r(N)


egen byte tag_program = ///
    tag(program_id)

count if tag_program == 1

display ///
    "Programs = " ///
    %9.0fc r(N)

drop tag_program


pwcorr ///
    z_exp_psu_rf ///
    z_exp_psu_rcine ///
    z_exp_psu_rgen, ///
    sig


/*******************************************************************************
11. MANUAL YEAR x EXPOSURE INTERACTIONS
*
* 2011 is intentionally omitted.
*******************************************************************************/

local years ///
    2007 2008 2009 2010 ///
    2012 2013 2014 2015 2016


/*
General.
*/

foreach y of local years {

    gen double es_g_`y' = ///
        z_exp_psu_rf * ///
        (ao_proceso == `y')

}


/*
CINE97.
*/

foreach y of local years {

    gen double es_c_`y' = ///
        z_exp_psu_rcine * ///
        (ao_proceso == `y')

}


/*
Generic.
*/

foreach y of local years {

    gen double es_r_`y' = ///
        z_exp_psu_rgen * ///
        (ao_proceso == `y')

}


/*******************************************************************************
12. RESULTS STORAGE
*******************************************************************************/

tempfile es_results


postfile ES ///
    str12 exposure ///
    str12 specification ///
    int year ///
    double beta ///
    double se ///
    double lb ///
    double ub ///
    double pre_F ///
    double pre_p ///
    long N ///
    long programs ///
    using `es_results', ///
    replace


/*******************************************************************************
13. ESTIMATION LOOP
*******************************************************************************/

foreach spec in baseline regionyear {


    display ""
    display "============================================================"
    display " SPECIFICATION: `spec'"
    display "============================================================"


    foreach e in general cine generic {


        /*
        Exposure-specific mappings.
        */

        if "`e'" == "general" {

            local prefix  "g"
            local fieldfe "fy_general"

        }


        if "`e'" == "cine" {

            local prefix  "c"
            local fieldfe "fy_cine"

        }


        if "`e'" == "generic" {

            local prefix  "r"
            local fieldfe "fy_generic"

        }


        /*
        Event-study regressors.
        */

        local esvars ""

        foreach y of local years {

            local esvars ///
                `esvars' ///
                es_`prefix'_`y'

        }


        /*
        Estimation.
        */

        if "`spec'" == "baseline" {

            reghdfe ///
                N_firstyear ///
                `esvars', ///
                absorb( ///
                    program_id ///
                    `fieldfe' ///
                ) ///
                vce(cluster program_id)

        }


        if "`spec'" == "regionyear" {

            reghdfe ///
                N_firstyear ///
                `esvars', ///
                absorb( ///
                    program_id ///
                    `fieldfe' ///
                    region_year_id ///
                ) ///
                vce(cluster program_id)

        }


        local Nreg = e(N)
        local df   = e(df_r)


        /*
        Number of programs in actual estimation sample.
        */

        egen byte tag_est = ///
            tag(program_id) ///
            if e(sample)

        count if tag_est == 1

        local Preg = r(N)

        drop tag_est


        /*
        Joint pretrend test.
        */

        test ///
            es_`prefix'_2007 ///
            es_`prefix'_2008 ///
            es_`prefix'_2009 ///
            es_`prefix'_2010


        local preF = r(F)
        local prep = r(p)


        display ""
        display "---------------------------------------------"
        display "Exposure      = `e'"
        display "Specification = `spec'"
        display "Field FE      = `fieldfe'"
        display "N             = " %9.0fc `Nreg'
        display "Programs      = " %9.0fc `Preg'
        display "Pretrend F    = " %9.4f `preF'
        display "Pretrend p    = " %9.6f `prep'
        display "---------------------------------------------"


        /*
        95% CI critical value.
        */

        local crit = ///
            invttail(`df', 0.025)


        /*
        2007-2010.
        */

        foreach y of numlist 2007/2010 {

            local b = ///
                _b[es_`prefix'_`y']

            local s = ///
                _se[es_`prefix'_`y']

            local lo = ///
                `b' - `crit' * `s'

            local hi = ///
                `b' + `crit' * `s'


            post ES ///
                ("`e'") ///
                ("`spec'") ///
                (`y') ///
                (`b') ///
                (`s') ///
                (`lo') ///
                (`hi') ///
                (`preF') ///
                (`prep') ///
                (`Nreg') ///
                (`Preg')

        }


        /*
        Reference year: 2011.
        */

        post ES ///
            ("`e'") ///
            ("`spec'") ///
            (2011) ///
            (0) ///
            (0) ///
            (0) ///
            (0) ///
            (`preF') ///
            (`prep') ///
            (`Nreg') ///
            (`Preg')


        /*
        2012-2016.
        */

        foreach y of numlist 2012/2016 {

            local b = ///
                _b[es_`prefix'_`y']

            local s = ///
                _se[es_`prefix'_`y']

            local lo = ///
                `b' - `crit' * `s'

            local hi = ///
                `b' + `crit' * `s'


            post ES ///
                ("`e'") ///
                ("`spec'") ///
                (`y') ///
                (`b') ///
                (`s') ///
                (`lo') ///
                (`hi') ///
                (`preF') ///
                (`prep') ///
                (`Nreg') ///
                (`Preg')

        }

    }

}


postclose ES


/*******************************************************************************
14. LOAD RESULTS
*******************************************************************************/

use `es_results', clear


sort ///
    specification ///
    exposure ///
    year


count

assert r(N) == 60


format ///
    beta ///
    se ///
    lb ///
    ub ///
    pre_F ///
    pre_p ///
    %9.4f


/*******************************************************************************
15. PRINT FULL RESULTS
*******************************************************************************/

list ///
    specification ///
    exposure ///
    year ///
    beta ///
    se ///
    lb ///
    ub ///
    pre_F ///
    pre_p ///
    N ///
    programs, ///
    noobs sepby(specification exposure)


/*******************************************************************************
16. PRETREND SUMMARY
*******************************************************************************/

preserve

    keep if year == 2011

    keep ///
        specification ///
        exposure ///
        pre_F ///
        pre_p ///
        N ///
        programs

    sort ///
        specification ///
        exposure


    display ""
    display "============================================================"
    display " JOINT PRETREND TESTS: MATCHED FIELD FE"
    display "============================================================"


    list ///
        specification ///
        exposure ///
        pre_F ///
        pre_p ///
        N ///
        programs, ///
        noobs clean

restore


/*******************************************************************************
17. GRAPH X POSITIONS
*******************************************************************************/

gen double x_general = ///
    year - 0.12

gen double x_cine = ///
    year

gen double x_generic = ///
    year + 0.12


/*******************************************************************************
18. BASELINE GRAPH
*******************************************************************************/

#delimit ;

twoway

    (rcap lb ub x_general
        if specification == "baseline"
        & exposure == "general"
        & year != 2011,
        lcolor(navy)
        lwidth(medthin))

    (scatter beta x_general
        if specification == "baseline"
        & exposure == "general"
        & year != 2011,
        mcolor(navy)
        msymbol(O)
        msize(medsmall))

    (rcap lb ub x_cine
        if specification == "baseline"
        & exposure == "cine"
        & year != 2011,
        lcolor(forest_green)
        lwidth(medthin))

    (scatter beta x_cine
        if specification == "baseline"
        & exposure == "cine"
        & year != 2011,
        mcolor(forest_green)
        msymbol(D)
        msize(medsmall))

    (rcap lb ub x_generic
        if specification == "baseline"
        & exposure == "generic"
        & year != 2011,
        lcolor(maroon)
        lwidth(medthin))

    (scatter beta x_generic
        if specification == "baseline"
        & exposure == "generic"
        & year != 2011,
        mcolor(maroon)
        msymbol(T)
        msize(medsmall))

    (scatteri 0 2011,
        mcolor(black)
        msymbol(O)
        msize(small))

    ,
    xline(
        2011,
        lcolor(gs8)
        lpattern(dash)
    )

    yline(
        0,
        lcolor(gs10)
        lpattern(solid)
    )

    xlabel(
        2007(1)2016,
        labsize(small)
    )

    xtitle("Year")

    ytitle(
        "Coefficient on exposure x year"
    )

    title(
        "Event study: PSU cosine exposure by field definition"
    )

    subtitle(
        "Program FE + corresponding field x year FE; 95% confidence intervals"
    )

    legend(
        order(
            2 "General field"
            4 "CINE97"
            6 "Generic career area"
        )
        rows(1)
        position(6)
        size(small)
    )

    graphregion(color(white))
    plotregion(color(white))

    ylabel(
        ,
        angle(horizontal)
        grid
        glcolor(gs14)
    )

    name(es_field_baseline_matchedFE, replace)
;


graph export
    "$output/cosine_field_definitions_event_study_matchedFE_baseline.pdf",
    replace
;



/*******************************************************************************
19. REGION x YEAR GRAPH
*******************************************************************************/

twoway

    (rcap lb ub x_general
        if specification == "regionyear"
        & exposure == "general"
        & year != 2011,
        lcolor(navy)
        lwidth(medthin))

    (scatter beta x_general
        if specification == "regionyear"
        & exposure == "general"
        & year != 2011,
        mcolor(navy)
        msymbol(O)
        msize(medsmall))

    (rcap lb ub x_cine
        if specification == "regionyear"
        & exposure == "cine"
        & year != 2011,
        lcolor(forest_green)
        lwidth(medthin))

    (scatter beta x_cine
        if specification == "regionyear"
        & exposure == "cine"
        & year != 2011,
        mcolor(forest_green)
        msymbol(D)
        msize(medsmall))

    (rcap lb ub x_generic
        if specification == "regionyear"
        & exposure == "generic"
        & year != 2011,
        lcolor(maroon)
        lwidth(medthin))

    (scatter beta x_generic
        if specification == "regionyear"
        & exposure == "generic"
        & year != 2011,
        mcolor(maroon)
        msymbol(T)
        msize(medsmall))

    (scatteri 0 2011,
        mcolor(black)
        msymbol(O)
        msize(small))

    ,
    xline(
        2011,
        lcolor(gs8)
        lpattern(dash)
    )

    yline(
        0,
        lcolor(gs10)
        lpattern(solid)
    )

    xlabel(
        2007(1)2016,
        labsize(small)
    )

    xtitle("Year")

    ytitle(
        "Coefficient on exposure x year"
    )

    title(
        "Event study: PSU cosine exposure by field definition"
    )

    subtitle(
        "Corresponding field x year FE + region x year FE; 95% confidence intervals"
    )

    legend(
        order(
            2 "General field"
            4 "CINE97"
            6 "Generic career area"
        )
        rows(1)
        position(6)
        size(small)
    )

    graphregion(color(white))
    plotregion(color(white))

    ylabel(
        ,
        angle(horizontal)
        grid
        glcolor(gs14)
    )

    name(es_field_regionyear_matchedFE, replace)
;


graph export
    "$output/cosine_field_definitions_event_study_matchedFE_regionyear.pdf",
    replace


