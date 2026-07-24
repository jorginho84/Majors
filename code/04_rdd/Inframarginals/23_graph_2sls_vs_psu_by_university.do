/**********************************************************************
* 23_graph_2sls_vs_psu_by_university.do
*
* Objetivo:
*   Graficar las estimaciones 2SLS por universidad contra la PSU media
*   de los estudiantes matriculados en su programa target.
*
* Definiciones:
*   1. First Cohort
*   2. 80% First Cohort
*   3. Minimum Cohort
*   4. 80% Minimum Cohort
*
* Importante:
*   - Los cuatro gráficos usan la misma escala vertical.
*   - La escala vertical es simétrica alrededor de cero.
*   - Se excluyen universidades con F-stat de primera etapa < 10.
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local het_results ///
    "$processed/university_heterogeneity_enrollmentthreshold_allapp_results.dta"

local master_base ///
    "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta"

local outdir "$output/figures"

capture mkdir "$output/figures"

**********************************************************************
* 0. Verificar archivos
**********************************************************************

foreach f in "`het_results'" "`master_base'" {

    capture confirm file "`f'"

    if _rc != 0 {
        di as error "No existe el archivo requerido:"
        di as error "`f'"
        exit 601
    }
}

**********************************************************************
* 1. Construir PSU promedio por universidad
*
* Selectividad:
*   promedio PSU Lenguaje-Matemática de quienes efectivamente se
*   matricularon en el programa target.
**********************************************************************

use "`master_base'", clear

keep if inrange(ao_proceso, 2007, 2016)
keep if enrolls_target == 1

foreach v in sigla_universidad lyc_actual mate_actual {
    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable en master_base: `v'"
        exit 111
    }
}

capture confirm variable promlm_actual

if _rc != 0 {
    gen mean_psu_student = (lyc_actual + mate_actual) / 2 ///
        if !missing(lyc_actual, mate_actual)
}
else {

    * Crear copia numérica sin destruir la variable original.
    capture drop promlm_num
    destring promlm_actual, gen(promlm_num) force

    gen mean_psu_student = promlm_num

    * Recuperar observaciones no convertibles usando L y M directamente.
    replace mean_psu_student = (lyc_actual + mate_actual) / 2 ///
        if missing(mean_psu_student) ///
        & !missing(lyc_actual, mate_actual)

    drop promlm_num
}

drop if missing(mean_psu_student)

replace sigla_universidad = upper(strtrim(sigla_universidad))

collapse (mean) mean_psu = mean_psu_student, ///
    by(sigla_universidad)

rename sigla_universidad university

isid university

tempfile psu_uni
save `psu_uni', replace

di as text "=================================================="
di as result "PSU promedio por universidad"
di as text "=================================================="

format mean_psu %9.1f
list university mean_psu, noobs clean

**********************************************************************
* 2. Abrir resultados 2SLS y agregar PSU promedio
**********************************************************************

use "`het_results'", clear

foreach v in university definition iv_coef iv_se fs_F {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable en resultados de heterogeneidad: `v'"
        exit 111
    }
}

replace university = upper(strtrim(university))

merge m:1 university using `psu_uni', keep(master match)

tab _merge, missing

count if _merge == 1
di as result "Resultados sin PSU promedio: " r(N)

keep if _merge == 3
drop _merge

**********************************************************************
* 3. Mantener cuatro definiciones principales
**********************************************************************

keep if inlist(definition, ///
    "first_enroll", ///
    "first_enroll80", ///
    "min_enroll", ///
    "min_enroll80")

count

if r(N) == 0 {
    di as error "No quedaron observaciones para las cuatro definiciones."
    exit 2000
}

**********************************************************************
* 4. Restringir a primeras etapas suficientemente fuertes
*
* Esto evita que universidades con instrumentos prácticamente nulos
* generen coeficientes IV extremos y hagan ilegible la escala.
**********************************************************************

local min_first_stage_F = 10

count if fs_F < `min_first_stage_F'
di as result ///
    "Observaciones excluidas por F-stat < `min_first_stage_F': " r(N)

keep if fs_F >= `min_first_stage_F'

**********************************************************************
* 5. Etiquetas de las definiciones
**********************************************************************

gen definition_order = .

replace definition_order = 1 if definition == "first_enroll"
replace definition_order = 2 if definition == "first_enroll80"
replace definition_order = 3 if definition == "min_enroll"
replace definition_order = 4 if definition == "min_enroll80"

gen definition_title = ""

replace definition_title = "First Cohort" ///
    if definition == "first_enroll"

replace definition_title = "80% First Cohort" ///
    if definition == "first_enroll80"

replace definition_title = "Minimum Cohort" ///
    if definition == "min_enroll"

replace definition_title = "80% Minimum Cohort" ///
    if definition == "min_enroll80"

sort definition_order university

**********************************************************************
* 6. Construir escala Y común y simétrica
**********************************************************************

summarize iv_coef, meanonly

local raw_limit = max(abs(r(min)), abs(r(max)))

* Agregar 10% de margen y redondear hacia arriba a la milésima.
local ylimit = ceil(1000 * 1.10 * `raw_limit') / 1000

* Evitar una escala demasiado estrecha si los coeficientes fueran mínimos.
if `ylimit' < 0.005 {
    local ylimit = 0.005
}

local ystep = `ylimit' / 4

di as text "=================================================="
di as result "Escala vertical común"
di as result "Límite inferior: -" %7.4f `ylimit'
di as result "Límite superior:  " %7.4f `ylimit'
di as text "=================================================="

**********************************************************************
* 7. Crear los cuatro gráficos
**********************************************************************

foreach d in first_enroll first_enroll80 min_enroll min_enroll80 {

    preserve

        keep if definition == "`d'"

        count

        if r(N) == 0 {
            di as error "No hay observaciones para `d'."
            restore
            continue
        }

        local graph_title ""

        if "`d'" == "first_enroll" {
            local graph_title "First Cohort"
        }

        if "`d'" == "first_enroll80" {
            local graph_title "80% First Cohort"
        }

        if "`d'" == "min_enroll" {
            local graph_title "Minimum Cohort"
        }

        if "`d'" == "min_enroll80" {
            local graph_title "80% Minimum Cohort"
        }

		count
		local n_universities = r(N)

		twoway ///
			(scatter iv_coef mean_psu, ///
				mlabel(university) ///
				mlabsize(vsmall) ///
				mlabposition(0) ///
				msymbol(circle) ///
				msize(small)) ///
			(lfit iv_coef mean_psu), ///
			title("`graph_title'", size(medsmall)) ///
			subtitle("First-stage F-stat ≥ `min_first_stage_F'; N = `n_universities' universities", ///
				size(vsmall)) ///
			xtitle("Mean PSU of target-program enrollees", size(small)) ///
			ytitle("2SLS estimate", size(small)) ///
			yline(0, lpattern(dash)) ///
			yscale(range(-`ylimit' `ylimit')) ///
			ylabel(-`ylimit'(`ystep')`ylimit', ///
				format(%6.3f) ///
				labsize(vsmall)) ///
			xlabel(, labsize(vsmall)) ///
			legend(off) ///
			graphregion(color(white)) ///
			plotregion(color(white)) ///
			name(g_`d', replace)

        graph save ///
            "`outdir'/scatter_2sls_psu_`d'.gph", ///
            replace

        graph export ///
            "`outdir'/scatter_2sls_psu_`d'.pdf", ///
            replace

        graph export ///
            "`outdir'/scatter_2sls_psu_`d'.png", ///
            replace width(2400)

    restore
}

**********************************************************************
* 8. Combinar los cuatro gráficos
**********************************************************************

graph combine ///
    g_first_enroll ///
    g_first_enroll80 ///
    g_min_enroll ///
    g_min_enroll80, ///
    cols(2) ///
    xcommon ///
    ycommon ///
    title("2SLS estimates and university selectivity", size(medsmall)) ///
    subtitle("Outcome: graduation from initially enrolled program within 8 years", ///
        size(vsmall)) ///
    note("Each point represents one university. The line reports the linear fit. " ///
         "All panels use the same symmetric vertical scale.", ///
         size(tiny)) ///
    graphregion(color(white)) ///
    name(g_four_definitions, replace)

graph save ///
    "`outdir'/scatter_2sls_psu_four_definitions.gph", ///
    replace

graph export ///
    "`outdir'/scatter_2sls_psu_four_definitions.pdf", ///
    replace

graph export ///
    "`outdir'/scatter_2sls_psu_four_definitions.png", ///
    replace width(3200)

**********************************************************************
* 9. Guardar base utilizada en los gráficos
**********************************************************************

sort definition_order mean_psu

save ///
    "$processed/scatter_2sls_psu_four_definitions_data.dta", ///
    replace

export delimited using ///
    "$processed/scatter_2sls_psu_four_definitions_data.csv", ///
    replace

di as text "=================================================="
di as result "Gráficos terminados."
di as result "Carpeta: `outdir'"
di as result ///
    "Figura combinada: scatter_2sls_psu_four_definitions.pdf"
di as result ///
    "Base usada: $processed/scatter_2sls_psu_four_definitions_data.dta"
di as text "=================================================="