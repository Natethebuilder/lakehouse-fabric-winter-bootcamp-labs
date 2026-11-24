# Walkthrough Challenge 4 - Lab 4: Materialized lake views and the change batch

[Previous Challenge Solution](../challenge-03/solution-03.md) - **[Home](../../Readme.md)** - [Next Challenge Solution](../challenge-05/solution-05.md)

Duration: 17 minutes (session minutes 43–60). Start the pipeline immediately
after the initial MLV check passes.

Based on the [specification](../../specs/bootcamp-lakehouse.spec.md) sections
2, 6, 7 and 8, [repair and recovery](../../labs/bootcamp/recovery.md) and the
fixed [validator](../../labs/bootcamp/validate-lakehouse.py).

## Prerequisites

Labs 1-3 passed their initial-load checks. If a prerequisite failed, the
participant stops and gets help instead of skipping it.

## Decision moments

| # | Decision | Copilot shows, then stops | Participant replies |
|---|---|---|---|
| 9 | MLV code | Both view definitions and how their refresh differs from explicit CDF | `approve`, `change: …` or `stop` |
| 10 | Change-batch go/no-go | No running job, an empty `changes/` folder, the file and the one pipeline run | `go` or `stop` |
| 11 | Final acceptance | Every stage's result and C002/C003/C007 history | Accept, or label recovery |

Decision 10 is a go/no-go because a landed file is immutable and the pipeline
carries it through every layer.

## Task 1: Materialized lake views

Correct definitions (spec section 7):

- Each generated cell is `%%sql` with a `-- Stage: mlv - …` header and reads
  only Silver, even though the views live in the `gold` schema.
- Both use `CREATE OR REPLACE MATERIALIZED LAKE VIEW`: real Fabric MLVs, not
  tables or ordinary views.
- `gold.sales_daily` joins `silver.orders` to `silver.order_lines` and groups by
  `date_key`, `store_id` and `channel`, with exactly `date_key INT, store_id
  STRING, channel STRING, sales_lines BIGINT, units BIGINT, net_amount
  DECIMAL(18,2)`. Net sales is the sum of per-line amounts rounded to two
  places. Six `ON MISMATCH FAIL` constraints require non-null grouping keys,
  positive line and unit counts and nonnegative sales; no row is silently
  dropped.
- `gold.customer_current` holds the current version of each customer:
  `customer_sk`, `customer_id`, `full_name`, `email`, `city`, `loyalty_tier`
  and `valid_from`, with an `ON MISMATCH FAIL` constraint for non-null keys.

Expected initial output (MLV has no baseline cell):

```text
gold.sales_daily: materialized lake view definition confirmed
gold.customer_current: materialized lake view definition confirmed
PASS: bootcamp mlv contract, initial load (fixed read-only checks)
bootcamp mlv rows validated: gold.customer_current=6, gold.sales_daily=7, silver.customer_history=6, silver.order_lines=9, silver.orders=7
```

Seven groups reconcile individually to Silver: nine lines, 16 units and 516.73
net sales. A rerun replaces the definitions; that is not evidence of
incremental refresh. Claim incremental refresh only when Fabric reports that
strategy.

## Task 2: Change batch and pipeline

The change file `Files/bootcamp/changes/customer_changes.csv` holds three
events, effective `2026-11-02T00:00:00` (spec section 2):

| Operation | Customer | Required outcome |
|---|---|---|
| U | C003 | Expire Utrecht/Plus; insert Amsterdam/Premium |
| I | C007 | Insert one current customer version |
| D | C002 | Remove current Bronze state; expire Silver history without removing it |

After the go, Copilot uploads the file, verifies its bytes and triggers
`pl_bootcamp_build` once. Every fixed check now expects the changed state:

| Stage | Expected `rows validated` line after the batch |
|---|---|
| Bronze | `bronze.customer_changes_source=3, bronze.customers_current=6, bronze.customers_source=6, bronze.order_lines=9, bronze.orders=7, bronze.products=4, bronze.stores=2` |
| Silver | `lab_ops.cdf_watermarks=10, silver.customer_history=8, silver.dim_product=4, silver.dim_store=2, silver.order_lines=9, silver.orders=7` |
| Gold | `gold.dim_customer=8, gold.dim_date=7, gold.dim_product=4, gold.dim_store=2, gold.fact_sales=9, lab_ops.cdf_watermarks=10, silver.customer_history=8, silver.order_lines=9, silver.orders=7` |
| MLV | `gold.customer_current=6, gold.sales_daily=7, silver.customer_history=8, silver.order_lines=9, silver.orders=7` |

Each stage prints
`PASS: bootcamp <stage> contract, after the customer change batch (fixed read-only checks)`.
Bronze, Silver and Gold also print
`PASS: bootcamp <stage> was built or brought to contract by this run`, because
their baseline cells found the layer not yet current for the new file.

The end state (spec sections 6 and 8): six current Bronze customers; eight
Silver history rows, six current and two expired, and the same eight rows in
Gold; C003 has an expired and a current version (Amsterdam, Premium), C007 one
current version and C002 no current version but retained history;
`gold.customer_current` has six rows; all ten watermarks match their source
versions. Sales stay at nine lines, 16 units and 516.73, and O1003 still uses
Chloe's Utrecht / Plus version. A partial change state is not a valid
checkpoint.

## Common failures

| Symptom | Cause and fix |
|---|---|
| `<view>: not a materialized lake view` | Defined as a table or an ordinary view. |
| `<view>: expected ON MISMATCH FAIL constraints` | Constraints missing or using another mismatch mode. |
| `MLV groups and totals: rows/values differ from the spec` | Wrong grouping keys, column types or rounding. |
| `MLV current customers: rows/values differ from the spec` | Not exactly the current Silver versions with the seven listed columns. |
| `customer_changes.csv: expected 3 immutable event rows` | The landed change file differs from the checked-in file. |
| `DELTA_UNSUPPORTED_SUBQUERY` in Bronze | The D event must stamp `effective_at` in one MERGE and remove the row in a second `MERGE ... WHEN MATCHED THEN DELETE`. |
| An unsupported materialized-lake-view feature | Stop and report instead of working around it (spec section 3). A query that returns the right values is not proof that an MLV was created. |

## Recovery

- Before the pipeline: approve a patch and run only the affected stage and its
  unchanged checks.
- After a terminal pipeline failure: keep the child notebook's actual error,
  approve a scoped repair to the failing notebook only, then explicitly approve
  one pipeline retry. Already-current Bronze, Silver and Gold stages must not
  change anything, and processing resumes from the persisted watermarks.
- An error retrieving output is not a failed execution and never authorizes a
  retry. Never start a competing notebook while the pipeline runs.
- Stop the live build at session minute 60. Record completed stages, actual
  output and pending job IDs; an accepted, running or unfinished job is not a
  PASS. Stop only sessions and jobs the participant started.
