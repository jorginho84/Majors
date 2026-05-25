/**********************************************************************
* 08b_build_program_year_attributes_nextbest.do
*
* Construye un lookup único de atributos programa-año para comparar:
*   target admitido vs next-best factible.
*
* Output:
*   $processed/program_year_attributes_nextbest.dta
*
* Atributos iniciales:
*   selectivity_program_year
*   p50_selectivity_program_year
*   retention_y2_rate
*   female_share_enrolled
*   graduation_rate_target_8y
*   cutoff_regular
*   program_size
*   is_university
*   tuition
*
* Notas:
*   - program_size = número de admitidos regulares en applications_rd.
*   - female_share_enrolled, is_university y tuition salen de matrícula.
*   - retention_y2_rate se calcula siguiendo al mismo programa en t+1.
*   - Para atributos de matrícula y retención se usa codigo_carrera_h para mejorar el match pre/post 2012.
**********************************************************************/

clear all
set more off


do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

capture mkdir "$processed"

local applications "$processed/applications_rd.dta"
local output      "$processed/program_year_attributes_nextbest.dta"

* Usar matrícula/titulados raw si existen en config.
local mat_raw "${mat_raw}"
local tit_raw "${tit_raw}"

* Si no hay raw, intentar con processed/enrollment.dta para lo que alcance.
local enrollment_processed "$processed/enrollment.dta"

* Período de estudio del RDD / next-best
local study_start 2007
local study_end   2016

* Para retención de la cohorte 2016 se necesita observar matrícula en 2017
local enrollment_end_for_retention = `study_end' + 1

* Último año disponible de titulados
local tit_end 2024

* Ventana de titulación
local grad_window 8


/**********************************************************************
* 1. Programas auxiliares
**********************************************************************/

capture program drop require_vars
program define require_vars
    syntax, VARS(string) CONTEXT(string)

    di as text "=================================================="
    di as result "Chequeando variables: `context'"
    di as text "=================================================="

    foreach v of local vars {
        capture confirm variable `v'
        if _rc != 0 {
            di as error "FALTA variable `v' en contexto: `context'"
            exit 111
        }
        else {
            di as result "OK: `v'"
        }
    }
end


capture program drop standardize_app_code_year
program define standardize_app_code_year

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
                    capture confirm variable cat_periodo
                    if _rc == 0 rename cat_periodo ao_proceso
                    else {
                        di as error "No existe variable de año reconocible."
                        exit 111
                    }
                }
            }
        }
    }

    capture confirm numeric variable codigo_carrera
    if _rc != 0 {
        tostring codigo_carrera, replace force
        replace codigo_carrera = trim(codigo_carrera)
        replace codigo_carrera = "" if codigo_carrera == "." | upper(codigo_carrera) == "NA"
        destring codigo_carrera, replace force
    }

    capture confirm numeric variable ao_proceso
    if _rc != 0 {
        destring ao_proceso, replace force
    }

end


capture program drop make_program_code_h
program define make_program_code_h
    syntax, CODEVAR(name) YEARVAR(name) NEWVAR(name)

    capture drop `newvar'
    capture drop __code_raw_str __code_h_str

    capture confirm numeric variable `codevar'
    if _rc == 0 {
        gen str20 __code_raw_str = string(`codevar', "%20.0f")
    }
    else {
        gen str20 __code_raw_str = trim(`codevar')
    }

    replace __code_raw_str = trim(__code_raw_str)

    gen str20 __code_h_str = __code_raw_str

    replace __code_h_str = ///
        substr(__code_raw_str, 1, 2) + "0" + substr(__code_raw_str, 3, .) ///
        if `yearvar' < 2012 & strlen(__code_raw_str) == 4

    destring __code_h_str, gen(`newvar') force

    drop __code_raw_str __code_h_str
end


capture program drop make_numeric_from_string
program define make_numeric_from_string
    syntax varname, GEN(name)

    capture drop `gen'
    capture drop __tmp_string

    capture confirm numeric variable `varlist'
    if _rc == 0 {
        gen double `gen' = `varlist'
    }
    else {
        gen str80 __tmp_string = trim(`varlist')
        replace __tmp_string = subinstr(__tmp_string, "$", "", .)
        replace __tmp_string = subinstr(__tmp_string, ".", "", .)
        replace __tmp_string = subinstr(__tmp_string, " ", "", .)
        replace __tmp_string = subinstr(__tmp_string, ",", ".", .)
        replace __tmp_string = "" if upper(__tmp_string) == "NA"
        replace __tmp_string = "" if upper(__tmp_string) == "SININFORMACION"
        replace __tmp_string = "" if upper(__tmp_string) == "SININFORMACIÓN"
        destring __tmp_string, gen(`gen') force
        drop __tmp_string
    }
end


/**********************************************************************
* 2. Base maestra de programa-año desde applications_rd
**********************************************************************/

di as text "=================================================="
di as result "Construyendo base maestra desde applications_rd"
di as text "=================================================="

use "`applications'", clear
standardize_app_code_year

keep if inrange(ao_proceso, `study_start', `study_end')

require_vars, ///
    vars("ao_proceso codigo_carrera estado_preferencia cutoff_regular") ///
    context("applications_rd para atributos")

keep ao_proceso codigo_carrera estado_preferencia cutoff_regular ///
     lyc_actual mate_actual promlm_actual

make_program_code_h, codevar(codigo_carrera) yearvar(ao_proceso) newvar(codigo_carrera_h)


/**********************************************************************
* Construir promedio PSU Lenguaje-Matemática canónico
*
* psu_lm es la variable oficial para selectividad.
* Regla:
*   1. Usar promedio de lyc_actual y mate_actual si ambos existen.
*   2. Usar promlm_actual solo como fallback.
*   3. Limpiar valores fuera de rango.
**********************************************************************/

capture drop psu_lm psu_lm_source
capture drop lyc_num mate_num promlm_num

gen double psu_lm = .
gen str20 psu_lm_source = ""

************************************************************
* 1. Convertir Lenguaje a numérico
************************************************************

capture confirm variable lyc_actual
if _rc == 0 {
    capture confirm numeric variable lyc_actual
    if _rc == 0 {
        gen double lyc_num = lyc_actual
    }
    else {
        gen str30 lyc_clean = trim(lyc_actual)
        replace lyc_clean = subinstr(lyc_clean, ",", ".", .)
        gen double lyc_num = real(lyc_clean)
        drop lyc_clean
    }
}
else {
    gen double lyc_num = .
}

************************************************************
* 2. Convertir Matemática a numérico
************************************************************

capture confirm variable mate_actual
if _rc == 0 {
    capture confirm numeric variable mate_actual
    if _rc == 0 {
        gen double mate_num = mate_actual
    }
    else {
        gen str30 mate_clean = trim(mate_actual)
        replace mate_clean = subinstr(mate_clean, ",", ".", .)
        gen double mate_num = real(mate_clean)
        drop mate_clean
    }
}
else {
    gen double mate_num = .
}

************************************************************
* 3. Convertir promlm_actual a numérico como fallback
************************************************************

capture confirm variable promlm_actual
if _rc == 0 {
    capture confirm numeric variable promlm_actual
    if _rc == 0 {
        gen double promlm_num = promlm_actual
    }
    else {
        gen str30 promlm_clean = trim(promlm_actual)
        replace promlm_clean = subinstr(promlm_clean, ",", ".", .)
        gen double promlm_num = real(promlm_clean)
        drop promlm_clean
    }
}
else {
    gen double promlm_num = .
}

************************************************************
* 4. Regla principal: promedio de Lenguaje y Matemática
************************************************************

replace psu_lm = (lyc_num + mate_num) / 2 ///
    if !missing(lyc_num, mate_num) ///
    & lyc_num > 0 ///
    & mate_num > 0

replace psu_lm_source = "lyc_mate" ///
    if !missing(psu_lm)

************************************************************
* 5. Fallback: usar promlm_actual solo si no se pudo calcular
************************************************************

replace psu_lm = promlm_num ///
    if missing(psu_lm) ///
    & !missing(promlm_num) ///
    & promlm_num > 0

replace psu_lm_source = "promlm_actual" ///
    if psu_lm_source == "" ///
    & !missing(psu_lm)

************************************************************
* 6. Limpiar valores fuera de rango razonable PSU
************************************************************

replace psu_lm = . if psu_lm <= 0
replace psu_lm = . if psu_lm < 100 | psu_lm > 1000

replace psu_lm_source = "" if missing(psu_lm)

label variable psu_lm ///
    "PSU LM average used in analysis"

label variable psu_lm_source ///
    "Source used to construct PSU LM average"

************************************************************
* 7. Diagnóstico de construcción
************************************************************

di as text "=================================================="
di as result "Diagnóstico psu_lm"
di as text "=================================================="

tab psu_lm_source, missing

count if missing(psu_lm)
di as text "psu_lm missing: " as result %12.0fc r(N)

count if missing(promlm_actual) & !missing(psu_lm)
di as text "promlm_actual missing pero psu_lm recuperado: " as result %12.0fc r(N)

drop lyc_num mate_num promlm_num

gen byte admitted = estado_preferencia == 24 if !missing(estado_preferencia)
replace admitted = 0 if missing(admitted)

gen double psu_lm_admitted = psu_lm if admitted == 1

collapse ///
    (mean) selectivity_program_year = psu_lm_admitted ///
    (p50)  p50_selectivity_program_year = psu_lm_admitted ///
    (count) n_admitted_score = psu_lm_admitted ///
    (sum) program_size = admitted ///
    (p50) cutoff_regular = cutoff_regular, ///
    by(ao_proceso codigo_carrera codigo_carrera_h)

label variable selectivity_program_year "Mean PSU LM among admitted students"
label variable p50_selectivity_program_year "Median PSU LM among admitted students"
label variable n_admitted_score "Admitted students with valid PSU LM"
label variable program_size "Number of admitted regular applicants"
label variable cutoff_regular "Regular admission cutoff"

tempfile master_attrs
save `master_attrs', replace



/**********************************************************************
* 3. Construir matrícula puente usando enrollment_demre
*
**********************************************************************/

tempfile enroll_long enrollment_attrs retention_lookup
local have_enroll_long 0

capture confirm file "$processed/enrollment_demre.dta"
if _rc != 0 {
    di as error "No existe $processed/enrollment_demre.dta. No se pueden construir atributos de matrícula con puente DEMRE."
}
else {

    /******************************************************************
    * 3.1 Leer matrícula raw para atributos individuales
    ******************************************************************/

    tempfile raw_all raw_num raw_first raw_individual
    local first_raw 1

    if "`mat_raw'" != "" {

        di as text "=================================================="
        di as result "Construyendo atributos individuales desde matrícula raw"
        di as text "=================================================="

        forvalues y = `study_start'/`enrollment_end_for_retention' {

            local files : dir "`mat_raw'" files "*.csv"
            local file ""

            foreach f of local files {
                if regexm("`f'", "`y'") & regexm("`f'", "matr") {
                    local file "`f'"
                    continue, break
                }
            }

            if "`file'" == "" {
                di as error "No se encontró archivo matrícula CSV para `y'. Se salta."
                continue
            }

            di as result "Matrícula `y': `file'"

            import delimited "`mat_raw'/`file'", clear varnames(1) encoding(UTF-8) bindquote(strict)
            rename *, lower

            * Año
            capture confirm variable cat_periodo
            if _rc != 0 gen cat_periodo = `y'
            rename cat_periodo ao_proceso
            capture confirm numeric variable ao_proceso
            if _rc != 0 destring ao_proceso, replace force
            replace ao_proceso = `y' if missing(ao_proceso)

            * MRUN
            capture confirm variable mrun
            if _rc != 0 {
                di as error "No existe mrun en matrícula `y'. Se salta."
                continue
            }
            capture confirm numeric variable mrun
            if _rc != 0 destring mrun, replace force
            drop if missing(mrun)

            gen str20 mrun_str = string(mrun, "%20.0f")
            replace mrun_str = trim(mrun_str)

            * Código único para graduación
            capture confirm variable codigo_unico
            if _rc == 0 {
                capture confirm numeric variable codigo_unico
                if _rc == 0 tostring codigo_unico, gen(codigo_unico_str) format(%30.0f) force
                else gen str40 codigo_unico_str = trim(codigo_unico)
                replace codigo_unico_str = trim(codigo_unico_str)
                replace codigo_unico_str = "" if codigo_unico_str == "."
            }
            else {
                gen str40 codigo_unico_str = ""
            }

            * Año ingreso carrera origen
            local entryvar ""
            foreach cand in anio_ing_carr_ori año_ing_carr_ori ano_ing_carr_ori {
                capture confirm variable `cand'
                if _rc == 0 {
                    local entryvar "`cand'"
                    continue, break
                }
            }

            if "`entryvar'" != "" {
                capture confirm numeric variable `entryvar'
                if _rc == 0 gen double entry_year = `entryvar'
                else destring `entryvar', gen(entry_year) force
                replace entry_year = . if inlist(entry_year, 9995, 9998, 9999, 1900)
            }
            else {
                gen double entry_year = .
            }

            * Género
            capture confirm variable gen_alu
            if _rc == 0 {
                capture confirm numeric variable gen_alu
                if _rc == 0 gen byte female = (gen_alu == 2) if inlist(gen_alu, 1, 2)
                else {
                    gen str20 gen_clean = lower(trim(gen_alu))
                    gen byte female = .
                    replace female = 1 if regexm(gen_clean, "2|mujer|femenino|female")
                    replace female = 0 if regexm(gen_clean, "1|hombre|masculino|male")
                    drop gen_clean
                }
            }
            else gen byte female = .

            * Tipo institución
            capture confirm variable tipo_inst_1
            if _rc == 0 {
                gen str60 tipo_inst_clean = upper(trim(tipo_inst_1))
                gen byte is_university = regexm(tipo_inst_clean, "UNIVERS")
                drop tipo_inst_clean
            }
            else gen byte is_university = .

            * Arancel
            capture confirm variable valor_arancel
            if _rc == 0 make_numeric_from_string valor_arancel, gen(tuition)
            else gen double tuition = .
            replace tuition = . if tuition <= 0

            keep mrun mrun_str ao_proceso codigo_unico_str entry_year ///
                 female is_university tuition

            if `first_raw' == 1 {
                save `raw_all', replace
                local first_raw 0
            }
            else {
                append using `raw_all'
                save `raw_all', replace
            }
        }
    }

    if `first_raw' == 0 {

        * Colapsar atributos numéricos a nivel estudiante-año.
        use `raw_all', clear
        collapse ///
            (mean) female = female ///
            (p50) tuition = tuition ///
            (max) is_university = is_university ///
            (p50) entry_year = entry_year, ///
            by(mrun ao_proceso)
        save `raw_num', replace

        * Tomar un código único representativo para graduación.
        use `raw_all', clear
        keep mrun mrun_str ao_proceso codigo_unico_str
        drop if codigo_unico_str == ""
        sort mrun ao_proceso codigo_unico_str
        by mrun ao_proceso: keep if _n == 1
        save `raw_first', replace

        use `raw_num', clear
        merge 1:1 mrun ao_proceso using `raw_first', keep(master match) nogen
        capture confirm variable mrun_str
        if _rc != 0 {
            gen str20 mrun_str = string(mrun, "%20.0f")
            replace mrun_str = trim(mrun_str)
        }
        save `raw_individual', replace


        /**************************************************************
        * 3.2 Pegar código DEMRE matriculado desde enrollment_demre
        **************************************************************/

        use "$processed/enrollment_demre.dta", clear
        keep if inrange(ao_proceso, `study_start', `enrollment_end_for_retention')

        capture confirm numeric variable mrun
        if _rc != 0 destring mrun, replace force

        capture confirm numeric variable codigo_carrera
        if _rc != 0 destring codigo_carrera, replace force

        keep mrun ao_proceso codigo_carrera
        drop if missing(mrun, ao_proceso, codigo_carrera)
        duplicates drop mrun ao_proceso codigo_carrera, force

        merge m:1 mrun ao_proceso using `raw_individual', keep(master match) nogen

        gen str20 mrun_str2 = string(mrun, "%20.0f")
        replace mrun_str2 = trim(mrun_str2)
        replace mrun_str = mrun_str2 if missing(mrun_str) | mrun_str == ""
        drop mrun_str2

        * Para compatibilidad con bloques posteriores
        make_program_code_h, codevar(codigo_carrera) yearvar(ao_proceso) newvar(codigo_carrera_h)

        save `enroll_long', replace
        local have_enroll_long 1
    }
}


if `have_enroll_long' == 1 {

    /******************************************************************
    * 3.3 Atributos contemporáneos desde matrícula + puente DEMRE
    ******************************************************************/

    use `enroll_long', clear
    keep if inrange(ao_proceso, `study_start', `study_end')
    gen one = 1

    collapse ///
        (mean) female_share_enrolled = female ///
        (count) n_gender_enrolled = female ///
        (p50) tuition = tuition ///
        (mean) tuition_mean = tuition ///
        (count) n_tuition_base = tuition ///
        (max) is_university = is_university ///
        (sum) n_enrolled_program_year = one, ///
        by(ao_proceso codigo_carrera)

    label variable female_share_enrolled "Share female among enrolled students"
    label variable tuition "Median annual tuition"
    label variable tuition_mean "Mean annual tuition"
    label variable is_university "Program belongs to a university"
    label variable n_enrolled_program_year "Number of enrolled students"

    save `enrollment_attrs', replace


    /******************************************************************
    * 3.4 Retención segundo año
    *
    * Importante:
    *   enrollment_demre.dta identifica el código DEMRE de entrada, pero
    *   NO sirve para medir continuidad en t+1 porque contiene matrículas
    *   de ingreso DEMRE, no necesariamente stock de matrícula continua.
    *
    *   Por eso:
    *       - el programa de entrada se asigna con enrollment_demre;
    *       - la continuidad t+1 se mide en la matrícula raw usando
    *         codigo_unico_str, que identifica institución-sede-carrera-
    *         jornada-versión.
    ******************************************************************/

    tempfile raw_stock entrants retained_flags

    * Stock matrícula por estudiante-año-programa raw
    use `raw_all', clear
    keep mrun mrun_str ao_proceso codigo_unico_str
    drop if missing(mrun, ao_proceso)
    drop if codigo_unico_str == ""
    duplicates drop mrun mrun_str ao_proceso codigo_unico_str, force
    save `raw_stock', replace

    * Entrantes DEMRE con programa raw de entrada
    use `enroll_long', clear
    keep if inrange(ao_proceso, `study_start', `study_end')
    keep mrun mrun_str ao_proceso codigo_carrera codigo_unico_str
    drop if missing(mrun, ao_proceso, codigo_carrera)
    drop if codigo_unico_str == ""
    rename ao_proceso entry_year
    rename codigo_carrera entry_codigo_carrera
    rename codigo_unico_str entry_codigo_unico
    duplicates drop mrun entry_year entry_codigo_carrera entry_codigo_unico, force
    save `entrants', replace

    * Presencia en t+1 en el mismo codigo_unico
    use `raw_stock', clear
    replace ao_proceso = ao_proceso - 1
    rename ao_proceso entry_year
    rename codigo_unico_str entry_codigo_unico
    gen byte retained_y2 = 1
    keep mrun entry_year entry_codigo_unico retained_y2
    duplicates drop mrun entry_year entry_codigo_unico, force
    save `retained_flags', replace

    use `entrants', clear
    merge m:1 mrun entry_year entry_codigo_unico using `retained_flags', ///
        keep(master match) nogen

    replace retained_y2 = 0 if missing(retained_y2)

    collapse ///
        (mean) retention_y2_rate = retained_y2 ///
        (count) n_retention_y2_base = retained_y2, ///
        by(entry_year entry_codigo_carrera)

    rename entry_year ao_proceso
    rename entry_codigo_carrera codigo_carrera

    label variable retention_y2_rate ///
        "Second-year retention rate in same raw program, assigned to DEMRE code"

    save `retention_lookup', replace
}


/**********************************************************************
* 4. Graduación target 8y desde matrícula + titulados raw
**********************************************************************/

tempfile graduation_lookup
local have_graduation_lookup 0

if `have_enroll_long' == 1 & "`tit_raw'" != "" {

    di as text "=================================================="
    di as result "Construyendo graduación 8y desde titulados raw: `tit_raw'"
    di as text "=================================================="

    * Entrantes: cohorte programa-año desde matrícula
    use `enroll_long', clear
    keep if inrange(ao_proceso, `study_start', `study_end')
    keep mrun_str ao_proceso codigo_carrera codigo_carrera_h codigo_unico_str entry_year
    drop if mrun_str == "" | mrun_str == "."
    drop if missing(ao_proceso, codigo_carrera)
    drop if codigo_unico_str == ""
    drop if entry_year != ao_proceso
    rename ao_proceso entry_year_check
    rename entry_year cohort_year
    drop entry_year_check
    rename cohort_year ao_proceso
    rename codigo_unico_str entry_codigo_unico
    duplicates drop mrun_str ao_proceso codigo_carrera codigo_carrera_h entry_codigo_unico, force

    tempfile entrants_grad
    save `entrants_grad', replace

    * Titulados
    tempfile all_tit
    local first_tit 1
    local max_tit_year = .

    forvalues y = `study_start'/`tit_end' {

        local files : dir "`tit_raw'" files "*titulados*`y'_web.csv"

        if `"`files'"' == "" {
            local files : dir "`tit_raw'" files "*`y'_web.csv"
        }

        if `"`files'"' == "" {
            continue
        }

        local file ""
        foreach f of local files {
            local fl = lower("`f'")
            if regexm("`fl'", "\.csv$") {
                local file "`f'"
                continue, break
            }
        }

        if "`file'" == "" continue

        di as result "Titulados `y': `file'"

        import delimited "`tit_raw'/`file'", clear varnames(1) encoding(UTF-8) bindquote(strict)
        rename *, lower

        capture confirm variable cat_periodo
        if _rc != 0 gen cat_periodo = `y'
        capture confirm numeric variable cat_periodo
        if _rc == 0 gen grad_year = cat_periodo
        else destring cat_periodo, gen(grad_year) force
        replace grad_year = `y' if missing(grad_year)

        quietly summarize grad_year
        if missing(`max_tit_year') local max_tit_year = r(max)
        else if r(max) > `max_tit_year' local max_tit_year = r(max)

        capture confirm variable mrun
        if _rc != 0 continue

        capture confirm numeric variable mrun
        if _rc == 0 tostring mrun, gen(mrun_str) format(%12.0f) force
        else gen str20 mrun_str = trim(mrun)

        replace mrun_str = trim(mrun_str)
        drop if mrun_str == "" | mrun_str == "."

        local entryvar ""
        foreach cand in año_ing_carr_ori ano_ing_carr_ori anio_ing_carr_ori a_o_ing_carr_ori {
            capture confirm variable `cand'
            if _rc == 0 {
                local entryvar "`cand'"
                continue, break
            }
        }

        if "`entryvar'" == "" continue

        capture confirm numeric variable `entryvar'
        if _rc == 0 gen double ao_proceso = `entryvar'
        else destring `entryvar', gen(ao_proceso) force
        replace ao_proceso = . if inlist(ao_proceso, 9995, 9998, 9999, 1900)

        capture confirm variable codigo_unico
        if _rc != 0 continue

        capture confirm numeric variable codigo_unico
        if _rc == 0 tostring codigo_unico, gen(entry_codigo_unico) format(%30.0f) force
        else gen str40 entry_codigo_unico = trim(codigo_unico)

        replace entry_codigo_unico = trim(entry_codigo_unico)
        replace entry_codigo_unico = "" if entry_codigo_unico == "."

        keep mrun_str ao_proceso entry_codigo_unico grad_year
        drop if missing(ao_proceso, grad_year)
        drop if entry_codigo_unico == ""

        keep if grad_year <= ao_proceso + `grad_window'

        gen byte graduated_target_8y = 1
        keep mrun_str ao_proceso entry_codigo_unico graduated_target_8y
        duplicates drop

        if `first_tit' == 1 {
            save `all_tit', replace
            local first_tit 0
        }
        else {
            append using `all_tit'
            duplicates drop
            save `all_tit', replace
        }
    }

    if `first_tit' == 0 {
        use `entrants_grad', clear

        * Mantener solo cohortes con ventana completa si se detectó último año de titulados
        if !missing(`max_tit_year') {
            keep if ao_proceso + `grad_window' <= `max_tit_year'
        }

        merge m:1 mrun_str ao_proceso entry_codigo_unico using `all_tit', ///
            keep(master match) nogen

        replace graduated_target_8y = 0 if missing(graduated_target_8y)

        collapse ///
            (mean) graduation_rate_target_8y = graduated_target_8y ///
            (count) n_graduation_8y_base = graduated_target_8y, ///
            by(ao_proceso codigo_carrera_h)

        label variable graduation_rate_target_8y "Target-program graduation rate within 8 years"
        save `graduation_lookup', replace
        local have_graduation_lookup 1
    }
}


if `have_graduation_lookup' == 0 {
    * Fallback: usar output existente si existe.
    capture confirm file "$processed/analysis_sample_with_fields_graduation_8y.dta"
    if _rc == 0 {
        di as error "No se pudo construir graduación raw. Usando fallback desde analysis_sample_with_fields_graduation_8y.dta."
        use "$processed/analysis_sample_with_fields_graduation_8y.dta", clear
        keep if inrange(ao_proceso, `study_start', `study_end')

        capture confirm variable t_codigo_carrera
        if _rc != 0 {
            capture confirm variable codigo_carrera
            if _rc == 0 rename codigo_carrera t_codigo_carrera
        }

        make_program_code_h, codevar(t_codigo_carrera) yearvar(ao_proceso) newvar(codigo_carrera_h)

        capture confirm variable graduates_target_8y
        if _rc == 0 {
            collapse ///
                (mean) graduation_rate_target_8y = graduates_target_8y ///
                (count) n_graduation_8y_base = graduates_target_8y, ///
                by(ao_proceso codigo_carrera_h)
            save `graduation_lookup', replace
            local have_graduation_lookup 1
        }
    }
}


/**********************************************************************
* 5. Unir todos los atributos en un lookup único
**********************************************************************/

di as text "=================================================="
di as result "Uniendo atributos en lookup único"
di as text "=================================================="

use `master_attrs', clear

if `have_enroll_long' == 1 {
    merge 1:1 ao_proceso codigo_carrera using `enrollment_attrs', keep(master match) nogen
    merge 1:1 ao_proceso codigo_carrera using `retention_lookup', keep(master match) nogen
}

if `have_graduation_lookup' == 1 {
    merge 1:1 ao_proceso codigo_carrera_h using `graduation_lookup', keep(master match) nogen
}

order ao_proceso codigo_carrera codigo_carrera_h ///
      selectivity_program_year p50_selectivity_program_year ///
      retention_y2_rate female_share_enrolled graduation_rate_target_8y ///
      cutoff_regular program_size is_university tuition

compress

save "`output'", replace


/**********************************************************************
* 6. Diagnóstico
**********************************************************************/

di as text "=================================================="
di as result "Diagnóstico final: program_year_attributes_nextbest"
di as text "=================================================="

count
tab ao_proceso, missing

foreach v in selectivity_program_year p50_selectivity_program_year ///
             retention_y2_rate female_share_enrolled graduation_rate_target_8y ///
             cutoff_regular program_size is_university tuition {
    capture confirm variable `v'
    if _rc == 0 {
        di as text "--------------------------------------------------"
        di as result "`v'"
        count if missing(`v')
        summarize `v', detail
    }
}

di as text "--------------------------------------------------"
di as result "Período de estudio usado: `study_start'-`study_end'"
di as result "Matrícula leída hasta: `enrollment_end_for_retention' (por retención t+1)"
di as result "Titulados leídos hasta: `tit_end'"
di as result "Última cohorte con graduación 8y completa: `= `tit_end' - `grad_window''"
di as result "Lookup guardado en: `output'"


use "$processed/program_year_attributes_nextbest.dta", clear

************************************************************
* Limpiar aranceles sospechosamente bajos
************************************************************

replace tuition = . if tuition < 500000
replace tuition_mean = . if tuition_mean < 500000

************************************************************
* Opcional: dejar is_university como chequeo, pero no usar como delta
************************************************************

save "$processed/program_year_attributes_nextbest.dta", replace



/**********************************************************************
* 7. Verificación para uso en 09 / next-best all-targets
**********************************************************************/

use "$processed/program_year_attributes_nextbest.dta", clear

di as text "=================================================="
di as result "Verificación final para next-best attributes"
di as text "=================================================="

foreach v in ///
    ao_proceso ///
    codigo_carrera ///
    codigo_carrera_h ///
    selectivity_program_year ///
    p50_selectivity_program_year ///
    graduation_rate_target_8y ///
    cutoff_regular ///
    program_size {

    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable necesaria para 09: `v'"
        exit 111
    }
    else {
        di as result "OK: `v'"
    }
}

duplicates report ao_proceso codigo_carrera

count
di as result "Total program-years in attributes lookup: " r(N)

summarize selectivity_program_year graduation_rate_target_8y ///
          cutoff_regular program_size, detail

di as text "=================================================="
di as result "08 terminado correctamente"
di as result "Output:"
di as result "$processed/program_year_attributes_nextbest.dta"
di as text "=================================================="n

