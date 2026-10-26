#!/bin/bash
# Program VA pipeline (issue #9). Run from project root on the server.
# Usage: bash code/ProgramVA/run_all.sh [first_script]   (default: start at 01)
# Stata batch exit codes are unreliable: stop on the first r(...) error in a log.
scripts="01_build_feasibility 01b_build_income_rank 01c_build_vacancies_2007_2025 02_estimate_va 03_va_correlates 04_diagnostics_figures 04b_split_sample"
start=${1:-01_build_feasibility}
go=0
for s in $scripts; do
    [ "$s" = "$start" ] && go=1
    [ $go -eq 0 ] && continue
    /usr/local/stata17/stata-mp -b do code/ProgramVA/$s.do
    if grep -qE "^r\([0-9]+\);" $s.log; then
        echo "ERROR in $s"; grep -nE -B5 "^r\([0-9]+\);" $s.log | tail -15; exit 1
    fi
    echo "done $s"
done
