

/**********************************************************************
* 1. Construir composición región × PSU de incumbentes y entrantes
*
* Año: 2011
* Universo:
*   - 25 universidades incumbentes SUA
*   - 8 universidades que ingresaron al SUA en 2012
*
* Unidad individual:
*   estudiante × programa SIES
*
* Primer año:
*   año de ingreso a carrera de origen == 2011
**********************************************************************/
/**********************************************************************
* 01_build_cosine_exposure_2011.do
**********************************************************************/


do "code/config.do"

import delimited ///
    "$mat_raw/Matrícula_Ed_Superior_2011.csv", ///
    clear ///
    varnames(1) ///
    encoding("UTF-8") ///
    bindquote(strict)

rename *, lower

/**********************************************************************
* 3.1 Mantener universidades de pregrado
**********************************************************************/

keep if tipo_inst_1 == "Universidades"
keep if nivel_global == "Pregrado"

/**********************************************************************
* 3.2 Identificar matriculados de primer año
*
* Seguimos la definición utilizada en el ejercicio anterior:
* año de ingreso a carrera de origen == año observado.
**********************************************************************/

keep if anio_ing_carr_ori == 2011

/*
No imponemos sem_ing_carr_act == 1.
La definición anterior se basó en el año de ingreso a la carrera
de origen y no en el semestre.
*/

drop if missing(mrun)
drop if missing(codigo_unico)

/**********************************************************************
* 3.3 Estandarizar código institucional
**********************************************************************/

capture confirm numeric variable cod_inst

if !_rc {

    tostring cod_inst, ///
        replace ///
        format(%20.0f) ///
        force
}

replace cod_inst = ///
    itrim(ustrtrim(cod_inst))

/**********************************************************************
* 3.4 Incorporar roster de incumbentes y entrantes
**********************************************************************/

merge m:1 ///
    cod_inst ///
    using "$processed/sua_university_roster_manual.dta", ///
    keep(master match) ///
    generate(_merge_roster)

tabulate _merge_roster

/*
Conservar únicamente las 33 universidades del ejercicio.
*/

keep if _merge_roster == 3
drop _merge_roster

/**********************************************************************
* 3.5 Validar grupos institucionales
**********************************************************************/

egen byte tag_university = tag(cod_inst)

count if tag_university == 1

di as result ///
    "Universidades encontradas en matrícula 2011: " r(N)

tabulate entrant_2012 ///
    if tag_university == 1, ///
    missing

list ///
    sigla_universidad ///
    cod_inst ///
    entrant_2012 ///
    nomb_inst_roster ///
    if tag_university == 1, ///
    noobs clean

/**********************************************************************
* 3.6 Mantener programas regulares
**********************************************************************/

tabulate tipo_plan_carr, missing

gen byte plan_regular = ///
    ustrupper(itrim(ustrtrim(tipo_plan_carr))) == "PLAN REGULAR"

tabulate plan_regular, missing

keep if plan_regular == 1

drop tag_university

/**********************************************************************
* 3.6.1 Mantener únicamente jornada diurna
**********************************************************************/

tabulate jornada, missing

gen str30 jornada_clean = ///
    ustrupper(itrim(ustrtrim(jornada)))

tabulate jornada_clean, missing

keep if jornada_clean == "DIURNO"

assert jornada_clean == "DIURNO"

drop jornada_clean
	
/**********************************************************************
* 3.7 Dejar una observación por estudiante-programa
**********************************************************************/

duplicates report ///
    mrun ///
    codigo_unico

egen byte tag_student_program = tag( ///
    mrun ///
    codigo_unico ///
)

keep if tag_student_program == 1

drop tag_student_program

isid ///
    mrun ///
    codigo_unico
	
/**********************************************************************
* 3.8 Incorporar región del establecimiento y tramo PSU
**********************************************************************/

merge m:1 ///
    mrun ///
    using "$processed/psu2011_student_geo_psu_cells.dta", ///
    keep(master match) ///
    generate(_merge_geo_psu)

tabulate _merge_geo_psu

gen byte has_geo_psu = ///
    _merge_geo_psu == 3

	
/**********************************************************************
* 3.9 Guardar tamaño TOTAL de primer año por programa
*
* El denominador de los pesos debe incluir TODOS los programas
* de las 8 universidades entrantes, incluso aquellos sin vector
* región × PSU observable.
**********************************************************************/

preserve

    collapse ///
        (count) N_firstyear_total = mrun, ///
        by( ///
            codigo_unico ///
            cod_inst ///
            sigla_universidad ///
            nomb_inst_roster ///
            entrant_2012 ///
            sua_incumbent ///
            nomb_inst ///
            nomb_sede ///
            nomb_carrera ///
            cod_sede ///
            cod_carrera ///
            modalidad ///
            jornada ///
            version ///
        )

    isid codigo_unico

    tempfile program_totals_2011
    save `program_totals_2011', replace

    save ///
        "$processed/program_totals_firstyear_2011_all.dta", ///
        replace

restore


/**********************************************************************
* 3.10 Calcular cobertura observada por programa
**********************************************************************/

capture confirm variable has_geo_psu

if _rc {
    gen byte has_geo_psu = ///
        _merge_geo_psu == 3
}

bysort codigo_unico: ///
    egen long N_firstyear_geo_psu = total(has_geo_psu)

bysort codigo_unico: ///
    gen long N_firstyear_total_check = _N

gen double program_geo_psu_coverage = ///
    N_firstyear_geo_psu / N_firstyear_total_check

assert inrange(program_geo_psu_coverage, 0, 1)

/**********************************************************************
* 3.11 Mantener estudiantes con región y PSU
**********************************************************************/

keep if has_geo_psu == 1

drop ///
    _merge_geo_psu ///
    has_geo_psu ///
    N_firstyear_total_check

	
/**********************************************************************
* 4. Construir vector región × PSU de cada programa
**********************************************************************/

gen long one_student = 1

collapse ///
    (sum) N_cell = one_student ///
    (firstnm) ///
        N_firstyear_geo_psu ///
        program_geo_psu_coverage, ///
    by( ///
        codigo_unico ///
        cod_inst ///
        sigla_universidad ///
        nomb_inst_roster ///
        entrant_2012 ///
        sua_incumbent ///
        geo_psu_cell ///
        codigo_region ///
        psu_bin_lower ///
        psu_bin_upper ///
    )

isid codigo_unico geo_psu_cell


merge m:1 ///
    codigo_unico ///
    using `program_totals_2011', ///
    generate(_merge_totals)

/*
Todo programa que tiene vector debe encontrar su total.
Sí se permiten programas que aparezcan solo en el archivo de totales,
porque pueden tener cero estudiantes con región y PSU observadas.
*/

assert _merge_totals != 1

count if _merge_totals == 2

di as result ///
    "Programas sin vector observable región × PSU: " ///
    %9.0fc r(N)

/*
Guardar programas con matrícula de primer año,
pero sin ningún estudiante con región y PSU observable.
*/

preserve

    keep if _merge_totals == 2

    save ///
        "$processed/programs_without_geo_psu_vector_2011.dta", ///
        replace

restore

/*
Continuar únicamente con programas que sí tienen vector observable.
*/

keep if _merge_totals == 3
drop _merge_totals

assert ///
    N_firstyear_geo_psu <= ///
    N_firstyear_total

gen double coverage_check = ///
    N_firstyear_geo_psu / N_firstyear_total

assert abs( ///
    coverage_check - program_geo_psu_coverage ///
) < 1e-10

drop coverage_check

label variable N_cell ///
    "First-year students in region × PSU cell, 2011"

label variable N_firstyear_total ///
    "Total first-year enrollment in program, 2011"

label variable N_firstyear_geo_psu ///
    "First-year enrollment with observed region and PSU"

label variable program_geo_psu_coverage ///
    "Share of first-year enrollment with observed region and PSU"
	
	
sort ///
    entrant_2012 ///
    codigo_unico ///
    geo_psu_cell

compress

save ///
    "$processed/program_geo_psu_vectors_2011.dta", ///
    replace

/**********************************************************************
* 5. Diagnóstico de los vectores por programa
**********************************************************************/

preserve

    collapse ///
        (firstnm) ///
            N_firstyear_total ///
            N_firstyear_geo_psu ///
            program_geo_psu_coverage ///
        (count) n_nonzero_cells = geo_psu_cell, ///
        by( ///
            codigo_unico ///
            cod_inst ///
            sigla_universidad ///
            nomb_inst_roster ///
            entrant_2012 ///
            sua_incumbent ///
        )

    gen byte vector_n10 = ///
        N_firstyear_geo_psu >= 10

    gen byte vector_n20 = ///
        N_firstyear_geo_psu >= 20

    gen byte coverage_50 = ///
        program_geo_psu_coverage >= 0.50

    gen byte coverage_75 = ///
        program_geo_psu_coverage >= 0.75

    tabulate entrant_2012 vector_n10, row
    tabulate entrant_2012 vector_n20, row
    tabulate entrant_2012 coverage_50, row
    tabulate entrant_2012 coverage_75, row

    summarize ///
        N_firstyear_total ///
        N_firstyear_geo_psu ///
        program_geo_psu_coverage ///
        n_nonzero_cells, ///
        detail

    sort ///
        entrant_2012 ///
        sigla_universidad ///
        codigo_unico

    list ///
        sigla_universidad ///
        codigo_unico ///
        entrant_2012 ///
        N_firstyear_total ///
        N_firstyear_geo_psu ///
        program_geo_psu_coverage ///
        n_nonzero_cells ///
        if entrant_2012 == 1, ///
        sepby(sigla_universidad) ///
        abbreviate(20)

    save ///
        "$processed/program_geo_psu_vector_diagnostics_2011.dta", ///
        replace

restore

/**********************************************************************
* 6. Calcular similitud coseno entre programas
**********************************************************************/

use ///
    "$processed/program_geo_psu_vectors_2011.dta", ///
    clear

/**********************************************************************
* 6.1 Identificador interno y norma de cada vector
**********************************************************************/

egen long program_id_cosine = group(codigo_unico)

isid program_id_cosine geo_psu_cell

gen double N_cell_sq = ///
    N_cell^2

bysort program_id_cosine: ///
    egen double vector_sum_sq = total(N_cell_sq)

gen double vector_norm = ///
    sqrt(vector_sum_sq)

assert vector_norm > 0
assert !missing(vector_norm)

/**********************************************************************
* 6.2 Guardar características únicas por programa
**********************************************************************/

preserve

    keep ///
        program_id_cosine ///
        codigo_unico ///
        cod_inst ///
        sigla_universidad ///
        nomb_inst_roster ///
        entrant_2012 ///
        sua_incumbent ///
        N_firstyear_total ///
        N_firstyear_geo_psu ///
        program_geo_psu_coverage ///
        vector_norm

    duplicates drop

    isid program_id_cosine

    save ///
        "$processed/cosine_program_characteristics_2011.dta", ///
        replace

restore

/**********************************************************************
* 6.3 Guardar vectores incumbentes
**********************************************************************/

preserve

    keep if entrant_2012 == 0

    keep ///
        program_id_cosine ///
        codigo_unico ///
        sigla_universidad ///
        geo_psu_cell ///
        N_cell ///
        vector_norm ///
        N_firstyear_total ///
        N_firstyear_geo_psu ///
        program_geo_psu_coverage

    rename ///
        (program_id_cosine codigo_unico sigla_universidad ///
         N_cell vector_norm N_firstyear_total ///
         N_firstyear_geo_psu program_geo_psu_coverage) ///
        (incumbent_id incumbent_code incumbent_university ///
         N_cell_incumbent norm_incumbent N_total_incumbent ///
         N_observed_incumbent coverage_incumbent)

    tempfile incumbent_vectors
    save `incumbent_vectors'

restore

/**********************************************************************
* 6.4 Guardar vectores entrantes
**********************************************************************/

keep if entrant_2012 == 1

keep ///
    program_id_cosine ///
    codigo_unico ///
    sigla_universidad ///
    geo_psu_cell ///
    N_cell ///
    vector_norm ///
    N_firstyear_total ///
    N_firstyear_geo_psu ///
    program_geo_psu_coverage

rename ///
    (program_id_cosine codigo_unico sigla_universidad ///
     N_cell vector_norm N_firstyear_total ///
     N_firstyear_geo_psu program_geo_psu_coverage) ///
    (entrant_id entrant_code entrant_university ///
     N_cell_entrant norm_entrant N_total_entrant ///
     N_observed_entrant coverage_entrant)

tempfile entrant_vectors
save `entrant_vectors'

/**********************************************************************
* 6.5 Producto punto entre cada incumbente y entrante
**********************************************************************/

use `incumbent_vectors', clear

joinby geo_psu_cell ///
    using `entrant_vectors'

gen double dot_component = ///
    N_cell_incumbent * N_cell_entrant

collapse ///
    (sum) dot_product = dot_component ///
    (firstnm) ///
        incumbent_code ///
        incumbent_university ///
        norm_incumbent ///
        N_total_incumbent ///
        N_observed_incumbent ///
        coverage_incumbent ///
        entrant_code ///
        entrant_university ///
        norm_entrant ///
        N_total_entrant ///
        N_observed_entrant ///
        coverage_entrant, ///
    by( ///
        incumbent_id ///
        entrant_id ///
    )

isid incumbent_id entrant_id

/**********************************************************************
* 6.6 Similitud coseno
**********************************************************************/

gen double cosine_similarity = ///
    dot_product / ///
    (norm_incumbent * norm_entrant)

assert inrange(cosine_similarity, 0, 1.0000001)

replace cosine_similarity = 1 ///
    if cosine_similarity > 1 ///
    & cosine_similarity < 1.0000001

label variable cosine_similarity ///
    "Cosine similarity: region × PSU composition"

summarize cosine_similarity, detail

save ///
    "$processed/incumbent_entrant_cosine_pairs_2011.dta", ///
    replace
	


/**********************************************************************
* 7. Construir ponderadores de programas entrantes
*
* PDF:
*
*                    N_firstyear_j,2011
* w_j = ------------------------------------------------
*       total first-year enrollment in ALL entrant
*       programs of the 8 entrant universities in 2011
**********************************************************************/

/**********************************************************************
* 7.1 Denominador: TODOS los programas entrantes
**********************************************************************/

use ///
    "$processed/program_totals_firstyear_2011_all.dta", ///
    clear

keep if entrant_2012 == 1

egen double total_entrant_enrollment_all = ///
    total(N_firstyear_total)

summarize total_entrant_enrollment_all, meanonly
local total_entrant_all = r(max)

display ///
    "Total entrant first-year enrollment, all programs = " ///
    %12.0fc `total_entrant_all'

assert `total_entrant_all' > 0


/**********************************************************************
* 7.2 Numeradores: programas entrantes con vector observable
**********************************************************************/

use ///
    "$processed/cosine_program_characteristics_2011.dta", ///
    clear

keep if entrant_2012 == 1

gen double entrant_weight = ///
    N_firstyear_total / ///
    `total_entrant_all'


/**********************************************************************
* 7.3 Cobertura de los pesos observables
**********************************************************************/

egen double observed_weight_sum = ///
    total(entrant_weight)

gen double missing_vector_weight = ///
    1 - observed_weight_sum

display ///
    "Weight represented by programs WITH vectors = " ///
    %9.4f observed_weight_sum[1]

display ///
    "Weight represented by programs WITHOUT vectors = " ///
    %9.4f missing_vector_weight[1]

assert observed_weight_sum[1] <= 1.0000001


/**********************************************************************
* 7.4 Guardar ponderadores
**********************************************************************/

keep ///
    program_id_cosine ///
    codigo_unico ///
    sigla_universidad ///
    N_firstyear_total ///
    N_firstyear_geo_psu ///
    program_geo_psu_coverage ///
    entrant_weight

rename ///
    (program_id_cosine codigo_unico sigla_universidad) ///
    (entrant_id entrant_code_check entrant_university_check)

isid entrant_id

save ///
    "$processed/cosine_entrant_weights_2011.dta", ///
    replace
	
/**********************************************************************
* 8. Exposición coseno por programa incumbente
**********************************************************************/

use ///
    "$processed/incumbent_entrant_cosine_pairs_2011.dta", ///
    clear

merge m:1 entrant_id ///
    using "$processed/cosine_entrant_weights_2011.dta", ///
    assert(match) ///
    nogen

assert entrant_code == entrant_code_check

drop ///
    entrant_code_check ///
    entrant_university_check

gen double weighted_cosine_component = ///
    entrant_weight * cosine_similarity

collapse ///
    (sum) cosine_exposure_2011 = weighted_cosine_component ///
    (count) n_positive_similarity_pairs = entrant_id ///
    (firstnm) ///
        incumbent_code ///
        incumbent_university ///
        N_total_incumbent ///
        N_observed_incumbent ///
        coverage_incumbent, ///
    by(incumbent_id)

label variable cosine_exposure_2011 ///
    "Weighted cosine exposure based on region × PSU composition"
	
/**********************************************************************
* 8.1 Incorporar todos los programas incumbentes
**********************************************************************/

tempfile exposure_positive_pairs
save `exposure_positive_pairs'

use ///
    "$processed/cosine_program_characteristics_2011.dta", ///
    clear

keep if entrant_2012 == 0

rename ///
    (program_id_cosine codigo_unico sigla_universidad ///
     N_firstyear_total N_firstyear_geo_psu ///
     program_geo_psu_coverage) ///
    (incumbent_id incumbent_code_master incumbent_university_master ///
     N_total_incumbent_master N_observed_incumbent_master ///
     coverage_incumbent_master)

merge 1:1 incumbent_id ///
    using `exposure_positive_pairs'

replace cosine_exposure_2011 = 0 ///
    if _merge == 1

replace n_positive_similarity_pairs = 0 ///
    if _merge == 1

replace incumbent_code = incumbent_code_master ///
    if missing(incumbent_code)

replace incumbent_university = incumbent_university_master ///
    if missing(incumbent_university)

replace N_total_incumbent = N_total_incumbent_master ///
    if missing(N_total_incumbent)

replace N_observed_incumbent = N_observed_incumbent_master ///
    if missing(N_observed_incumbent)

replace coverage_incumbent = coverage_incumbent_master ///
    if missing(coverage_incumbent)

drop ///
    incumbent_code_master ///
    incumbent_university_master ///
    N_total_incumbent_master ///
    N_observed_incumbent_master ///
    coverage_incumbent_master ///
    _merge

isid incumbent_id

summarize cosine_exposure_2011, detail

gsort -cosine_exposure_2011

list ///
    incumbent_university ///
    incumbent_code ///
    cosine_exposure_2011 ///
    N_total_incumbent ///
    N_observed_incumbent ///
    coverage_incumbent ///
    n_positive_similarity_pairs ///
    in 1/30, ///
    noobs clean

save ///
    "$processed/cosine_exposure_incumbents_2011.dta", ///
    replace
	

/**********************************************************************
* 9. Diagnóstico de matrícula entrante cubierta por los vectores
**********************************************************************/

use ///
    "$processed/cosine_program_characteristics_2011.dta", ///
    clear

keep if entrant_2012 == 1

summarize ///
    N_firstyear_total ///
    N_firstyear_geo_psu ///
    program_geo_psu_coverage

egen double entrant_enrollment_total = ///
    total(N_firstyear_total)

egen double entrant_enrollment_observed = ///
    total(N_firstyear_geo_psu)

gen double entrant_student_coverage = ///
    entrant_enrollment_observed / entrant_enrollment_total

summarize entrant_student_coverage

/**********************************************************************
* 9.1 Distribución de ponderadores entre universidades entrantes
**********************************************************************/

use ///
    "$processed/cosine_entrant_weights_2011.dta", ///
    clear

collapse ///
    (sum) entrant_weight ///
    (sum) entrant_enrollment = N_firstyear_total ///
    (count) n_entrant_programs = entrant_id, ///
    by(entrant_university_check)

gsort -entrant_weight

format entrant_weight %9.4f
format entrant_enrollment %12.0fc

list, noobs clean


/**********************************************************************
* 9.2 Cobertura total de matrícula entrante,
*     incluyendo programas sin vector
**********************************************************************/

use ///
    "$processed/cosine_program_characteristics_2011.dta", ///
    clear

keep if entrant_2012 == 1

collapse ///
    (sum) enroll_with_vec = N_firstyear_total ///
    (sum) students_observed = N_firstyear_geo_psu

tempfile entrant_with_vector
save `entrant_with_vector'

use ///
    "$processed/programs_without_geo_psu_vector_2011.dta", ///
    clear

tabulate entrant_2012, missing

keep if entrant_2012 == 1

count

/*
Si existen programas entrantes sin vector, sumar su matrícula.
*/

if r(N) > 0 {

    collapse ///
        (sum) enroll_without_vec = N_firstyear_total

    cross using `entrant_with_vector'
}

/*
Si no existe ninguno, recuperar la base con vector
y asignar matrícula excluida igual a cero.
*/

else {

    use `entrant_with_vector', clear

    gen double enroll_without_vec = 0
}

gen double enroll_all = ///
    enroll_with_vec + enroll_without_vec

gen double share_enroll_with_vec = ///
    enroll_with_vec / enroll_all

gen double share_students_observed = ///
    students_observed / enroll_all

format ///
    enroll_with_vec ///
    enroll_without_vec ///
    enroll_all ///
    students_observed ///
    %12.0fc

format ///
    share_enroll_with_vec ///
    share_students_observed ///
    %9.4f

list, noobs clean