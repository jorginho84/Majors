/*******************************************************************************
 03_build_program_year_enrollment
* BUILD PROGRAM-YEAR ENROLLMENT DIRECTLY FROM STUDENT DESTINATIONS
*
* Source:
* analysis_sample_with_fields_graduation_8y.dta
*
* Unit after first step:
* student x application year
*
* Final unit:
* enrolled DEMRE program x year
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"

use ///
    "$processed/analysis_sample_with_fields_graduation_8y.dta", ///
    clear

keep if inrange(ao_proceso, 2007, 2016)


/**********************************************************************
* 1. Keep only student-level enrollment destination information
**********************************************************************/

keep ///
    mrun ///
    ao_proceso ///
    codigo_carrera_demre ///
    codigo_carrera_mineduc ///
    enrolls_he ///
    enrolls_uni


/**********************************************************************
* 2. Collapse application rows to one student-year destination
*
* Audit showed these variables are constant within mrun x year.
**********************************************************************/

duplicates drop

isid mrun ao_proceso


/**********************************************************************
* 3. Keep students with an observed DEMRE enrollment destination
**********************************************************************/

keep if !missing(codigo_carrera_demre)

count

display ///
    "Student-years with DEMRE enrollment destination = " ///
    r(N)


/**********************************************************************
* 4. Verify one student-year = one destination
**********************************************************************/

isid mrun ao_proceso

duplicates report ///
    mrun ///
    ao_proceso ///
    codigo_carrera_demre


/**********************************************************************
* 5. Harmonize DEMRE code across 2012 coding change
*
* old four-digit abcd -> new five-digit ab0cd
**********************************************************************/

tostring codigo_carrera_demre, ///
    gen(codigo_demre_id) ///
    format(%05.0f)

replace codigo_demre_id = ///
    substr(codigo_demre_id,2,4) ///
    if ///
        strlen(codigo_demre_id) == 5 & ///
        substr(codigo_demre_id,1,1) == "0"

gen str5 codigo_demre_harmonized = ///
    codigo_demre_id

replace codigo_demre_harmonized = ///
    substr(codigo_demre_id,1,2) + ///
    "0" + ///
    substr(codigo_demre_id,3,2) ///
    if strlen(codigo_demre_id) == 4


/**********************************************************************
* 6. Count unique enrolled students by DEMRE program-year
**********************************************************************/

collapse ///
    (count) N_enrolled_demre = mrun, ///
    by( ///
        ao_proceso ///
        codigo_demre_harmonized ///
    )

label variable N_enrolled_demre ///
    "Enrollment reconstructed from student DEMRE destination"


/**********************************************************************
* 7. Basic diagnostics
**********************************************************************/

isid ///
    codigo_demre_harmonized ///
    ao_proceso

summarize N_enrolled_demre, detail

bysort ao_proceso: ///
    egen long total_enrolled_year = ///
        total(N_enrolled_demre)

bysort ao_proceso: ///
    egen long n_programs_year = ///
        count(N_enrolled_demre)

bysort ao_proceso: ///
    gen byte tag_year = _n == 1

list ///
    ao_proceso ///
    total_enrolled_year ///
    n_programs_year ///
    if tag_year, ///
    noobs clean


/**********************************************************************
* 8. Save audit panel
**********************************************************************/

drop total_enrolled_year n_programs_year tag_year

save ///
    "$processed/enrollment_by_demre_destination_2007_2016.dta", ///
    replace