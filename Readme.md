# Zava Lakehouse Bootcamp

**Build a Microsoft Fabric lakehouse with AI: 15-minute introduction +
45-minute hands-on lab.**

- [MicroHack introduction](#microhack-introduction)
- [MicroHack context](#microhack-context)
- [Objectives](#objectives)
- [General prerequisites](#general-prerequisites)
- [How the session runs](#how-the-session-runs)
- [Challenges](#challenges)
- [Solutions - Spoiler warning](#solutions---spoiler-warning)

## MicroHack introduction

*Agentic* means Copilot can plan, write code and use tools for an approved step.
No prior experience is needed. **You decide;
Copilot assists; Fabric executes; fixed checks test the result.**

### The story: the customer moved; the sale didn't

On 11 October, Chloe (`C003`) places order `O1003`: Utrecht / Plus rewards.
On 2 November, she moves: Amsterdam / Premium rewards. **Who is Chloe now,
and who was she when she bought?** Her current profile changes; October's
sale stays linked to Utrecht / Plus.
Customer reward levels are **Standard, Plus and Premium**.

## MicroHack context

**Lab goal:** keep the source, preserve dated customer versions and report
sales without rewriting history. Bronze keeps the source; Silver keeps the
versions; Gold matches the sale to its customer-at-purchase; materialized lake
views (MLVs) serve checked results.

**Build first, then introduce change.** Labs 1-3 and the first MLV run use
only the initial snapshot: Chloe is still Utrecht / Plus. Only Lab 4 lands
the November file and runs the pipeline. Afterward her current profile is
Amsterdam / Premium; O1003 still points to Utrecht / Plus.

## Objectives

After completing this MicroHack you will be able to:

- Land immutable source files in Bronze tables that keep raw values, audit
  columns and a Change Data Feed.
- Build Silver from the Bronze change feed and keep dated customer versions
  (SCD2) with surrogate keys.
- Build a Gold star from the Silver change feed that links each sale to the
  customer version valid at purchase.
- Serve reconciled results with materialized lake views, and carry one change
  batch through every layer with a single pipeline run.
- Work with Copilot agentically: review its plan, write set and checks, and
  approve one step at a time.

## General prerequisites

The MicroHack lab automation prepares each participant before the session.
Your dashboard lists:

- your lab account, for Fabric and Azure sign-in;
- **Fabric workspace** and **Fabric workspace URL**: your own empty workspace;
- **Fabric capacity**, **Fabric capacity SKU** and **Fabric capacity region**:
  the dedicated, Active F2 assigned to that workspace;
- **Fabric workspace role**: Contributor, enough to create and run every lab
  item. Organizers administer the capacity.

GitHub Copilot is not on the dashboard: your organizers arrange a Copilot seat
for you separately. Sign in to Copilot CLI with the GitHub account that holds
it, and use the lab account for `az login` and Fabric.

Work from a **git clone of this repository**, not a downloaded ZIP: Copilot
reads `.github/copilot-instructions.md`, `specs/`, `data/` and the scripts in
`labs/bootcamp/` from your local folder.

```powershell
git clone https://github.com/Natethebuilder/lakehouse-fabric-winter-bootcamp-labs.git
cd lakehouse-fabric-winter-bootcamp-labs
```

Complete [pre-work](labs/bootcamp/pre-work.md): tools, clone, sign-in,
access, **where to type** and a glossary. Start with an assigned **empty
workspace on a dedicated active F2**. Create nothing and do not warm Spark.
If you get blocked during the labs, use [repair and recovery](labs/bootcamp/recovery.md).

## How the session runs

Open Challenge 1 (Lab 1) beside Copilot at the repo root.
Paste its setup prompt with your workspace name. Approve
[setup](labs/bootcamp/setup.md), then use the separate Bronze prompt.
Copilot reads the [spec](specs/bootcamp-lakehouse.spec.md) and the
guardrails in `.github/copilot-instructions.md`; you review its plan.

### Follow the labs in order

Use **one Copilot conversation, one prompt at a time**. Ask what it will
read, change and check before replying `approve`, `change: <what>` or `stop`.
Approval permits only the displayed step. Code approval saves and runs one
notebook; if submission is unavailable, use manual **Run all** instead,
never both. Keep fixed cells unchanged. A running job or generated code is
not a PASS; wait for your own actual output before continuing.

| Minutes | Lab | Build | Definition of done |
|---|---|---|---|
| 0-15 | Introduction | Follow Chloe's order | Explain why history matters. |
| 15–28 | 1. Setup + Bronze | Preserve the source and original customer row | Setup verified; Bronze PASS, audit intact; counts 6/4/2/7/9. |
| 28–35 | 2. Silver + SCD2 | Build history handling; load six initial versions | Silver PASS; unique keys, CDF and five watermarks. |
| 35–43 | 3. Gold from CDF | Link O1003 to the version valid at purchase | Gold PASS; 9 facts, 16 units, 516.73 net; keys resolve. |
| 43–60 | 4. MLVs + changes | Apply the batch and check current versus historical answers | MLVs reconcile; pipeline passes without rewriting O1003's history. |

Use one Spark workload at a time; run the pipeline only **after all four checks pass**.

Lab N is Challenge N. After Lab 4, the Finish page wraps up the live session:
explain the two answers and stop at session minute 60. Labs 5 and 6 are
optional and run after the session.

Keep source files immutable. Use only your confirmed workspace and lakehouse;
change no capacity or permissions. Never paste credentials into prompts or
commit credentials or environment-specific IDs.

## Challenges

- [Challenge 1 - Lab 1: create the lakehouse and Bronze](challenges/challenge-01.md) **<- Start here**
- [Challenge 2 - Lab 2: Silver from the Bronze change feed](challenges/challenge-02.md)
- [Challenge 3 - Lab 3: Gold from the Silver change feed](challenges/challenge-03.md)
- [Challenge 4 - Lab 4: Materialized lake views and the change batch](challenges/challenge-04.md)
- [Challenge 5 - Lab 5: Project Osmos](challenges/challenge-05.md) (optional, after the session)
- [Challenge 6 - Lab 6: Semantic model and Fabric IQ](challenges/challenge-06.md) (optional, after the session)
- [Finish](challenges/finish.md)

## Solutions - Spoiler warning

Coach guides: expected check output, decision moments, common failures and recovery.

- [Solution 1 - Lab 1: create the lakehouse and Bronze](./walkthrough/challenge-01/solution-01.md)
- [Solution 2 - Lab 2: Silver from the Bronze change feed](./walkthrough/challenge-02/solution-02.md)
- [Solution 3 - Lab 3: Gold from the Silver change feed](./walkthrough/challenge-03/solution-03.md)
- [Solution 4 - Lab 4: Materialized lake views and the change batch](./walkthrough/challenge-04/solution-04.md)
- [Solution 5 - Lab 5: Project Osmos](./walkthrough/challenge-05/solution-05.md)
- [Solution 6 - Lab 6: Semantic model and Fabric IQ](./walkthrough/challenge-06/solution-06.md)

## For organizers

The lab automation in the repository's `labautomation` folder gives every
participant their own empty Fabric workspace on a dedicated, Active F2
capacity, with several participants per Azure subscription. Its README covers
tenant settings, licenses, quota, cost and cleanup. The folder is not
published to participants or coaches.
