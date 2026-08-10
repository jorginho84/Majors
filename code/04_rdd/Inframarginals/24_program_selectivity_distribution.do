/**********************************************************************
* 24_program_selectivity_distribution.do
*
* Objetivo:
*   Construir una medida de selectividad a nivel programa y estudiar
*   su distribución antes de definir cuatro grupos de selectividad.
*
* Definición principal:
*   Selectividad del programa =
*   PSU promedio Lenguaje-Matemática de los estudiantes que
*   efectivamente se matricularon en ese programa durante 2007--2016.
*
* Outputs:
*   1. $processed/program_selectivity_2007_2016.dta
*   2. $processed/program_selectivity_2007_2016.csv
*   3. Histogramas y gráficos en $output/figures
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local master_base ///
    "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta"

local output_dta ///
    "$processed/program_selectivity_2007_2016.dta"

local output_csv ///
    "$processed/program_selectivity_2007_2016.csv"

local outdir "$output/figures"

capture mkdir "`outdir'"

**********************************************************************
* 0. Verificar base
**********************************************************************/

capture confirm file "`master_base'"

if _rc != 0 {
    di as error "No existe la base requerida:"
    di as error "`master_base'"
    exit 601
}

**********************************************************************
* 1. Abrir base individual
**********************************************************************/

use "`master_base'", clear

keep if inrange(ao_proceso, 2007, 2016)

foreach v in ///
    mrun ///
    ao_proceso ///
    sigla_universidad ///
    codigo_carrera_harmonized ///
    enrolls_target ///
    lyc_actual ///
    mate_actual {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable en master_base: `v'"
        exit 111
    }
}

**********************************************************************
* 2. Mantener matrícula efectiva en el programa target
**********************************************************************/

keep if enrolls_target == 1

di as result "Observaciones matriculadas en target: " _N

**********************************************************************
* 3. Construir PSU Lenguaje-Matemática individual
**********************************************************************/

capture drop psu_lm

capture confirm variable promlm_actual

if _rc == 0 {

    * No modificar la variable original.
    capture drop promlm_num

    destring promlm_actual, gen(promlm_num) force

    gen double psu_lm = promlm_num

    * Fallback si promlm_actual no pudo convertirse.
    replace psu_lm = (lyc_actual + mate_actual) / 2 ///
        if missing(psu_lm) ///
        & !missing(lyc_actual, mate_actual)

    drop promlm_num
}
else {

    gen double psu_lm = (lyc_actual + mate_actual) / 2 ///
        if !missing(lyc_actual, mate_actual)
}

count if missing(psu_lm)

di as result "Observaciones sin PSU L-M: " r(N)

drop if missing(psu_lm)

**********************************************************************
* 4. Normalizar identificadores
**********************************************************************/

replace sigla_universidad = upper(strtrim(sigla_universidad))

capture confirm numeric variable codigo_carrera_harmonized

if _rc != 0 {
    destring codigo_carrera_harmonized, replace force
}

capture confirm variable program_id_rank_analysis

if _rc != 0 {
    egen program_id_rank_analysis = ///
        group(sigla_universidad codigo_carrera_harmonized)
}

**********************************************************************
* 5. Evitar duplicar estudiantes dentro de programa-año
**********************************************************************/

egen tag_student_program_year = tag( ///
    mrun ///
    program_id_rank_analysis ///
    ao_proceso ///
)

keep if tag_student_program_year == 1

drop tag_student_program_year

**********************************************************************
* 6. Estadísticas programa-año
**********************************************************************/

collapse ///
    (mean) mean_psu_program_year = psu_lm ///
    (sd)   sd_psu_program_year   = psu_lm ///
    (count) enrolled_students_year = psu_lm, ///
    by( ///
        program_id_rank_analysis ///
        sigla_universidad ///
        codigo_carrera_harmonized ///
        ao_proceso ///
    )

label var mean_psu_program_year ///
    "Mean Language-Math PSU among target enrollees, program-year"

label var enrolled_students_year ///
    "Number of target enrollees with observed PSU, program-year"

tempfile program_year_selectivity

save `program_year_selectivity', replace

**********************************************************************
* 7. Construir dos medidas de selectividad por programa
*
* A. Pooled:
*    promedio ponderado por número de matriculados de cada año.
*
* B. Equal-year:
*    promedio simple entre años; cada cohorte pesa lo mismo.
**********************************************************************/

gen double weighted_psu = ///
    mean_psu_program_year * enrolled_students_year

collapse ///
    (sum) total_weighted_psu = weighted_psu ///
          total_enrolled_psu = enrolled_students_year ///
    (mean) mean_psu_equal_year = mean_psu_program_year ///
    (sd)   sd_mean_psu_across_years = mean_psu_program_year ///
    (count) years_observed = ao_proceso ///
    (min) first_year_observed = ao_proceso ///
    (max) last_year_observed  = ao_proceso, ///
    by( ///
        program_id_rank_analysis ///
        sigla_universidad ///
        codigo_carrera_harmonized ///
    )

gen double mean_psu_program = ///
    total_weighted_psu / total_enrolled_psu

label var mean_psu_program ///
    "Pooled mean PSU L-M among target enrollees, 2007-2016"

label var mean_psu_equal_year ///
    "Mean program-year PSU, equal weight by year"

label var years_observed ///
    "Number of program-years observed"

label var total_enrolled_psu ///
    "Target enrollees with observed PSU, 2007-2016"

**********************************************************************
* 8. Diagnósticos principales
**********************************************************************/

di as text "=================================================="
di as result "PROGRAM SELECTIVITY DISTRIBUTION"
di as text "=================================================="

count

di as result "Programs: " r(N)

summarize mean_psu_program, detail

di as text "--------------------------------------------------"
di as result "Key percentiles"
di as text "--------------------------------------------------"

di as result "P1  = " %8.2f r(p1)
di as result "P5  = " %8.2f r(p5)
di as result "P10 = " %8.2f r(p10)
di as result "P25 = " %8.2f r(p25)
di as result "P50 = " %8.2f r(p50)
di as result "P75 = " %8.2f r(p75)
di as result "P90 = " %8.2f r(p90)
di as result "P95 = " %8.2f r(p95)
di as result "P99 = " %8.2f r(p99)

**********************************************************************
* 9. Tabla por rangos preliminares de PSU
*
* Estos cortes son solamente descriptivos.
* No son todavía los grupos definitivos.
**********************************************************************/

gen byte psu_range_preliminary = .

replace psu_range_preliminary = 1 ///
    if mean_psu_program < 550

replace psu_range_preliminary = 2 ///
    if inrange(mean_psu_program, 550, 599.999)

replace psu_range_preliminary = 3 ///
    if inrange(mean_psu_program, 600, 649.999)

replace psu_range_preliminary = 4 ///
    if mean_psu_program >= 650 ///
    & !missing(mean_psu_program)

label define psu_range_lbl ///
    1 "<550" ///
    2 "550--599" ///
    3 "600--649" ///
    4 "650+"

label values psu_range_preliminary psu_range_lbl

tab psu_range_preliminary, missing

tabstat ///
    mean_psu_program ///
    total_enrolled_psu ///
    years_observed, ///
    by(psu_range_preliminary) ///
    statistics(n mean p25 p50 p75 min max) ///
    columns(statistics)

**********************************************************************
* 10. Cuartiles, sólo como referencia
**********************************************************************/

xtile selectivity_quartile = mean_psu_program, nq(4)

label define selectivity_q_lbl ///
    1 "Q1: lowest selectivity" ///
    2 "Q2" ///
    3 "Q3" ///
    4 "Q4: highest selectivity"

label values selectivity_quartile selectivity_q_lbl

tab selectivity_quartile

tabstat mean_psu_program, ///
    by(selectivity_quartile) ///
    statistics(n min p25 p50 p75 max mean) ///
    columns(statistics)

**********************************************************************
* 11. Comparar pooled vs equal-year
**********************************************************************/

pwcorr mean_psu_program mean_psu_equal_year, sig

gen double difference_pooled_equalyear = ///
    mean_psu_program - mean_psu_equal_year

summarize difference_pooled_equalyear, detail

**********************************************************************
* 12. Histogramas
**********************************************************************/

histogram mean_psu_program, ///
    width(10) ///
    frequency ///
    xline(550 600 650, lpattern(dash)) ///
    xtitle("Mean PSU Language-Mathematics") ///
    ytitle("Number of programs") ///
    title("Distribution of Program Selectivity") ///
    subtitle("Target-program enrollees, 2007--2016") ///
    note("Dashed lines show preliminary cutoffs at 550, 600, and 650.") ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(hist_program_selectivity, replace)

graph export ///
    "`outdir'/hist_program_selectivity.pdf", ///
    replace

graph export ///
    "`outdir'/hist_program_selectivity.png", ///
    replace width(2400)

**********************************************************************
* 13. Histograma con cuartiles reales
**********************************************************************/

summarize mean_psu_program, detail

local p25 = r(p25)
local p50 = r(p50)
local p75 = r(p75)

histogram mean_psu_program, ///
    width(10) ///
    frequency ///
    xline(`p25' `p50' `p75', lpattern(dash)) ///
    xtitle("Mean PSU Language-Mathematics") ///
    ytitle("Number of programs") ///
    title("Distribution of Program Selectivity") ///
    subtitle("Dashed lines indicate empirical quartiles") ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(hist_program_selectivity_qtls, replace)

graph export ///
    "`outdir'/hist_program_selectivity_qtls.pdf", ///
    replace

graph export ///
    "`outdir'/hist_program_selectivity_qtls.png", ///
    replace width(2400)

**********************************************************************
* 14. Guardar base de selectividad por programa
**********************************************************************/

order ///
    program_id_rank_analysis ///
    sigla_universidad ///
    codigo_carrera_harmonized ///
    mean_psu_program ///
    mean_psu_equal_year ///
    total_enrolled_psu ///
    years_observed ///
    first_year_observed ///
    last_year_observed ///
    psu_range_preliminary ///
    selectivity_quartile

sort mean_psu_program

compress

save "`output_dta'", replace

export delimited using "`output_csv'", replace

di as text "=================================================="
di as result "Finished program selectivity distribution."
di as result "Base: `output_dta'"
di as result "CSV:  `output_csv'"
di as result "Figures: `outdir'"
di as text "=================================================="