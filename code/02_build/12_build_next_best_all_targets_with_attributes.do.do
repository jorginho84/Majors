/**********************************************************************
* 12_build_next_best_all_targets_with_attributes.do
*
* Objetivo:
*   Construir next-best feasible alternative para TODA la muestra RDD,
*   no solo para admitidos, y pegar atributos programa-año creados en 08.
*
* Inputs:
*   $processed/analysis_sample.dta
*   $processed/applications_rd.dta
*   $processed/program_year_attributes_nextbest.dta
*
* Output:
*   $processed/next_best_all_targets_with_attributes.dta
*
* Nota:
*   Este script NO crea delta_group.
*   Los grupos se definen manualmente en 14, 15 y 18.
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local targets_source "$processed/analysis_sample.dta"
local applications   "$processed/applications_rd.dta"
local attr_lookup    "$processed/program_year_attributes_nextbest.dta"

local study_start 2007
local study_end   2016

capture confirm file "`targets_source'"
if _rc != 0 {
    di as error "No existe `targets_source'."
    exit 601
}

capture confirm file "`applications'"
if _rc != 0 {
    di as error "No existe `applications'."
    exit 601
}

capture confirm file "`attr_lookup'"
if _rc != 0 {
    di as error "No existe `attr_lookup'. Corre primero 08_build_program_year_attributes_nextbest.do"
    exit 601
}


/**********************************************************************
* 1. Programas auxiliares
**********************************************************************/

capture program drop standardize_code_year
program define standardize_code_year

    capture confirm variable codigo_carrera
    if _rc != 0 {
        capture confirm variable t_codigo_carrera
        if _rc == 0 rename t_codigo_carrera codigo_carrera
        else {
            di as error "No existe codigo_carrera ni t_codigo_carrera."
            exit 111
        }
    }

    capture confirm variable ao_proceso
    if _rc != 0 {
        capture confirm variable anyo_proceso
        if _rc == 0 rename anyo_proceso ao_proceso
        else {
            capture confirm variable año_proceso
            if _rc == 0 rename año_proceso ao_proceso
            else {
                capture confirm variable ano_proceso
                if _rc == 0 rename ano_proceso ao_proceso
                else {
                    di as error "No existe variable de año reconocible."
                    exit 111
                }
            }
        }
    }

    capture confirm numeric variable codigo_carrera
    if _rc != 0 destring codigo_carrera, replace force

    capture confirm numeric variable ao_proceso
    if _rc != 0 destring ao_proceso, replace force

end


capture program drop attach_attributes
program define attach_attributes

    syntax using/, ATTRS(string)

    tempfile lookup_target lookup_next

    /************************************************************
    * Lookup target
    ************************************************************/

    preserve

        use "`using'", clear

        keep ao_proceso codigo_carrera `attrs'

        duplicates drop ao_proceso codigo_carrera, force

        foreach v of local attrs {
            rename `v' target_`v'
        }

        rename codigo_carrera target_codigo_carrera

        save `lookup_target', replace

    restore

    merge m:1 ao_proceso target_codigo_carrera using `lookup_target', ///
        keep(master match) nogen


    /************************************************************
    * Lookup next-best
    ************************************************************/

    preserve

        use "`using'", clear

        keep ao_proceso codigo_carrera `attrs'

        duplicates drop ao_proceso codigo_carrera, force

        foreach v of local attrs {
            rename `v' nextbest_`v'
        }

        rename codigo_carrera nextbest_codigo_carrera

        save `lookup_next', replace

    restore

    merge m:1 ao_proceso nextbest_codigo_carrera using `lookup_next', ///
        keep(master match) nogen


    /************************************************************
    * Deltas target - next-best
    ************************************************************/

    foreach v of local attrs {

        capture confirm numeric variable target_`v'
        if _rc == 0 {

            capture confirm numeric variable nextbest_`v'
            if _rc == 0 {

                capture drop delta_`v'

                gen double delta_`v' = target_`v' - nextbest_`v' ///
                    if has_nextbest == 1 ///
                    & !missing(target_`v', nextbest_`v')

                label variable delta_`v' "Target minus next-best: `v'"
            }
        }
    }

end


/**********************************************************************
* 2. Construir base de candidatos desde applications_rd
**********************************************************************/

tempfile candidates targets nextbest

use "`applications'", clear

standardize_code_year

keep if inrange(ao_proceso, `study_start', `study_end')

foreach v in mrun ao_proceso preferencia codigo_carrera ///
             estado_preferencia application_score cutoff_regular {

    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable necesaria en applications_rd: `v'"
        exit 111
    }
}

capture confirm variable score_rd
if _rc != 0 {
    gen double score_rd = application_score - cutoff_regular ///
        if !missing(application_score, cutoff_regular)
}

capture confirm variable above_cutoff
if _rc != 0 {
    gen byte above_cutoff = score_rd >= 0 if !missing(score_rd)
}

gen byte would_admit = application_score >= cutoff_regular ///
    if !missing(application_score, cutoff_regular)

replace would_admit = 0 if missing(would_admit)

keep mrun ao_proceso preferencia codigo_carrera ///
     estado_preferencia application_score cutoff_regular ///
     score_rd above_cutoff would_admit

drop if missing(mrun, ao_proceso, preferencia, codigo_carrera)

rename preferencia          cand_preferencia
rename codigo_carrera       cand_codigo_carrera
rename estado_preferencia   cand_estado_preferencia
rename application_score    cand_application_score
rename cutoff_regular       cand_cutoff_regular
rename score_rd             cand_score_rd
rename above_cutoff         cand_above_cutoff
rename would_admit          cand_would_admit

save `candidates', replace


/**********************************************************************
* 3. Construir base de targets desde analysis_sample
*
**********************************************************************/

use "`targets_source'", clear

standardize_code_year

keep if inrange(ao_proceso, `study_start', `study_end')

foreach v in mrun ao_proceso preferencia codigo_carrera ///
             estado_preferencia application_score cutoff_regular {

    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable necesaria en analysis_sample: `v'"
        exit 111
    }
}

capture confirm variable score_rd
if _rc != 0 {
    gen double score_rd = application_score - cutoff_regular ///
        if !missing(application_score, cutoff_regular)
}

capture confirm variable above_cutoff
if _rc != 0 {
    gen byte above_cutoff = score_rd >= 0 if !missing(score_rd)
}

gen byte target_would_admit_aux = application_score >= cutoff_regular ///
    if !missing(application_score, cutoff_regular)

replace target_would_admit_aux = 0 if missing(target_would_admit_aux)

rename preferencia              target_preferencia
rename codigo_carrera           target_codigo_carrera
rename estado_preferencia       target_estado_preferencia
rename application_score        target_application_score
rename cutoff_regular           target_cutoff_regular
rename score_rd                 target_score_rd
rename above_cutoff             target_above_cutoff
rename target_would_admit_aux   target_would_admit

egen long target_id = group(mrun ao_proceso target_preferencia target_codigo_carrera)

keep target_id mrun ao_proceso ///
     target_preferencia target_codigo_carrera ///
     target_estado_preferencia ///
     target_application_score target_cutoff_regular ///
     target_score_rd target_above_cutoff target_would_admit

duplicates report target_id
duplicates drop target_id, force

save `targets', replace


/**********************************************************************
* 4. Elegir primera preferencia inferior factible
**********************************************************************/

use `targets', clear

joinby mrun ao_proceso using `candidates'

keep if cand_preferencia > target_preferencia
keep if cand_would_admit == 1

sort target_id cand_preferencia

by target_id: keep if _n == 1

keep target_id ///
     cand_preferencia cand_codigo_carrera cand_estado_preferencia ///
     cand_application_score cand_cutoff_regular ///
     cand_score_rd cand_above_cutoff cand_would_admit

rename cand_preferencia          nextbest_preferencia
rename cand_codigo_carrera       nextbest_codigo_carrera
rename cand_estado_preferencia   nextbest_estado_preferencia
rename cand_application_score    nextbest_application_score
rename cand_cutoff_regular       nextbest_cutoff_regular
rename cand_score_rd             nextbest_score_rd
rename cand_above_cutoff         nextbest_above_cutoff
rename cand_would_admit          nextbest_would_admit

save `nextbest', replace


/********************************************************************************
* 5. Unir targets con next-best
********************************************************************************/

use `targets', clear

merge 1:1 target_id using `nextbest', keep(master match) nogen

gen byte has_nextbest = !missing(nextbest_codigo_carrera)

label define has_nextbest_lbl ///
    0 "No next-best feasible alternative" ///
    1 "Has next-best feasible alternative", replace

label values has_nextbest has_nextbest_lbl


/**********************************************************************
* 6. Crear lookup corto de atributos desde 08
**********************************************************************/

tempfile attr_lookup_short

preserve

    use "`attr_lookup'", clear

    capture confirm variable codigo_carrera
    if _rc != 0 {
        capture confirm variable t_codigo_carrera
        if _rc == 0 rename t_codigo_carrera codigo_carrera
        else {
            di as error "No existe codigo_carrera ni t_codigo_carrera en attr_lookup."
            exit 111
        }
    }

    capture confirm numeric variable codigo_carrera
    if _rc != 0 destring codigo_carrera, replace force

    capture confirm numeric variable ao_proceso
    if _rc != 0 destring ao_proceso, replace force

    foreach v in ///
        selectivity_program_year ///
        p50_selectivity_program_year ///
        retention_y2_rate ///
        female_share_enrolled ///
        graduation_rate_target_8y ///
        cutoff_regular ///
        program_size {

        capture confirm variable `v'
        if _rc != 0 {
            di as error "Falta variable en attr_lookup: `v'"
            exit 111
        }
    }

    rename selectivity_program_year      selectivity
    rename p50_selectivity_program_year  p50_selectivity
    rename retention_y2_rate             retention_y2
    rename female_share_enrolled         female_share
    rename graduation_rate_target_8y     grad_target_8y

    keep ao_proceso codigo_carrera ///
         selectivity ///
         p50_selectivity ///
         retention_y2 ///
         female_share ///
         grad_target_8y ///
         cutoff_regular ///
         program_size

    duplicates drop ao_proceso codigo_carrera, force

    save `attr_lookup_short', replace

restore


/**********************************************************************
* 7. Pegar atributos al target y next-best
**********************************************************************/

local attrs ///
    selectivity ///
    p50_selectivity ///
    retention_y2 ///
    female_share ///
    grad_target_8y ///
    cutoff_regular ///
    program_size

attach_attributes using `attr_lookup_short', attrs(`attrs')


/**********************************************************************
* 8. Variables auxiliares
**********************************************************************/

capture drop delta_selectivity_10
capture drop delta_p50_selectivity_10

capture confirm variable delta_selectivity
if _rc == 0 {
    gen double delta_selectivity_10 = delta_selectivity / 10
    label variable delta_selectivity_10 "Delta selectivity divided by 10"
}

capture confirm variable delta_p50_selectivity
if _rc == 0 {
    gen double delta_p50_selectivity_10 = delta_p50_selectivity / 10
    label variable delta_p50_selectivity_10 "Delta p50 selectivity divided by 10"
}


/**********************************************************************
* 9. Ordenar variables y guardar output único
**********************************************************************/

order target_id mrun ao_proceso ///
      target_preferencia target_estado_preferencia target_codigo_carrera ///
      target_application_score target_cutoff_regular ///
      target_score_rd target_above_cutoff target_would_admit ///
      nextbest_preferencia nextbest_estado_preferencia nextbest_codigo_carrera ///
      nextbest_application_score nextbest_cutoff_regular ///
      nextbest_score_rd nextbest_above_cutoff nextbest_would_admit ///
      has_nextbest ///
      target_selectivity nextbest_selectivity delta_selectivity ///
      target_p50_selectivity nextbest_p50_selectivity delta_p50_selectivity ///
      target_retention_y2 nextbest_retention_y2 delta_retention_y2 ///
      target_female_share nextbest_female_share delta_female_share ///
      target_grad_target_8y nextbest_grad_target_8y delta_grad_target_8y ///
      target_cutoff_regular nextbest_cutoff_regular delta_cutoff_regular ///
      target_program_size nextbest_program_size delta_program_size ///
      delta_selectivity_10 delta_p50_selectivity_10

compress

save "$processed/next_best_all_targets_with_attributes.dta", replace


/**********************************************************************
* 10. Diagnóstico final
**********************************************************************/

di as text "=================================================="
di as result "Diagnóstico final next-best all targets + atributos"
di as text "=================================================="

count
di as result "Total targets en output: " r(N)

tab target_estado_preferencia, missing
tab has_nextbest, missing

di as text "--------------------------------------------------"
di as result "Dentro de bandwidth target |score_rd| <= 25"
di as text "--------------------------------------------------"

count if abs(target_score_rd) <= 25
tab has_nextbest if abs(target_score_rd) <= 25, missing

summarize delta_selectivity if abs(target_score_rd) <= 25, detail
summarize delta_grad_target_8y if abs(target_score_rd) <= 25, detail

foreach v in selectivity p50_selectivity ///
             retention_y2 female_share grad_target_8y ///
             cutoff_regular program_size {

    capture confirm variable delta_`v'

    if _rc == 0 {

        di as text "--------------------------------------------------"
        di as result "delta_`v'"
        count if has_nextbest == 1 & missing(delta_`v')
        summarize target_`v' nextbest_`v' delta_`v', detail
    }
}

duplicates report mrun ao_proceso target_preferencia target_codigo_carrera

di as text "=================================================="
di as result "09 terminado correctamente"
di as result "Output:"
di as result "$processed/next_best_all_targets_with_attributes.dta"
di as text "=================================================="