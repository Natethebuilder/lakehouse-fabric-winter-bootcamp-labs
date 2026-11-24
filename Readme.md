# Zava Lakehouse Bootcamp

**Build a Microsoft Fabric lakehouse with AI: 15-minute introduction +
45-minute hands-on lab.**

*Agentic* means Copilot can plan, write code and use tools for an approved step.
No prior experience is needed. **You decide;
Copilot assists; Fabric executes; fixed checks test the result.**

## The story: the customer moved; the sale didn't

On 11 October, Chloe (`C003`) places order `O1003`: Utrecht / Plus rewards.
On 2 November, she moves: Amsterdam / Premium rewards. **Who is Chloe now,
and who was she when she bought?** Her current profile changes; October's
sale stays linked to Utrecht / Plus.
Customer reward levels are **Standard, Plus and Premium**.

**Lab goal:** keep the source, preserve dated customer versions and report
sales without rewriting history. Bronze keeps the source; Silver keeps the
versions; Gold matches the sale to its customer-at-purchase; materialized lake
views (MLVs) serve checked results.

**Build first, then introduce change.** Labs 1-3 and the first MLV run use
only the initial snapshot: Chloe is still Utrecht / Plus. Only Lab 4 lands
the November file and runs the pipeline. Afterward her current profile is
Amsterdam / Premium; O1003 still points to Utrecht / Plus.

## Get started

Complete [pre-work](labs/bootcamp/pre-work.md): tools, clone, sign-in,
access, **where to type** and a glossary. Start with an assigned **empty
workspace on a dedicated active F2**. Create nothing and do not warm Spark.

Open [Lab 1](labs/bootcamp/01-bronze.md) beside Copilot at the repo root.
Paste its setup prompt with your workspace name. Approve
[setup](labs/bootcamp/setup.md), then use the separate Bronze prompt.
Copilot reads the [spec](specs/bootcamp-lakehouse.spec.md) and
[guardrails](.github/copilot-instructions.md); you review its plan.

## Follow the labs in order

Use **one Copilot conversation, one prompt at a time**. Ask what it will
read, change and check before replying `approve`, `change: <what>` or `stop`.
Approval permits only the displayed step. Code approval saves and runs one
notebook; if submission is unavailable, use manual **Run all** instead,
never both. Keep fixed cells unchanged. A running job or generated code is
not a PASS; wait for your own actual output before continuing.

| Minutes | Lab | Build | Definition of done |
|---|---|---|---|
| 0-15 | Introduction | Follow Chloe's order | Explain why history matters. |
| 15–28 | [1. Setup + Bronze](labs/bootcamp/01-bronze.md) | Preserve the source and original customer row | Setup verified; Bronze PASS, audit intact; counts 6/4/2/7/9. |
| 28–35 | [2. Silver + SCD2](labs/bootcamp/02-silver-scd2.md) | Build history handling; load six initial versions | Silver PASS; unique keys, CDF and five watermarks. |
| 35–43 | [3. Gold from CDF](labs/bootcamp/03-gold-cdf.md) | Link O1003 to the version valid at purchase | Gold PASS; 9 facts, 16 units, 516.73 net; keys resolve. |
| 43–60 | [4. MLVs + changes](labs/bootcamp/04-materialized-view.md) | Apply the batch and check current versus historical answers | MLVs reconcile; pipeline passes without rewriting O1003's history. |

Use one Spark workload at a time; run the pipeline only **after all four checks pass**.

## Finish

Explain the two answers: **Chloe now = Amsterdam / Premium; O1003 at
purchase = Utrecht / Plus.** Show fixed-check output, retained history and
MLV lineage; Lab 4 includes optional read-only queries for the comparison.

**45 minutes is a time box, not a completion guarantee.** Stop at session
minute 60. Keep notebooks, output and pending job IDs; stop only sessions you
started. If blocked, use [recovery](labs/bootcamp/recovery.md) and label
supplied or incomplete stages. Never change fixtures or checks to force a pass.

## Optional labs after the session

| Lab | Definition of done |
|---|---|
| [5. Project Osmos](labs/bootcamp/05-osmos-replay.md) | Replay in a fresh approved target; the same fixed checks pass. |
| [6. Semantic model + Fabric IQ](labs/bootcamp/06-semantic-model-fabric-iq.md) | Approve, create and query a model; answers reconcile to Gold. |

Keep source files immutable. Use only your confirmed workspace and lakehouse;
change no capacity or permissions. Never paste credentials into prompts or
commit credentials or environment-specific IDs.
