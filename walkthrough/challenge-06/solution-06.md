# Walkthrough Challenge 6 - Lab 6: Semantic model and Fabric IQ

[Previous Challenge Solution](../challenge-05/solution-05.md) - **[Home](../../Readme.md)**

Duration: optional and untimed, after the session; outside the 45-minute
time box.

Based on the [specification](../../specs/bootcamp-lakehouse.spec.md) sections
6, 7 and 9.

## Prerequisites

- Completed Gold and MLV checks, including the change batch
  ([Challenge 4 walkthrough](../challenge-04/solution-04.md)).
- Authoring, licensing and client capabilities are discovered first (spec
  section 9). Creating a Power BI semantic model in a workspace on an F2 needs a
  Power BI Pro license; the lab automation's `M365-E5-Users` group normally
  provides it through Microsoft 365 E5. The participant's Contributor role can
  create the model item. Missing access or features are incomplete outcomes,
  not permission to change infrastructure or invent results.

## Task 1: Approve the model before creation

Gold stays read-only. Only the participant-approved semantic-model item may be
created; no report is required. Check the proposal against spec section 9:

- Direct Lake is preferred.
- If the model includes customer history, `fact_sales.customer_sk` relates to
  the unique `dim_customer.customer_sk`, never to the repeated `customer_id`,
  so as-of customer attributes are preserved.
- The participant approves the proposed model and its measures before anything
  is created.

## Task 2: Verify the deployed model

Verify the actual deployment, refresh and Fabric IQ query execution. Every
approved measure reconciles, at total and daily-group levels, to equivalent
Gold queries under identical filters. The reference values come from the
contract:

| Check | Expected value |
|---|---|
| Sales lines / units / net sales | 9 / 16 / 516.73 |
| Daily groups (`gold.sales_daily`) | 7 date, store and channel groups |
| Current customers (`gold.customer_current`) | 6 |
| O1003 (11 October 2026) | Chloe's original Utrecht / Plus version, not her later Amsterdam / Premium profile |

Keep the actual Fabric IQ output and the reconciliation results as evidence:
the proof is an executed query against the real model, not an answer that
merely sounds right.

## Common failures

| Symptom | Cause and fix |
|---|---|
| Customer totals double-count | The fact relates to `customer_id`, which repeats across versions; use `customer_sk`. |
| C003's October sales appear under Amsterdam / Premium | The model uses the current profile instead of the as-of version. |
| Totals differ from `gold.sales_daily` | The comparison uses different filters or another grain; reconcile at total and daily-group levels under identical filters. |
| Authoring or Fabric IQ connection unavailable | Record the design and mark creation incomplete; do not change capacity, permissions or workspaces. |
