/**********************************************************************
* 41b_design5_rol_groupings_trends.do
*
* Design V (issue #8): the ROL-groupings table of 41 with program-
* specific linear trends in every column (programs##c.ao_proceso, as
* in 39). 39 shows that the levels estimate on program graduation
* disappears with trends under Top 1 and exact ROLs; this checks the
* same under the other groupings.
*
*   columns, unit, n, Z, Y, x, FE, SE: as in 41, plus program trends
*
* Inputs:  as 41
* Outputs: output/inframarginal/tables/im_d5_rolgroups_trends.tex
*          output/inframarginal/tables/im_d5_rolgroups_trends.csv
**********************************************************************/

do "code/04_rdd/Inframarginals/41_design5_rol_groupings.do" trend
