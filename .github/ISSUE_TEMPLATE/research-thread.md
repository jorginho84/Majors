---
name: Research thread
about: Open one of these before exploring a new empirical question, then report progress as comments
title: "<short name of the design or question>"
labels: research
---

<!--
Convention for this repo: one issue per research thread, opened BEFORE writing code,
and used as the running record of that thread. See issue #1 for the reference example.
Delete any section that genuinely does not apply rather than leaving it empty.
-->

## Why this design exists

What problem with the existing approach are we escaping? Be concrete about the endogeneity,
measurement or power concern that makes this worth doing.

## The identifying event

What is the source of variation, and what exactly does it shift? Institutional detail matters
here — what changed, when, for whom, and what stayed the same.

State plainly what the instrument is: which part is the shock and which part is predetermined.

## Estimating equations

First stage, second stage, reduced form. Define every term.

- Fixed effects and what they absorb
- Sample restrictions, and why
- Expected sign of the first stage, and the economics behind that expectation
- What to lead with in the paper
- Inference: level of clustering, and any design-specific SE correction

## Data and construction

Which raw sources, which units, which years. How the key variables are built.

## Threats and their answers

| Threat | Answer |
|---|---|
| | |

Include the diagnostic or placebo that actually tests each one, not just the reassurance.

## Where this lives in the repo

Folder, run order, and a link to that folder's README if it has one.

## Open items

Split blockers from specification questions — blockers stop the work, specification
questions change what the estimate means.

**Blocking**

- [ ]

**Specification gaps**

- [ ]

---

<!--
As the work advances, add comments to this issue recording:
  - what was run, and on which data vintage
  - the estimates, with standard errors and N
  - what broke, and the fix
  - decisions taken and why (especially ones that change the estimand)
Update the checkboxes above as items close.
-->
