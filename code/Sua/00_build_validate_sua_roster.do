/**********************************************************************
* 00_build_validate_sua_roster.do
*
* Objetivo:
*   Crear y validar el roster institucional utilizado en el ejercicio
*   de expansión del Sistema Único de Admisión.
*
* Universo:
*   - 25 universidades incumbentes.
*   - 8 universidades privadas que conforman el grupo entrante.
*
* Output:
*   $processed/sua_university_roster_manual.dta
*
* Importante:
*   entrant_2012 identifica el grupo tratado en la especificación base.
*   El año exacto de incorporación de cada universidad debe validarse
*   posteriormente con las ofertas académicas DEMRE.
*
* Este código:
*   - no abre matrículas;
*   - no construye exposición;
*   - no estima regresiones.
**********************************************************************/

clear all
set more off

do "code/config.do"

/**********************************************************************
* 1. Crear roster institucional
**********************************************************************/

input ///
    str6  sigla_universidad ///
    str3  cod_inst ///
    byte entrant_2012 ///
    str80 nomb_inst_roster

/*
25 universidades incumbentes
*/

"PUCV"  "89" 0 "PONTIFICIA UNIVERSIDAD CATOLICA DE VALPARAISO"
"UACH"  "90" 0 "UNIVERSIDAD AUSTRAL DE CHILE"
"UANT"  "73" 0 "UNIVERSIDAD DE ANTOFAGASTA"
"UBB"   "75" 0 "UNIVERSIDAD DEL BIO-BIO"
"UC"    "86" 0 "PONTIFICIA UNIVERSIDAD CATOLICA DE CHILE"
"UCH"   "70" 0 "UNIVERSIDAD DE CHILE"
"UCM"   "92" 0 "UNIVERSIDAD CATOLICA DEL MAULE"
"UCN"   "91" 0 "UNIVERSIDAD CATOLICA DEL NORTE"
"UCSC"  "93" 0 "UNIVERSIDAD CATOLICA DE LA SANTISIMA CONCEPCION"
"UCT"   "94" 0 "UNIVERSIDAD CATOLICA DE TEMUCO"
"UDA"   "79" 0 "UNIVERSIDAD DE ATACAMA"
"UDEC"  "87" 0 "UNIVERSIDAD DE CONCEPCION"
"UFRO"  "76" 0 "UNIVERSIDAD DE LA FRONTERA"
"ULAG"  "84" 0 "UNIVERSIDAD DE LOS LAGOS"
"ULS"   "74" 0 "UNIVERSIDAD DE LA SERENA"
"UMAG"  "77" 0 "UNIVERSIDAD DE MAGALLANES"
"UMCE"  "82" 0 "UNIVERSIDAD METROPOLITANA DE CIENCIAS DE LA EDUCACION"
"UNAP"  "81" 0 "UNIVERSIDAD ARTURO PRAT"
"UPA"   "83" 0 "UNIVERSIDAD DE PLAYA ANCHA DE CIENCIAS DE LA EDUCACION"
"USACH" "71" 0 "UNIVERSIDAD DE SANTIAGO DE CHILE"
"UTA"   "80" 0 "UNIVERSIDAD DE TARAPACA"
"UTAL"  "78" 0 "UNIVERSIDAD DE TALCA"
"UTEM"  "85" 0 "UNIVERSIDAD TECNOLOGICA METROPOLITANA"
"UTFSM" "88" 0 "UNIVERSIDAD TECNICA FEDERICO SANTA MARIA"
"UV"    "72" 0 "UNIVERSIDAD DE VALPARAISO"

/*
8 universidades del grupo entrante
*/

"UAH"   "69" 1 "UNIVERSIDAD ALBERTO HURTADO"
"UAI"   "23" 1 "UNIVERSIDAD ADOLFO IBAÑEZ"
"UANDE" "34" 1 "UNIVERSIDAD DE LOS ANDES"
"UDD"   "45" 1 "UNIVERSIDAD DEL DESARROLLO"
"UDP"   "3"  1 "UNIVERSIDAD DIEGO PORTALES"
"UFT"   "2"  1 "UNIVERSIDAD FINIS TERRAE"
"UMAYO" "10" 1 "UNIVERSIDAD MAYOR"
"UNAB"  "20" 1 "UNIVERSIDAD ANDRES BELLO"

end


/**********************************************************************
* 2. Normalizar identificadores
**********************************************************************/

replace sigla_universidad = ///
    upper(itrim(ustrtrim(sigla_universidad)))

replace cod_inst = ///
    itrim(ustrtrim(cod_inst))

replace nomb_inst_roster = ///
    upper(itrim(ustrtrim(nomb_inst_roster)))

assert sigla_universidad != ""
assert cod_inst != ""
assert nomb_inst_roster != ""

isid cod_inst
isid sigla_universidad


/**********************************************************************
* Validar primer año observado en postulaciones DEMRE
**********************************************************************/

tempfile first_sua_year

preserve

    use "$processed/applications_rd.dta", clear

    confirm variable sigla_universidad
    confirm variable ao_proceso

    keep sigla_universidad ao_proceso

    replace sigla_universidad = ///
        upper(itrim(ustrtrim(sigla_universidad)))

    keep if inrange(ao_proceso, 2007, 2016)
    drop if missing(sigla_universidad)

    collapse ///
        (min) first_sua_year = ao_proceso, ///
        by(sigla_universidad)

    save `first_sua_year'

restore

merge 1:1 ///
    sigla_universidad ///
    using `first_sua_year', ///
    keep(master match)

/**********************************************************************
* Revisar las ocho universidades entrantes
**********************************************************************/

list ///
    sigla_universidad ///
    cod_inst ///
    entrant_2012 ///
    first_sua_year ///
    _merge ///
    if entrant_2012 == 1, ///
    noobs clean

assert _merge == 3 ///
    if entrant_2012 == 1

assert first_sua_year == 2012 ///
    if entrant_2012 == 1

gen int entry_year_sua = ///
    first_sua_year ///
    if entrant_2012 == 1

label variable entry_year_sua ///
    "First SUA admission process observed in DEMRE"

drop first_sua_year _merge
/**********************************************************************
* 3. Construir indicadores institucionales
**********************************************************************/

assert inlist(entrant_2012, 0, 1)

gen byte sua_incumbent = ///
    entrant_2012 == 0

assert ///
    sua_incumbent + entrant_2012 == 1

label define entrant_lbl ///
    0 "SUA incumbent" ///
    1 "Entered SUA in 2012", ///
    replace

label values ///
    entrant_2012 ///
    entrant_lbl

label variable entrant_2012 ///
    "University entered the SUA in the 2012 admission process"

label variable sua_incumbent ///
    "University was incumbent in the centralized system"

label variable cod_inst ///
    "SIES institution code"

label variable sigla_universidad ///
    "University abbreviation"

label variable nomb_inst_roster ///
    "Institution name in SUA roster"

/**********************************************************************
* 4. Validar composición del roster
**********************************************************************/

count

di as result ///
    "Universidades totales: " r(N)

assert r(N) == 33

count if sua_incumbent == 1

di as result ///
    "Universidades incumbentes: " r(N)

assert r(N) == 25

count if entrant_2012 == 1

di as result ///
    "Universidades del grupo entrante: " r(N)

assert r(N) == 8

assert entrant_2012 == 0 ///
    if sua_incumbent == 1

assert entrant_2012 == 1 ///
    if sua_incumbent == 0

/**********************************************************************
* 5. Mostrar roster validado
**********************************************************************/

sort ///
    entrant_2012 ///
    sigla_universidad

di as text "=================================================="
di as result "ROSTER INSTITUCIONAL SUA"
di as text "=================================================="

list ///
    sigla_universidad ///
    cod_inst ///
    sua_incumbent ///
    entrant_2012 ///
    nomb_inst_roster, ///
    sepby(entrant_2012) ///
    noobs clean abbreviate(45)

/**********************************************************************
* 6. Ordenar y guardar
**********************************************************************/

order ///
    cod_inst ///
    sigla_universidad ///
    nomb_inst_roster ///
    sua_incumbent ///
    entrant_2012

sort ///
    entrant_2012 ///
    sigla_universidad

compress

save ///
    "$processed/sua_university_roster_manual.dta", ///
    replace

di as text "=================================================="
di as result "ROSTER SUA CREADO Y VALIDADO"
di as text "=================================================="

di as result ///
    "Archivo guardado en:"

di as text ///
    "$processed/sua_university_roster_manual.dta"