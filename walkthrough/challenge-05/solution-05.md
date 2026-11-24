# Walkthrough Challenge 5 - Lab 5: Project Osmos

[Previous Challenge Solution](../challenge-04/solution-04.md) - **[Home](../../Readme.md)** - [Next Challenge Solution](../challenge-06/solution-06.md)

Duration: optional and untimed, after the session; outside the 45-minute
time box.

Based on the [specification](../../specs/bootcamp-lakehouse.spec.md) sections
1, 3, 8 and 9 and the fixed
[validator](../../labs/bootcamp/validate-lakehouse.py).

## Prerequisites

- A **fresh approved target** (spec section 9): a separate empty workspace on
  its own active capacity, so the replay never overwrites a completed live
  build. The lab automation provisions only each participant's live-build
  workspace; provide this second target by hand if you offer the lab.
- That target has reached the Lab 1 setup checkpoint (spec section 8):
  schema-enabled `lh_bootcamp`, five exact uploads, the empty `changes/`
  folder, four bound shells with fixed checks and an unscheduled serial
  pipeline.
- One workload at a time (spec section 3): nothing else writes to the target
  while the replay runs.

## Task 1: Bounded task

Project Osmos consumes LLM tokens as well as Spark compute, so it starts
bounded: one task in one workspace. Measure both, with the Microsoft Fabric
Capacity Metrics app for Spark and the Project Osmos consumption page for the
agent. On a shared capacity, on-demand (autoscale) billing bounds Spark compute,
not LLM tokens.

The replay keeps the same contracts, separate layer notebooks and fixed checks.
Every decision moment from spec section 1 still applies: no remote write or
job runs without its matching decision.

## Task 2: Expected result

The same fixed checks pass, in the same order as Labs 1-4:

- before the change file lands, each stage prints
  `PASS: bootcamp <stage> contract, initial load (fixed read-only checks)`;
- after the pipeline run, each stage prints
  `PASS: bootcamp <stage> contract, after the customer change batch (fixed read-only checks)`;
- Bronze, Silver and Gold also print either
  `PASS: bootcamp <stage> was built or brought to contract by this run` or
  `PASS: bootcamp <stage> was already current and the rerun changed nothing`.
  MLV prints its contract PASS and row counts only.

The `rows validated` lines match those in the walkthroughs for Challenges 1-4,
for example the [Challenge 4 walkthrough](../challenge-04/solution-04.md)
after the batch. History, facts,
keys and all ten watermarks meet the same contract; both real MLVs pass with
seven reconciled groups and the current customers, and lineage is inspected.

## What to look for

- Real bounded change-feed reads, version ranges and watermark ordering, not
  only matching counts: matching values do not prove CDF consumption.
- MLV DDL from `SHOW CREATE MATERIALIZED LAKE VIEW` and Fabric lineage: a
  successful create does not prove incremental refresh.
- Layer isolation: each of the four notebooks writes only its own layer and
  keeps the fixed validator, baseline and check cells unchanged.
- Anything unsupported or incomplete is labelled as such.

## Recovery

The same rules as Labs 1-4: fix generated code, never the spec, fixtures,
checks or expected values; stop on a CDF retention gap or an unsupported MLV
feature; stop the sessions started for the exercise.
