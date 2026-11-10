# Project to-dos

## Open
- [ ] Share the GitHub repo link with the full team — created 2026-10-15 · status: Not started
- [ ] Add a geographic-distance kernel to the Design III exposure measure — created 2026-10-15 · status: Not started
- [ ] Revisit the RDD framing to align with the high-return program narrative — created 2026-10-15 · status: Not started
- [ ] Review a Chris Walters-style reallocation paper — created 2026-10-15 · status: Not started
- [ ] Re-run the value-added figures with institution-only fixed effects — created 2026-10-27 · issue #9 · status: Not started
- [ ] Add a motivating figure: program returns vs. average change in program size over 10–15 years — created 2026-10-27 · issue #9 · status: Not started
- [ ] Validate program VA within the RD bandwidth against RD jumps (tax-authority earnings as a possible source) — created 2026-10-27 · issue #9 · status: Not started
- [ ] Look up and compare the Mata–Viera value-added paper — created 2026-10-27 · status: Not started
- [ ] Re-run the Design V balance table controlling for PSU score (and possibly PSU quantiles) — created 2026-11-10 · issue #10 · status: Not started
- [ ] Verify the balance table: program-year clustering, school-type shares that don't sum to 100%, units of the private-subsidized coefficient (14 pp?) — created 2026-11-10 · issue #10 · status: Not started
- [ ] Look up university financial statements from the Superintendencia de Educación Superior (revenue channel behind the T−1 graduation coefficient) — created 2026-11-10 · status: Not started
- [ ] Ask Agustín for program-level average earnings from Central Bank data (zeros included, up to ~10 years after enrollment, conditional on enrollment) — created 2026-11-10 · issues #9, #11 · status: Not started
- [ ] Update the team on the Ministry of Labor response — created 2026-11-10 · status: Not started

## Done
- [x] Send the labor market data request to the Ministry of Labor — created 2026-10-15 · closed 2026-11-10 · evidence: email sent to the Ministry contact before the 2026-11-10 meeting (`docs/meetings/2026-11-10.md`); proposal in `docs/mintrab/`
- [x] Run placebo checks on the characteristics of inframarginal students (PSU and SES vs. Z; leads/lags t−3 to t+3) — created 2026-10-27 · closed 2026-11-09 · issues #8, #10 · evidence: `40_design5_placebo.do` (`5fc0a8d`, `1626a2e`), `im_d5_placebo_balance.tex`, `im_d5_leadlag_*.pdf`
- [x] Try alternative ROL groupings for Design V — created 2026-10-27 · closed 2026-11-09 · issue #8 · evidence: `16b` + `41_design5_rol_groupings.do` (`5fc0a8d`); field-based groupings gave the same answer and were dropped in `1626a2e` in favor of a seven-definition ROL ladder (`im_d5_rolgroups*.tex`, `42_design5_balance_rolgroups.do`)
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
