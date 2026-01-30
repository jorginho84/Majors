
*---- Figures about graduation (any institution, university and graduation in target).

*---- Hugo Salgado Morales.
*----- Last modification: 30th December, 2025.

clear all
*--- Globals -------------------------------------------------------------------
global root "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA"
global data "$root/01_data"
global code "$root/02_code"
global temp "$root/03_temp"
*global results "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\02_RESULTADOS\20251205"
** Actualizar con fecha de última extracción.
global figures "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\RIS_INVESTIGACION_8\03_EFECTOS_POLITICAS\03_EDITABLES\01_DATOS_SALIDA\02_codes\majors\Figures"

** Optimal bandwidht para todas las regresiones
global b_bwr_opt 25


cd "${temp}"
use base_returns_actualizada.dta, clear
cap ren UCH_PUC uch_puc


*** Center distribution 
	*(1) Compute max negative value:
	gen aux = score_rd if score_rd < 0 
	egen max_min_izq = max(aux)
	drop aux
	*(2) Compute min positive value:
	gen aux = score_rd if score_rd > 0 
	egen min_max_der = min(aux)
	drop aux
	*(3) Gen new variable for figures:
	gen score_rd2 = score_rd + abs(max_min_izq)  if score_rd < 0
	replace score_rd2 = score_rd - min_max_der if score_rd > 0		

	*label variable p75_adm "Enrollment on top 25% quality program"
	*label variable dummy_top_inc "Enrollment on top 25% income program"
	tab año_proceso, gen(yr_)

********************************************************************************
*** Program to generate reduced form plots (all sample and deltas).
********************************************************************************

program drop _all

capture program drop reduced_form_plot
program define reduced_form_plot

  args o x rv iv band1 band2 bw1 bw2 bin1 bin2 restrictions cluster yfe yfeb rv2 file_name delta
  
*** Locals:
	local if "`rv' >= -`bw1' & `rv' <= `bw2' `restrictions' & (2022 - año_proceso>=8)"
	
	if "`delta'" != "all" {
	local if "`if' & delta_sel==`delta'"
	}
	local vtext1: variable label `o'
	local vtext2: variable label `iv'

  if `yfeb' == 6 local years "yr_2 yr_3 yr_4 yr_5 yr_6"
  if `yfeb' == 9 local years "yr_2 yr_3 yr_4 yr_5 yr_6 yr_7 yr_8 yr_9"
  if `yfeb' == 15 local years "yr_2 yr_3 yr_4 yr_5 yr_6 yr_7 yr_8 yr_9 yr_10 yr_11 yr_12 yr_13 yr_14 yr_15"

	*** Remove years noise:
	reghdfe `o'  if `o' !=. & `if' , absorb(i.`cluster'#i.`yfe')  residuals 
	predict `o'2, residuals
	local b_cons = _b[_cons]

	sum `o' if `o' !=. & `rv' >=-0.05 & `rv' < 0 & `if'

	replace `o'2 = `o'2 + `b_cons'
	local nbins1 = round(`bw1'/`bin1')
	local nbins2 = round(`bw2'/`bin2')

  *** Generate bins:
	#delimit;
	rdplot `o'2 `rv' if `if' , c(0) p(`x')
	nbins(`nbins1' `nbins2')  kernel(uniform)
	h(`band1' `band2') support(`band1' `band2') hide genvars;
	#delimit cr;

	bys rdplot_mean_y: gen bin_id = _n


  *** Define parameters for chart:
	sum rdplot_mean_y
	local lb = round(r(min),0.05) - 0.05
	local ub = 1
	local xl = 0
	local yl = `ub' - 0.175
	local gap = 0.05
	local bin_gap =`bin1'*2
	
	
	
	*** Decimales aproximados 
	local bw1_formatted : display round(`bw1', 0.001)
	local bw2_formatted : display round(`bw2', 0.001)


 *** RD regression: Degree 1
	

	
	if `x' == 1{
	reghdfe `o' `iv' `rv' 1.`iv'#c.`rv' if abs(score_rd) <= 25 & `if', absorb(i.`cluster'#i.`yfe')
	local a1 = round(_b[`iv'], 0.001)
	local a2 = round(_se[`iv'], 0.001)
	local a3 = `a1'*10
	local my_text1 "ß = `a1' (`a2')"
	di "`my_text1'"
	}
	
	
	if `x' == 2{
		
	reghdfe `o' `iv' `rv' 1.`iv'#c.`rv'  c.`rv'#c.`rv' 1.`iv'#c.`rv'#c.`rv' if  abs(score_rd)<= `band1', cluster(i.`cluster'#i.`yfe') absorb(`cluster' `yfe')
	local a1 : display %6.2f _b[`iv']
	local a2 = display %6.2f _se[`iv']
	local my_text1 "ß = `a1' (`a2')"

	}
	/* Esto tenía el código antes cuando graficaba los intervalos de confianza. Se cambio por qfit
	(lfitci `o'2 `rv2' if `rv2' <  0 ,  ciplot(rline)   lcolor(red))
	(lfitci `o'2 `rv2' if `rv2' >= 0 ,  ciplot(rline)   lcolor(red))
		*/

	if `x' == 1{
		#delimit;
		twoway (histogram `rv2',  yaxis(2) width(`bin1') start(-`bw1') frequency fintensity(40) fcolor(edkblue) lwidth(none))
		(lfit `o'2 `rv2' if `rv2' <  0 ,  estopts(vce(cluster `cluster')) lcolor(red))
		(lfit `o'2 `rv2' if `rv2' >= 0 , estopts(vce(cluster `cluster')) lcolor(red))
		(scatter rdplot_mean_y rdplot_mean_x if bin_id == 1, sort  mcolor(navy) msize(vsmall) msymbol(circle) text(`yl' 0.01 "`my_text1'", place(e) size(medium) color(black)))
		(scatteri `xl' 0 `ub' 0, recast(line) lpattern(dash) lcolor(black))
		if `o' !=. & `if',
		ytitle("`vtext1'") ytitle(, size(medsmall) orientation(rvertical))
		yscale(range(`xl' `ub')) ylabel(`xl'(`gap')`ub', labels labsize(small) labcolor(black) angle(horizontal) format(%9.0gc))
		ytitle(Frequencies, axis(2)) ytitle(, size(medsmall) axis(2))
		ylabel(, labsize(small) angle(horizontal) format(%9.0gc) axis(2))
		xline(0, lpattern(dash) lcolor(black))
		xtitle("`vtext2'") xtitle(, size(medsmall))
		xlabel(-`bw1_formatted'(`bin_gap')`bw2_formatted', labsize(small))
		legend(off)
		scale(1.3)
		plotregion(lcolor(black) lwidth(thin));
		#delimit cr
	}
	
   if `x' == 2 {


		#delimit;
		twoway (histogram `rv2', yaxis(2) width(`bin1') start(-`bw1') frequency fintensity(40) fcolor(edkblue) lwidth(none))
		(qfit `o'2 `rv2' if `rv2' <  0 ,  estopts(vce(cluster `cluster')) lcolor(red))
		(qfit `o'2 `rv2' if `rv2' >= 0 , estopts(vce(cluster `cluster')) lcolor(red))
		(scatter rdplot_mean_y rdplot_mean_x if bin_id == 1 , sort  mcolor(navy) msize(vsmall) msymbol(circle) text(`yl' 0.01 "`my_text1'", place(e) size(medium) color(black))	
		text(100 0 "`my_text1'", place(e) size(small) color(black)))
		(scatteri `xl' 0 `ub' 0, recast(line) lpattern(dash) lcolor(black))
		if `o' !=. & `if',
		ytitle("`vtext1'") ytitle(, size(medsmall) orientation(rvertical))
		yscale(range(`xl' `ub')) ylabel(`xl'(`gap')`ub' , labels labsize(small) labcolor(black) angle(horizontal) format(%9.0gc))
		ytitle(Frequencies, axis(2)) ytitle(, size(medsmall) axis(2))
		ylabel(, labsize(small) angle(horizontal) format(%9.0gc) axis(2))
		xtitle("`vtext2'") xtitle(, size(medsmall))
		xlabel(-`bw1_formatted'(`bin_gap')`bw2_formatted', labsize(small))
		legend(off)
		scale(1.3)
		plotregion(lcolor(black) lwidth(thin));
		#delimit cr

	}


	drop rdplot_id rdplot_mean_x rdplot_mean_y rdplot_ci_l rdplot_ci_r bin_id rdplot_N rdplot_min_bin rdplot_max_bin rdplot_mean_bin rdplot_se_y rdplot_hat_y `o'2
	cd "${figures}"
	graph save   "`file_name'.gph",replace
	graph export "`file_name'_delta`delta'.pdf",replace as(pdf)

end

* Figure 3: graduate in any institution.
reduced_form_plot graduate8 1 score_rd above_cutoff ${b_bwr_opt} ${b_bwr_opt} 25 25 5 5 " " año_proceso t_codigo_carrera 9 score_rd2 "Higher_education_completition_8_years_after_applying" all

foreach d in 1 2 3 4 5 6 {
* Figure 3 (deltas): graduate in any institution for deltas
reduced_form_plot graduate8 1 score_rd above_cutoff ${b_bwr_opt} ${b_bwr_opt} 25 25 5 5 " " año_proceso t_codigo_carrera 9 score_rd2 "Higher_education_completition_8_years_after_applying_delta`d'" `d'
}


* Figure 4: university degree completition.
reduced_form_plot collegue_graduate8 1 score_rd above_cutoff ${b_bwr_opt} ${b_bwr_opt} 25 25 5 5 " " año_proceso t_codigo_carrera 9 score_rd2 "University_degree_completition_8_years_applying" all


foreach d in 1 2 3 4 5 6 {
* Figure 4 (deltas): university degree completition for deltas
reduced_form_plot collegue_graduate8 1 score_rd above_cutoff ${b_bwr_opt} ${b_bwr_opt} 25 25 5 5 " " año_proceso t_codigo_carrera 9 score_rd2 "University_degree_completition_8_years_applying_delta`d'" `d'
}

* Figure 5: rd_grad_target.
reduced_form_plot grad_target 1 score_rd above_cutoff ${b_bwr_opt} ${b_bwr_opt} 25 25 5 5 " " año_proceso t_codigo_carrera 9 score_rd2 "Grad_in_target_degree" all

* Figure 6: rd_grad_target_8_years
reduced_form_plot grad_target8 1 score_rd above_cutoff ${b_bwr_opt} ${b_bwr_opt} 25 25 5 5 " " año_proceso t_codigo_carrera 9 score_rd2 "Grad_in_target_degree_8_years" all




