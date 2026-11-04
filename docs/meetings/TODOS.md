# Project to-dos

## Open
- [ ] Send the labor market data request to the Ministry of Labor; review and submit the application — created 2026-10-15 · status: In progress · missing: draft proposal in `docs/mintrab/` (untracked), not yet sent; aim at 3+ years of coverage
- [ ] Share the GitHub repo link with the full team — created 2026-10-15 · status: Not started
- [ ] Add a geographic-distance kernel to the Design III exposure measure — created 2026-10-15 · status: Not started
- [ ] Revisit the RDD framing to align with the high-return program narrative — created 2026-10-15 · status: Not started
- [ ] Review a Chris Walters-style reallocation paper — created 2026-10-15 · status: Not started
- [ ] Run placebo checks on the characteristics of inframarginal students (PSU and SES vs. Z; completion on leads/lags t−3 to t+3) — created 2026-10-27 · issues #8, #10 · status: In progress · done: PSU/NEM balance (2026-10-20) and Z_t+1 lead placebo (2026-10-26, `38_design5_balance.do`) · missing: SES check, leads/lags t−3 to t+3
- [ ] Try alternative ROL groupings for Design V: OECD field (broad and sub-areas), university × field, field × selectivity bracket — created 2026-10-27 · issue #8 · status: Not started
- [ ] Re-run the value-added figures with institution-only fixed effects — created 2026-10-27 · issue #9 · status: Not started
- [ ] Add a motivating figure: program returns vs. average change in program size over 10–15 years — created 2026-10-27 · issue #9 · status: Not started
- [ ] Validate program VA within the RD bandwidth against RD jumps (tax-authority earnings as a possible source) — created 2026-10-27 · issue #9 · status: Not started
- [ ] Look up and compare the Mata–Viera value-added paper — created 2026-10-27 · status: Not started

## Done
- [x] Try a log-log specification for Design I (done as first differences of logs) — created 2026-10-15 · done 2026-10-19 · status: Done; slide "Design I: first differences of logs" (`35_design1_dlogs.do`). The levels with program FE and log-log version (issue #7) was dropped and its script and table removed.
- [x] Run the individual-level inframarginal design with application-portfolio (ROL) fixed effects (Design V) — created 2026-10-20 · done 2026-10-20 · issue #8 · status: Done; estimates and balance/placebo posted on the issue. Note: the placebo with next-year vacancies flags within-program trends, so how to absorb them is still open on #8.
  Original email that motivated it:
  > We are currently using program-level data, not individual-level outcomes, but I don't see why we can't run regressions at the individual level. Let Y_i = 1 if I graduates within 8 years
  >
  > Y_i = \beta_0 + \beta_1 n_{ipt} + x_{ipt}'\beta_2 + \phi_p + \phi_{ROL(i)} + eps_{ipt}
  > n_{ipt} = \alpha_0 + \alpha_1 Z_{ipt}  + x_{ipt}'\alpha_2 + \psi_p + \psi_{ROL(i)} + nu_{ipt}
  >
  > Here are some comparisons with inframarginal design 1:
  > It exploits the same variation--changes in Z_{ipt} over time within a program.
  > It allows us to control for more stuff that might affect graduation: individual-level covariates like PSU scores and SES, for example
  > If we include fixed effects for the application portfolio (\phi_{ROL(i)}) this arguably controls for preferences for college attendance. Among individuals who applied to the same set of schools, do the ones who attended when the cohort was larger graduate at lower rates?
  > There may be a timing assumption we can exploit. Because the 1st stage (2nd equation above) controls for \psi_p, the identifying variation is coming from changes in Z_{ipt} over time around the program's historic mean. If students know the historic mean, but they don't know the year-to-year variation when they apply (maybe vacancies are submitted to the mechanism after application) then variation in Z_{ipt} is likely to be exogenous.
  > This is a big regression with a lot of fixed effects. Maybe start with a 20% sample?
  > Make sure to cluster SEs by the year or program-year
  > We will want to estimate these on only the inframarginal students.

## Dropped
