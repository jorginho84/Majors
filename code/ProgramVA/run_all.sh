#!/bin/bash
# Program VA pipeline (issue #9). Run from project root on the server.
# Stata batch exit codes are unreliable: stop on the first r(...) error in a log.
for s in 01_build_feasibility 01b_build_income_rank 02_estimate_va 03_va_correlates; do
    /usr/local/stata17/stata-mp -b do code/ProgramVA/$s.do
    if grep -qE "^r\([0-9]+\);" $s.log; then
        echo "ERROR in $s"; grep -nE -B5 "^r\([0-9]+\);" $s.log | tail -15; exit 1
    fi
    echo "done $s"
done
