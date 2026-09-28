/**********************************************************************
* 21d_inframarginal_log_diagnostics.do
*
* Objective:
*   Diagnose whether log transformations of total enrollment and
*   vacancies are feasible before estimating log first stages / 2SLS.
*
* IMPORTANT:
*   - Does NOT estimate regressions.
*   - Does NOT modify existing inframarginal definitions.
*   - Does NOT replace zero values or use log(x+1).
*   - Uses the four panels already produced by 21b.
**********************************************************************/

clear all
set more off

do "code/config.do"

/**********************************************************************
* 1. Existing inframarginal panels
**********************************************************************/

local prefix ///
    "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016"

local defs ///
    first_enroll ///
    first_enroll80 ///
    min_enroll ///
    min_enroll80


/**********************************************************************
* 2. Loop over definitions
**********************************************************************/

foreach def of local defs {

    di as text "============================================================"
    di as result "LOG DIAGNOSTICS: `def'"
    di as text "============================================================"

    use "`prefix'_`def'.dta", clear


    /******************************************************************
    * A. Basic panel checks
    ******************************************************************/

    describe ///
        program_id_rank_analysis ///
        ao_proceso ///
        N_total_enter ///
        Z_total_cupos ///
        D_N_total_enter ///
        D_Z_total_cupos ///
        sample_firststage

    duplicates report program_id_rank_analysis ao_proceso

    xtset program_id_rank_analysis ao_proceso


    /******************************************************************
    * B. Levels: missing, zero, and negative values
    ******************************************************************/

    di as text "------------------------------------------------------------"
    di as result "LEVEL SUPPORT"
    di as text "------------------------------------------------------------"

    count
    local N_panel = r(N)

    count if missing(N_total_enter)
    local miss_N = r(N)

    count if N_total_enter == 0 & !missing(N_total_enter)
    local zero_N = r(N)

    count if N_total_enter < 0 & !missing(N_total_enter)
    local neg_N = r(N)

    count if missing(Z_total_cupos)
    local miss_Z = r(N)

    count if Z_total_cupos == 0 & !missing(Z_total_cupos)
    local zero_Z = r(N)

    count if Z_total_cupos < 0 & !missing(Z_total_cupos)
    local neg_Z = r(N)

    di as result "Panel observations             = " %9.0fc `N_panel'
    di as result "Missing total enrollment       = " %9.0fc `miss_N'
    di as result "Zero total enrollment          = " %9.0fc `zero_N'
    di as result "Negative total enrollment      = " %9.0fc `neg_N'
    di as result "Missing vacancies              = " %9.0fc `miss_Z'
    di as result "Zero vacancies                 = " %9.0fc `zero_Z'
    di as result "Negative vacancies             = " %9.0fc `neg_Z'


    /******************************************************************
    * C. Construct logs ONLY when strictly positive
    ******************************************************************/

    capture drop ln_N_total_enter ln_Z_total_cupos

    gen double ln_N_total_enter = ln(N_total_enter) ///
        if N_total_enter > 0

    gen double ln_Z_total_cupos = ln(Z_total_cupos) ///
        if Z_total_cupos > 0


    /******************************************************************
    * D. Construct first differences in logs
    *
    * D.ln(x) automatically requires valid current and lagged values.
    ******************************************************************/

    capture drop D_ln_N_total_enter D_ln_Z_total_cupos

    gen double D_ln_N_total_enter = D.ln_N_total_enter
    gen double D_ln_Z_total_cupos = D.ln_Z_total_cupos


    /******************************************************************
    * E. Compare original and log first-stage samples
    ******************************************************************/

    capture drop sample_firststage_log

    gen byte sample_firststage_log = ///
        !missing(D_ln_N_total_enter, D_ln_Z_total_cupos)

    di as text "------------------------------------------------------------"
    di as result "FIRST-STAGE SAMPLE COMPARISON"
    di as text "------------------------------------------------------------"

    count if sample_firststage == 1
    local N_level = r(N)

    distinct program_id_rank_analysis if sample_firststage == 1
    local P_level = r(ndistinct)

    count if sample_firststage_log == 1
    local N_log = r(N)

    distinct program_id_rank_analysis if sample_firststage_log == 1
    local P_log = r(ndistinct)

    count if sample_firststage == 1 & sample_firststage_log == 0
    local lost = r(N)

    di as result "Level first-stage observations = " %9.0fc `N_level'
    di as result "Level first-stage programs     = " %9.0fc `P_level'

    di as result "Log first-stage observations   = " %9.0fc `N_log'
    di as result "Log first-stage programs       = " %9.0fc `P_log'

    di as result "Observations lost relative to levels = " %9.0fc `lost'

    if `N_level' > 0 {
        di as result "Share of level sample retained = " ///
            %6.2f (100 * `N_log' / `N_level') "%"
    }


    /******************************************************************
    * F. Why are observations lost?
    ******************************************************************/

    di as text "------------------------------------------------------------"
    di as result "SOURCE OF LOG-SAMPLE ATTRITION"
    di as text "------------------------------------------------------------"

    gen byte bad_N_current = ///
        N_total_enter <= 0 if !missing(N_total_enter)

    gen byte bad_N_lag = ///
        L.N_total_enter <= 0 if !missing(L.N_total_enter)

    gen byte bad_Z_current = ///
        Z_total_cupos <= 0 if !missing(Z_total_cupos)

    gen byte bad_Z_lag = ///
        L.Z_total_cupos <= 0 if !missing(L.Z_total_cupos)

    count if sample_firststage == 1 & bad_N_current == 1
    di as result "Lost: current enrollment <= 0 = " %9.0fc r(N)

    count if sample_firststage == 1 & bad_N_lag == 1
    di as result "Lost: lag enrollment <= 0     = " %9.0fc r(N)

    count if sample_firststage == 1 & bad_Z_current == 1
    di as result "Lost: current vacancies <= 0  = " %9.0fc r(N)

    count if sample_firststage == 1 & bad_Z_lag == 1
    di as result "Lost: lag vacancies <= 0      = " %9.0fc r(N)


    /******************************************************************
    * G. Distribution of levels and log changes
    ******************************************************************/

    di as text "------------------------------------------------------------"
    di as result "DISTRIBUTIONS"
    di as text "------------------------------------------------------------"

    summarize ///
        N_total_enter ///
        Z_total_cupos ///
        if sample_firststage_log == 1, detail

    summarize ///
        D_N_total_enter ///
        D_Z_total_cupos ///
        if sample_firststage_log == 1, detail

    summarize ///
        D_ln_N_total_enter ///
        D_ln_Z_total_cupos ///
        if sample_firststage_log == 1, detail


    /******************************************************************
    * H. Inspect potentially extreme proportional changes
    ******************************************************************/

    gen double abs_DlnN = abs(D_ln_N_total_enter)
    gen double abs_DlnZ = abs(D_ln_Z_total_cupos)

    di as text "------------------------------------------------------------"
    di as result "LARGE LOG CHANGES"
    di as text "------------------------------------------------------------"

    count if abs_DlnN > 1 & sample_firststage_log == 1
    di as result "|Delta ln enrollment| > 1 = " %9.0fc r(N)

    count if abs_DlnZ > 1 & sample_firststage_log == 1
    di as result "|Delta ln vacancies| > 1  = " %9.0fc r(N)

    count if abs_DlnN > 2 & sample_firststage_log == 1
    di as result "|Delta ln enrollment| > 2 = " %9.0fc r(N)

    count if abs_DlnZ > 2 & sample_firststage_log == 1
    di as result "|Delta ln vacancies| > 2  = " %9.0fc r(N)


    /******************************************************************
    * I. Years represented in log sample
    ******************************************************************/

    di as text "------------------------------------------------------------"
    di as result "LOG SAMPLE BY YEAR"
    di as text "------------------------------------------------------------"

    tab ao_proceso if sample_firststage_log == 1


    /******************************************************************
    * J. Programs losing observations
    ******************************************************************/

    bysort program_id_rank_analysis: egen ///
        n_level_fs = total(sample_firststage == 1)

    bysort program_id_rank_analysis: egen ///
        n_log_fs = total(sample_firststage_log == 1)

    egen tag_program = tag(program_id_rank_analysis)

    count if tag_program == 1 & n_level_fs > 0 & n_log_fs == 0
    di as result ///
        "Programs completely lost under logs = " %9.0fc r(N)

    count if tag_program == 1 & n_log_fs < n_level_fs & n_log_fs > 0
    di as result ///
        "Programs partially losing years     = " %9.0fc r(N)


    di as text "============================================================"
    di as result "END DIAGNOSTICS: `def'"
    di as text "============================================================"
    di ""
}