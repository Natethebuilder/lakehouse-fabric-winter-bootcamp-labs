# Pre-work: get ready

Prepare tools and access before the session. Begin the live build with an
**empty workspace** and a dedicated active F2 capacity already assigned.
Lab 1 creates the lakehouse, stages the five initial CSVs and provisions
shells/pipeline; setup and cold Spark startup count inside the 45-minute build.

## How you and Copilot work together

You do not need to know agentic development already. An **agent** is an AI
assistant that can plan, write code and use tools, not just suggest an answer.
Here Copilot proposes one step, you review it, and Fabric executes it only
after approval. A **skill** is a reusable set of instructions for Copilot;
`spark-cli` helps it use Fabric correctly, but grants no extra permissions.

Keep three places straight:

| Where | What belongs there |
|---|---|
| PowerShell terminal | Commands such as `git clone`, `az login` and `copilot` |
| Copilot conversation | The lab's `text` prompt blocks, `/plugin` commands and your decisions |
| Fabric in the browser | Inspect the lakehouse, notebooks and run output in Monitor |

Use one Copilot conversation from the repository root for Labs 1-4. Paste
one prompt, not the whole lab page, then wait. Copilot reads the spec and
writes the plan/tasks; you do not have to author those files yourself.
If you restart, tell it which lab passed and ask it to confirm the existing
target and job state before continuing; do not repeat setup.

Before `approve`, ask Copilot to explain **what it reads, what it changes,
and which check proves success**. For example: “Explain these cells in plain
language and show why they cannot change Silver yet.” If you cannot explain
the proposed action, use `change: <what>` or `stop` and get help. Approval
is for the displayed step, not the rest of the lab. Tool-permission dialogs
must match that scope; do not enable blanket approvals to save time.
Here `stop` declines the pending step; it does not cancel an already-running
Fabric job. Keep its job ID and monitor it or request a scoped cancellation;
do not submit another job while it runs.

## 1. Check tools and access

You need:

- Git, Python 3.10+ and Azure CLI.
- GitHub Copilot CLI with an active Copilot account.
- Your assigned empty Fabric workspace, permission to create the lakehouse,
  notebooks and pipeline, and its dedicated active F2 capacity with
  Materialized Lake View support.
- The public [Skills for Fabric](https://github.com/microsoft/skills-for-fabric)
  bundle, including `spark-cli`.

From PowerShell:

```powershell
git clone https://github.com/anezami/fabric-winter-bootcamp-labs.git
cd fabric-winter-bootcamp-labs
az login
az account show
copilot
```

If already cloned, open that folder instead of cloning again. Your GitHub
sign-in enables Copilot; `az login` selects the identity for Fabric. These
are separate sign-ins, so follow Copilot's sign-in prompt as well.
If your Fabric identity has no Azure subscription, use
`az login --allow-no-subscriptions`. Confirm the correct tenant and identity
with your instructor; do not paste tokens into chat.

Inside Copilot, check installed plugins. If the Fabric bundle is missing:

```text
/plugin marketplace add microsoft/skills-for-fabric
/plugin install fabric-skills@fabric-collection
```

Restart Copilot after installation and confirm `spark-cli` is available.
If you use another supported Copilot client, follow the public package's
client-specific setup. Do not copy CLI configuration into a different client.

## 2. Check access only

In Copilot, replace the placeholder and paste this read-only request:

```text
Use spark-cli. Check my signed-in identity and assigned workspace
<assigned workspace name>, its capacity assignment and Active status,
current items and my access. Confirm that it is empty.
Do not create or change anything, upload files or start Spark.
Report blockers and stop.
```

Ask the instructor to confirm that the capacity is dedicated to your workspace
and that the runtime supports MLVs. Do not test access by creating items. Your
Fabric permissions are the authorization boundary: never paste credentials or
tokens into a prompt. Because the F2 is dedicated to your workspace, nobody
else's jobs compete with yours; run one workload at a time yourself.

Check that the workspace is empty and the local [CSV files](../../data/bootcamp/)
(five initial files and one change file) are present. If the workspace
contains another build, stop and ask the instructor for the correct target.
Do not delete, reset or overwrite anything.

Do not create a lakehouse, upload CSVs, provision notebooks/pipelines, create
tables or start Spark during pre-work. Do not load prepared transformations.
The [Lab 1 setup prompt](01-bronze.md) performs [setup](setup.md) after
approval and selects each shell's unchanged stage sections from the
[validator](validate-lakehouse.py).

## Terms you will meet

| Term | Meaning in this lab |
|---|---|
| Spec / contract | The agreed goal, boundaries and exact expected results |
| Write set | The complete list of items or tables a step may change |
| Notebook shell | A bound notebook with fixed checks and a placeholder, not finished code |
| Grain | What one row represents; one sales fact is one order line |
| SCD2 (Slowly Changing Dimension Type 2) | Keep dated customer versions instead of overwriting history |
| Surrogate key (`customer_sk`) | An ID for one customer version, not for the person across all time |
| CDF (Change Data Feed) | A Delta table's inserted, updated and deleted rows |
| Watermark | A saved bookmark recording which change versions were processed |
| MLV (materialized lake view) | A query whose result Fabric stores and manages |
| Pipeline | The runner that executes Bronze, Silver, Gold and MLV in order |

**Story checkpoint:** Labs 1-3 build from the initial files only. Chloe is
Utrecht / Plus throughout those labs. Lab 4 introduces the November file;
only then should her current profile become Amsterdam / Premium.

## Ready check

- GitHub Copilot, `spark-cli`, Python and Azure CLI are available; sign-in works.
- Correct identity and assigned **empty workspace**, with its dedicated F2
  capacity already assigned and Active.
- The five initial CSVs and the change CSV exist locally under
  `data/bootcamp/`; no upload is required yet.
- No lakehouse, notebooks, pipeline, data tables or Spark session exist yet.

If anything is blocked, ask the instructor before starting. Do not change
workspaces, capacities or permissions yourself.

**Next:** [Lab 1 - create the lakehouse and Bronze](01-bronze.md).
