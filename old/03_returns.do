/*------------------------------------------------------------------------------
				
						   Papers about majors.
							
						  Hugo Salgado Morales
								V.2.0
								
						    December 30th, 2025
------------------------------------------------------------------------------*/

*--- Globals -------------------------------------------------------------------
global root "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA"
global data "$root/01_data"
global code "$root/02_code"
global temp "$root/03_temp"
*global results "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\02_RESULTADOS\20251205" //modificar según fecha de extracción.

*--- Preparing datasets --------------------------------------------------------

*-- (1) Weights ----------------------------------------------------------------
use "$root/03_temp/weights_2004_2016.dta", clear
/*
replace w_gpa = w_gpa/100
replace w_rank = w_rank/100
replace w_reading = w_reading/100
replace w_math = w_math/100
replace w_history = w_history/100
replace w_science = w_science/100
rename program_code codigo_carrera
rename application_year año_proceso
*/
replace min_application_score = 0 if min_application_score ==. 
replace min_reading_math = 0 if min_reading_math ==.
save "$temp/weights_2004_2016.dta", replace


*-- (2) Scores -----------------------------------------------------------------
forv x = 2007/2016 {
use "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\BASES_COMUNES2\MINEDUC\PSU\Formulario_A/`x'/PSU_Formulario_A_`x'_innomi", clear
	drop codigo_enseñanza
	save "$temp/scores`x'.dta", replace
}

clear 
forvalues x = 2007/2016 {
	append using "$temp/scores`x'.dta", force
	erase "$temp/scores`x'.dta"
}
rename nuevo_run_falso mrun
*-- Register first time an individual applies for college:
bys mrun: egen first = min(año_proceso)
duplicates drop mrun año_proceso, force //one observation deleted
save "$temp/scores.dta", replace 

*-- (3) Enrollment -------------------------------------------------------------

*--- Demre 
forvalues x = 2007/2016 {
	
use "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\BASES_COMUNES2\MINEDUC\PSU\Formulario_D/`x'/PSU_Formulario_D_`x'_innomi", clear
	rename nuevo_run_falso mrun
	keep mrun año_proceso codigo_carrera nombre_carrera sigla_universidad 
	renvarlab codigo_carrera nombre_carrera sigla_universidad, postfix(_m)
	gen enrolls_he  = 1
	gen enrolls_uni = 1
	save "$temp/enrolls_demre`x'.dta", replace

}

clear 
forvalues x = 2007/2016 {
	
	append using "$temp/enrolls_demre`x'.dta"
	erase "$temp/enrolls_demre`x'.dta"
}

save "$temp/enrolls_demre.dta", replace


*--- Enrollment Mineduc: to generate dataset that identifies the exact program in which a student enrolls:
forvalues x = 2007/2016 {
	
	use"\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\BASES_COMUNES2\MINEDUC\Matricula_Ed_Superior/`x'/MATRICULA_EDUCACION_SUPERIOR_`x'_INN", clear
	rename numero_documento_inn mrun
	format mrun %20.0f
	destring codigo_demre, replace
	destring mrun, replace
	replace tipo_inst_1 = lower(tipo_inst_1)
	replace nivel_global = lower(nivel_global)
	keep if strpos(nivel_global, "pregrado") > 0
	
	*rename anio_ing_carr_ori anio_mat_pri_anio
	*rename anio_ing_carr_act anio_ing_carrera
	
	*--- Identify students completing high school in t-1:
	gen anio_mat_pri_anio=`x'
	merge m:1 mrun using "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA\03_temp\all_students_ris.dta", keep(1 3) keepusing(año_egreso) nogen
	
	*--- Identify students taking the psu the same year
	merge m:1 mrun using "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA\03_temp\01_psu_ris\psu_`x'.dta", keep(1 3)
	
	*--- Keep if student completed high school in t-1 or if s/he took the psu for this process
	keep if anio_mat_pri_anio == año_egreso + 1 | _merge == 3
	drop _merge 
	*destring anio_mat_pri_anio anio_ing_carrera, replace
	*keep if anio_mat_pri_anio == `x' | anio_ing_carrera == `x'	
	
	*--- Keep best institution in which student is enrolled
	tab tipo_inst_1, gen(inst_)	
	bys mrun: egen cft = max(inst_1)
	bys mrun: egen ip  = max(inst_2)
	bys mrun: egen uni = max(inst_3)
	bys mrun: gen N = _N
	drop if N > 1 & cft == 1 & ip + uni >= 1
	drop if N > 1 & ip == 1  & uni >= 1
	drop N cft ip uni inst_*
	
	*--- Keep institution with demre code: 
	gen aux  = codigo_demre !=. 
	bys mrun: egen demre = max(aux) 
	bys mrun: gen N = _N
	drop if N > 1 & demre == 1 & codigo_demre ==.
	drop aux demre N
	
	*--- Drop mrun:
	duplicates drop mrun, force 
	
	*--- Keep only relevant variables: 	
	** No se cuenta con acreditación.
	** No se cuenta en esta base con área de carrera genérica ni área del conocimiento.
	
	keep mrun tipo_inst_1 cod_inst nomb_inst nivel_global nomb_carrera codigo_demre area_carrera_generica valor_arancel anio_mat_pri_anio area_conocimiento cod_sede nomb_sede
	
	
	foreach var of varlist nomb_inst nomb_carrera area_carrera_generica {
		replace `var' = lower(`var') 
		replace `var' = subinstr(`var', "á", "a", .)
		replace `var' = subinstr(`var', "é", "e", .)
		replace `var' = subinstr(`var', "í", "i", .)
		replace `var' = subinstr(`var', "ó", "o", .)
		replace `var' = subinstr(`var', "ú", "u", .)
		replace `var' = subinstr(`var', "ñ", "n", .)
		replace `var' = subinstr(`var', "ö", "o", .)
		replace `var' = subinstr(`var', "ü", "u", .)
		
		replace `var' = subinstr(`var', "Á", "a", .)
		replace `var' = subinstr(`var', "É", "e", .)
		replace `var' = subinstr(`var', "Í", "i", .)
		replace `var' = subinstr(`var', "Ó", "o", .)
		replace `var' = subinstr(`var', "Ú", "u", .)
		replace `var' = subinstr(`var', "Ñ", "n", .)
		replace `var' = subinstr(`var', "Ö", "o", .)
		replace `var' = subinstr(`var', "Ü", "u", .)
	}
	
	gen enrolls_he  = 1
	gen enrolls_uni = strpos(tipo_inst_1, "universidad") == 1
	gen año_proceso = `x'
	
	rename codigo_demre codigo_carrera 
	drop if mrun ==.
	
	save "$temp/enrolls_mineduc`x'.dta", replace
}

clear 
forvalues x = 2007/2016 {
	append using "$temp/enrolls_mineduc`x'.dta"
	*erase "$temp/enrolls_mineduc`x'.dta"
}

save "$temp/enrolls_mineduc_2007_2016.dta", replace


use "$temp/enrolls_mineduc_2007_2016.dta", clear
merge 1:1 mrun año_proceso using "$temp/scores.dta", keep(1 3) keepusing(promlm_actual) nogen
replace promlm_actual = . if promlm_actual ==0

bys año_proceso cod_inst codigo_carrera: egen selectivity = mean(promlm_actual)
replace selectivity =. if codigo_carrera ==. 
bys año_proceso cod_inst nomb_carrera: egen aux0 = mean(promlm_actual)
bys año_proceso cod_inst area_carrera_generica: egen aux1 = mean(promlm_actual)

replace selectivity = aux0 if selectivity ==.
replace selectivity = aux1 if selectivity ==.

drop aux*
drop anio_mat_pri_anio

ren nomb_inst nomb_inst_mat
ren nomb_carrera nomb_carrera_mat
ren cod_sede cod_sede_mat
ren nomb_sede nomb_sede_mat
save "$temp/enrolls_mineduc.dta", replace

*--- Adding selectivity of "non-enrollment"
use "$temp/scores.dta", clear
merge 1:1 mrun año_proceso using "$temp/enrolls_mineduc.dta", keep(1) nogen keepusing(mrun)
replace promlm_actual =. if promlm_actual == 0
bys año_proceso: egen selectivity= mean(promlm_actual)
keep mrun año_proceso selectivity 
duplicates drop 
save "$temp/selectivity_noenroll.dta", replace


*-- (4) Applications -----------------------------------------------------------

forvalues x = 2007/2015 {
	
	use "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\BASES_COMUNES2\MINEDUC\PSU\Formulario_C/`x'/PSU_Formulario_C_`x'_innomi", clear
	rename nuevo_run_falso mrun
	if `x' == 2016 {
	replace puntaje = subinstr(puntaje, ",", "", .)
	destring puntaje, replace
	}
	
	save "$temp/applications`x'.dta", replace
	
	}

clear 
forvalues x = 2007/2015 {
	append using "$temp/applications`x'.dta", force
	*erase "$temp/applications`x'.dta"
}


*-- Regular cutoff
preserve 
keep if estado_preferencia == 24
destring puntaje, replace dpcomma
replace puntaje = puntaje/100 if puntaje > 10000
bys codigo_carrera año_proceso: egen cutoff_regular = min(puntaje)
keep codigo_carrera año_proceso cutoff_regular
duplicates drop 
save "$temp/cutoff_regular.dta", replace
restore

save "$temp/applications.dta", replace 

use "$temp/applications.dta", clear

foreach var of varlist nombre_carrera sede_carrera sigla_universidad {
		replace `var' = lower(`var') 
		replace `var' = subinstr(`var', "á", "a", .)
		replace `var' = subinstr(`var', "é", "e", .)
		replace `var' = subinstr(`var', "í", "i", .)
		replace `var' = subinstr(`var', "ó", "o", .)
		replace `var' = subinstr(`var', "ú", "u", .)
		replace `var' = subinstr(`var', "ñ", "n", .)
		replace `var' = subinstr(`var', "ö", "o", .)
		replace `var' = subinstr(`var', "ü", "u", .)
		
		replace `var' = subinstr(`var', "Á", "a", .)
		replace `var' = subinstr(`var', "É", "e", .)
		replace `var' = subinstr(`var', "Í", "i", .)
		replace `var' = subinstr(`var', "Ó", "o", .)
		replace `var' = subinstr(`var', "Ú", "u", .)
		replace `var' = subinstr(`var', "Ñ", "n", .)
		replace `var' = subinstr(`var', "Ö", "o", .)
		replace `var' = subinstr(`var', "Ü", "u", .)
	}
	
ren nombre_carrera nomb_carrera_post
ren sede_carrera sede_post
ren sigla_universidad sigla_post

save "$temp/applications.dta", replace 

** Recovering the university name.
use "$temp/applications.dta", clear
ren nomb_carrera_post carrera
merge m:1 año_proceso carrera codigo_carrera using "$temp/archivo_demre_full", keep (1 3) keepusing (nomb_inst_post)
ren carrera nomb_carrera_post
save "$temp/applications.dta", replace 
*--- (5) Recovering application scores -----------------------------------------
use "$temp/applications.dta", clear
keep if estado_preferencia == 24 | estado_preferencia == 25 | estado_preferencia == 26

rename (puntaje)(application_score)
destring application_score, replace dpcomma 
replace  application_score = application_score/100 if application_score> 10000

merge m:1 mrun año_proceso using "$temp/scores.dta", keepusing(ptje_nem ptje_ranking lyc_actual mate_actual hycs_actual ciencias_actual promlm_actual bea lyc_anterior mate_anterior hycs_anterior ciencias_anterior promlm_anterior first bea) keep(1 3) nogen

*generate bea1 = bea == "BEA" | bea_app == "BEA"
*drop bea bea_app

merge m:1 codigo_carrera año_proceso using "$temp/weights_2004_2016.dta", keep(1 3) nogen 

gen app_score_actual   =. 
gen app_score_anterior =.

foreach process in "actual" "anterior" {	
	replace app_score_`process' = w_gpa*ptje_nem + w_rank*ptje_ranking + w_reading*lyc_`process' + w_math*mate_`process' + w_history*hycs_`process' + w_science*ciencias_`process' if choose_hist_science=="NO" & lyc_`process' >= 150 & lyc_`process' <= 850 & mate_`process' >= 150 & mate_`process' <= 850
	replace app_score_`process' = w_gpa*ptje_nem + w_rank*ptje_ranking + w_reading*lyc_`process' + w_math*mate_`process' + w_history*max(hycs_`process', ciencias_`process') if choose_hist_science=="SI" & lyc_`process' >= 150 & lyc_`process' <= 850 & mate_`process' >= 150 & mate_`process' <= 850
}

generate app_score = application_score  if application_score != 0 
replace  app_score = app_score_actual   if application_score == 0 & app_score_actual != 0 & app_score_actual != .
replace  app_score = app_score_anterior if application_score == 0 & app_score_anterior != 0 & app_score_anterior != .

save "$temp/applications.dta", replace


*--- (7) Compute next-best option (for all students) ---------------------------
use "$temp/applications.dta", clear
merge m:1 codigo_carrera año_proceso using "$temp/cutoff_regular.dta", nogen keep(1 3)
*drop if bea1 == 1

*--- Fix admission status considering special admission:
keep mrun año_proceso preferencia codigo_carrera estado_preferencia app_score cutoff_regular
rename app_score application_score

*Keep first application
bysort mrun (año_proceso): egen first_año = min(año_proceso)
keep if año_proceso == first_año


reshape wide codigo_carrera estado_preferencia application_score cutoff_regular, i(mrun) j(preferencia)


*--- Next best option:
*--- Preference status = 25 (waiting list): if student is on the waiting list on 
*--- preference x, then assign as next best option the first one in which he/she 
*--- would have been admitted:
forvalues x = 1/9 {
	
	local z = `x' + 1
	gen nb_`x' =. 
	
	forvalues y = `z'/10 {
		replace nb_`x' = codigo_carrera`y' if estado_preferencia`x' == 25  & nb_`x' ==. & application_score`y' !=. & (estado_preferencia`y' == 24)
	}
}
   
*--- Preference status = 24 (admitted): if student is admitted to preference x, 
*--- then assign as next best option the first one in status 26 in which he/she 
*--- would have been admitted:   
forvalues x = 1/9 {
	
	local z = `x' + 1
	forvalues y = `z'/10 {
		replace nb_`x' = codigo_carrera`y' if estado_preferencia`x' == 24 & nb_`x' ==. & application_score`y' !=. & ( application_score`y' >= cutoff_regular`y')
	}
}   

reshape long codigo_carrera estado_preferencia application_score cutoff_regular nb_, i(mrun) j(preferencia)
rename nb_ nb
drop if codigo_carrera ==. 
keep if estado_preferencia == 24 | estado_preferencia == 25
save "$temp/all_applicants_nb.dta", replace

*--- Characterize applications -------------------------------------------------
*--- (1) Selectivity -----------------------------------------------------------
*-- Selectivity for admitted guys:
use "$temp/applications.dta", clear
merge m:1 mrun año_proceso using "$temp/scores.dta", keepusing(promlm_actual) keep(1 3) nogen
keep if estado_preferencia == 24 
bys año_proceso codigo_carrera: egen avg_selectivity = mean(promlm_actual)
bys año_proceso codigo_carrera: egen p50_selectivity = pctile(promlm_actual), p(50)
keep año_proceso codigo_carrera avg_selectivity p50_selectivity
duplicates drop
save "$temp/selectivity_app.dta", replace


*-- Add missing category selectivity:
use "$temp/applications.dta", clear
merge m:1 mrun año_proceso using "$temp/scores.dta", keepusing(promlm_actual) keep(1 3) nogen
gen adm = estado_preferencia == 24
bys mrun año_proceso: egen admitted = max(adm)
drop if admitted == 1
drop adm admitted
replace promlm_actual = . if promlm_actual ==.
bys año_proceso: egen avg_selectivity = mean(promlm_actual)
bys año_proceso: egen p50_selectivity = pctile(promlm_actual), p(50)
keep año_proceso codigo_carrera avg_selectivity p50_selectivity
replace codigo_carrera =.
duplicates drop 
append using  "$temp/selectivity_app.dta"
save "$temp/selectivity_app.dta", replace

*--- Add information and compute deltas:
use "$temp/all_applicants_nb.dta", clear
merge m:1 año_proceso codigo_carrera using "$temp/selectivity_app.dta", keepusing(avg_selectivity p50_selectivity) keep(1 3) nogen 
renvarlab avg_selectivity p50_selectivity, prefix(t_)

rename(codigo_carrera nb)(t_codigo_carrera codigo_carrera)
merge m:1 año_proceso codigo_carrera using "$temp/selectivity_app.dta", keepusing(avg_selectivity p50_selectivity) keep(1 3) nogen 
renvarlab codigo_carrera avg_selectivity p50_selectivity, prefix(nb_)

gen delta_avg_selectivity = (t_avg_selectivity - nb_avg_selectivity)/10
gen delta_p50_selectivity = (t_p50_selectivity - nb_p50_selectivity)/10

*--- Add outcomes
*--- Characeristics of program in which the student enrolls:
merge m:1 mrun año_proceso using "$temp/enrolls_mineduc.dta", keepusing(valor_arancel codigo_carrera enrolls_he enrolls_uni selectivity nomb_inst_mat nomb_carrera_mat area_conocimiento area_carrera_generica) keep(1 3) nogen
ren area_conocimiento area_conocimiento_mat
ren area_carrera_generica area_carrera_generica_mat
foreach var of varlist enrolls_he enrolls_uni {
	
	replace `var' = 0 if `var' ==. 
}

merge m:1 mrun año_proceso using "$temp/selectivity_noenroll.dta", keepusing(selectivity) keep(1 3) update nogen
gen enrolls_target = t_codigo_carrera == codigo_carrera
replace selectivity = selectivity/10
destring valor_arancel, replace



*--- Characteristics of programs from which students graduate:
merge m:1 mrun using "$temp/11_tit.dta", keep(1 3) keepusing(año_tit area_carrera_generica_t graduate collegue_graduate nomb_inst_t nomb_sede_t nomb_carrera_t) nogen 

foreach var of varlist nomb_inst_t nomb_sede_t nomb_carrera_t area_carrera_generica_t {
		replace `var' = lower(`var') 
		replace `var' = subinstr(`var', "á", "a", .)
		replace `var' = subinstr(`var', "é", "e", .)
		replace `var' = subinstr(`var', "í", "i", .)
		replace `var' = subinstr(`var', "ó", "o", .)
		replace `var' = subinstr(`var', "ú", "u", .)
		replace `var' = subinstr(`var', "ñ", "n", .)
		replace `var' = subinstr(`var', "ö", "o", .)
		replace `var' = subinstr(`var', "ü", "u", .)
		
		replace `var' = subinstr(`var', "Á", "a", .)
		replace `var' = subinstr(`var', "É", "e", .)
		replace `var' = subinstr(`var', "Í", "i", .)
		replace `var' = subinstr(`var', "Ó", "o", .)
		replace `var' = subinstr(`var', "Ú", "u", .)
		replace `var' = subinstr(`var', "Ñ", "n", .)
		replace `var' = subinstr(`var', "Ö", "o", .)
		replace `var' = subinstr(`var', "Ü", "u", .)
	}

***

save base_provisoria_act.dta, replace	

*** Adding nomb_carrera_post:

use archivo_demre_full.dta, clear
ren codigo_carrera t_codigo_carrera
ren carrera nomb_carrera_post
save archivo_demre_full_target.dta, replace


************************************************************
************************************************************

use base_provisoria_act.dta, clear
merge m:1 año_proceso t_codigo_carrera using archivo_demre_full_target.dta, keep (1 3) keepusing(nomb_carrera_post nomb_inst_post)

***-- New variables:
gen grad_target = ///
(nomb_inst_post == nomb_inst_t & nomb_carrera_post == nomb_carrera_t)

gen new_enrolls_target = ///
(t_codigo_carrera == codigo_carrera) | ///
(nomb_inst_mat == nomb_inst_post & nomb_carrera_mat == nomb_carrera_t)



foreach var of varlist graduate collegue_graduate {
	
	replace `var' = 0 if `var' ==. 
}




foreach var of varlist graduate collegue_graduate {
	
	forvalues x = 4/10 {
		
		local y = `x' + 1
		gen `var'`y' = `var' == 1 & año_tit - año_proceso <= `x'
	}
}


*** Similar to target degree?

foreach var of varlist new_enrolls_target grad_target {
	
	replace `var' = 0 if `var' ==. 
}




foreach var of varlist grad_target{
	
	forvalues x = 4/10 {
		
		local y = `x' + 1
		gen `var'`y' = `var' == 1 & año_tit - año_proceso <= `x'
	}
}


*--- Salary and employment:
drop _merge
**-- Merge with AFC.
merge m:1 mrun using "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA\03_temp\base_renta_cuentas_full.dta", keepusing(rem2008-rem2024 emp2008-emp2024) keep(1 3) 

*--- Merge with AFP.
merge m:1 mrun using "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA\03_temp\afp_full.dta", keep(1 3) nogen


*--- Update and generate new outcomes:	
egen non_missing = rownonmiss(rem2008 rem2009 rem2010 rem2011 rem2012 rem2013 rem2014 rem2015 rem2016 rem2017 rem2018 rem2019 rem2020 rem2021 rem2022 rem2023 rem2024)
gen afc_account = non_missing != 0
drop non_missing 

egen non_missing = rownonmiss(rem2014_AFP rem2015_AFP rem2016_AFP rem2017_AFP rem2018_AFP rem2019_AFP rem2020_AFP rem2021_AFP rem2022_AFP rem2023_AFP rem2024_AFP)
gen afp_account = non_missing != 0
drop non_missing 

*--- Replace by 0 observations with no AFC account and with no AFP cotization:
foreach var of varlist rem* emp* {
		replace `var' = 0 if `var' ==. 
}

*--- Generate variables to study earnings and employment after HS:
*--- Using data from AFC:
forvalues x = 1/17 {		
	gen earnings`x' = 0
	gen employment`x' = 0
}	

forvalues y = 2008/2024 {		
	
	forvalues x = 1/17{
		replace earnings`x'   = rem`y' if `y' - año_proceso == (`x'-1)  
		replace employment`x' = emp`y' if `y' - año_proceso == (`x'-1)
	}
}

*--- Using data from AFP (The AFP dataset begins in 2014, 7 years after the first 2007 cohort).
forvalues x = 7/17 {		
	gen earningsAFP`x' = 0
	gen employmentAFP`x' = 0
}	
forvalues y = 2014/2024 {		
	
	forvalues x = 7/17{
		replace earningsAFP`x'   = rem`y'_AFP if `y' - año_proceso == (`x'-1)  
		replace employmentAFP`x' = emp`y'_AFP if `y' - año_proceso == (`x'-1)
	}
}	


/*
cd "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA\03_temp"
save base_provisoria.dta, replace

use base_provisoria.dta, clear
*/


replace earningsAFP7 = earningsAFP7/(12*0.1)
replace earningsAFP8 = earningsAFP8/(12*0.1)
replace earningsAFP9 = earningsAFP9/(12*0.1)
replace earningsAFP10 = earningsAFP10/(12*0.1)
replace earningsAFP11= earningsAFP11/(12*0.1)
replace earningsAFP12 = earningsAFP12/(12*0.1)
replace earningsAFP13 = earningsAFP13/(12*0.1)
replace earningsAFP14 = earningsAFP14/(12*0.1)
replace earningsAFP15 = earningsAFP15/(12*0.1)
replace earningsAFP16 = earningsAFP16/(12*0.1)
replace earningsAFP17 = earningsAFP17/(12*0.1)

egen earningsTot7   = rowmax(earnings7 earningsAFP7)
egen earningsTot8   = rowmax(earnings8 earningsAFP8)
egen earningsTot9   = rowmax(earnings9 earningsAFP9)
egen earningsTot10   = rowmax(earnings10 earningsAFP10)
egen earningsTot11   = rowmax(earnings11 earningsAFP11)
egen earningsTot12   = rowmax(earnings12 earningsAFP12)
egen earningsTot13   = rowmax(earnings13 earningsAFP13)
egen earningsTot14   = rowmax(earnings14 earningsAFP14)
egen earningsTot15   = rowmax(earnings15 earningsAFP15)
egen earningsTot16   = rowmax(earnings16 earningsAFP16)
egen earningsTot17   = rowmax(earnings17 earningsAFP17)


/*
*--- Combine both variables (revisar, dado que AFP comienza después. Además, la información es sobre el 10% del salario total en AFP (¿dividir en 0,1?)):
forvalues x = 7/17{
		gen aux1 = earningsAFP`x'/(12*0.1)
		gen aux2 = employmentAFP`x'/(12*0.1)
		egen earningsTot`x'   = rowmax(earnings`x' aux1)
		egen employmentTot`x' = rowmax(employment`x' aux2)
		drop aux1 aux2 
}
*/
*--- Running variable 

gen  score_rd = application_score - cutoff_regular
generate above_cutoff = score_rd >= 0 & score_rd !=.


*** Change 1: keep only those waiting list==25.
	*cd "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA\03_temp"
*use base_provisoria.dta, clear
drop _merge
merge m:1 año_proceso t_codigo_carrera using "${temp}\base_waiting_list.dta"
keep if _merge==3

****---- Generate new deltas selectivity:
gen delta_sel = 1 if delta_avg_selectivity <-10 & nb_codigo_carrera!=.
replace delta_sel = 2 if delta_avg_selectivity >= -10  & delta_avg_selectivity <15 & nb_codigo_carrera!=.
replace delta_sel = 3 if delta_avg_selectivity >= 15  & delta_avg_selectivity <40 & nb_codigo_carrera!=.
replace delta_sel = 4 if delta_avg_selectivity >= 40  & delta_avg_selectivity <70 & nb_codigo_carrera!=.
replace delta_sel = 5 if delta_avg_selectivity >= 70 & nb_codigo_carrera!=.
replace delta_sel = 6 if nb_codigo_carrera ==.

**-- Generamos la nueva running con el cambio de escala de los puntajes ponderados:

gen application_score_2=floor(application_score*100)
gen cutoff_regular_2=floor(cutoff_regular*100)
gen score_rd_2=application_score_2-cutoff_regular_2
gen above_cutoff_2 = score_rd_2>=0 & score_rd_2!=. 

**- Base final:
cd "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA\03_temp"
save base_returns_act.dta, replace

********************************************************
********************************************************

**-- Recovering area conocimiento:

cd "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA\03_temp"
use base_returns_act.dta, clear
cap drop _merge
cap drop area_conocimiento_t
merge m:1 t_codigo_carrera using base_conocimiento_all.dta, keep (1 3) keepusing (area_conocimiento)
ren area_conocimiento area_conocimiento_target
save base_returns_act.dta, replace

** For next best option:
use base_conocimiento_all.dta, clear
ren t_codigo_carrera nb_codigo_carrera
save base_conocimiento_nb.dta, replace


** Merge:
use base_returns_act.dta, replace
cap drop _merge
cap drop area_conocimiento_nb
cap drop area_conocimiento
merge m:1 nb_codigo_carrera using base_conocimiento_nb.dta, keep (1 3) keepusing (area_conocimiento)
ren area_conocimiento area_conocimiento_nb
save base_returns_actualizada.dta, replace


*****--- New variables:

use base_returns_actualizada.dta, clear
gen same_area=0
replace same_area=1 if area_conocimiento_target==area_conocimiento_nb
save base_returns_actualizada.dta, replace

***** New graphs.
cd "${temp}"
use base_returns_actualizada.dta, clear



*uch_puc == 1 ya que incluye uch_puc==1 en target y uch_puc==0 en nb, por eso no la repito.
cap ren UCH_PUC uch_puc
gen carrera_uni_elite =0
replace carrera_uni_elite=1 if uch_puc==1 & carrera_elite_target==1 & (carrera_elite_nb!=1) 

save base_returns_actualizada.dta, replace

cd "${temp}"
use base_returns_actualizada.dta, clear

** Same area: check
cap drop uch_puc
gen uch_puc=0
** Es 1 si su post es UCH o PUC pero su next best no es ni UCH ni PUC.
replace uch_puc=1 if (nomb_inst_post== "pontificia universidad catolica de chile" | nomb_inst_post== "universidad de chile") & (nomb_inst_post_nb!="pontificia universidad catolica de chile" & nomb_inst_post_nb!="universidad de chile")
**UCH_PUC: check

drop carrera_elite_target
drop carrera_elite_nb

gen carrera_elite_target = 0 

replace carrera_elite_target =1 if strpos(lower(nomb_carrera_post), "ingenieria") > 0
replace carrera_elite_target =1 if strpos(lower(nomb_carrera_post), "medicina") > 0 
replace carrera_elite_target =1 if strpos(lower(nomb_carrera_post), "derecho") > 0
replace carrera_elite_target =1 if strpos(lower(nomb_carrera_post), "ingenieria comercial") > 0 
replace carrera_elite_target =0 if strpos(lower(nomb_carrera_post), "veterinaria") > 0

gen carrera_elite_nb = 0

replace carrera_elite_nb =1 if strpos(lower(carrera_nb), "ingenieria") > 0
replace carrera_elite_nb =1 if strpos(lower(carrera_nb), "medicina") > 0
replace carrera_elite_nb =1 if strpos(lower(carrera_nb), "derecho") > 0
replace carrera_elite_nb =1 if strpos(lower(carrera_nb), "ingenieria comercial") > 0
replace carrera_elite_nb =0 if strpos(lower(carrera_nb), "veterinaria") > 0


save base_returns_actualizada.dta, replace
*****************************************************************************
*****************************************************************************
