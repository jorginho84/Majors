/*******************************************************************************
Cosine_Exposure_Distributions.do

PURPOSE

Graph the distribution of the five final cosine-exposure measures for
incumbent SUA programs.

Two figures are produced:

    1. Zeros included
    2. Positive exposure only

Exposure is reported in percentage points.

INPUT

    $processed/cosine_exposure_incumbents_2011_psu_campus_region.dta
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
1. LOAD FINAL COSINE EXPOSURE DATA
*******************************************************************************/

use ///
    "$processed/cosine_exposure_incumbents_2011_psu_campus_region.dta", ///
    clear

isid codigo_unico_2011


/*******************************************************************************
2. CONVERT EXPOSURE TO PERCENTAGE POINTS
*******************************************************************************/

gen double pct_psu = ///
    100 * exp_psu

gen double pct_psu_reg = ///
    100 * exp_psu_region

gen double pct_psu_addreg = ///
    100 * exp_psu_plus_region

gen double pct_psu_regfld = ///
    100 * exp_psu_region_field

gen double pct_psu_addfld = ///
    100 * exp_psu_plus_region_field


/*******************************************************************************
3. HISTOGRAM DEFINITIONS
*******************************************************************************/

local var_1 pct_psu
local var_2 pct_psu_reg
local var_3 pct_psu_addreg
local var_4 pct_psu_regfld
local var_5 pct_psu_addfld

local ttl_1 `"A. PSU only"'
local ttl_2 `"B. PSU x campus region"'
local ttl_3 `"C. PSU + campus region"'
local ttl_4 `"D. PSU x region x Broad field"'
local ttl_5 `"E. PSU + region + Broad field"'

local g0_1 h0_psu
local g0_2 h0_psu_reg
local g0_3 h0_psu_add
local g0_4 h0_psu_regfld
local g0_5 h0_psu_addfld

local g1_1 h1_psu
local g1_2 h1_psu_reg
local g1_3 h1_psu_add
local g1_4 h1_psu_regfld
local g1_5 h1_psu_addfld

local col_1 navy
local col_2 maroon
local col_3 forest_green
local col_4 dkorange
local col_5 teal


/*******************************************************************************
4. BUILD HISTOGRAMS
*******************************************************************************/

forvalues i = 1/5 {

    local xvar `var_`i''
    local ttl  `ttl_`i''
    local g0   `g0_`i''
    local g1   `g1_`i''
    local col  `col_`i''


    /***************************************************************************
    4.1 MEASURE-SPECIFIC X-AXIS
    ***************************************************************************/

    quietly summarize `xvar', meanonly

    local xmax_raw = r(max)

    local xmax = ///
        ceil(`xmax_raw' / 5) * 5

    if `xmax' < 5 {
        local xmax = 5
    }


    /*
    Choose intuitive tick spacing.
    */

    if `xmax' <= 10 {
        local xstep = 2
    }
    else if `xmax' <= 25 {
        local xstep = 5
    }
    else if `xmax' <= 50 {
        local xstep = 10
    }
    else {
        local xstep = 20
    }


    /*
    Choose a reasonable histogram bin width.
    */

    if `xmax' <= 10 {
        local bw = 0.5
    }
    else if `xmax' <= 25 {
        local bw = 1
    }
    else if `xmax' <= 50 {
        local bw = 2
    }
    else {
        local bw = 4
    }


    /***************************************************************************
    4.2 ZEROS INCLUDED
    ***************************************************************************/

    histogram ///
        `xvar', ///
        percent ///
        start(0) ///
        width(`bw') ///
        xscale(range(0 `xmax')) ///
        xlabel( ///
            0(`xstep')`xmax', ///
            labsize(vsmall) ///
        ) ///
        ylabel( ///
            , ///
            angle(horizontal) ///
            labsize(vsmall) ///
        ) ///
        color(`col'%65) ///
        lcolor(`col') ///
        title( ///
            "`ttl'", ///
            size(small) ///
        ) ///
        subtitle( ///
            "Zeros included", ///
            size(vsmall) ///
        ) ///
        xtitle( ///
            "Exposure (percentage points)", ///
            size(vsmall) ///
        ) ///
        ytitle( ///
            "Percent of programs", ///
            size(vsmall) ///
        ) ///
        graphregion(color(white)) ///
        plotregion(color(white)) ///
        name(`g0', replace)


    /***************************************************************************
    4.3 POSITIVE EXPOSURE ONLY
    ***************************************************************************/

    quietly count ///
        if `xvar' > 0

    if r(N) > 0 {

        histogram ///
            `xvar' ///
            if `xvar' > 0, ///
            percent ///
            start(0) ///
            width(`bw') ///
            xscale(range(0 `xmax')) ///
            xlabel( ///
                0(`xstep')`xmax', ///
                labsize(vsmall) ///
            ) ///
            ylabel( ///
                , ///
                angle(horizontal) ///
                labsize(vsmall) ///
            ) ///
            color(`col'%65) ///
            lcolor(`col') ///
            title( ///
                "`ttl'", ///
                size(small) ///
            ) ///
            subtitle( ///
                "Positive exposure only", ///
                size(vsmall) ///
            ) ///
            xtitle( ///
                "Exposure (percentage points)", ///
                size(vsmall) ///
            ) ///
            ytitle( ///
                "Percent of programs", ///
                size(vsmall) ///
            ) ///
            graphregion(color(white)) ///
            plotregion(color(white)) ///
            name(`g1', replace)
    }
}


/*******************************************************************************
5. COMBINE: ZEROS INCLUDED
*******************************************************************************/

graph combine ///
    h0_psu ///
    h0_psu_reg ///
    h0_psu_add ///
    h0_psu_regfld ///
    h0_psu_addfld, ///
    cols(3) ///
    imargin(vsmall) ///
    title( ///
        "Cosine exposure distributions", ///
        size(medium) ///
    ) ///
    subtitle( ///
        "One observation per incumbent program", ///
        size(medsmall) ///
    ) ///
    note( ///
        "Zeros included. Exposure measured in percentage points; each panel uses its own x-axis scale.", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    name(cos_dist_zero, replace)


/*******************************************************************************
6. COMBINE: POSITIVE EXPOSURE ONLY
*******************************************************************************/

graph combine ///
    h1_psu ///
    h1_psu_reg ///
    h1_psu_add ///
    h1_psu_regfld ///
    h1_psu_addfld, ///
    cols(3) ///
    imargin(vsmall) ///
    title( ///
        "Cosine exposure distributions", ///
        size(medium) ///
    ) ///
    subtitle( ///
        "One observation per incumbent program", ///
        size(medsmall) ///
    ) ///
    note( ///
        "Positive exposure only. Exposure measured in percentage points; each panel uses its own x-axis scale.", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    name(cos_dist_pos, replace)


/*******************************************************************************
7. EXPORT
*******************************************************************************/

graph display cos_dist_zero

graph export ///
    "$output/cosine_exposure_distributions_zero_included.png", ///
    replace ///
    width(3200)

graph export ///
    "$output/cosine_exposure_distributions_zero_included.pdf", ///
    replace


graph display cos_dist_pos

graph export ///
    "$output/cosine_exposure_distributions_positive_only.png", ///
    replace ///
    width(3200)

graph export ///
    "$output/cosine_exposure_distributions_positive_only.pdf", ///
    replace


display ""
display "============================================================"
display " COSINE EXPOSURE FIGURES SAVED"
display "============================================================"
display "$output/cosine_exposure_distributions_zero_included.png"
display "$output/cosine_exposure_distributions_positive_only.png"