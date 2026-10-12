/**********************************************************************
* 15_build_admission_rank.do
*
* Builds the admission-rank file used by the inframarginal Design I
* scripts (04_rdd/Inframarginals/21b, 21c). The file had no builder in
* the repo (issue #3).
*
* Source: DEMRE Formulario C (postulaciones y selección), column LUGAR,
* which 01_clean/02_clean_applications.do does not keep.
*
* LUGAR is the position in the program's selection list. It is positive
* only for admitted (estado 24) and waitlisted (estado 25) applications:
* admitted take places 1..n_admitted (the maximum place among admits
* equals the number of admits) and the waiting list continues the ranking.
* It is 0 for every other status. Only LUGAR > 0 rows are kept.
*
* Input:  $app_raw/C_POSTULACIONES_SELECCION_PSU_YYYY_PRIV_MRUN.csv
* Output: $processed/admission_rank_inframarginal_2007_2016.dta
*         keys: mrun ao_proceso codigo_carrera sigla_universidad; lugar
**********************************************************************/

do "code/config.do"

tempfile rank

forvalues y = 2007/2016 {
    import delimited "$app_raw/C_POSTULACIONES_SELECCION_PSU_`y'_PRIV_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(windows-1252) stringcols(_all)
    rename *, lower
    keep mrun codigo_carrera sigla_universidad estado_preferencia preferencia lugar
    destring mrun codigo_carrera estado_preferencia preferencia lugar, replace force
    gen int ao_proceso = `y'
    keep if lugar > 0 & !missing(lugar)

    * LUGAR should exist only for admitted and waitlisted applications
    count if !inlist(estado_preferencia, $admitted, $waiting_list)
    if r(N) > 0 di as error "`y': " r(N) " rows with LUGAR > 0 and status not 24/25"

    if `y' > 2007 append using `rank'
    save `rank', replace
}

replace sigla_universidad = upper(strtrim(sigla_universidad))
label var lugar "Place in the program's selection list (DEMRE LUGAR)"

di as text _n "Ranked applications by year and status"
tab ao_proceso estado_preferencia

duplicates report mrun ao_proceso codigo_carrera sigla_universidad

compress
sort ao_proceso codigo_carrera lugar
save "$processed/admission_rank_inframarginal_2007_2016.dta", replace
di as result "admission_rank_inframarginal_2007_2016.dta saved."
