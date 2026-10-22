/**********************************************************************
* 01b_build_income_rank.do
*
* Program value-added (issue #9): main outcome.
*
*   inc_rank_i = percentile (1-100) of the Mi Futuro income index of the
*                program i graduates from within 8 years, ranked among
*                the graduates of the sample; 0 if i does not graduate.
*
* Mi Futuro's unit is institution x carrera generica (the codigo_unico in
* 08_mifuturo_supply.dta is just the most recent matricula record of that
* cell, see cuposBEA/02c_mifuturo_supply_data.do), and income is the
* midpoint of a bracket (mean income in the 4th year after the title).
* The raw files "mi futuro 2010-2015.xlsx" are copies of the 2018-2023
* files, so only reference years >= 2017 are used (files 2018-2025,
* already shifted by -1 in that script).
*
* Income index of a cell: log income, demeaned by reference year
* (removes inflation and level shifts), averaged over years.
*
* Degree: first undergraduate title (titulados 2007-2024) obtained in
* [t, t+8] in a program entered in t or later (switchers count, unlike
* graduates_he_8y). Ties on the date: highest index. The title's
* codigo_unico is mapped to (cod_inst, carrera generica) with the
* area_generica field of the raw titulados files.
*
* Fallbacks when the cell has no Mi Futuro income (suppressed cells, IP
* and CFT programs): (2) national mean of the carrera generica; (3) mean
* of the institution. Shares by level are reported; graduates still
* without an index get a missing outcome.
*
* Inputs:  data/MINEDUC/Mifuturo/08_mifuturo_supply.dta
*          (copy of ~/Documents/mifuturo/data/08_mifuturo_supply.dta)
*          $processed/diagnostic_titulados_all.dta
*          $processed/pva_students_2007_2016.dta
*          $tit_raw/titulados_ed_superior_YYYY_web.csv (area_generica)
* Output:  $processed/pva_students_2007_2016.dta (adds the outcome)
*          $processed/pva_mifuturo_index.dta
**********************************************************************/

clear all
set more off
do "code/config.do"

capture log close
log using "$logs/pva_01b_build_income_rank.log", replace text

/**********************************************************************
* 1. Mi Futuro income index by institution x carrera generica
**********************************************************************/

capture program drop norm_generica
program define norm_generica
    args v
    replace `v' = subinstr(subinstr(`v', "*", "", .), "\", "", .)
    replace `v' = ustrto(ustrnormalize(lower(strtrim(itrim(`v'))), "nfd"), "ascii", 2)
end

use "$raw/MINEDUC/Mifuturo/08_mifuturo_supply.dta", clear
rename año_mi_futuro mf_year
keep if mf_year >= 2017 & mean_income > 0 & !missing(mean_income, cod_inst)
rename area_carrera_generica gen
norm_generica gen
drop if gen == ""

di as result "=== Mi Futuro cells by reference year ==="
tab mf_year

collapse (mean) mean_income, by(cod_inst gen mf_year)
gen double li = ln(mean_income)
bysort mf_year: egen double li_m = mean(li)
gen double li_d = li - li_m
collapse (mean) idx_ig = li_d (count) mf_nyears = li_d, by(cod_inst gen)
label var idx_ig "Mi Futuro log income, demeaned by year, averaged"
save "$processed/pva_mifuturo_index.dta", replace

preserve
    collapse (mean) idx_g = idx_ig, by(gen)
    tempfile ig
    save `ig'
restore
preserve
    collapse (mean) idx_i = idx_ig, by(cod_inst)
    tempfile ii
    save `ii'
restore

* crosswalk codigo_unico -> carrera generica, from the raw titulados files
tempfile xw
local first 1
forvalues y = 2007/2024 {
    local files : dir "$tit_raw" files "*`y'*.csv"
    local file : word 1 of `files'
    if "`file'" == "" continue
    import delimited "$tit_raw/`file'", clear varnames(1) encoding(UTF-8) ///
        bindquote(strict) stringcols(_all)
    rename *, lower
    capture rename area_carrera_generica area_generica
    keep codigo_unico area_generica
    contract codigo_unico area_generica, freq(nf)
    if !`first' append using `xw'
    save `xw', replace
    local first 0
}
use `xw', clear
replace codigo_unico = upper(strtrim(codigo_unico))
rename area_generica gen
norm_generica gen
drop if codigo_unico == "" | gen == ""
collapse (sum) nf, by(codigo_unico gen)
gsort codigo_unico -nf
bysort codigo_unico: keep if _n == 1
keep codigo_unico gen
save `xw', replace

/**********************************************************************
* 2. First title within 8 years for sample students
**********************************************************************/

use mrun ao_proceso using "$processed/pva_students_2007_2016.dta", clear
tostring mrun, gen(mrun_str) format(%12.0f) force
replace mrun_str = trim(mrun_str)
keep mrun_str ao_proceso mrun
tempfile keys
save `keys'

use mrun_str grad_entry_year grad_year fecha_obtencion_titulo cod_inst ///
    cod_carrera grad_codigo_unico tipo_inst_1 ///
    using "$processed/diagnostic_titulados_all.dta", clear
joinby mrun_str using `keys'
keep if grad_year >= ao_proceso & grad_year <= ao_proceso + 8
keep if grad_entry_year >= ao_proceso | missing(grad_entry_year)

rename grad_codigo_unico codigo_unico
replace codigo_unico = upper(strtrim(codigo_unico))
merge m:1 codigo_unico using `xw', keep(1 3) nogen
merge m:1 cod_inst gen using "$processed/pva_mifuturo_index.dta", ///
    keepusing(idx_ig) keep(1 3) nogen
merge m:1 gen using `ig', keep(1 3) nogen
merge m:1 cod_inst using `ii', keep(1 3) nogen
gen byte idx_level = cond(!missing(idx_ig), 1, cond(!missing(idx_g), 2, ///
    cond(!missing(idx_i), 3, 9)))
gen double inc_idx = cond(idx_level == 1, idx_ig, cond(idx_level == 2, idx_g, idx_i))

* first title; ties on the date: highest index
gen double neg_idx = -inc_idx
bysort mrun ao_proceso (fecha_obtencion_titulo neg_idx): keep if _n == 1
keep mrun ao_proceso inc_idx idx_level tipo_inst_1 grad_year
rename tipo_inst_1 grad_inst_type
gen byte grad_any_8y = 1

di as result _n "=== Index source among graduates (1 inst x generica, 2 generica, 3 inst, 9 none) ==="
tab idx_level
tab grad_inst_type idx_level, row nofreq

tempfile grads
save `grads'

/**********************************************************************
* 3. Outcome
**********************************************************************/

use "$processed/pva_students_2007_2016.dta", clear
capture drop inc_idx idx_level grad_inst_type grad_year grad_any_8y inc_rank
merge 1:1 mrun ao_proceso using `grads', keep(1 3) nogen
replace grad_any_8y = 0 if missing(grad_any_8y)

* percentile among graduates with an index (equal weight per graduate)
quietly count if grad_any_8y & !missing(inc_idx)
local G = r(N)
egen double r_aux = rank(inc_idx) if grad_any_8y & !missing(inc_idx), track
gen double inc_rank = ceil(100 * r_aux / `G') if !missing(r_aux)
replace inc_rank = 0 if grad_any_8y == 0
drop r_aux

label var grad_any_8y "Any undergraduate title within 8 years (entered t or later)"
label var inc_idx     "Mi Futuro income index of the first title's program"
label var idx_level   "Index source: 1 inst x generica, 2 generica, 3 inst, 9 none"
label var inc_rank    "Income rank (1-100) of program graduated from; 0 if no title"

di as result _n "=== Outcome ==="
tab grad_any_8y
summarize inc_rank, detail
count if grad_any_8y & missing(inc_rank)
di as text "graduates without any index (outcome missing): " r(N)
tabstat grad_any_8y inc_rank graduates_he_8y, by(ao_proceso) stat(mean)

compress
save "$processed/pva_students_2007_2016.dta", replace

log close
