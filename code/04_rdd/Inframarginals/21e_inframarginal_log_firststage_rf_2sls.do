/**********************************************************************
* 21e_inframarginal_log_firststage_rf_2sls.do
*
* Objective:
*   Estimate log first stage, reduced form, and 2SLS for the four
*   enrollment-threshold inframarginal definitions.
*
* First stage:
*
*   Delta ln(N_total_enter)_pt =
*       pi * Delta ln(Z_total_cupos)_pt
*       + year FE + error_pt
*
* Reduced form:
*
*   Delta GraduationRate_infra_pt =
*       rho * Delta ln(Z_total_cupos)_pt
*       + year FE + error_pt
*
* 2SLS:
*
*   Delta GraduationRate_infra_pt =
*       beta * Delta ln(N_total_enter)_pt
*       + year FE + error_pt
*
*   Instrument:
*       Delta ln(Z_total_cupos)_pt
*
* Weights:
*   - First stage main: avg_N_total_enter
*   - Reduced form / 2SLS: avg_N_infra_enter
*
* SEs clustered at program level.
*
* IMPORTANT:
*   - Uses panels already created by 21b.
*   - Does NOT modify inframarginal definitions.
*   - Does NOT use ln(x+1).
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


/**********************************************************************
* 1. Inputs
**********************************************************************/

local prefix ///
    "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016"

local defs ///
    first_enroll ///
    first_enroll80 ///
    min_enroll ///
    min_enroll80

local label_first_enroll   "First enrolled threshold"
local label_first_enroll80 "80 percent first enrolled threshold"
local label_min_enroll     "Minimum enrolled threshold"
local label_min_enroll80   "80 percent minimum enrolled threshold"


/**********************************************************************
* 2. Results container
**********************************************************************/

capture postclose results

postfile results ///
    str20 definition ///
    str50 definition_label ///
    double N_fs ///
    double programs_fs ///
    double fs_unw ///
    double fs_unw_se ///
    double fs_unw_F ///
    double fs_w ///
    double fs_w_se ///
    double fs_w_F ///
    double N_iv ///
    double programs_iv ///
    double rf ///
    double rf_se ///
    double rf_p ///
    double iv ///
    double iv_se ///
    double iv_p ///
    double iv_firststage_F ///
    using "`c(tmpdir)'/inframarginal_log_results.dta", replace


/**********************************************************************
* 3. Estimate models
**********************************************************************/

foreach def of local defs {

    local deflabel : copy local label_`def'

    di as text "============================================================"
    di as result "`deflabel'"
    di as text "============================================================"

    use "`prefix'_`def'.dta", clear

    xtset program_id_rank_analysis ao_proceso


    /******************************************************************
    * A. Log variables
    ******************************************************************/

    capture drop ///
        ln_N_total_enter ///
        ln_Z_total_cupos ///
        D_ln_N_total_enter ///
        D_ln_Z_total_cupos ///
        sample_firststage_log ///
        sample_iv_log

    gen double ln_N_total_enter = ln(N_total_enter)
    gen double ln_Z_total_cupos = ln(Z_total_cupos)

    gen double D_ln_N_total_enter = D.ln_N_total_enter
    gen double D_ln_Z_total_cupos = D.ln_Z_total_cupos


    /******************************************************************
    * B. Samples
    ******************************************************************/

    gen byte sample_firststage_log = ///
        !missing( ///
            D_ln_N_total_enter, ///
            D_ln_Z_total_cupos, ///
            avg_N_total_enter ///
        )

    gen byte sample_iv_log = ///
        sample_firststage_log == 1 ///
        & !missing( ///
            D_grad_enrolled_program_rate_8y, ///
            avg_N_infra_enter ///
        )


    /******************************************************************
    * C. Sample sizes
    ******************************************************************/

    count if sample_firststage_log == 1
    local N_fs = r(N)

    distinct program_id_rank_analysis ///
        if sample_firststage_log == 1
    local P_fs = r(ndistinct)

    count if sample_iv_log == 1
    local N_iv = r(N)

    distinct program_id_rank_analysis ///
        if sample_iv_log == 1
    local P_iv = r(ndistinct)

    di as result "First-stage observations = " %9.0fc `N_fs'
    di as result "First-stage programs     = " %9.0fc `P_fs'

    di as result "IV observations          = " %9.0fc `N_iv'
    di as result "IV programs              = " %9.0fc `P_iv'


    /******************************************************************
    * D. FIRST STAGE — unweighted robustness
    ******************************************************************/

    di as text "------------------------------------------------------------"
    di as result "FIRST STAGE — UNWEIGHTED"
    di as text "------------------------------------------------------------"

    reg D_ln_N_total_enter ///
        D_ln_Z_total_cupos ///
        i.ao_proceso ///
        if sample_firststage_log == 1, ///
        vce(cluster program_id_rank_analysis)

    local fs_unw    = _b[D_ln_Z_total_cupos]
    local fs_unw_se = _se[D_ln_Z_total_cupos]

    test D_ln_Z_total_cupos = 0
    local fs_unw_F = r(F)


    /******************************************************************
    * E. FIRST STAGE — main weighted specification
    ******************************************************************/

    di as text "------------------------------------------------------------"
    di as result "FIRST STAGE — WEIGHTED"
    di as text "------------------------------------------------------------"

    reg D_ln_N_total_enter ///
        D_ln_Z_total_cupos ///
        i.ao_proceso ///
        [aw = avg_N_total_enter] ///
        if sample_firststage_log == 1, ///
        vce(cluster program_id_rank_analysis)

    local fs_w    = _b[D_ln_Z_total_cupos]
    local fs_w_se = _se[D_ln_Z_total_cupos]

    test D_ln_Z_total_cupos = 0
    local fs_w_F = r(F)


    /******************************************************************
    * F. REDUCED FORM
    *
    * Effect of proportional changes in vacancies directly on the
    * inframarginal graduation outcome.
    ******************************************************************/

    di as text "------------------------------------------------------------"
    di as result "REDUCED FORM"
    di as text "------------------------------------------------------------"

    reg D_grad_enrolled_program_rate_8y ///
        D_ln_Z_total_cupos ///
        i.ao_proceso ///
        [aw = avg_N_infra_enter] ///
        if sample_iv_log == 1, ///
        vce(cluster program_id_rank_analysis)

    local rf    = _b[D_ln_Z_total_cupos]
    local rf_se = _se[D_ln_Z_total_cupos]
    local rf_p  = 2 * normal(-abs(`rf' / `rf_se'))


    /******************************************************************
    * G. 2SLS
    *
    * Endogenous:
    *   Delta ln(total enrollment)
    *
    * Instrument:
    *   Delta ln(total vacancies)
    ******************************************************************/

    di as text "------------------------------------------------------------"
    di as result "2SLS"
    di as text "------------------------------------------------------------"

    ivregress 2sls ///
        D_grad_enrolled_program_rate_8y ///
        i.ao_proceso ///
        (D_ln_N_total_enter = D_ln_Z_total_cupos) ///
        [aw = avg_N_infra_enter] ///
        if sample_iv_log == 1, ///
        vce(cluster program_id_rank_analysis)

    local iv    = _b[D_ln_N_total_enter]
    local iv_se = _se[D_ln_N_total_enter]
    local iv_p  = 2 * normal(-abs(`iv' / `iv_se'))


    /******************************************************************
    * H. First stage corresponding exactly to 2SLS sample and weights
    ******************************************************************/

    estat firststage

    matrix FS = r(singleresults)

    local iv_fs_F = FS[1,4]


    /******************************************************************
    * I. Compact output
    ******************************************************************/

    di as text "------------------------------------------------------------"
    di as result "SUMMARY | `deflabel'"
    di as text "------------------------------------------------------------"

    di as result ///
        "FS weighted: " ///
        %9.4f `fs_w' ///
        " (" %9.4f `fs_w_se' ")" ///
        " | F = " %9.2f `fs_w_F'

    di as result ///
        "Reduced form: " ///
        %9.5f `rf' ///
        " (" %9.5f `rf_se' ")" ///
        " | p = " %7.4f `rf_p'

    di as result ///
        "2SLS: " ///
        %9.5f `iv' ///
        " (" %9.5f `iv_se' ")" ///
        " | p = " %7.4f `iv_p'

    di as result ///
        "2SLS first-stage F = " ///
        %9.2f `iv_fs_F'


    /******************************************************************
    * J. Save results
    ******************************************************************/

    post results ///
        ("`def'") ///
        ("`deflabel'") ///
        (`N_fs') ///
        (`P_fs') ///
        (`fs_unw') ///
        (`fs_unw_se') ///
        (`fs_unw_F') ///
        (`fs_w') ///
        (`fs_w_se') ///
        (`fs_w_F') ///
        (`N_iv') ///
        (`P_iv') ///
        (`rf') ///
        (`rf_se') ///
        (`rf_p') ///
        (`iv') ///
        (`iv_se') ///
        (`iv_p') ///
        (`iv_fs_F')
}

postclose results


/**********************************************************************
* 4. Summary table
**********************************************************************/

use "`c(tmpdir)'/inframarginal_log_results.dta", clear

format N_fs programs_fs N_iv programs_iv %9.0fc

format ///
    fs_unw fs_unw_se ///
    fs_w fs_w_se ///
    %9.4f

format ///
    fs_unw_F ///
    fs_w_F ///
    iv_firststage_F ///
    %9.2f

format ///
    rf rf_se ///
    iv iv_se ///
    %10.5f

format ///
    rf_p ///
    iv_p ///
    %8.4f

list ///
    definition ///
    N_fs programs_fs ///
    fs_w fs_w_se fs_w_F ///
    N_iv programs_iv ///
    rf rf_se rf_p ///
    iv iv_se iv_p ///
    iv_firststage_F, ///
    noobs clean

