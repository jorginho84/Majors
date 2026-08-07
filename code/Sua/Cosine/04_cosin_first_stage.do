/*******************************************************************************
04_cosin_first_stage
* COSINE FIRST STAGE - CLEAN NATIVE SIES CONSTRUCTION
*
* Unit: SIES codigo_unico x year
*
* Outcome:
*   N_firstyear = actual administrative first-year enrollment from SIES
*
* Exposure:
*   fixed 2011 cosine exposure at codigo_unico level
*
* No DEMRE crosswalk is used in this construction.
*******************************************************************************/

clear all
set more off
set varabbrev off


/**********************************************************************
* 0. Paths
**********************************************************************/

local sies_panel ///
    "$processed/sua_exposure/sies_program_year_with_demre_2007_2016.dta"

local roster ///
    "$processed/sua_exposure/sua_university_sies_roster.dta"

local exposure ///
    "$processed/cosine_exposure_incumbents_2011_final.dta"


/**********************************************************************
* 1. Native SIES program-year panel
**********************************************************************/

use "`sies_panel'", clear

keep if inrange(ao_proceso, 2007, 2016)

/*
Native SIES program-year identifier.
*/
isid codigo_unico ao_proceso


/**********************************************************************
* 2. Attach SUA incumbent / entrant classification
**********************************************************************/

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


gen byte sua_incumbent = ///
    entrant_2012 == 0

gen byte sua_entrant_2012 = ///
    entrant_2012 == 1


/**********************************************************************
* 3. Keep incumbent programs only
**********************************************************************/

keep if sua_incumbent == 1


/**********************************************************************
* 4. Attach fixed 2011 cosine exposure DIRECTLY by codigo_unico
**********************************************************************/

preserve

    use "`exposure'", clear

    isid codigo_unico_2011

    rename codigo_unico_2011 codigo_unico

    keep ///
        codigo_unico ///
        cosine_exposure_2011 ///
        cosine_exposure_std ///
        N_total_incumbent ///
        N_observed_incumbent ///
        coverage_incumbent

    tempfile exposure_clean
    save `exposure_clean', replace

restore


merge m:1 ///
    codigo_unico ///
    using `exposure_clean', ///
    gen(_merge_cosine)

tab _merge_cosine

/**********************************************************************
* 5. Longitudinal sample
**********************************************************************/

keep if _merge_cosine == 3

drop _merge_cosine

drop if missing(N_firstyear)
drop if missing(cosine_exposure_std)


bysort codigo_unico: ///
    egen byte has_pre = ///
        max(ao_proceso <= 2011)

bysort codigo_unico: ///
    egen byte has_post = ///
        max(ao_proceso >= 2012)

keep if ///
    has_pre == 1 & ///
    has_post == 1
	
	isid codigo_unico ao_proceso

egen long program_id = ///
    group(codigo_unico)

	/**********************************************************************
* 6. Fix program characteristics at 2011
**********************************************************************/

gen str56 field_2011_temp = ///
    area_conocimiento ///
    if ao_proceso == 2011

bysort codigo_unico: ///
    egen str56 field_pre = ///
        mode(field_2011_temp), ///
        minmode

drop field_2011_temp


gen double region_2011_temp = ///
    id_region ///
    if ao_proceso == 2011

bysort codigo_unico: ///
    egen double region_pre = ///
        max(region_2011_temp)

drop region_2011_temp

/**********************************************************************
* 7. Treatment variables
**********************************************************************/

gen byte post_2012 = ///
    ao_proceso >= 2012

gen double exposure_post = ///
    cosine_exposure_std * ///
    post_2012


egen long field_year_id = ///
    group(field_pre ao_proceso)

egen long region_year_id = ///
    group(region_pre ao_proceso)
	
reghdfe ///
    N_firstyear ///
    exposure_post, ///
    absorb( ///
        program_id ///
        field_year_id ///
    ) ///
    vce(cluster program_id)

test exposure_post


display "beta = " _b[exposure_post]
display "SE   = " _se[exposure_post]
display "t    = " _b[exposure_post] / _se[exposure_post]

/**********************************************************************
* Baseline + region x year FE
**********************************************************************/

reghdfe ///
    N_firstyear ///
    exposure_post, ///
    absorb( ///
        program_id ///
        field_year_id ///
        region_year_id ///
    ) ///
    vce(cluster program_id)

display "beta region-year = " _b[exposure_post]
display "SE region-year   = " _se[exposure_post]
