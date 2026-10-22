# Project to-dos

## Open
- [ ] Send the labor market data request to the Ministry of Labor — created 2026-10-15 · status: In progress · missing: letter drafted, not yet sent
- [ ] Share the GitHub repo link with the full team — created 2026-10-15 · status: Not started
- [ ] Add a geographic-distance kernel to the Design III exposure measure — created 2026-10-15 · status: Not started
- [ ] Try a log-log specification for Design I — created 2026-10-15 · status: Not started
- [ ] Revisit the RDD framing to align with the high-return program narrative — created 2026-10-15 · status: Not started
- [ ] Review a Chris Walters-style reallocation paper — created 2026-10-15 · status: Not started

## Done
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
