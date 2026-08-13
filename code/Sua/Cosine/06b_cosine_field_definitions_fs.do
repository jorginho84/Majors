/*******************************************************************************
06b_cosine_field_definitions_fs.do

PURPOSE

Compare first-stage estimates across three definitions of the academic
competition market, holding the cosine vector fixed at PSU bins.

Each exposure is paired with the corresponding field x year FE:

1. Region x General field
       Exposure: z_exp_psu_rf
       FE: area_conocimiento_2011 x year

2. Region x CINE97
       Exposure: z_exp_psu_rcine
       FE: cine_f_13_subarea_2011 x year

3. Region x Generic career area
       Exposure: z_exp_psu_rgen
       FE: area_carrera_generica_2011 x year

OUTCOME:
    N_firstyear

BASELINE:
    Program FE
    Corresponding field x year FE

ROBUSTNESS:
    Program FE
    Corresponding field x year FE
    Region x year FE

CLUSTER:
    Program

IMPORTANT:
    Exposure is standardized across incumbent programs.
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
1. LOAD SIES PANEL
*******************************************************************************/

use "`panel'", clear

keep if inrange(ao_proceso, 2007, 2016)

isid ///
    codigo_unico ///
    ao_proceso


/*******************************************************************************
2. IDENTIFY SUA INCUMBENTS
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
3. MERGE GENERAL-FIELD EXPOSURE
*******************************************************************************/

preserve

    use "`exp_general'", clear

    keep ///
        codigo_unico_2011 ///
        z_exp_psu_rf ///
        exp_psu_rf

    rename codigo_unico_2011 ///
        codigo_unico

    isid codigo_unico

    tempfile exposure_general
    save `exposure_general', replace

restore


merge m:1 codigo_unico ///
    using `exposure_general', ///
    keep(master match) ///
    gen(_m_general)

keep if _m_general == 3

drop _m_general


/*******************************************************************************
4. MERGE CINE97 EXPOSURE
*******************************************************************************/

preserve

    use "`exp_cine'", clear

    keep ///
        codigo_unico_2011 ///
        z_exp_psu_rcine ///
        exp_psu_rcine

    rename codigo_unico_2011 ///
        codigo_unico

    isid codigo_unico

    tempfile exposure_cine
    save `exposure_cine', replace

restore


merge m:1 codigo_unico ///
    using `exposure_cine', ///
    keep(master match) ///
    gen(_m_cine)

keep if _m_cine == 3

drop _m_cine


/*******************************************************************************
5. MERGE GENERIC-AREA EXPOSURE
*******************************************************************************/

preserve

    use "`exp_generic'", clear

    keep ///
        codigo_unico_2011 ///
        z_exp_psu_rgen ///
        exp_psu_rgen

    rename codigo_unico_2011 ///
        codigo_unico

    isid codigo_unico

    tempfile exposure_generic
    save `exposure_generic', replace

restore


merge m:1 codigo_unico ///
    using `exposure_generic', ///
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


gen byte post2012 = ///
    ao_proceso >= 2012


/*******************************************************************************
7. FIX ALL FIELD DEFINITIONS AT 2011
*******************************************************************************/

/*
7.1 General field
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
7.2 CINE97
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
7.3 Generic career area
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
7.4 Region
*/

gen double region_temp = ///
    id_region ///
    if ao_proceso == 2011

bysort codigo_unico: ///
    egen double region_pre = ///
        max(region_temp)

drop region_temp


/*
Require all three 2011 field definitions and region.
*/

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
9. CREATE FE IDS
*******************************************************************************/

egen long program_id = ///
    group(codigo_unico)


/*
Corresponding field x year FEs.
*/

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


/*
Region x year FE.
*/

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
display " COMMON RAW FIRST-STAGE SAMPLE"
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


display ""
display "===== EXPOSURE CORRELATIONS ====="

pwcorr ///
    z_exp_psu_rf ///
    z_exp_psu_rcine ///
    z_exp_psu_rgen, ///
    sig


/*******************************************************************************
11. POST INTERACTIONS
*******************************************************************************/

gen double fs_general = ///
    z_exp_psu_rf * ///
    post2012


gen double fs_cine = ///
    z_exp_psu_rcine * ///
    post2012


gen double fs_generic = ///
    z_exp_psu_rgen * ///
    post2012


/*******************************************************************************
12. RESULTS STORAGE
*******************************************************************************/

tempfile firststage_results


postfile results ///
    str12 exposure ///
    str12 specification ///
    double beta ///
    double se ///
    double t ///
    double F ///
    double p ///
    long N ///
    long programs ///
    using `firststage_results', ///
    replace


/*******************************************************************************
13. FIRST-STAGE SPECIFICATIONS

Specifications:

    1. year:
           Program FE
           Year FE

    2. fieldyear:
           Program FE
           Year FE
           Corresponding field x year FE

    3. regionyear:
           Program FE
           Year FE
           Corresponding field x year FE
           Region x year FE

Year FE are redundant once field x year FE are included. They are written
explicitly to match the requested presentation.
*******************************************************************************/


/*******************************************************************************
13.1 PROGRAM FE + YEAR FE: GENERAL FIELD
*******************************************************************************/

reghdfe ///
    N_firstyear ///
    fs_general, ///
    absorb( ///
        program_id ///
        ao_proceso ///
    ) ///
    vce(cluster program_id)
	
	



local beta = _b[fs_general]
local se   = _se[fs_general]
local t    = `beta' / `se'
local F    = (`t')^2
local p    = 2 * ttail(e(df_r), abs(`t'))
local N    = e(N)


egen byte tag_est = ///
    tag(program_id) ///
    if e(sample)

quietly count if tag_est == 1

local P = r(N)

drop tag_est


post results ///
    ("general") ///
    ("year") ///
    (`beta') ///
    (`se') ///
    (`t') ///
    (`F') ///
    (`p') ///
    (`N') ///
    (`P')


display ""
display "GENERAL: PROGRAM FE + YEAR FE"
display "Beta     = " %9.4f `beta'
display "SE       = " %9.4f `se'
display "F        = " %9.3f `F'
display "p        = " %9.4f `p'
display "N        = " %9.0fc `N'
display "Programs = " %9.0fc `P'


/*******************************************************************************
13.2 PROGRAM FE + YEAR FE: CINE97
*******************************************************************************/

reghdfe ///
    N_firstyear ///
    fs_cine, ///
    absorb( ///
        program_id ///
        ao_proceso ///
    ) ///
    vce(cluster program_id)


local beta = _b[fs_cine]
local se   = _se[fs_cine]
local t    = `beta' / `se'
local F    = (`t')^2
local p    = 2 * ttail(e(df_r), abs(`t'))
local N    = e(N)


egen byte tag_est = ///
    tag(program_id) ///
    if e(sample)

quietly count if tag_est == 1

local P = r(N)

drop tag_est


post results ///
    ("cine97") ///
    ("year") ///
    (`beta') ///
    (`se') ///
    (`t') ///
    (`F') ///
    (`p') ///
    (`N') ///
    (`P')


display ""
display "CINE97: PROGRAM FE + YEAR FE"
display "Beta     = " %9.4f `beta'
display "SE       = " %9.4f `se'
display "F        = " %9.3f `F'
display "p        = " %9.4f `p'
display "N        = " %9.0fc `N'
display "Programs = " %9.0fc `P'


/*******************************************************************************
13.3 PROGRAM FE + YEAR FE: GENERIC AREA
*******************************************************************************/

reghdfe ///
    N_firstyear ///
    fs_generic, ///
    absorb( ///
        program_id ///
        ao_proceso ///
    ) ///
    vce(cluster program_id)


local beta = _b[fs_generic]
local se   = _se[fs_generic]
local t    = `beta' / `se'
local F    = (`t')^2
local p    = 2 * ttail(e(df_r), abs(`t'))
local N    = e(N)


egen byte tag_est = ///
    tag(program_id) ///
    if e(sample)

quietly count if tag_est == 1

local P = r(N)

drop tag_est


post results ///
    ("generic") ///
    ("year") ///
    (`beta') ///
    (`se') ///
    (`t') ///
    (`F') ///
    (`p') ///
    (`N') ///
    (`P')


display ""
display "GENERIC: PROGRAM FE + YEAR FE"
display "Beta     = " %9.4f `beta'
display "SE       = " %9.4f `se'
display "F        = " %9.3f `F'
display "p        = " %9.4f `p'
display "N        = " %9.0fc `N'
display "Programs = " %9.0fc `P'


/*******************************************************************************
13.4 PROGRAM FE + YEAR FE + GENERAL FIELD x YEAR FE
*******************************************************************************/

reghdfe ///
    N_firstyear ///
    fs_general, ///
    absorb( ///
        program_id ///
        ao_proceso ///
        fy_general ///
    ) ///
    vce(cluster program_id)


local beta = _b[fs_general]
local se   = _se[fs_general]
local t    = `beta' / `se'
local F    = (`t')^2
local p    = 2 * ttail(e(df_r), abs(`t'))
local N    = e(N)


egen byte tag_est = ///
    tag(program_id) ///
    if e(sample)

quietly count if tag_est == 1

local P = r(N)

drop tag_est


post results ///
    ("general") ///
    ("fieldyear") ///
    (`beta') ///
    (`se') ///
    (`t') ///
    (`F') ///
    (`p') ///
    (`N') ///
    (`P')


display ""
display "GENERAL: PROGRAM + YEAR + FIELD x YEAR FE"
display "Beta     = " %9.4f `beta'
display "SE       = " %9.4f `se'
display "F        = " %9.3f `F'
display "p        = " %9.4f `p'
display "N        = " %9.0fc `N'
display "Programs = " %9.0fc `P'


/*******************************************************************************
13.5 PROGRAM FE + YEAR FE + CINE97 x YEAR FE
*******************************************************************************/

reghdfe ///
    N_firstyear ///
    fs_cine, ///
    absorb( ///
        program_id ///
        ao_proceso ///
        fy_cine ///
    ) ///
    vce(cluster program_id)


local beta = _b[fs_cine]
local se   = _se[fs_cine]
local t    = `beta' / `se'
local F    = (`t')^2
local p    = 2 * ttail(e(df_r), abs(`t'))
local N    = e(N)


egen byte tag_est = ///
    tag(program_id) ///
    if e(sample)

quietly count if tag_est == 1

local P = r(N)

drop tag_est


post results ///
    ("cine97") ///
    ("fieldyear") ///
    (`beta') ///
    (`se') ///
    (`t') ///
    (`F') ///
    (`p') ///
    (`N') ///
    (`P')


display ""
display "CINE97: PROGRAM + YEAR + FIELD x YEAR FE"
display "Beta     = " %9.4f `beta'
display "SE       = " %9.4f `se'
display "F        = " %9.3f `F'
display "p        = " %9.4f `p'
display "N        = " %9.0fc `N'
display "Programs = " %9.0fc `P'


/*******************************************************************************
13.6 PROGRAM FE + YEAR FE + GENERIC AREA x YEAR FE
*******************************************************************************/

reghdfe ///
    N_firstyear ///
    fs_generic, ///
    absorb( ///
        program_id ///
        ao_proceso ///
        fy_generic ///
    ) ///
    vce(cluster program_id)


local beta = _b[fs_generic]
local se   = _se[fs_generic]
local t    = `beta' / `se'
local F    = (`t')^2
local p    = 2 * ttail(e(df_r), abs(`t'))
local N    = e(N)


egen byte tag_est = ///
    tag(program_id) ///
    if e(sample)

quietly count if tag_est == 1

local P = r(N)

drop tag_est


post results ///
    ("generic") ///
    ("fieldyear") ///
    (`beta') ///
    (`se') ///
    (`t') ///
    (`F') ///
    (`p') ///
    (`N') ///
    (`P')


display ""
display "GENERIC: PROGRAM + YEAR + FIELD x YEAR FE"
display "Beta     = " %9.4f `beta'
display "SE       = " %9.4f `se'
display "F        = " %9.3f `F'
display "p        = " %9.4f `p'
display "N        = " %9.0fc `N'
display "Programs = " %9.0fc `P'


/*******************************************************************************
13.7 PROGRAM + YEAR + GENERAL FIELD x YEAR + REGION x YEAR FE
*******************************************************************************/

reghdfe ///
    N_firstyear ///
    fs_general, ///
    absorb( ///
        program_id ///
        ao_proceso ///
        fy_general ///
        region_year_id ///
    ) ///
    vce(cluster program_id)


local beta = _b[fs_general]
local se   = _se[fs_general]
local t    = `beta' / `se'
local F    = (`t')^2
local p    = 2 * ttail(e(df_r), abs(`t'))
local N    = e(N)


egen byte tag_est = ///
    tag(program_id) ///
    if e(sample)

quietly count if tag_est == 1

local P = r(N)

drop tag_est


post results ///
    ("general") ///
    ("regionyear") ///
    (`beta') ///
    (`se') ///
    (`t') ///
    (`F') ///
    (`p') ///
    (`N') ///
    (`P')


display ""
display "GENERAL: PROGRAM + YEAR + FIELD x YEAR + REGION x YEAR FE"
display "Beta     = " %9.4f `beta'
display "SE       = " %9.4f `se'
display "F        = " %9.3f `F'
display "p        = " %9.4f `p'
display "N        = " %9.0fc `N'
display "Programs = " %9.0fc `P'


/*******************************************************************************
13.8 PROGRAM + YEAR + CINE97 x YEAR + REGION x YEAR FE
*******************************************************************************/

reghdfe ///
    N_firstyear ///
    fs_cine, ///
    absorb( ///
        program_id ///
        ao_proceso ///
        fy_cine ///
        region_year_id ///
    ) ///
    vce(cluster program_id)


local beta = _b[fs_cine]
local se   = _se[fs_cine]
local t    = `beta' / `se'
local F    = (`t')^2
local p    = 2 * ttail(e(df_r), abs(`t'))
local N    = e(N)


egen byte tag_est = ///
    tag(program_id) ///
    if e(sample)

quietly count if tag_est == 1

local P = r(N)

drop tag_est


post results ///
    ("cine97") ///
    ("regionyear") ///
    (`beta') ///
    (`se') ///
    (`t') ///
    (`F') ///
    (`p') ///
    (`N') ///
    (`P')


display ""
display "CINE97: PROGRAM + YEAR + FIELD x YEAR + REGION x YEAR FE"
display "Beta     = " %9.4f `beta'
display "SE       = " %9.4f `se'
display "F        = " %9.3f `F'
display "p        = " %9.4f `p'
display "N        = " %9.0fc `N'
display "Programs = " %9.0fc `P'


/*******************************************************************************
13.9 PROGRAM + YEAR + GENERIC AREA x YEAR + REGION x YEAR FE
*******************************************************************************/

reghdfe ///
    N_firstyear ///
    fs_generic, ///
    absorb( ///
        program_id ///
        ao_proceso ///
        fy_generic ///
        region_year_id ///
    ) ///
    vce(cluster program_id)


local beta = _b[fs_generic]
local se   = _se[fs_generic]
local t    = `beta' / `se'
local F    = (`t')^2
local p    = 2 * ttail(e(df_r), abs(`t'))
local N    = e(N)


egen byte tag_est = ///
    tag(program_id) ///
    if e(sample)

quietly count if tag_est == 1

local P = r(N)

drop tag_est


post results ///
    ("generic") ///
    ("regionyear") ///
    (`beta') ///
    (`se') ///
    (`t') ///
    (`F') ///
    (`p') ///
    (`N') ///
    (`P')


display ""
display "GENERIC: PROGRAM + YEAR + FIELD x YEAR + REGION x YEAR FE"
display "Beta     = " %9.4f `beta'
display "SE       = " %9.4f `se'
display "F        = " %9.3f `F'
display "p        = " %9.4f `p'
display "N        = " %9.0fc `N'
display "Programs = " %9.0fc `P'	
	
	
	
	
	
/*******************************************************************************
15. RESULTS
*******************************************************************************/

postclose results


use `firststage_results', clear


sort ///
    specification ///
    exposure


format ///
    beta ///
    se ///
    t ///
    F ///
    p ///
    %9.4f


display ""
display "============================================================"
display " FIRST-STAGE RESULTS: MATCHED FIELD FE"
display "============================================================"


list ///
    exposure ///
    specification ///
    beta ///
    se ///
    F ///
    p ///
    N ///
    programs, ///
    noobs clean
