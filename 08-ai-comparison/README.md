# Finance AI readiness comparison

This demo compares two semantic models over the same `WH_Finance_Gold` data. The data, relationships, and row counts are shared; only semantic quality and AI preparation differ.

| Experience | Semantic model | Fabric item ID | Purpose |
|---|---|---|---|
| Before | `SM_Finance_AI_Unprepared` | `9490c297-5260-45e1-9644-4832eddc6882` | Valid model with source-style names, implicit aggregation, ambiguous measures, and no Prep for AI artifacts. |
| After | `SM_Finance_AI_Ready` | `60f5ecdd-48e2-449c-8375-5f001364eedd` | Business names, explicit measures, descriptions, synonyms, scoped AI schema, example prompts, and finance instructions. |

The comparison agents are deployed and published in `WS_Finance_POC`:

| Experience | Data Agent | Fabric item ID | Connected semantic model |
|---|---|---|---|
| Before | `DA_Finance_AI_Unprepared` | `929e9cab-963e-4def-b675-15765a337ac1` | `SM_Finance_AI_Unprepared` |
| After | `DA_Finance_AI_Ready` | `4cab8429-5bda-4973-b267-63962b515c46` | `SM_Finance_AI_Ready` |

Both agents have a published version available. Publishing to the Microsoft 365 Agent Store is disabled.

Both models use Direct Lake on SQL against:

- Workspace: `WS_Finance_POC` (`ad5bf890-cd6e-4786-b69c-15876240823d`)
- Warehouse: `WH_Finance_Gold` (`d88b4acf-a3ee-4568-aa66-8403b6b9ceaa`)
- Tables: `gold.DimDate`, `gold.DimCustomer`, `gold.DimGLAccount`, `gold.FactRevenue`

The shared model expression uses `Sql.Database` with the Warehouse SQL analytics endpoint hostname and Warehouse item GUID. `AzureStorage.DataLake` is the Direct Lake on OneLake connector and causes web-model schema refresh to fail with `Unable to load a query that produces no tables` for this Warehouse model.

## Intentional differences

The unprepared model deliberately exposes names such as `FactRevenue`, `DimGLAccount`, `LineAmount`, and measures named `Amount`, `Count`, and `Avg`. IDs are summable, currency intent is unspecified, descriptions are absent, and there are no model-level AI instructions or synonyms.

The prepared model definition:

- Uses `Date`, `Customer`, `GL Account`, and `Revenue` as business-facing table names.
- Hides surrogate keys and disables accidental aggregation on IDs and raw numeric attributes.
- Defines revenue in USD, invoice count, line count, quantity, customer counts, average invoice value, YTD revenue, prior-year revenue, and growth.
- Describes the grain, currency, date semantics, and preferred use of each field.
- Maps terms such as sales, turnover, orders, clients, and average order value to specific model objects.
- Restricts the AI schema to useful business fields.
- Specifies model instructions in `prepared-model/Copilot/Instructions/instructions.md`.

## Deploy models

```powershell
$workspaceId = "ad5bf890-cd6e-4786-b69c-15876240823d"

./08-ai-comparison/deploy-semantic-model.ps1 `
  -WorkspaceId $workspaceId `
  -DisplayName "SM_Finance_AI_Unprepared" `
  -ModelRoot "./08-ai-comparison/baseline-model"

./08-ai-comparison/deploy-semantic-model.ps1 `
  -WorkspaceId $workspaceId `
  -DisplayName "SM_Finance_AI_Ready" `
  -ModelRoot "./08-ai-comparison/prepared-model"
```

Fabric can return `202 Accepted` for semantic model creation. Confirm the long-running operation succeeds before treating the deployment as complete.

## Current validation baseline

Validated against the Warehouse on 12 August 2026:

| Metric | Expected value |
|---|---:|
| Total Revenue USD | $50,790,104.33 |
| Invoice Count | 887 |
| Average Revenue per Invoice USD | $57,260.55 |
| Revenue fact rows | 2,550 |
| Revenue date range | 2025-01-01 through 2027-02-26 |

The Gold calendar was extended through 2027 so every revenue row has a matching date. Time-based totals now reconcile to the unfiltered fact total.

## Supported authoring boundary

Both TMDL models are deployed from this repository. In this workspace, Fabric accepted `Copilot/` parts on create and update requests but omitted them from the subsequent `getDefinition` export. Therefore, use the files under `prepared-model/Copilot/` as the reviewed source specification and apply the AI schema and instructions through **Prep data for AI** in the Power BI service.

Fabric Data Agent generic REST definition authoring is not currently documented in the Fabric item-management support matrix, and Verified Answer payload schemas are not public. The two agents and three verified answers were authored in the portal; [agent-and-verified-answer-runbook.md](agent-and-verified-answer-runbook.md) records the live configuration and comparison tests. Do not invent `DataAgent` REST payloads or Verified Answer JSON.
