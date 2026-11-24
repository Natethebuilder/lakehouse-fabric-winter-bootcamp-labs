# Walkthrough Challenge 2 - Lab 2: Silver from the Bronze change feed

[Previous Challenge Solution](../challenge-01/solution-01.md) - **[Home](../../Readme.md)** - [Next Challenge Solution](../challenge-03/solution-03.md)

Duration: 7 minutes (session minutes 28–35).

Based on the [specification](../../specs/bootcamp-lakehouse.spec.md) sections
3 and 5, [repair and recovery](../../labs/bootcamp/recovery.md) and the fixed
[validator](../../labs/bootcamp/validate-lakehouse.py).

## Prerequisites

Lab 1 passed: Bronze initial-load PASS. Silver consumes the Bronze change
feed, so Silver code cannot pass on top of a failing Bronze layer.

## Decision moments

| # | Decision | Copilot shows, then stops | Participant replies |
|---|---|---|---|
| 4 | Customer key | Two `customer_sk` strategies, one trade-off each | `A` or `B` |
| 5 | Silver code | Cells, SCD2 validity, watermark order and write set | `approve`, `change: …` or `stop` |
| 6 | Accept Silver | Actual check output and `customer_history` | The next prompt, or `repair` |

Decision 4 is a genuine design choice; both options satisfy the contract (a
unique, non-null BIGINT) and Gold copies the chosen key unchanged:

- **A:** `xxhash64(customer_id, valid_from)`, deterministic, so a rebuild
  reproduces the same keys.
- **B:** the current maximum key plus `row_number()`, a compact sequence whose
  values depend on processing order.

## Task 1: What correct Silver code looks like

- Every generated cell is `%%sql` with a `-- Stage: silver - …` header.
- It reads Bronze only through `table_changes()`, from each watermark + 1
  (version 0 on the first run) through the source's latest change version,
  ignores `update_preimage` and keeps the latest change per key.
- Typed tables: prices DECIMAL(18,2), `line_number` and `quantity` INT,
  `discount` DECIMAL(6,4), `order_ts` TIMESTAMP, other attributes STRING; CDF
  enabled on all five Silver tables.
- `dim_product`, `dim_store`, `orders` and `order_lines` use a keyed MERGE on
  `product_id`, `store_id`, `order_id`, and `order_id` + `line_number`.
- `customer_history` is SCD2: a MERGE closes the current version, then an
  `INSERT` guarded by `WHERE NOT EXISTS` opens the new one. Bounds come from the
  business `effective_at`, not processing time; an open version ends at
  `9999-12-31 00:00:00`; expired versions and their keys are kept.
- Every MERGE source is inline in `USING (...)`, and no statement uses
  `mergeSchema` or schema auto-merge.
- Each of the five `lab_ops.cdf_watermarks` rows advances only after its target
  write: `bronze.products`, `bronze.stores`, `bronze.orders`,
  `bronze.order_lines` and `bronze.customers_current` to their Silver targets.
- No Gold or MLV code in any cell.

## Task 2: Expected result

```text
bootcamp silver: layer not built yet; the generated cell builds it
PASS: bootcamp silver contract, initial load (fixed read-only checks)
bootcamp silver rows validated: lab_ops.cdf_watermarks=5, silver.customer_history=6, silver.dim_product=4, silver.dim_store=2, silver.order_lines=9, silver.orders=7
PASS: bootcamp silver was built or brought to contract by this run
```

The first line comes from the fixed baseline cell. The watermark count is the
whole `lab_ops.cdf_watermarks` table: 5 rows now, and 10 once Gold has added
its own five pairs in Lab 3. The check compares six customer versions with
the source, all current with `valid_from = effective_at`, each with a unique
key and a Bronze `source_commit_version`.

## Common failures

| Symptom | Cause and fix (spec section 3) |
|---|---|
| `DELTA_CDC_NON_CONSTANT_ARGUMENT` | `table_changes()` takes literals and session variables, not subqueries. Read the latest change version into a variable first. |
| `DELTA_CDC_START_VERSION_AFTER_LATEST` | The start version is beyond the latest change. Read from `LEAST(<from>, <to>)` and keep rows with `_commit_version >= <from>`. |
| `UNRESOLVED_COLUMN` when reading a temporary view | A temporary view wraps `table_changes()` with session-variable arguments. Write the `table_changes()` subquery inline in each statement. |
| `Failed to decode multipart name` | A MERGE source is a temporary view over a Delta table; inline it in `USING (...)`. |
| `SCD2 keys must be unique/non-null` | The `customer_sk` strategy from decision 4 is not applied consistently. |
| `SCD2 rows need source commit versions within Bronze history` or `<customer>: commit versions must increase per version` | `source_commit_version` is not the Bronze commit version that produced the row. |
| `SCD2 attributes, validity, and retained history: rows/values differ from the spec` | Wrong validity bounds, overwritten history or a version opened twice. |
| `Missing watermark ...`, `... watermark is not current`, `Duplicate watermark pairs`, `Unexpected watermark pairs for this layer` | Watermark rows are missing, duplicated, misnamed or not advanced to the source's latest change version. |
| `Rerunning the silver generated cell changed an already-current layer` | A MERGE matches unchanged rows or a statement commits without new input. |

## Recovery

The participant replies `repair: <actual error>`, approves the patch to the
generated code and reruns the notebook. Never recreate history, reset
watermarks, reseed a missing watermark for an existing target or change
expected results. Missing CDF history needs an explicit instructor repair
decision, not an automatic reset. A watermark advances only after its target
write, so rerunning an interrupted Silver stage is safe.
