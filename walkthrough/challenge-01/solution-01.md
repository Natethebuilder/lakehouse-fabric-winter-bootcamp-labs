# Walkthrough Challenge 1 - Lab 1: create the lakehouse and Bronze

**[Home](../../Readme.md)** - [Next Challenge Solution](../challenge-02/solution-02.md)

Duration: 13 minutes (session minutes 15–28), including lakehouse creation,
uploads, shell and pipeline provisioning and cold Spark startup.

This guide is for coaches. It is based on the
[specification](../../specs/bootcamp-lakehouse.spec.md),
[repair and recovery](../../labs/bootcamp/recovery.md) and the fixed
[validator](../../labs/bootcamp/validate-lakehouse.py). It deliberately
contains no implementation code: participants generate it live.

## Prerequisites

- The participant's dashboard lists their own **Fabric workspace**, on a
  dedicated, Active F2 (**Fabric capacity**), with the **Fabric workspace
  role** Contributor. Before Lab 1 the workspace is empty: no lakehouse,
  staged CSVs, notebooks, pipeline or warm Spark session.
- The participant works from a git clone, has completed the
  [pre-work](../../labs/bootcamp/pre-work.md) and runs Copilot from the
  repository root with `spark-cli`.

## Decision moments

Copilot ends its response at each decision and waits (spec section 1):

| # | Decision | Copilot shows, then stops | Participant replies |
|---|---|---|---|
| 1 | Setup go/no-go | Identity, workspace, capacity, empty contents and the setup write set | `approve`, `change: …` or `stop` |
| 2 | Bronze code | Plan, `%%sql` cells and exact write set | `approve`, `change: …` or `stop` |
| 3 | Accept Bronze | Actual fixed-check output | The next prompt, or `repair` |

Setup approval authorizes only the setup write set, never transformations.
Code approval authorizes one run of that notebook: Copilot replaces the
implementation placeholder with the approved cells, keeps every fixed cell
unchanged, confirms that no job is running, triggers only that notebook,
monitors it and shows the actual check output. If notebook submission is
unsupported, the participant runs the cells manually instead; never both.

## Task 1: Setup checkpoint

The approved setup write set (spec sections 1 and 3) is exactly:

- schema-enabled `lh_bootcamp`, created with `creationPayload.enableSchemas=true`
  and verified, never a schema-disabled substitute;
- the five initial CSVs under `Files/bootcamp/initial/`, verified byte for byte;
- the empty folder `Files/bootcamp/changes/`, so Bronze can read the change
  source as zero rows. The change CSV is **not** uploaded until Lab 4;
- `nb_bootcamp_bronze`, `nb_bootcamp_silver`, `nb_bootcamp_gold` and
  `nb_bootcamp_mlv`, each with a markdown description, only its own fixed
  validator sections, a fixed baseline cell (not MLV), a fail-fast `%%sql`
  placeholder and the unchanged final check;
- `pl_bootcamp_build`, serial Bronze → Silver → Gold → MLV with success-only
  dependencies, not scheduled and not run.

On a retry Copilot reconciles only items from the same confirmed setup, polls
accepted operations instead of resubmitting, skips identical files and stops
on unexpected items or conflicting files. Supplied recovery code cannot replace
a missing lakehouse, input files or notebook bindings.

## Task 2: What correct Bronze code looks like

Check the proposed cells against spec sections 3 and 4:

- Every generated cell is `%%sql`, starts with `-- Stage: bronze - <what the
  cell does>` and holds at least one statement; a cell with only comments
  fails the job.
- Raw string snapshots `customers_source`, `products`, `stores`, `orders` and
  `order_lines` use `CREATE TABLE IF NOT EXISTS ... AS SELECT` from a CSV
  temporary view, enable CDF at creation and are never rewritten.
- `customer_changes_source` is created empty on the first run and later loaded
  once with `INSERT ... WHERE NOT EXISTS`.
- `customers_current` is the only mutable Bronze table: a keyed MERGE on
  `customer_id` whose source is inline in `USING (...)`.
- Exactly three audit columns: `_ingested_at` TIMESTAMP, `_source_file` STRING
  (the clean file path) and `_batch_id` STRING from one `v_batch_id` session
  variable.
- Minimal cleansing only: trim strings, empty strings to null, drop all-null
  rows. No quarantine or invented data-quality rules.
- No Silver, Gold or MLV references and no `mergeSchema` or schema auto-merge.

## Task 3: Expected result

The fixed baseline cell prints, on the first run:

```text
bootcamp bronze: layer not built yet; the generated cell builds it
```

The fixed check cell then prints:

```text
PASS: bootcamp bronze contract, initial load (fixed read-only checks)
bootcamp bronze rows validated: bronze.customers_current=6, bronze.customers_source=6, bronze.order_lines=9, bronze.orders=7, bronze.products=4, bronze.stores=2
PASS: bootcamp bronze was built or brought to contract by this run
```

The `rows validated` line lists every table the check read, sorted by name.
An optional second **Run all** in the warm session ends with
`PASS: bootcamp bronze was already current and the rerun changed nothing`.

## Common failures

| Symptom | Cause and fix (spec section 3) |
|---|---|
| `PATH_NOT_FOUND` | A missing path or a glob without a match. Setup must create the empty `Files/bootcamp/changes/` folder; an existing empty folder reads only with an explicit column list. |
| `read_files()` is not available | Read CSVs with `CREATE OR REPLACE TEMPORARY VIEW <name> USING csv OPTIONS (path ..., header 'true')`. |
| `bronze.<table>: missing/wrong audit lineage` | `input_file_name()` adds `?version=` and `?flength=` suffixes; strip them with `regexp_replace(input_file_name(), '[?].*$', '')`. |
| `Failed to decode multipart name` | A MERGE reads a temporary view over a Delta table; write that source inline in `USING (...)`. |
| `<table>: expected types {...}, got {...}` | A column is not STRING, an audit column has the wrong type, or there are extra columns. |
| `<table>: CDF must be enabled` | CDF was not enabled when the table was created. |
| `<file>: expected <n> immutable source rows` | The landed CSV differs from the checked-in file; files are immutable after landing. |
| `Rerunning the bronze generated cell changed an already-current layer` | A statement commits on a rerun, for example rewriting a raw table, re-enabling a property or a MERGE that matches unchanged rows. |

Access or capacity blocks during setup are not code problems. Check that the
dashboard's workspace, capacity and role match what Copilot discovered, and
escalate to the organizers rather than creating or changing workspaces,
capacities or permissions.

## Recovery

On a job failure the participant waits for the job to end, copies the actual
exception from the notebook run snapshot in Fabric Monitor and replies
`repair: <actual error>`. Copilot fixes only the generated implementation,
shows the patch and write set and stops at the code decision again. Never edit
the spec, fixtures, validator or expected values, drop tables or reset history.
A malformed raw Bronze table may be dropped only with explicit instructor
approval, and only before the change file has landed. Supplied recovery cells
are recorded as **supplied recovery**, not live generation.
