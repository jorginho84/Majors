/*******************************************************************************
06_cosine_same_region_field_first_stage.do

PURPOSE

Estimate the first stage using cosine exposure measures restricted
to entrant programs in the same:

    program region × field of study

Exposure measures:

1. PSU-only cosine:
       z_exp_psu_rf

2. School-region × PSU cosine:
       z_exp_geo_rf

Outcome:
    N_firstyear

Unit:
    codigo_unico × year

Sample:
    SUA incumbent programs, 2007-2016,
    with at least one pre-2012 and one post-2012 observation.

Specifications:

A. Program FE + field × year FE
B. Program FE + field × year FE + region × year FE

Standard errors clustered at program level.
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

local exposure ///
    "$processed/cosine_exposure_incumbents_2011_same_region_field.dta"

/*******************************************************************************
1. NATIVE SIES PROGRAM-YEAR PANEL
*******************************************************************************/

use "`panel'", clear

keep if inrange(ao_proceso, 2007, 2016)

/*
Native SIES program-year identifier.
*/

isid codigo_unico ao_proceso


/*******************************************************************************
2. ATTACH SUA INCUMBENT / ENTRANT CLASSIFICATION
*******************************************************************************/

preserve

    use "`roster'", clear

    keep ///
        cod_inst ///
        sigla_universidad ///
        first_sua_year ///
        entrant_2012

    duplicates drop

    isid cod_inst

    tempfile roster_clean
    save `roster_clean', replace

restore


merge m:1 ///
    cod_inst ///
    using `roster_clean', ///
    keep(master match) ///
    gen(_merge_roster)


/*
Keep only universities in the SUA roster.
*/

keep if _merge_roster == 3
drop _merge_roster


gen byte sua_inc = ///
    entrant_2012 == 0

gen byte sua_ent = ///
    entrant_2012 == 1


/*******************************************************************************
3. KEEP INCUMBENT PROGRAMS AND MERGE RESTRICTED EXPOSURES
*******************************************************************************/

keep if sua_inc == 1


/*
Prepare exposure file with the same identifier name as the
native SIES panel.
*/

preserve

    use "`exposure'", clear

    isid codigo_unico_2011

    rename ///
        codigo_unico_2011 ///
        codigo_unico

    keep ///
        codigo_unico ///
        exp_psu_rf ///
        z_exp_psu_rf ///
        exp_geo_rf ///
        z_exp_geo_rf ///
        region_2011 ///
        field_2011 ///
        n_pair_psu_rf ///
        n_pair_geo_rf

    tempfile exposure_clean
    save `exposure_clean', replace

restore


/*
Direct merge by native SIES codigo_unico.
*/

merge m:1 ///
    codigo_unico ///
    using `exposure_clean', ///
    gen(_merge_exp)

tabulate _merge_exp, missing


/*
Keep incumbent programs with restricted exposure defined.
*/

keep if _merge_exp == 3
drop _merge_exp


isid codigo_unico ao_proceso


/*******************************************************************************
4. LONGITUDINAL SAMPLE
*
* Require at least one pre and one post observation.
*******************************************************************************/

gen byte pre = ///
    ao_proceso <= 2011

gen byte post = ///
    ao_proceso >= 2012


bysort codigo_unico: ///
    egen byte has_pre = max(pre)

bysort codigo_unico: ///
    egen byte has_post = max(post)


keep if has_pre == 1 ///
    & has_post == 1


drop ///
    has_pre ///
    has_post


/*******************************************************************************
5. FIX PROGRAM CHARACTERISTICS AT 2011
*
* Field and region must remain fixed across time.
*******************************************************************************/

preserve

    keep if ao_proceso == 2011

    keep ///
        codigo_unico ///
        area_conocimiento ///
        id_region

    isid codigo_unico


    rename area_conocimiento field_2011_panel
    rename id_region          region_2011_panel


    tempfile chars2011
    save `chars2011', replace

restore


merge m:1 codigo_unico ///
    using `chars2011', ///
    keep(master match) ///
    gen(_merge_chars)

keep if _merge_chars == 3
drop _merge_chars


/*******************************************************************************
6. VERIFY EXPOSURE MARKET CHARACTERISTICS
*******************************************************************************/

/*
These should correspond to the region × field used when
constructing the restricted exposure.
*/

count if region_2011 != region_2011_panel
display ///
    "Region mismatches = " ///
    %9.0fc r(N)


count if ///
    field_2011 != field_2011_panel ///
    & !missing(field_2011) ///
    & !missing(field_2011_panel)

display ///
    "Field mismatches = " ///
    %9.0fc r(N)


/*******************************************************************************
7. CREATE ESTIMATION VARIABLES
*******************************************************************************/

gen byte post2012 = ///
    ao_proceso >= 2012


gen double psu_rf_post = ///
    z_exp_psu_rf * post2012


gen double geo_rf_post = ///
    z_exp_geo_rf * post2012


/*
Program fixed-effect identifier.
*/

egen long program_id = ///
    group(codigo_unico)


/*
Field × year FE.
*/

egen long field_year = ///
    group( ///
        field_2011_panel ///
        ao_proceso ///
    )


/*
Region × year FE.
*/

egen long region_year = ///
    group( ///
        region_2011_panel ///
        ao_proceso ///
    )


/*******************************************************************************
8. SAMPLE DIAGNOSTICS
*******************************************************************************/

count
display ///
    "Program-year observations = " ///
    %9.0fc r(N)


egen byte tag_program = ///
    tag(program_id)

count if tag_program
display ///
    "Programs = " ///
    %9.0fc r(N)


summarize ///
    N_firstyear ///
    z_exp_psu_rf ///
    z_exp_geo_rf ///
    psu_rf_post ///
    geo_rf_post


pwcorr ///
    z_exp_psu_rf ///
    z_exp_geo_rf


/*******************************************************************************
9. BASELINE FIRST STAGE
*
* Program FE + field × year FE
*******************************************************************************/

display ""
display "=============================================="
display "BASELINE: PSU, SAME REGION x FIELD"
display "=============================================="


reghdfe ///
    N_firstyear ///
    psu_rf_post, ///
    absorb( ///
        program_id ///
        field_year ///
    ) ///
    vce(cluster program_id)

* Baseline PSU
local b_psu  = _b[psu_rf_post]
local se_psu = _se[psu_rf_post]
local t_psu  = `b_psu' / `se_psu'
local f_psu  = (`t_psu')^2

display ///
    "Beta PSU RF = " ///
    %9.4f `b_psu'

display ///
    "SE PSU RF   = " ///
    %9.4f `se_psu'

display ///
    "F PSU RF    = " ///
    %9.2f `f_psu'


display ""
display "=============================================="
display "BASELINE: GEO-PSU, SAME REGION x FIELD"
display "=============================================="


reghdfe ///
    N_firstyear ///
    geo_rf_post, ///
    absorb( ///
        program_id ///
        field_year ///
    ) ///
    vce(cluster program_id)


* Baseline Geo-PSU
local b_geo  = _b[geo_rf_post]
local se_geo = _se[geo_rf_post]
local t_geo  = `b_geo' / `se_geo'
local f_geo  = (`t_geo')^2

display ///
    "Beta GEO RF = " ///
    %9.4f `b_geo'

display ///
    "SE GEO RF   = " ///
    %9.4f `se_geo'

display ///
    "F GEO RF    = " ///
    %9.2f `f_geo'


/*******************************************************************************
10. REGION × YEAR SPECIFICATION
*******************************************************************************/

display ""
display "=============================================="
display "REGION-YEAR FE: PSU, SAME REGION x FIELD"
display "=============================================="


reghdfe ///
    N_firstyear ///
    psu_rf_post, ///
    absorb( ///
        program_id ///
        field_year ///
        region_year ///
    ) ///
    vce(cluster program_id)

local b_psu_ry  = _b[psu_rf_post]
local se_psu_ry = _se[psu_rf_post]
local t_psu_ry  = `b_psu_ry' / `se_psu_ry'
local f_psu_ry  = (`t_psu_ry')^2


display ///
    "Beta PSU RF + RY = " ///
    %9.4f `b_psu_ry'

display ///
    "SE PSU RF + RY   = " ///
    %9.4f `se_psu_ry'

display ///
    "F PSU RF + RY    = " ///
    %9.2f `f_psu_ry'


display ""
display "=============================================="
display "REGION-YEAR FE: GEO-PSU, SAME REGION x FIELD"
display "=============================================="


reghdfe ///
    N_firstyear ///
    geo_rf_post, ///
    absorb( ///
        program_id ///
        field_year ///
        region_year ///
    ) ///
    vce(cluster program_id)

local b_geo_ry  = _b[geo_rf_post]
local se_geo_ry = _se[geo_rf_post]
local t_geo_ry  = `b_geo_ry' / `se_geo_ry'
local f_geo_ry  = (`t_geo_ry')^2

display ///
    "Beta GEO RF + RY = " ///
    %9.4f `b_geo_ry'

display ///
    "SE GEO RF + RY   = " ///
    %9.4f `se_geo_ry'

display ///
    "F GEO RF + RY    = " ///
    %9.2f `f_geo_ry'


/*******************************************************************************
11. COMPACT RESULTS
*******************************************************************************/

display ""
display "======================================================"
display "                 KEY FIRST-STAGE RESULTS"
display "======================================================"

display ///
    "PSU RF baseline      : " ///
    %8.3f `b_psu' ///
    " (" ///
    %8.3f `se_psu' ///
    "), F=" ///
    %7.2f `f_psu'


display ///
    "Geo-PSU RF baseline : " ///
    %8.3f `b_geo' ///
    " (" ///
    %8.3f `se_geo' ///
    "), F=" ///
    %7.2f `f_geo'


display ///
    "PSU RF + region-year: " ///
    %8.3f `b_psu_ry' ///
    " (" ///
    %8.3f `se_psu_ry' ///
    "), F=" ///
    %7.2f `f_psu_ry'


display ///
    "Geo RF + region-year: " ///
    %8.3f `b_geo_ry' ///
    " (" ///
    %8.3f `se_geo_ry' ///
    "), F=" ///
    %7.2f `f_geo_ry'


display "======================================================"