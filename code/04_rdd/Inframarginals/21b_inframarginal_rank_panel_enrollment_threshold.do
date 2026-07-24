/**********************************************************************
* 21b_inframarginal_rank_panel_altdefs_enrollment_threshold_all_applicants.do
*
* Objetivo:
*   Construir definiciones alternativas de inframarginales usando
*   umbrales basados en matricula efectiva, pero aplicando esos umbrales
*   sobre todos los postulantes con ranking observado.
*
* Idea central:
*   - La matricula efectiva se usa SOLO para calcular el tamano del umbral.
*   - La definicion de inframarginal se aplica a todos los postulantes:
*       infra = 1(lugar <= threshold)
*   - NO se restringe la muestra inframarginal a enrolls_target == 1.
*
* Base principal:
*   $processed/analysis_sample_with_fields_graduation_8y_enrolledprogram.dta
*
* Base auxiliar:
*   $processed/admission_rank_inframarginal_2007_2016.dta
*   Solo se usa para traer lugar/ranking de admision.
*
* Definiciones:
*   1) first_enroll   : lugar <= matricula efectiva del primer ano observado
*   2) first_enroll80 : lugar <= 0.8 * matricula efectiva del primer ano observado
*   3) min_enroll     : lugar <= minimo anual de matricula efectiva observado
*   4) min_enroll80   : lugar <= 0.8 * minimo anual de matricula efectiva observado
*
* Especificacion:
*   Outcome principal: grad_enrolled_program_rate_8y
*   Endogenous:       D_N_total_enter
*   Instrument:       D_Z_total_cupos
*
* Outputs:
*   - Base individual maestra:
*       $processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta
*   - Paneles por definicion:
*       $processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_*.dta
*   - Tabla resumen:
*       $processed/inframarginal_altdefs_enrollmentthreshold_allapp_summary.dta
*       $processed/inframarginal_altdefs_enrollmentthreshold_allapp_summary.csv
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local grad_base      "$processed/analysis_sample_with_fields_graduation_8y_enrolledprogram.dta"
local rank_file      "$processed/admission_rank_inframarginal_2007_2016.dta"
local vacancies_file "$processed/program_year_vacancies_2007_2016.dta"

local master_out "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta"
local outprefix  "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016"

/**********************************************************************
* 0. Check inputs
**********************************************************************/

foreach f in "`grad_base'" "`rank_file'" "`vacancies_file'" {
    capture confirm file `f'
    if _rc != 0 {
        di as error "No existe archivo requerido: `f'"
        exit 601
    }
}

/**********************************************************************
* 1. Load main graduation/enrollment base
**********************************************************************/

use "`grad_base'", clear
keep if inrange(ao_proceso, 2007, 2016)

foreach v in mrun ao_proceso preferencia sigla_universidad enrolls_target ///
             graduates_enrolled_program_8y graduates_uni_8y graduates_he_8y {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable en grad_base: `v'"
        exit 111
    }
}

* Program code of application/target program.
capture drop codigo_carrera_orig
capture confirm variable t_codigo_carrera
if !_rc {
    gen codigo_carrera_orig = t_codigo_carrera
}
else {
    capture confirm variable codigo_carrera
    if !_rc {
        gen codigo_carrera_orig = codigo_carrera
    }
    else {
        di as error "No existe t_codigo_carrera ni codigo_carrera en grad_base"
        exit 111
    }
}

capture confirm numeric variable codigo_carrera_orig
if _rc destring codigo_carrera_orig, replace force

capture confirm numeric variable ao_proceso
if _rc destring ao_proceso, replace force

capture confirm numeric variable preferencia
if _rc destring preferencia, replace force

tostring sigla_universidad, replace force
replace sigla_universidad = upper(strtrim(sigla_universidad))

* Harmonize 4-digit DEMRE program codes into 5-digit post-2012 format.
capture drop codigo_str
capture drop codigo_carrera_harmonized

gen codigo_str = string(codigo_carrera_orig, "%12.0f")
replace codigo_str = strtrim(codigo_str)

gen codigo_carrera_harmonized = codigo_carrera_orig
replace codigo_carrera_harmonized = real( ///
    substr(codigo_str, 1, length(codigo_str)-2) + ///
    "0" + ///
    substr(codigo_str, length(codigo_str)-1, 2) ///
    ) if length(codigo_str) == 4

drop codigo_str

/**********************************************************************
* 2. Prepare rank file: keep only ranking variable and keys
**********************************************************************/

preserve

    use "`rank_file'", clear
    keep if inrange(ao_proceso, 2007, 2016)

    foreach v in mrun ao_proceso sigla_universidad lugar {
        capture confirm variable `v'
        if _rc != 0 {
            di as error "Falta variable en rank_file: `v'"
            exit 111
        }
    }

    capture drop codigo_carrera_orig
    capture confirm variable t_codigo_carrera
    if !_rc {
        gen codigo_carrera_orig = t_codigo_carrera
    }
    else {
        capture confirm variable codigo_carrera
        if !_rc {
            gen codigo_carrera_orig = codigo_carrera
        }
        else {
            capture confirm variable codigo_carrera_harmonized
            if !_rc {
                gen codigo_carrera_orig = codigo_carrera_harmonized
            }
            else {
                di as error "No existe codigo de carrera en rank_file"
                exit 111
            }
        }
    }

    capture confirm numeric variable codigo_carrera_orig
    if _rc destring codigo_carrera_orig, replace force

    capture confirm numeric variable ao_proceso
    if _rc destring ao_proceso, replace force

    capture confirm numeric variable lugar
    if _rc destring lugar, replace force

    tostring sigla_universidad, replace force
    replace sigla_universidad = upper(strtrim(sigla_universidad))

    capture drop codigo_str
    capture drop codigo_carrera_harmonized

    gen codigo_str = string(codigo_carrera_orig, "%12.0f")
    replace codigo_str = strtrim(codigo_str)

    gen codigo_carrera_harmonized = codigo_carrera_orig
    replace codigo_carrera_harmonized = real( ///
        substr(codigo_str, 1, length(codigo_str)-2) + ///
        "0" + ///
        substr(codigo_str, length(codigo_str)-1, 2) ///
        ) if length(codigo_str) == 4

    drop codigo_str

    keep mrun ao_proceso sigla_universidad codigo_carrera_harmonized lugar

    duplicates report mrun ao_proceso sigla_universidad codigo_carrera_harmonized
    duplicates drop mrun ao_proceso sigla_universidad codigo_carrera_harmonized, force

    tempfile rank_clean
    save `rank_clean'

restore

/**********************************************************************
* 3. Merge ranking into main base
**********************************************************************/

merge m:1 mrun ao_proceso sigla_universidad codigo_carrera_harmonized ///
    using `rank_clean', keep(master match) nogen

count if missing(lugar)
di as result "Observaciones sin ranking luego del merge: " r(N)

* Comment: many applications do not match the rank file. That is expected.
* Inframarginal definitions are only meaningful for observations with lugar.

/**********************************************************************
* 4. Build total enrollment by program-year from effective enrollment
*    IMPORTANT: enrolls_target==1 is used only here to compute thresholds.
**********************************************************************/

preserve

    keep if enrolls_target == 1

    egen program_id_tmp = group(sigla_universidad codigo_carrera_harmonized)
    egen tag_total = tag(mrun program_id_tmp codigo_carrera_harmonized ao_proceso)

    collapse (sum) N_total_enter = tag_total, ///
        by(program_id_tmp sigla_universidad codigo_carrera_harmonized ao_proceso)

    bysort program_id_tmp: egen first_year_enroll = min(ao_proceso)
    gen N_first_tmp = N_total_enter if ao_proceso == first_year_enroll
    bysort program_id_tmp: egen threshold_first_enroll = max(N_first_tmp)
    bysort program_id_tmp: egen threshold_min_enroll   = min(N_total_enter)

    keep program_id_tmp sigla_universidad codigo_carrera_harmonized ///
         threshold_first_enroll threshold_min_enroll
    duplicates drop program_id_tmp sigla_universidad codigo_carrera_harmonized, force

    tempfile enroll_thresholds
    save `enroll_thresholds'

restore

/**********************************************************************
* 5. Create program ID and merge enrollment-based thresholds
**********************************************************************/

egen program_id_rank_analysis = group(sigla_universidad codigo_carrera_harmonized)
rename program_id_rank_analysis program_id_tmp

merge m:1 program_id_tmp sigla_universidad codigo_carrera_harmonized ///
    using `enroll_thresholds', keep(master match) nogen

rename program_id_tmp program_id_rank_analysis

foreach v in threshold_first_enroll threshold_min_enroll {
    capture confirm numeric variable `v'
    if _rc destring `v', replace force
}

/**********************************************************************
* 6. Construct enrollment-threshold inframarginal definitions
*    Applied to ALL applicants with ranking observed, not only enrolled.
**********************************************************************/

capture drop threshold_first_enroll80 threshold_min_enroll80

gen threshold_first_enroll80 = floor(0.8 * threshold_first_enroll)
replace threshold_first_enroll80 = 1 if threshold_first_enroll80 < 1 ///
    & !missing(threshold_first_enroll80)

gen threshold_min_enroll80 = floor(0.8 * threshold_min_enroll)
replace threshold_min_enroll80 = 1 if threshold_min_enroll80 < 1 ///
    & !missing(threshold_min_enroll80)

capture drop infra_first_enroll infra_first_enroll80 infra_min_enroll infra_min_enroll80

gen infra_first_enroll = (lugar <= threshold_first_enroll) ///
    if !missing(lugar, threshold_first_enroll)

gen infra_first_enroll80 = (lugar <= threshold_first_enroll80) ///
    if !missing(lugar, threshold_first_enroll80)

gen infra_min_enroll = (lugar <= threshold_min_enroll) ///
    if !missing(lugar, threshold_min_enroll)

gen infra_min_enroll80 = (lugar <= threshold_min_enroll80) ///
    if !missing(lugar, threshold_min_enroll80)

foreach def in infra_first_enroll infra_first_enroll80 infra_min_enroll infra_min_enroll80 {
    replace `def' = 0 if missing(`def')
}

label var threshold_first_enroll   "Effective enrollment in first observed cohort"
label var threshold_first_enroll80 "80 percent of first observed enrolled cohort"
label var threshold_min_enroll     "Minimum observed annual effective enrollment"
label var threshold_min_enroll80   "80 percent of minimum observed annual enrollment"

label var infra_first_enroll   "Infra: rank <= first observed enrolled cohort threshold"
label var infra_first_enroll80 "Infra: rank <= 80 percent first observed enrolled cohort threshold"
label var infra_min_enroll     "Infra: rank <= minimum annual enrolled cohort threshold"
label var infra_min_enroll80   "Infra: rank <= 80 percent minimum annual enrolled cohort threshold"

/**********************************************************************
* 7. Diagnostics and save master individual-level base
**********************************************************************/

di as text "=================================================="
di as result "Enrollment-threshold inframarginal definitions over all ranked applicants"
di as text "=================================================="

count if !missing(lugar)
local total_ranked = r(N)
di as result "Total ranked applicants/applications: " %12.0fc `total_ranked'

count if enrolls_target == 1
local total_enrolled = r(N)
di as result "Total effective enrolled observations: " %12.0fc `total_enrolled'

foreach def in infra_first_enroll infra_first_enroll80 infra_min_enroll infra_min_enroll80 {
    count if !missing(lugar) & `def' == 1
    local n_ranked = r(N)

    count if enrolls_target == 1 & `def' == 1
    local n_enrolled = r(N)

    di as result "`def': infra among ranked = " %12.0fc `n_ranked' ///
        " | share ranked = " %6.2f (100*`n_ranked'/`total_ranked') "%" ///
        " | infra enrolled = " %12.0fc `n_enrolled' ///
        " | share enrolled = " %6.2f (100*`n_enrolled'/`total_enrolled') "%"
}

count if !missing(threshold_first_enroll, threshold_min_enroll) ///
    & threshold_first_enroll != threshold_min_enroll

di as result "Obs with first-enrollment threshold != min-enrollment threshold: " r(N)

compress
save "`master_out'", replace

tempfile full_master
save `full_master', replace

/**********************************************************************
* 8. Build total enrollment panel from master base
**********************************************************************/

preserve

    keep if enrolls_target == 1

    egen tag_total = tag(mrun program_id_rank_analysis ///
                         codigo_carrera_harmonized ao_proceso)

    collapse (sum) N_total_enter = tag_total, ///
        by(program_id_rank_analysis codigo_carrera_harmonized ///
           sigla_universidad ao_proceso)

    tempfile total_panel
    save `total_panel'

restore

/**********************************************************************
* 9. Prepare total cupos file
**********************************************************************/

preserve

    use "`vacancies_file'", clear

    capture drop codigo_carrera_orig
    capture confirm variable t_codigo_carrera
    if !_rc {
        gen codigo_carrera_orig = t_codigo_carrera
    }
    else {
        capture confirm variable codigo_carrera
        if !_rc {
            gen codigo_carrera_orig = codigo_carrera
        }
        else {
            capture confirm variable codigo_carrera_harmonized
            if !_rc {
                gen codigo_carrera_orig = codigo_carrera_harmonized
            }
            else {
                di as error "No existe codigo de carrera en vacancies_file"
                exit 111
            }
        }
    }

    capture confirm numeric variable ao_proceso
    if _rc destring ao_proceso, replace force

    capture confirm numeric variable codigo_carrera_orig
    if _rc destring codigo_carrera_orig, replace force

    capture drop codigo_str
    capture drop codigo_carrera_harmonized

    gen codigo_str = string(codigo_carrera_orig, "%12.0f")
    replace codigo_str = strtrim(codigo_str)

    gen codigo_carrera_harmonized = codigo_carrera_orig
    replace codigo_carrera_harmonized = real( ///
        substr(codigo_str, 1, length(codigo_str)-2) + ///
        "0" + ///
        substr(codigo_str, length(codigo_str)-1, 2) ///
        ) if length(codigo_str) == 4

    drop codigo_str

    capture confirm variable Z_total_cupos
    if _rc {
        capture confirm variable total_cupos
        if !_rc gen Z_total_cupos = total_cupos
    }

    capture confirm variable Z_total_cupos
    if _rc {
        di as error "No existe Z_total_cupos ni total_cupos en vacancies_file"
        exit 111
    }

    keep ao_proceso codigo_carrera_harmonized Z_total_cupos
    duplicates drop ao_proceso codigo_carrera_harmonized, force

    tempfile vacancies_clean
    save `vacancies_clean'

restore

/**********************************************************************
* 10. Definitions and results postfile
**********************************************************************/

local defs infra_first_enroll infra_first_enroll80 infra_min_enroll infra_min_enroll80

local suffix_infra_first_enroll   "first_enroll"
local suffix_infra_first_enroll80 "first_enroll80"
local suffix_infra_min_enroll     "min_enroll"
local suffix_infra_min_enroll80   "min_enroll80"

local label_infra_first_enroll   "First enrolled threshold"
local label_infra_first_enroll80 "80 percent of first enrolled threshold"
local label_infra_min_enroll     "Minimum enrolled threshold"
local label_infra_min_enroll80   "80 percent of minimum enrolled threshold"

capture postclose results
postfile results str25 definition str90 definition_label ///
    double total_ranked_applications infra_ranked share_ranked ///
    double total_enrolled_students infra_enrolled share_enrolled ///
    double fd_obs programs ///
    double first_stage first_stage_se first_stage_F ///
    double iv_program iv_program_se iv_program_p ///
    using "`c(tmpdir)'/enrollmentthreshold_allapp_results.dta", replace

/**********************************************************************
* 11. Main loop: build panel and estimate
**********************************************************************/

foreach def of local defs {

    use `full_master', clear

    local suffix : copy local suffix_`def'
    local deflabel : copy local label_`def'
    local output_panel "`outprefix'_`suffix'.dta"

    di as text "=================================================="
    di as result "BUILDING PANEL USING: `deflabel' (`def')"
    di as text "=================================================="

    count if !missing(lugar)
    local total_ranked_loop = r(N)

    count if `def' == 1
    local infra_ranked = r(N)

    local share_ranked = 100 * `infra_ranked' / `total_ranked_loop'

    count if enrolls_target == 1
    local total_enrolled_loop = r(N)

    count if enrolls_target == 1 & `def' == 1
    local infra_enrolled = r(N)

    local share_enrolled = 100 * `infra_enrolled' / `total_enrolled_loop'

    di as result "Total ranked applications = " %12.0fc `total_ranked_loop'
    di as result "Infra ranked applications = " %12.0fc `infra_ranked'
    di as result "Share ranked infra        = " %8.2f `share_ranked' "%"
    di as result "Total enrolled students   = " %12.0fc `total_enrolled_loop'
    di as result "Infra enrolled students   = " %12.0fc `infra_enrolled'
    di as result "Share enrolled infra      = " %8.2f `share_enrolled' "%"

    preserve

        * IMPORTANT: do NOT keep only enrolls_target==1 here.
        * The inframarginal sample is all ranked applicants satisfying the threshold.
        keep if `def' == 1

        count
        if r(N) == 0 {
            di as error "No quedaron inframarginales para definicion: `def'"
            exit 2000
        }

        egen tag_infra = tag(mrun program_id_rank_analysis ///
                             codigo_carrera_harmonized ao_proceso)

        collapse ///
            (sum)  N_infra_enter = tag_infra ///
            (mean) grad_enrolled_program_rate_8y = graduates_enrolled_program_8y ///
                   grad_uni_rate_8y    = graduates_uni_8y ///
                   grad_he_rate_8y     = graduates_he_8y, ///
            by(program_id_rank_analysis codigo_carrera_harmonized ///
               sigla_universidad ao_proceso)

        tempfile infra_panel_`suffix'
        save `infra_panel_`suffix''

    restore

    use `infra_panel_`suffix'', clear

    merge 1:1 program_id_rank_analysis codigo_carrera_harmonized ///
        sigla_universidad ao_proceso ///
        using `total_panel', keep(master match) nogen

    merge m:1 ao_proceso codigo_carrera_harmonized ///
        using `vacancies_clean', keep(master match) nogen

    bysort program_id_rank_analysis: egen n_years_panel = count(ao_proceso)
    keep if n_years_panel >= 2

    xtset program_id_rank_analysis ao_proceso

    foreach v in ///
        N_total_enter ///
        N_infra_enter ///
        grad_enrolled_program_rate_8y ///
        grad_uni_rate_8y ///
        grad_he_rate_8y ///
        Z_total_cupos {

        gen D_`v' = D.`v'
    }

    gen L_N_total_enter = L.N_total_enter
    gen avg_N_total_enter = (N_total_enter + L_N_total_enter) / 2

    gen L_N_infra_enter = L.N_infra_enter
    gen avg_N_infra_enter = (N_infra_enter + L_N_infra_enter) / 2

    gen sample_firststage = !missing(D_N_total_enter, D_Z_total_cupos, avg_N_total_enter)
    gen sample_iv = sample_firststage ///
        & !missing(D_grad_enrolled_program_rate_8y, avg_N_infra_enter)

    compress
    save "`output_panel'", replace

    count if sample_iv == 1
    local fd_obs = r(N)

    distinct program_id_rank_analysis if sample_iv == 1
    local programs = r(ndistinct)

    di as text "--------------------------------------------------"
    di as result "FIRST STAGE | `deflabel'"

    reg D_N_total_enter D_Z_total_cupos i.ao_proceso ///
        [aw = avg_N_total_enter] ///
        if sample_firststage == 1, ///
        vce(cluster program_id_rank_analysis)

    local fs_coef = _b[D_Z_total_cupos]
    local fs_se   = _se[D_Z_total_cupos]

    test D_Z_total_cupos = 0
    local fs_F = r(F)

    di as text "--------------------------------------------------"
    di as result "2SLS | `deflabel'"

    ivregress 2sls D_grad_enrolled_program_rate_8y i.ao_proceso ///
        (D_N_total_enter = D_Z_total_cupos) ///
        [aw = avg_N_infra_enter] ///
        if sample_iv == 1, ///
        vce(cluster program_id_rank_analysis)

    local iv_coef = _b[D_N_total_enter]
    local iv_se   = _se[D_N_total_enter]
    local iv_p    = 2 * normal(-abs(_b[D_N_total_enter] / _se[D_N_total_enter]))

    estat firststage

    post results ("`suffix'") ("`deflabel'") ///
        (`total_ranked_loop') (`infra_ranked') (`share_ranked') ///
        (`total_enrolled_loop') (`infra_enrolled') (`share_enrolled') ///
        (`fd_obs') (`programs') ///
        (`fs_coef') (`fs_se') (`fs_F') ///
        (`iv_coef') (`iv_se') (`iv_p')
}

postclose results

/**********************************************************************
* 12. Save results summary
**********************************************************************/

use "`c(tmpdir)'/enrollmentthreshold_allapp_results.dta", clear

format total_ranked_applications infra_ranked total_enrolled_students infra_enrolled %12.0fc
format share_ranked share_enrolled %8.2f
format fd_obs programs %9.0fc
format first_stage first_stage_se iv_program iv_program_se %9.5f
format first_stage_F %9.1f
format iv_program_p %9.3f

list, noobs clean

save "$processed/inframarginal_altdefs_enrollmentthreshold_allapp_summary.dta", replace
export delimited using "$processed/inframarginal_altdefs_enrollmentthreshold_allapp_summary.csv", replace


di as text "=================================================="
di as result "Finished enrollment-threshold definitions over all ranked applicants."
di as result "Master saved: `master_out'"
di as result "Panels saved with prefix: `outprefix'_*.dta"
di as result "Summary saved: $processed/inframarginal_altdefs_enrollmentthreshold_allapp_summary.*"
di as text "=================================================="

