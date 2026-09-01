/*******************************************************************************
Sua_Programs_Graphics.do

SUA PROGRAM COUNTS OVER TIME

PURPOSE

Create four complementary figures:

    1. All SIES programs offered by the analytical SUA universities
    2. Programs participating in centralized admission
    3. Centralized-admission programs by incumbent/entrant status
    4. All SIES programs by the ten Broad fields

UNIVERSITY UNIVERSE

    - 25 incumbent universities throughout 2007-2016
    - 8 entrant universities beginning in 2012

*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
0. INPUTS AND OUTPUTS
*******************************************************************************/

local program_panel ///
    "$processed/sua_exposure/sies_program_year_with_demre_2007_2016.dta"

local sua_roster ///
    "$processed/sua_exposure/sua_university_sies_roster.dta"


local graph_all ///
    "$output/sua_programs_over_time"

local graph_demre ///
    "$output/sua_programs_over_time_demre"

local graph_status ///
    "$output/sua_programs_over_time_demre_by_status"

local graph_field ///
    "$output/sua_programs_over_time_by_field"


/*******************************************************************************
1. PREPARE UNIVERSITY ROSTER
*******************************************************************************/

preserve

    use "`sua_roster'", clear

    keep ///
        cod_inst ///
        entrant_2012

    drop if missing( ///
        cod_inst, ///
        entrant_2012 ///
    )

    duplicates drop

    isid cod_inst

    tempfile roster_clean

    save `roster_clean', replace

restore


/*******************************************************************************
2. ANALYTICAL UNIVERSITY UNIVERSE
*******************************************************************************/

use "`program_panel'", clear

keep if inrange(ao_proceso, 2007, 2016)

drop if missing( ///
    codigo_unico, ///
    cod_inst, ///
    ao_proceso ///
)

isid codigo_unico ao_proceso


/*
Attach incumbent/entrant status.
*/

merge m:1 cod_inst ///
    using `roster_clean', ///
    keep(match) ///
    nogen


/*
Before 2012, retain only incumbent universities.

Beginning in 2012, retain incumbents and the eight entrant universities.
*/

keep if ///
    entrant_2012 == 0 | ///
    ( ///
        entrant_2012 == 1 & ///
        ao_proceso >= 2012 ///
    )


isid codigo_unico ao_proceso


label variable ao_proceso ///
    "Admission year"


/*
All SIES programs offered by universities in the analytical universe.
*/

tempfile all_sies_programs

save `all_sies_programs', replace


/*******************************************************************************
3. CENTRALIZED-ADMISSION PROGRAMS
*******************************************************************************/

assert inlist( ///
    has_demre_sies_year, ///
    0, ///
    1 ///
)


/*
Retain program-years with a recognized DEMRE program code.
*/

keep if has_demre_sies_year == 1


tempfile demre_programs

save `demre_programs', replace


/*******************************************************************************
4. GRAPH 1: ALL SIES PROGRAMS
*******************************************************************************/

use `all_sies_programs', clear


/*
Each observation is one unique program-year.
*/

gen byte one_program = 1


collapse ///
    (sum) number_programs = one_program, ///
    by(ao_proceso)


label variable number_programs ///
    "Number of programs"


display ""
display "============================================================"
display " ALL SIES PROGRAMS"
display "============================================================"

list ///
    ao_proceso ///
    number_programs, ///
    noobs clean


#delimit ;

twoway
    (
        connected
        number_programs
        ao_proceso,
        sort
        lcolor("70 96 120")
        mcolor("70 96 120")
        lwidth(medthick)
        msymbol(circle)
        msize(small)
    ),
    xline(
        2012,
        lcolor(gs8)
        lpattern(dash)
        lwidth(thin)
    )
    xlabel(
        2007(1)2016,
        labsize(small)
        format(%4.0f)
    )
    ylabel(
        ,
        angle(horizontal)
        labsize(small)
        format(%9.0fc)
        glcolor("225 232 238")
        glwidth(vthin)
    )
    xtitle(
        "Admission year",
        size(small)
    )
    ytitle(
        "Number of programs",
        size(small)
        margin(medsmall)
    )
    title(
        "Programs offered by the analytical SUA universities",
        size(medsmall)
        color("19 48 74")
    )
    subtitle(
        "All SIES program records",
        size(small)
        color(gs5)
    )
    note(
        "Incumbents are included throughout; entrant universities are included from 2012.",
        size(vsmall)
        color(gs5)
    )
    graphregion(
        color(white)
        margin(medsmall)
    )
    plotregion(
        color(white)
        margin(small)
    )
    xsize(10)
    ysize(6)
    name(
        sua_programs_all,
        replace
    )
;

#delimit cr


graph export ///
    "`graph_all'.png", ///
    width(2400) ///
    replace

graph export ///
    "`graph_all'.pdf", ///
    replace


/*******************************************************************************
5. GRAPH 2: PROGRAMS PARTICIPATING IN CENTRALIZED ADMISSION
*******************************************************************************/

use `demre_programs', clear

gen byte one_program = 1


collapse ///
    (sum) number_programs = one_program, ///
    by(ao_proceso)


label variable number_programs ///
    "Number of programs"


display ""
display "============================================================"
display " PROGRAMS WITH RECOGNIZED DEMRE CODE"
display "============================================================"

list ///
    ao_proceso ///
    number_programs, ///
    noobs clean


#delimit ;

twoway
    (
        connected
        number_programs
        ao_proceso,
        sort
        lcolor("19 48 74")
        mcolor("19 48 74")
        lwidth(medthick)
        msymbol(circle)
        msize(small)
    ),
    xline(
        2012,
        lcolor("91 155 213")
        lpattern(dash)
        lwidth(medthin)
    )
    xlabel(
        2007(1)2016,
        labsize(small)
        format(%4.0f)
    )
    ylabel(
        ,
        angle(horizontal)
        labsize(small)
        format(%9.0fc)
        glcolor("225 232 238")
        glwidth(vthin)
    )
    xtitle(
        "Admission year",
        size(small)
    )
    ytitle(
        "Number of programs",
        size(small)
        margin(medsmall)
    )
    title(
        "Programs participating in centralized admission",
        size(medsmall)
        color("19 48 74")
    )
    subtitle(
        "Program-years with a recognized DEMRE code",
        size(small)
        color(gs5)
    )
    note(
        "The vertical line marks the 2012 entry of eight private universities.",
        size(vsmall)
        color(gs5)
    )
    graphregion(
        color(white)
        margin(medsmall)
    )
    plotregion(
        color(white)
        margin(small)
    )
    xsize(10)
    ysize(6)
    name(
        sua_programs_demre,
        replace
    )
;

#delimit cr


graph export ///
    "`graph_demre'.png", ///
    width(2400) ///
    replace

graph export ///
    "`graph_demre'.pdf", ///
    replace


/*******************************************************************************
GRAPH: ALL SIES PROGRAMS BY UNIVERSITY STATUS
*******************************************************************************/

use `all_sies_programs', clear

/*
Count one program record per admission year and university status.
*/

gen byte one_program = 1

collapse ///
    (sum) number_programs = one_program, ///
    by( ///
        ao_proceso ///
        entrant_2012 ///
    )


/*
Create separate incumbent and entrant series.
*/

reshape wide ///
    number_programs, ///
    i(ao_proceso) ///
    j(entrant_2012)

rename ///
    number_programs0 ///
    incumbent_programs

rename ///
    number_programs1 ///
    entrant_programs


/*
Entrant universities are outside the analytical SUA universe before 2012.
*/

replace entrant_programs = 0 ///
    if missing(entrant_programs)


gen total_programs = ///
    incumbent_programs + ///
    entrant_programs


/*
Graph.
*/

twoway ///
    (connected ///
        incumbent_programs ///
        ao_proceso, ///
        lcolor("22 73 111") ///
        mcolor("22 73 111") ///
        msymbol(circle) ///
        lwidth(medthick)) ///
    (connected ///
        entrant_programs ///
        ao_proceso, ///
        lcolor("84 149 211") ///
        mcolor("84 149 211") ///
        msymbol(triangle) ///
        lpattern(dash) ///
        lwidth(medthick)) ///
    (connected ///
        total_programs ///
        ao_proceso, ///
        lcolor(black) ///
        mcolor(black) ///
        msymbol(diamond) ///
        lwidth(thick)), ///
    xline( ///
        2012, ///
        lcolor(gs8) ///
        lpattern(dash) ///
        lwidth(thin) ///
    ) ///
    xlabel( ///
        2007(1)2016, ///
        labsize(small) ///
    ) ///
    ylabel( ///
        , ///
        format(%9.0fc) ///
        angle(horizontal) ///
        labsize(small) ///
        grid ///
        glcolor("224 233 239") ///
    ) ///
    xtitle( ///
        "Admission year", ///
        size(small) ///
    ) ///
    ytitle( ///
        "Number of programs", ///
        size(small) ///
    ) ///
    title( ///
        "Programs offered by the analytical SUA universities", ///
        size(medsmall) ///
        color("19 48 74") ///
    ) ///
    subtitle( ///
        "Incumbent, entrant and total program counts", ///
        size(small) ///
        color(gs6) ///
    ) ///
    legend( ///
		order( ///
			1 "Incumbent programs" ///
			2 "Entrant programs" ///
			3 "Total programs" ///
		) ///
		cols(2) ///
		position(6) ///
		ring(1) ///
		size(small) ///
		region(lcolor(none)) ///
	) ///
	xsize(10) ///
	ysize(6) ///
	graphregion( ///
		color(white) ///
		margin(small) ///
	) ///
	plotregion(color(white)) ///
	name(sua_programs_by_status, replace)


graph export ///
    "$output/sua_programs_over_time_by_status.png", ///
    width(2400) ///
    replace

graph export ///
    "$output/sua_programs_over_time_by_status.pdf", ///
    replace


/*******************************************************************************
7. PREPARE PROGRAM COUNTS BY BROAD FIELD
*******************************************************************************/

use `all_sies_programs', clear

drop if missing(area_conocimiento)


egen int broad_field = ///
    group(area_conocimiento), ///
    label


levelsof broad_field, ///
    local(field_values)

local number_fields : ///
    word count `field_values'


display ""
display ///
    "Number of Broad fields = " ///
    %9.0f `number_fields'


if `number_fields' != 10 {

    display as error ///
        "Expected 10 Broad fields, but found `number_fields'."

    exit 459
}


gen byte one_program = 1


collapse ///
    (sum) number_programs = one_program, ///
    by( ///
        broad_field ///
        ao_proceso ///
    )


fillin ///
    broad_field ///
    ao_proceso

replace number_programs = 0 ///
    if missing(number_programs)

drop _fillin


label variable number_programs ///
    "Number of programs"


display ""
display "============================================================"
display " ALL SIES PROGRAMS BY BROAD FIELD"
display "============================================================"

sort ///
    broad_field ///
    ao_proceso

list ///
    broad_field ///
    ao_proceso ///
    number_programs, ///
    sepby(broad_field) ///
    noobs clean


/*******************************************************************************
8. GRAPH 4: ALL SIES PROGRAMS BY BROAD FIELD
*******************************************************************************/

#delimit ;

twoway

    (
        connected number_programs ao_proceso
        if broad_field == 1,
        sort
        lcolor("19 48 74")
        mcolor("19 48 74")
        lwidth(medium)
        msymbol(circle)
        msize(vsmall)
    )

    (
        connected number_programs ao_proceso
        if broad_field == 2,
        sort
        lcolor("31 78 121")
        mcolor("31 78 121")
        lpattern(dash)
        lwidth(medium)
        msymbol(diamond)
        msize(vsmall)
    )

    (
        connected number_programs ao_proceso
        if broad_field == 3,
        sort
        lcolor("70 114 159")
        mcolor("70 114 159")
        lpattern(shortdash)
        lwidth(medium)
        msymbol(triangle)
        msize(vsmall)
    )

    (
        connected number_programs ao_proceso
        if broad_field == 4,
        sort
        lcolor("91 155 213")
        mcolor("91 155 213")
        lpattern(longdash)
        lwidth(medium)
        msymbol(square)
        msize(vsmall)
    )

    (
        connected number_programs ao_proceso
        if broad_field == 5,
        sort
        lcolor("42 111 126")
        mcolor("42 111 126")
        lwidth(medium)
        msymbol(circle)
        msize(vsmall)
    )

    (
        connected number_programs ao_proceso
        if broad_field == 6,
        sort
        lcolor("71 137 145")
        mcolor("71 137 145")
        lpattern(dash)
        lwidth(medium)
        msymbol(diamond)
        msize(vsmall)
    )

    (
        connected number_programs ao_proceso
        if broad_field == 7,
        sort
        lcolor("91 108 125")
        mcolor("91 108 125")
        lpattern(shortdash)
        lwidth(medium)
        msymbol(triangle)
        msize(vsmall)
    )

    (
        connected number_programs ao_proceso
        if broad_field == 8,
        sort
        lcolor("126 146 162")
        mcolor("126 146 162")
        lpattern(longdash)
        lwidth(medium)
        msymbol(square)
        msize(vsmall)
    )

    (
        connected number_programs ao_proceso
        if broad_field == 9,
        sort
        lcolor("55 55 55")
        mcolor("55 55 55")
        lwidth(medium)
        msymbol(circle)
        msize(vsmall)
    )

    (
        connected number_programs ao_proceso
        if broad_field == 10,
        sort
        lcolor(black)
        mcolor(black)
        lpattern(dash)
        lwidth(medium)
        msymbol(diamond)
        msize(vsmall)
    ),

    xline(
        2012,
        lcolor(gs8)
        lpattern(dash)
        lwidth(thin)
    )

    xlabel(
        2007(1)2016,
        labsize(small)
        format(%4.0f)
    )

    ylabel(
        0(100)800,
        angle(horizontal)
        labsize(small)
        format(%9.0f)
        glcolor("225 232 238")
        glwidth(vthin)
    )

    xtitle(
        "Admission year",
        size(small)
    )

    ytitle(
        "Number of programs",
        size(small)
        margin(medsmall)
    )

    title(
        "Programs offered by the analytical SUA universities",
        size(medsmall)
        color("19 48 74")
    )

    subtitle(
        "All SIES program records, by Broad field",
        size(small)
        color(gs5)
    )

    legend( ///
		order( ///
			1  "Administration and Business" ///
			2  "Agriculture" ///
			3  "Arts and Architecture" ///
			4  "Basic Sciences" ///
			5  "Social Sciences" ///
			6  "Law" ///
			7  "Education" ///
			8  "Humanities" ///
			9  "Health" ///
			10 "Technology" ///
		) ///
		cols(5) ///
		position(6) ///
		ring(1) ///
		size(vsmall) ///
		region(lcolor(none)) ///
	) ///
	xsize(10) ///
	ysize(6) ///
	graphregion( ///
		color(white) ///
		margin(small) ///
	) ///
	plotregion(color(white)) ///
	name(sua_programs_by_field, replace)
;

#delimit cr


graph export ///
    "`graph_field'.png", ///
    width(2400) ///
    replace

graph export ///
    "`graph_field'.pdf", ///
    replace


/*******************************************************************************
9. END
*******************************************************************************/

display ""
display "============================================================"
display " SUA PROGRAM-COUNT GRAPHS COMPLETED"
display "============================================================"

display ""
display "1. All SIES programs:"
display "   `graph_all'.png"

display ""
display "2. DEMRE-recognized programs:"
display "   `graph_demre'.png"

display ""
display "3. Incumbent, entrant and total DEMRE programs:"
display "   `graph_status'.png"

display ""
display "4. All SIES programs by Broad field:"
display "   `graph_field'.png"