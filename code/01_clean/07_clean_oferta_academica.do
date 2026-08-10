****************************************************
* clean_oferta_academica.do
* Clean minimal Oferta Académica Excel files
****************************************************

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


****************************************************
* 0. Paths
****************************************************

global oferta_raw "C:/Users/jigodoy/Documents/jose-local/data/DEMRE/Postulacion"
global oferta_clean "$processed"

cap mkdir "$oferta_clean"

****************************************************
* 1. Import each Excel and save as .dta
****************************************************

forvalues y = 2007/2016 {

    di as text "=================================================="
    di as result "Cleaning Oferta Académica `y'"
    di as text "=================================================="

    local file "$oferta_raw/OfertaAcadémica_Admisión`y'.xlsx"

    capture confirm file "`file'"
    if _rc {
        di as error "File not found: `file'"
        continue
    }

    import excel using "`file'", firstrow clear

    gen ao_proceso = `y'

    ****************************************************
    * Convert only clean numeric-looking strings
    ****************************************************

    foreach v of varlist _all {

        capture confirm string variable `v'

        if _rc == 0 {

            capture destring `v', replace

            if _rc == 0 {
                di as result "Converted to numeric: `v'"
            }
            else {
                di as text "Kept as string: `v'"
            }
        }
    }

    compress

    save "$oferta_clean/oferta_academica_`y'.dta", replace

    di as result "Saved: $oferta_clean/oferta_academica_`y'.dta"
}

di as result "Done cleaning Oferta Académica files."


****************************************************
* 2. Append yearly clean files
****************************************************

clear

local first = 1

forvalues y = 2007/2016 {

    local file "$oferta_clean/oferta_academica_`y'.dta"

    capture confirm file "`file'"
    if _rc {
        di as error "Clean file not found: `file'"
        continue
    }

    if `first' == 1 {
        use "`file'", clear
        local first = 0
    }
    else {
        append using "`file'"
    }
}

compress

save "$oferta_clean/oferta_academica_2007_2016_appended.dta", replace

di as result "Saved appended file:"
di as result "$oferta_clean/oferta_academica_2007_2016_appended.dta"