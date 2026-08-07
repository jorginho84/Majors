/*******************************************************************************
    
    02_MERGE_COSINE_EXPOSURE_ANALYSIS_PANEL

    PURPOSE

    Transfer the baseline 2011 cosine-exposure measure constructed at the
    MINEDUC codigo_unico level to the main analysis database.

    IDENTIFICATION BRIDGE

        codigo_unico
            -> harmonized institution-major names
            -> codigo_demre
            -> main analysis database

    The bridge uses the existing major-homologation files constructed by
    Sofía Schuster:

        08_h_codigo_unico.dta
        08_h_codigo_demre.dta

    Since the harmonization identifies majors at the institution-major
    level, exposures from multiple campuses or versions are aggregated
    using 2011 first-year enrollment weights.

*******************************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

set varabbrev off


/**********************************************************************
* 1. Prepare cosine exposure at codigo_unico level
**********************************************************************/

use ///
    "$processed/cosine_exposure_incumbents_2011_final.dta", ///
    clear

isid codigo_unico_2011

/*
The homologation file uses the original variable name codigo_unico.
*/

rename codigo_unico_2011 codigo_unico

describe ///
    codigo_unico ///
    cosine_exposure_2011 ///
    cosine_exposure_std ///
    N_total_incumbent ///
    N_observed_incumbent

summarize ///
    cosine_exposure_2011 ///
    cosine_exposure_std ///
    N_total_incumbent ///
    N_observed_incumbent, ///
    detail


/**********************************************************************
* 2. Link codigo_unico to harmonized institution-major names
**********************************************************************/

merge 1:1 codigo_unico ///
    using "$data/08_h_codigo_unico.dta", ///
    keepusing( ///
        nomb_inst ///
        nomb_carrera ///
        h_codigo_unico ///
    ) ///
    generate(_merge_h_unico)

tabulate _merge_h_unico, missing

/*
All incumbent programs used to construct exposure should appear in the
codigo_unico homologation file.
*/

count if _merge_h_unico == 1
assert r(N) == 0

keep if _merge_h_unico == 3
drop _merge_h_unico

assert codigo_unico != ""
assert nomb_inst != ""
assert nomb_carrera != ""

isid codigo_unico


/**********************************************************************
* 3. Aggregate exposure to harmonized institution-major level
*
* The homologation files do not distinguish campuses or versions.
* Therefore, exposure is aggregated using 2011 first-year enrollment.
**********************************************************************/

/*
Convertir nombres largos a strings de longitud fija para poder usarlos
posteriormente como llaves de merge.
*/

recast str244 nomb_carrera
recast str120 nomb_inst

gen double cosine_exposure_num = ///
    cosine_exposure_2011 * N_total_incumbent

gen double cosine_exposure_std_num = ///
    cosine_exposure_std * N_total_incumbent

gen byte one_codigo_unico = 1

collapse ///
    (sum) ///
        cosine_exposure_num ///
        cosine_exposure_std_num ///
        N_total_incumbent ///
        N_observed_incumbent ///
        n_codigo_unico = one_codigo_unico, ///
    by( ///
        nomb_inst ///
        nomb_carrera ///
    )

gen double cosine_exposure_2011 = ///
    cosine_exposure_num / N_total_incumbent

gen double cosine_exposure_std = ///
    cosine_exposure_std_num / N_total_incumbent

gen double cosine_input_coverage = ///
    N_observed_incumbent / N_total_incumbent

drop ///
    cosine_exposure_num ///
    cosine_exposure_std_num

label variable cosine_exposure_2011 ///
    "2011 entrant-weighted cosine exposure"

label variable cosine_exposure_std ///
    "Standardized 2011 entrant-weighted cosine exposure"

label variable cosine_input_coverage ///
    "Share of incumbent enrollment observed in exposure vectors"

label variable n_codigo_unico ///
    "Number of codigo_unico programs aggregated"

label variable N_total_incumbent ///
    "2011 first-year incumbent enrollment"

label variable N_observed_incumbent ///
    "2011 incumbent enrollment with valid vector inputs"

isid ///
    nomb_inst ///
    nomb_carrera

assert inrange(cosine_exposure_2011, 0, 1)
assert inrange(cosine_input_coverage, 0, 1)

summarize ///
    cosine_exposure_2011 ///
    cosine_exposure_std ///
    cosine_input_coverage ///
    n_codigo_unico, ///
    detail

tabulate n_codigo_unico, missing

tempfile exposure_harmonized_major
save `exposure_harmonized_major'

/**********************************************************************
* 4. Build codigo_demre-to-exposure bridge
**********************************************************************/

use "$data/08_h_codigo_demre.dta", clear

drop if codigo_demre == ""
drop if codigo_demre == "0"
drop if codigo_demre == "."

replace codigo_demre = ///
    itrim(ustrtrim(codigo_demre))

assert codigo_demre != ""

isid codigo_demre

/*
Stata no permite variables strL como llaves de merge.
Convertimos los nombres armonizados a strings de longitud fija,
usando las mismas longitudes de la base de exposición.
*/

recast str244 nomb_carrera
recast str120 nomb_inst

/*
Several codigo_demre values may refer to the same harmonized
institution-major pair. Each receives the same aggregated exposure.
*/

merge m:1 ///
    nomb_inst ///
    nomb_carrera ///
    using `exposure_harmonized_major', ///
    generate(_merge_h_major)

tabulate _merge_h_major, missing

count if inlist(_merge_h_major, 1, 3)
local N_demre_codes = r(N)

count if _merge_h_major == 3
local N_demre_exposure = r(N)

di as result ///
    "DEMRE codes in homologation table: " ///
    %9.0fc `N_demre_codes'

di as result ///
    "DEMRE codes receiving cosine exposure: " ///
    %9.0fc `N_demre_exposure'

di as result ///
    "Share of homologated DEMRE codes receiving exposure: " ///
    %6.2f (100 * `N_demre_exposure' / `N_demre_codes') "%"

keep if _merge_h_major == 3
drop _merge_h_major

isid codigo_demre

order ///
    codigo_demre ///
    h_codigo_demre ///
    nomb_inst ///
    nomb_carrera ///
    cosine_exposure_2011 ///
    cosine_exposure_std ///
    N_total_incumbent ///
    N_observed_incumbent ///
    cosine_input_coverage ///
    n_codigo_unico

compress

save ///
    "$processed/cosine_exposure_by_codigo_demre_2011.dta", ///
    replace

/**********************************************************************
* 5. Merge cosine exposure into the full analysis database
**********************************************************************/

use ///
    "$processed/analysis_sample_with_fields_graduation_8y_enrolledprogram.dta", ///
    clear

/*
Preserve the original numeric DEMRE code and construct the string key
used by the homologation file.
*/

clonevar codigo_carrera_demre_original = ///
    codigo_carrera_demre

tostring codigo_carrera_demre, ///
    generate(codigo_demre) ///
    format(%20.0f)

replace codigo_demre = ///
    itrim(ustrtrim(codigo_demre))

replace codigo_demre = "" ///
    if missing(codigo_carrera_demre)

merge m:1 codigo_demre ///
    using "$processed/cosine_exposure_by_codigo_demre_2011.dta", ///
    keep(master match) ///
    generate(_merge_cosine)

	assert inlist(_merge_cosine, 1, 3)

count
assert r(N) == 2075472
/**********************************************************************
* 5.1 Overall merge diagnostics
**********************************************************************/

tabulate _merge_cosine, missing

count if _merge_cosine == 1
local N_master_only = r(N)

count if _merge_cosine == 3
local N_matched = r(N)

count if inlist(_merge_cosine, 1, 3)
local N_master = r(N)

di as result ///
    "Analysis observations: " ///
    %12.0fc `N_master'

di as result ///
    "Analysis observations receiving cosine exposure: " ///
    %12.0fc `N_matched'

di as result ///
    "Overall observation-level coverage: " ///
    %6.2f (100 * `N_matched' / `N_master') "%"

/**********************************************************************
* 5.2 Coverage among university enrollees with DEMRE code
**********************************************************************/

count if ///
    enrolls_uni == 1 ///
    & !missing(codigo_carrera_demre)

local N_eligible = r(N)

count if ///
    enrolls_uni == 1 ///
    & !missing(codigo_carrera_demre) ///
    & _merge_cosine == 3

local N_eligible_match = r(N)

di as result ///
    "University-enrollment observations with DEMRE code: " ///
    %12.0fc `N_eligible'

di as result ///
    "Eligible observations receiving exposure: " ///
    %12.0fc `N_eligible_match'

di as result ///
    "Coverage among university enrollees with DEMRE code: " ///
    %6.2f (100 * `N_eligible_match' / `N_eligible') "%"

/**********************************************************************
* 5.3 Coverage by application year
**********************************************************************/

gen byte has_cosine_exposure = ///
    _merge_cosine == 3

label variable has_cosine_exposure ///
    "Observation matched to baseline cosine exposure"

tabulate ///
    ao_proceso ///
    has_cosine_exposure ///
    if enrolls_uni == 1 ///
    & !missing(codigo_carrera_demre), ///
    row missing

/**********************************************************************
* 5.4 Coverage at DEMRE-code level
**********************************************************************/

egen byte tag_demre_analysis = tag(codigo_demre) ///
    if codigo_demre != "" ///
    & enrolls_uni == 1

tabulate _merge_cosine ///
    if tag_demre_analysis == 1, ///
    missing

count if ///
    tag_demre_analysis == 1 ///
    & inlist(_merge_cosine, 1, 3)

local N_codes_analysis = r(N)

count if ///
    tag_demre_analysis == 1 ///
    & _merge_cosine == 3

local N_codes_matched = r(N)

di as result ///
    "Distinct DEMRE codes in university-enrollment analysis sample: " ///
    %9.0fc `N_codes_analysis'

di as result ///
    "Distinct DEMRE codes receiving exposure: " ///
    %9.0fc `N_codes_matched'

di as result ///
    "DEMRE-code coverage: " ///
    %6.2f (100 * `N_codes_matched' / `N_codes_analysis') "%"

/**********************************************************************
* 5.5 Save unmatched DEMRE codes for inspection
**********************************************************************/

preserve

    keep if ///
        enrolls_uni == 1 ///
        & codigo_demre != "" ///
        & _merge_cosine == 1

    contract ///
        ao_proceso ///
        codigo_demre ///
        codigo_carrera_demre ///
        sigla_universidad ///
        nomb_carrera, ///
        freq(N_observations)

    gsort -N_observations

    save ///
        "$processed/cosine_exposure_unmatched_demre_codes.dta", ///
        replace

    list ///
        ao_proceso ///
        codigo_demre ///
        sigla_universidad ///
        nomb_carrera ///
        N_observations ///
        in 1/100, ///
        noobs clean

restore


/**********************************************************************
* 6. Finalize exposure variables
**********************************************************************/

/*
The exposure is defined only for incumbent university majors included
in the 2011 competitive-exposure exercise. Missing values for unmatched
programs must not be mechanically replaced with zero.
*/

label variable codigo_demre ///
    "DEMRE program code used for cosine-exposure merge"

label variable cosine_exposure_2011 ///
    "Baseline 2011 cosine exposure to entering universities"

label variable cosine_exposure_std ///
    "Standardized baseline 2011 cosine exposure"

label variable cosine_input_coverage ///
    "Share of baseline incumbent enrollment observed in vectors"

label variable n_codigo_unico ///
    "Number of MINEDUC unique programs aggregated"

drop ///
    _merge_cosine ///
    tag_demre_analysis

order ///
    ao_proceso ///
    mrun ///
    sigla_universidad ///
    codigo_carrera_demre ///
    codigo_demre ///
    cosine_exposure_2011 ///
    cosine_exposure_std ///
    has_cosine_exposure ///
    cosine_input_coverage ///
    N_total_incumbent ///
    N_observed_incumbent ///
    n_codigo_unico

compress

save ///
    "$processed/analysis_sample_with_fields_graduation_8y_enrolledprogram_cosine.dta", ///
    replace


/**********************************************************************
* 7. Final checks
**********************************************************************/

describe ///
    codigo_carrera_demre ///
    codigo_demre ///
    cosine_exposure_2011 ///
    cosine_exposure_std ///
    has_cosine_exposure ///
    cosine_input_coverage

summarize ///
    cosine_exposure_2011 ///
    cosine_exposure_std ///
    cosine_input_coverage ///
    if has_cosine_exposure == 1, ///
    detail

tabulate has_cosine_exposure, missing

di as result ///
    "Final database saved as:"

di as result ///
    "$processed/analysis_sample_with_fields_graduation_8y_enrolledprogram_cosine.dta"