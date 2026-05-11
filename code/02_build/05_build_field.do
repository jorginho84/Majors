************************************************************
* 05_build_field_one_output.do
* Recupera AREA_CONOCIMIENTO desde matrícula SIES,
* mergea con analysis_sample.dta, completa campos faltantes
* y guarda UN SOLO output final para RDD por field.
************************************************************

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

di as result "Config cargado correctamente."
di as result "Processed: $processed"
di as result "Matricula raw: $mat_raw"
di as result "Años: $year_start - $year_end"


************************************************************
* 1. Construir crosswalk temporal año-programa-área desde CSV matrícula
************************************************************

tempfile all_fields field_xwalk
local first 1

forvalues y = $year_start/$year_end {

    di as text "--------------------------------------------------"
    di as result "Procesando matrícula año: `y'"
    di as text "--------------------------------------------------"

    * Buscar cualquier archivo que contenga el año
    local files : dir "$mat_raw" files "*`y'*"

    if `"`files'"' == "" {
        di as error "No se encontró ningún archivo para el año `y' en $mat_raw"
        continue
    }

    di as text "Archivos encontrados para `y':"
    di as result `"`files'"'

    * Elegir archivo CSV, evitando PDFs
    local file ""
    foreach f of local files {
        local fl = lower("`f'")
        if regexm("`fl'", "\.csv$") {
            local file "`f'"
            continue, break
        }
    }

    if "`file'" == "" {
        di as error "No se encontró CSV usable para `y'. Se salta."
        continue
    }

    di as result "Archivo usado: `file'"

    import delimited "$mat_raw/`file'", ///
        clear ///
        varnames(1) ///
        encoding(UTF-8) ///
        bindquote(strict)

    rename *, lower

    * Variables clave
    capture confirm variable area_conocimiento
    if _rc != 0 {
        di as error "No existe area_conocimiento en `file'. Se salta."
        describe
        continue
    }

    capture confirm variable cat_periodo
    if _rc != 0 {
        gen cat_periodo = `y'
    }

    capture confirm variable codigo_demre
    if _rc != 0 {
        di as error "No existe codigo_demre en `file'. Se salta."
        describe
        continue
    }

    keep cat_periodo codigo_demre area_conocimiento

    rename cat_periodo ao_proceso
    rename codigo_demre t_codigo_carrera

    destring ao_proceso, replace force
    replace ao_proceso = `y' if missing(ao_proceso)

    * Limpiar código DEMRE
    tostring t_codigo_carrera, replace force
    replace t_codigo_carrera = trim(t_codigo_carrera)
    replace t_codigo_carrera = "" if t_codigo_carrera == "."
    replace t_codigo_carrera = "" if upper(t_codigo_carrera) == "NA"
    replace t_codigo_carrera = "" if upper(t_codigo_carrera) == "SIN INFORMACION"
    replace t_codigo_carrera = "" if upper(t_codigo_carrera) == "SIN INFORMACIÓN"
    destring t_codigo_carrera, replace force

    * Mantener solo observaciones útiles para DEMRE/SUA
    drop if missing(ao_proceso)
    drop if missing(t_codigo_carrera)
    drop if missing(area_conocimiento) | trim(area_conocimiento) == ""

    replace area_conocimiento = trim(area_conocimiento)

    if `first' == 1 {
        save `all_fields', replace
        local first 0
    }
    else {
        append using `all_fields'
        save `all_fields', replace
    }
}

if `first' == 1 {
    di as error "No se procesó ningún archivo CSV. Revisa nombres/ruta."
    exit 601
}

************************************************************
* 2. Limpiar crosswalk temporal año-programa-área
************************************************************

use `all_fields', clear

di as text "--------------------------------------------------"
di as result "Resumen inicial del crosswalk SIES temporal"
di as text "--------------------------------------------------"

count
tab area_conocimiento, missing

* Si un mismo año-programa aparece con más de un área,
* dejamos el área más frecuente en matrícula.
contract ao_proceso t_codigo_carrera area_conocimiento, freq(n_area)
gsort ao_proceso t_codigo_carrera -n_area
bysort ao_proceso t_codigo_carrera: keep if _n == 1

drop n_area
compress
save `field_xwalk', replace

************************************************************
* 3. Merge temporal con analysis_sample.dta
************************************************************

use "$processed/analysis_sample.dta", clear
capture drop _merge

merge m:1 ao_proceso t_codigo_carrera using `field_xwalk'

di as text "--------------------------------------------------"
di as result "Resultado del merge con fields SIES"
di as text "--------------------------------------------------"

tab _merge
count if _merge == 3
count if _merge == 1
count if _merge == 2

tab area_conocimiento if _merge == 3, missing

* Botar registros que están solo en el crosswalk auxiliar.
* Esto NO elimina observaciones de analysis_sample; elimina códigos SIES no usados.
drop if _merge == 2
drop _merge

************************************************************
* 4. Crear variable field simplificada
************************************************************

capture drop field
gen field = ""

replace field = "Business" if area_conocimiento == "Administración y Comercio"
replace field = "Agriculture" if area_conocimiento == "Agropecuaria"
replace field = "Arts and Architecture" if area_conocimiento == "Arte y Arquitectura"
replace field = "Basic Sciences" if area_conocimiento == "Ciencias Básicas"
replace field = "Social Sciences" if area_conocimiento == "Ciencias Sociales"
replace field = "Law" if area_conocimiento == "Derecho"
replace field = "Education" if area_conocimiento == "Educación"
replace field = "Humanities" if area_conocimiento == "Humanidades"
replace field = "Health" if area_conocimiento == "Salud"
replace field = "Technology" if area_conocimiento == "Tecnología"
replace field = "Undefined" if area_conocimiento == "Sin área definida"
replace field = "Missing" if field == ""

di as text "--------------------------------------------------"
di as result "Diagnóstico después del merge oficial SIES"
di as text "--------------------------------------------------"

tab field, missing
tab ao_proceso if field == "Missing", missing

************************************************************
* 5. Completar usando el mismo t_codigo_carrera
************************************************************
* Si un código DEMRE aparece clasificado en algún año,
* usamos su field más frecuente para completar missing.
************************************************************

tempfile xwalk_code

preserve
    keep if field != "Missing" & field != "" & !missing(field)
    keep t_codigo_carrera area_conocimiento field

    contract t_codigo_carrera area_conocimiento field, freq(n_code_field)

    gsort t_codigo_carrera -n_code_field
    bysort t_codigo_carrera: keep if _n == 1

    rename area_conocimiento area_from_code
    rename field field_from_code

    keep t_codigo_carrera area_from_code field_from_code
    save `xwalk_code', replace
restore

capture drop _merge
merge m:1 t_codigo_carrera using `xwalk_code'

replace area_conocimiento = area_from_code ///
    if (field == "Missing" | field == "" | missing(field)) ///
    & area_from_code != ""

replace field = field_from_code ///
    if (field == "Missing" | field == "" | missing(field)) ///
    & field_from_code != ""

drop area_from_code field_from_code _merge

di as text "=================================================="
di as text "DESPUES DE COMPLETAR POR CODIGO DEMRE"
di as text "=================================================="

count if field == "Missing" | field == "" | missing(field)
tab field, missing
tab ao_proceso if field == "Missing", missing

************************************************************
* 6. Completar usando nombre_carrera normalizado
************************************************************
* Si el mismo nombre de carrera aparece clasificado en otros casos,
* usamos su field más frecuente.
************************************************************

capture drop nombre_clean

gen nombre_clean = lower(strtrim(itrim(nombre_carrera)))

replace nombre_clean = subinstr(nombre_clean, "á", "a", .)
replace nombre_clean = subinstr(nombre_clean, "é", "e", .)
replace nombre_clean = subinstr(nombre_clean, "í", "i", .)
replace nombre_clean = subinstr(nombre_clean, "ó", "o", .)
replace nombre_clean = subinstr(nombre_clean, "ú", "u", .)
replace nombre_clean = subinstr(nombre_clean, "ñ", "n", .)
replace nombre_clean = subinstr(nombre_clean, "ü", "u", .)

replace nombre_clean = subinstr(nombre_clean, ".", "", .)
replace nombre_clean = subinstr(nombre_clean, ",", "", .)
replace nombre_clean = subinstr(nombre_clean, ":", "", .)
replace nombre_clean = subinstr(nombre_clean, ";", "", .)
replace nombre_clean = strtrim(itrim(nombre_clean))

tempfile xwalk_name

preserve
    keep if field != "Missing" & field != "" & !missing(field)
    keep nombre_clean area_conocimiento field

    contract nombre_clean area_conocimiento field, freq(n_name_field)

    gsort nombre_clean -n_name_field
    bysort nombre_clean: keep if _n == 1

    rename area_conocimiento area_from_name
    rename field field_from_name

    keep nombre_clean area_from_name field_from_name
    save `xwalk_name', replace
restore

capture drop _merge
merge m:1 nombre_clean using `xwalk_name'

replace area_conocimiento = area_from_name ///
    if (field == "Missing" | field == "" | missing(field)) ///
    & area_from_name != ""

replace field = field_from_name ///
    if (field == "Missing" | field == "" | missing(field)) ///
    & field_from_name != ""

drop area_from_name field_from_name _merge

di as text "=================================================="
di as text "DESPUES DE COMPLETAR POR NOMBRE DE CARRERA"
di as text "=================================================="

count if field == "Missing" | field == "" | missing(field)
tab field, missing
tab ao_proceso if field == "Missing", missing

************************************************************
* 7. Completar remanentes con reglas documentadas por texto
************************************************************
* Solo modifica observaciones que siguen con field == "Missing".
************************************************************

* Salud
replace area_conocimiento = "Salud" if field == "Missing" & ///
    regexm(nombre_clean, "medicina|enfermer|kinesiolog|odontolog|obstetric|puericultura|fonoaudiolog|nutric|dietet|tecnologia medica|terapia ocupacional|quimica y farmacia|farmacia|veterinaria|bioquimica")
replace field = "Health" if field == "Missing" & area_conocimiento == "Salud"

* Derecho
replace area_conocimiento = "Derecho" if field == "Missing" & ///
    regexm(nombre_clean, "derecho|juridic|juridicas|juridicas y sociales")
replace field = "Law" if field == "Missing" & area_conocimiento == "Derecho"

* Administración y Comercio
replace area_conocimiento = "Administración y Comercio" if field == "Missing" & ///
    regexm(nombre_clean, "ingenieria comercial|ingeniera comercial|auditoria|contador|administracion|adm de|gestion|finanzas|negocios|comercio|recursos gastronomicos|econom")
replace field = "Business" if field == "Missing" & area_conocimiento == "Administración y Comercio"

* Tecnología
replace area_conocimiento = "Tecnología" if field == "Missing" & ///
    regexm(nombre_clean, "ingenieria|ingeniera|ing civil|ing de ejec|ing ejec|ing\.|tecn universitario|tecnico universitario|informatica|computacion|electronica|electricidad|mecanica|minas|metalurgia|obras civiles|construccion|industrial|geomensura|prevencion de riesgos|biomedica|ambiental|quimica industrial")
replace field = "Technology" if field == "Missing" & area_conocimiento == "Tecnología"

* Educación
replace area_conocimiento = "Educación" if field == "Missing" & ///
    regexm(nombre_clean, "pedagog|ped |ped\.|educacion|profesor|ed media|ed gral|parvularia|diferencial|basica|castellano|ingles|historia y geografia|educacion fisica")
replace field = "Education" if field == "Missing" & area_conocimiento == "Educación"

* Ciencias Sociales
replace area_conocimiento = "Ciencias Sociales" if field == "Missing" & ///
    regexm(nombre_clean, "psicolog|sociolog|trabajo social|servicio social|periodismo|comunicacion social|ciencia politica|administracion publica|cs politicas|guber|antropolog")
replace field = "Social Sciences" if field == "Missing" & area_conocimiento == "Ciencias Sociales"

* Arte y Arquitectura
replace area_conocimiento = "Arte y Arquitectura" if field == "Missing" & ///
    regexm(nombre_clean, "arquitectura|diseno|diseo|arte|grafico|grafica|musica|teatro")
replace field = "Arts and Architecture" if field == "Missing" & area_conocimiento == "Arte y Arquitectura"

* Ciencias Básicas
replace area_conocimiento = "Ciencias Básicas" if field == "Missing" & ///
    regexm(nombre_clean, "biologia|fisica|matematica|quimica|ciencias exactas|lic en ciencias|bachillerato en ciencias")
replace field = "Basic Sciences" if field == "Missing" & area_conocimiento == "Ciencias Básicas"

* Humanidades
replace area_conocimiento = "Humanidades" if field == "Missing" & ///
    regexm(nombre_clean, "historia|filosofia|literatura|linguistica|ling |traduccion|humanidades|castellano")
replace field = "Humanities" if field == "Missing" & area_conocimiento == "Humanidades"

************************************************************
* 8. Casos especiales documentados
************************************************************
* Nota: NO forzamos bachillerato ingreso común genérico.
* Lo dejamos como Missing y luego se dropea si no tiene campo claro.
************************************************************

* Bachillerato en ciencias sociales y humanidades
replace area_conocimiento = "Humanidades" if field == "Missing" & ///
    regexm(nombre_clean, "bachillerato") & regexm(nombre_clean, "humanidades")
replace field = "Humanities" if field == "Missing" & area_conocimiento == "Humanidades"

* Bachillerato en ciencias
replace area_conocimiento = "Ciencias Básicas" if field == "Missing" & ///
    regexm(nombre_clean, "bachillerato") & regexm(nombre_clean, "ciencias")
replace field = "Basic Sciences" if field == "Missing" & area_conocimiento == "Ciencias Básicas"

* Plan común de ingenierías
replace area_conocimiento = "Tecnología" if field == "Missing" & ///
    regexm(nombre_clean, "plan comun") & regexm(nombre_clean, "ingenier")
replace field = "Technology" if field == "Missing" & area_conocimiento == "Tecnología"

************************************************************
* 9. Diagnóstico final antes del drop
************************************************************

di as text "=================================================="
di as text "DIAGNOSTICO FINAL ANTES DEL DROP"
di as text "=================================================="

count
count if field == "Missing" | field == "" | missing(field)

tab field, missing
tab ao_proceso if field == "Missing", missing

preserve
    keep if field == "Missing" | field == "" | missing(field)
    count
    if _N > 0 {
        contract t_codigo_carrera sigla_universidad nombre_carrera, freq(n_obs)
        gsort -n_obs

        gen cum_obs = sum(n_obs)
        egen total_missing = total(n_obs)
        gen cum_share = cum_obs / total_missing

        list t_codigo_carrera sigla_universidad nombre_carrera n_obs cum_share, ///
            abbreviate(60) sep(0)
    }
restore

************************************************************
* 10. Dropear remanentes sin campo claro y guardar ÚNICO output
************************************************************

count
count if field == "Missing" | field == "" | missing(field)

drop if field == "Missing" | field == "" | missing(field)

* Variable auxiliar usada solo para clasificación; no se necesita para análisis.
capture drop nombre_clean

count
tab field, missing

save "$processed/analysis_sample_with_fields_final.dta", replace

di as result "Output único guardado en:"
di as result "$processed/analysis_sample_with_fields_final.dta"

************************************************************
* Fin
************************************************************
