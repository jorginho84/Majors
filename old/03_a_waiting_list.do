/*------------------------------------------------------------------------------
				
						   Papers about majors.
							
						  Hugo Salgado Morales
			
								
						    November 2nd, 2025
------------------------------------------------------------------------------*/

* Globals -------------------------------------------------------------------
global root "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA"
global data "$root/01_data"
global code "$root/02_code"
global temp "$root/03_temp"

* Waiting list -------------------------------------------------------------------

use "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\BASES_COMUNES2\MINEDUC\PSU\Formulario_C\2007\PSU_Formulario_C_2007_innomi", clear

forvalues x = 2007/2015 {
	
	use "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\BASES_COMUNES2\MINEDUC\PSU\Formulario_C/`x'/PSU_Formulario_C_`x'_innomi", clear
	rename numero_documento_inn mrun
	save "$temp/applications`x'.dta", replace
}

clear 
forvalues x = 2007/2015 {
	append using "$temp/applications`x'.dta"
}

gen aux = estado_preferencia==25
bys codigo_carrera año_proceso: egen wl = total(aux)
keep if wl> 0 & wl!=.
drop aux

collapse (first) wl, by (codigo_carrera año_proceso)
ren codigo_carrera t_codigo_carrera
cd "${temp}"
save base_waiting_list.dta, replace
	
	
	
	
	
	