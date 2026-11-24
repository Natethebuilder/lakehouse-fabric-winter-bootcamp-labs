# Walkthrough Challenge 3 - Lab 3: Gold from the Silver change feed

[Previous Challenge Solution](../challenge-02/solution-02.md) - **[Home](../../Readme.md)** - [Next Challenge Solution](../challenge-04/solution-04.md)

Duration: 8 minutes (session minutes 35–43).

Based on the [specification](../../specs/bootcamp-lakehouse.spec.md) sections
3, 6 and 8, [repair and recovery](../../labs/bootcamp/recovery.md) and the
fixed [validator](../../labs/bootcamp/validate-lakehouse.py).

## Prerequisites

Lab 2 passed. Gold reconciles against Silver rather than revalidating it, so a
successful Silver run is its prerequisite.

## Decision moments

| # | Decision | Copilot shows, then stops | Participant replies |
|---|---|---|---|
| 7 | Gold code | Cells, replay safety, the as-of customer join and write set | `approve`, `change: …` or `stop` |
| 8 | Accept Gold | Actual check output | The next prompt, or `repair` |

The key rule to hear the participant explain in plain language:
`order_ts >= valid_from AND order_ts < valid_to`. O1003 (11 October) links to
Chloe's Utrecht / Plus version, the one valid on the order date.

## Task 1: What correct Gold code looks like

- Every generated cell is `%%sql` with a `-- Stage: gold - …` header.
- It uses Silver `table_changes()` from each watermark + 1 to identify changed
  keys, ignores `update_preimage`, and assembles affected facts and dates from
  current Silver rows. It never reads Bronze or builds Silver.
- `dim_customer` holds every Silver history version, keyed on `customer_sk`;
  `dim_product` and `dim_store` copy Silver with the same columns and types.
  Each uses a keyed MERGE with the source inline in `USING (...)`.
- `dim_date(date_key INT, date DATE, year INT, month INT, day_of_week INT)`
  covers the first through the last order date, with `yyyyMMdd` keys and Spark
  day-of-week numbering (1 = Sunday to 7 = Saturday); it inserts only missing
  days.
- `fact_sales` has one row per order line. It recomputes only the orders
  touched by the `orders` or `order_lines` change feed, joins the customer
  version valid at `order_ts`, computes `quantity * unit_price * (1 - discount)`
  rounded HALF_UP to two decimals per line, and removes deleted lines with
  `WHEN NOT MATCHED BY SOURCE` restricted to the touched orders.
- Gold tables carry descriptions and column comments; no `mergeSchema` or schema
  auto-merge.
- Five watermark pairs, each advanced after its target write:
  `silver.customer_history`, `silver.dim_product` and `silver.dim_store` to
  their Gold copies, and `silver.orders` and `silver.order_lines` to
  `gold.fact_sales`.

## Task 2: Expected result

```text
bootcamp gold: layer not built yet; the generated cell builds it
PASS: bootcamp gold contract, initial load (fixed read-only checks)
bootcamp gold rows validated: gold.dim_customer=6, gold.dim_date=7, gold.dim_product=4, gold.dim_store=2, gold.fact_sales=9, lab_ops.cdf_watermarks=10, silver.customer_history=6, silver.order_lines=9, silver.orders=7
PASS: bootcamp gold was built or brought to contract by this run
```

Nine facts total 16 units and 516.73 net sales; `dim_date` covers 2026-10-10
to 2026-10-16. The watermark count includes Silver's five pairs. Matching
totals alone do not prove CDF use: the generated code and the watermark rows
are the evidence of the consumed version ranges.

## Common failures

| Symptom | Cause and fix |
|---|---|
| `Gold customer history: rows/values differ from the spec` | `dim_customer` must copy every Silver version, including expired ones, with the same `customer_sk`. |
| `Sales facts: rows/values differ from the spec` | Wrong grain, a current-profile join instead of the as-of join, or rounding of the total instead of each line. |
| `Order must match exactly one as-of customer version` | The Silver history bounds overlap or leave a gap; the problem is in Silver, not in Gold. |
| `Date dimension: rows/values differ from the spec` | Wrong date range or day-of-week numbering. |
| `Missing watermark ...` or `Unexpected watermark pairs for this layer` | A Gold pair is missing or misnamed; both order sources map to `gold.fact_sales`. |
| `DELTA_UNSUPPORTED_SUBQUERY` | `DELETE ... WHERE key IN (subquery)` is rejected; remove keyed rows with a MERGE delete clause. |
| `Rerunning the gold generated cell changed an already-current layer` | The fact MERGE or a dimension MERGE commits without new input. |

The Runtime 2.0 rules from Lab 2 apply here too: `table_changes()` arguments
are literals or session variables, inline `table_changes()` and MERGE sources
instead of temporary views.

## Recovery

`repair: <actual error>`, approve the patch, rerun. Never reset watermarks,
overwrite history or relax the contract to pass. Do not run the full pipeline
before Lab 4.
