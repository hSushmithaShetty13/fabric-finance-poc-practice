# Demo Runbook — Rebuild + Run

## Step 1 — Create the Fabric items

1. Create a Workspace (e.g. `WS_Finance_POC`) attached to a capacity.
2. Create a Lakehouse named `LH_Finance`.
3. Create a Warehouse named `WH_Finance_Gold`.
4. Note the workspace ID, `LH_Finance` item ID, and `WH_Finance_Gold` SQL connection string only
  if you plan to use the optional JSON/PowerShell deployment route.

```powershell
az login
az rest --method get --resource "https://api.fabric.microsoft.com" `
  --url "https://api.fabric.microsoft.com/v1/workspaces" `
  --query "value[?displayName=='WS_Finance_POC'].id" -o tsv
```

## Step 2 — Deploy the SQL

```powershell
$server = "<your-warehouse-sql-endpoint>.datawarehouse.fabric.microsoft.com"
sqlcmd -S $server -d "WH_Finance_Gold" -G -i "03-sql\01_audit_framework.sql"
sqlcmd -S $server -d "WH_Finance_Gold" -G -i "03-sql\02_control_and_rejects.sql"
sqlcmd -S $server -d "WH_Finance_Gold" -G -i "03-sql\03_gold_warehouse_schema.sql"
sqlcmd -S $server -d "WH_Finance_Gold" -G -i "03-sql\04_validation_framework.sql"
```

Verify: `SELECT * FROM control.SourceConfig;` should return 6 rows.

## Step 3 — Land the source data

Follow [manual-upload-to-lakehouse.md](../02-data/manual-upload-to-lakehouse.md) to upload the six
included CSV files through the Fabric portal. `upload_to_onelake.ps1` is an optional automation
route.

Verify via the Fabric portal: `LH_Finance` → Files → `landing/` should show 6 subfolders, each
with one CSV.

## Step 4 — Build the 4 pipelines

Follow [portal-build-guide.md](../04-pipelines/portal-build-guide.md). Build and test in this order:

1. `PL_BRONZE_INGEST`
2. `PL_SILVER_LOAD`
3. `PL_GOLD_LOAD`
4. `PL_MASTER_ORCHESTRATOR`

The master uses `control.SourceConfig` to retrieve active entities and a parallel ForEach to run
Bronze then Silver per entity. Gold is gated after the complete ForEach succeeds.

### Optional JSON and PowerShell deployment

For each JSON in `04-pipelines/exports/`:
1. Open the file and replace every occurrence of the sample `workspaceId`
   (`ad5bf890-cd6e-4786-b69c-15876240823d`) and `artifactId` GUIDs
   (`3dfe3fbe-...` for `LH_Finance`, `d88b4acf-...` for `WH_Finance_Gold`) with your own IDs.
   Also replace the `endpoint` hostname with your Warehouse's SQL connection string.
2. For `pl-master-orchestrator-content.json`, additionally replace the 3 pipeline `referenceName`
   GUIDs (`470a6284-...`, `e07080e9-...`, `a7c308f8-...`) with the item IDs you get back from
   step 3 below, once you've deployed Bronze/Silver/Gold.

```powershell
cd ..\04-pipelines
.\deploy-pipeline.ps1 -WorkspaceId $ws -DisplayName "PL_BRONZE_INGEST" `
  -ContentJsonPath "exports\pl-bronze-ingest-content.json" -Description "Bronze ingest"
.\deploy-pipeline.ps1 -WorkspaceId $ws -DisplayName "PL_SILVER_LOAD" `
  -ContentJsonPath "exports\pl-silver-load-content.json" -Description "Silver load"
.\deploy-pipeline.ps1 -WorkspaceId $ws -DisplayName "PL_GOLD_LOAD" `
  -ContentJsonPath "exports\pl-gold-load-content.json" -Description "Gold load"
# now edit pl-master-orchestrator-content.json's referenceName GUIDs, then:
.\deploy-pipeline.ps1 -WorkspaceId $ws -DisplayName "PL_MASTER_ORCHESTRATOR" `
  -ContentJsonPath "exports\pl-master-orchestrator-content.json" -Description "Master orchestrator"
```

Each `deploy-pipeline.ps1` call prints the new item's `id` — save these.

## Step 5 — Run it

```powershell
$params = '{"p_load_type":"Full","p_run_date":"2026-08-11"}'
.\run-pipeline.ps1 -WorkspaceId $ws -ItemId $masterPipelineId -ParametersJson $params
```

`run-pipeline.ps1` prints the HTTP response headers including `Location` — the last segment of
that URL is the job instance ID. Poll it:

```powershell
az rest --method get --resource "https://api.fabric.microsoft.com" `
  --url "https://api.fabric.microsoft.com/v1/workspaces/$ws/items/$masterPipelineId/jobs/instances/$jobId"
```

Expect `status: InProgress` for roughly 10–15 minutes (dominated by the `Wait` buffers — see
[pl_master_orchestrator.md](../04-pipelines/pl_master_orchestrator.md)), then `Completed`.

## Step 6 — Verify

```sql
-- Full audit trail for one orchestration run
SELECT PipelineName, EntityName, [Status], SourceRowCount, TargetRowCount, RejectedRowCount
FROM audit.PipelineRunLog
WHERE ParentRunId = '<master RunId>' OR PipelineRunId = '<master RunId>'
ORDER BY LoggedAt;

-- Gold validation results
SELECT RuleName, Expected, Actual, [Result] FROM audit.ValidationLog ORDER BY CheckedAt DESC;

-- Spot-check row counts
SELECT COUNT(*) FROM gold.FactRevenue;
SELECT COUNT(*) FROM gold.DimCustomer WHERE IsCurrent = 1;
```

## Step 7 — Simulate a failure live

Easiest options, in increasing order of "visibility":
1. Run `PL_BRONZE_INGEST` standalone with `p_entity_name` set to something not in
   `control.SourceConfig` (e.g. `"Nonexistent"`) — `LKP_Config` returns no row, the Copy activity's
   dynamic content fails to resolve, and you get a genuine `Failed` run with a full error message
   in `audit.PipelineRunLog`.
2. Temporarily delete/rename a landing CSV in OneLake before running Bronze for that entity —
   0 files matched, Copy activity "succeeds" trivially (no rows, no error) — good for
   demonstrating the "job status ≠ data moved" lesson (see
   [lessons-learned.md](../06-monitoring/lessons-learned.md) #2).
3. Point to the genuine, already-present validation failure: `audit.SP_RunGoldValidation`'s
   "No duplicate invoice lines" rule fails every run because of real duplicate `InvoiceID`s in the
   generated source data — a live, unscripted example of the operational-excellence framework
   catching a real problem.

## 10-point demo checklist (matches the original ask)

| # | What to show | Where |
|---|---|---|
| 1 | Source data arrival | OneLake `Files/landing/*` after Step 3 |
| 2 | Pipeline execution | Fabric Monitoring Hub while `PL_MASTER_ORCHESTRATOR` runs |
| 3 | Parameter usage | `LKP_Config` resolving 6 different entity configs from one pipeline definition |
| 4 | Dataflow/Silver execution | `PL_SILVER_LOAD`'s Copy + Script DQ classification |
| 5 | Monitoring pipeline progress | Monitoring Hub Gantt view during the run |
| 6 | Simulated failure | Step 7 above |
| 7 | Alert generation | (optional — see note below) |
| 8 | Audit table updates | `audit.PipelineRunLog` after any run |
| 9 | Row-count reconciliation | `SourceRowCount`/`TargetRowCount`/`RejectedRowCount` columns |
| 10 | Successful Gold table loading | `gold.FactRevenue`, `gold.DimCustomer` row counts + `audit.ValidationLog` |

**Note on alerting**: this repo does not include a wired Fabric Activator alert. There is no
documented, reliable REST-API event source for "pipeline run failed" specifically (Activator's
Real-Time Hub source only covers item create/update/delete lifecycle events, not job execution
events). For a real alert, either (a) use the Fabric portal's pipeline monitoring "Set alert"
button on a failed run (UI-driven, creates the Activator wiring for you), or (b) add a Web Activity
in the `Fail_*` branch of any pipeline that posts to a Teams incoming webhook.
