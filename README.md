# Zava Lakehouse Bootcamp

**Build a Microsoft Fabric lakehouse with AI: 15-minute introduction +
45-minute hands-on lab.**

Start from an **empty workspace with a dedicated active F2**.

## The story: the customer moved; the sale didn't

On 11 October, Chloe (`C003`) places order `O1003` while her profile says
Utrecht / Silver. On 2 November, she moves to Amsterdam and her profile
becomes Amsterdam / Gold. Both answers are true: her profile is now
Amsterdam / Gold, but the October sale must stay linked to the Utrecht /
Silver version that was valid when she bought.

Follow that one story through the layers: Bronze keeps the source; Silver
remembers both dated customer versions; Gold matches each sale to the version
valid on its date; materialized lake views (MLVs) serve and reconcile the
results after the change batch. The key question is always: **who was the
customer when this sale happened?**

## Get started

You need Copilot CLI, Git, Python 3.10+, Azure CLI and an assigned empty
workspace on a **dedicated active F2** with notebook and MLV support.

```powershell
git clone https://github.com/anezami/fabric-winter-bootcamp-labs.git
cd fabric-winter-bootcamp-labs
az login
copilot
```

Install the Fabric skills in Copilot if needed:

```text
/plugin marketplace add microsoft/skills-for-fabric
/plugin install fabric-skills@fabric-collection
```

Restart Copilot after installation. Complete [pre-work](labs/bootcamp/pre-work.md)
before the session: tools, sign-in, access and local [starter CSVs](data/bootcamp/).
Create nothing in Fabric yet. Lab 1's [setup prompt](labs/bootcamp/01-bronze.md)
performs [setup](labs/bootcamp/setup.md) after approval; a separate Bronze
prompt follows. Setup and cold Spark startup count in the time box.

Read the [specification](specs/bootcamp-lakehouse.spec.md) and
[guardrails](.github/copilot-instructions.md).

## Follow the labs in order

For each layer: **prompt, generate, decide, run, check**. At each decision,
reply `approve`, `change: <what>` or `stop`. Notebooks, including fixed checks,
contain only their layer's code; every cell starts with a comment. Replace
only the placeholder; keep fixed checks and baselines. Generated code or an
accepted job is not a successful run.

| Minutes | Lab | Build | Definition of done |
|---|---|---|---|
| 0-15 | Introduction | Follow Chloe's order; see why history matters | O1003 stays linked to the version valid on its sale date. |
| 15–28 | [1. Setup + Bronze](labs/bootcamp/01-bronze.md) | Preserve the source and original customer row | Setup verified; Bronze PASS, audit intact; counts 6/4/2/7/9. |
| 28–35 | [2. Silver + SCD2](labs/bootcamp/02-silver-scd2.md) | Keep Chloe's old and new customer versions | Silver PASS; six customer versions with unique keys, CDF and five watermarks. |
| 35–43 | [3. Gold from CDF](labs/bootcamp/03-gold-cdf.md) | Link O1003 to the version valid at purchase | Gold PASS; 9 facts, 16 units, 516.73 net; keys resolve. |
| 43–60 | [4. MLVs + changes](labs/bootcamp/04-materialized-view.md) | Apply the batch and check current versus historical answers | MLVs reconcile; pipeline passes without rewriting O1003's history. |

Use one Spark workload at a time; run the pipeline only **after all four checks pass**.

## Finish

Show the sales query, C003's old and current versions, C002's retained history,
watermarks and validation output. Explain why October sales keep their original
customer version after the November change.

Stop after 45 minutes. Keep notebooks and outputs; stop Spark sessions you
started. If blocked, follow [recovery](labs/bootcamp/recovery.md) and label
supplied or incomplete stages. Never change fixtures or checks to force a pass.

## Optional labs after the session

| Lab | Definition of done |
|---|---|
| [5. Project Osmos](labs/bootcamp/05-osmos-replay.md) | In a fresh approved target, the same contracts, change batch and both real MLV checks pass; retain actual task output. |
| [6. Semantic model + Fabric IQ](labs/bootcamp/06-semantic-model-fabric-iq.md) | Approve the AI-proposed model/measures, deploy and refresh it, then execute queries whose totals and daily groups reconcile to Gold. |

Keep source files immutable. Use only your confirmed workspace and lakehouse;
change no capacity, permissions or other participant's resource. Never paste
credentials into prompts or commit credentials or environment-specific IDs.
