# Monitoring & Alerting Guide

This guide covers the operational monitoring story for the 6-entity Finance pipeline practice build.
It maps directly to the deployed items:

- `PL_MASTER_ORCHESTRATOR`
- `PL_BRONZE_INGEST`
- `PL_SILVER_LOAD`
- `PL_GOLD_LOAD`

The recommended demo combines Fabric's built-in Monitoring hub with the Warehouse audit tables.

## 1. Fabric Monitoring hub

In the Fabric portal:

1. Open the `WS_Finance_POC` workspace.
2. Select **Monitor** or **Monitoring hub**.
3. Filter `Item type` to **Data pipeline**.
4. Filter `Workspace` to the finance workspace.
5. Open a `PL_MASTER_ORCHESTRATOR` run.

Use the run details to show:

- Overall status: `NotStarted`, `InProgress`, `Completed`, or `Failed`.
- Start time, end time, and duration.
- Activity-level status and dependency paths.
- The six Bronze child pipelines running in parallel.
- The six Silver child pipelines waiting on their corresponding Bronze child.
- The Gold child pipeline waiting on all Silver children.
- Retry attempts and the activity error message.
- Rerun and rerun-from-failed-activity options where supported by the portal.
- Capacity/consumption details when displayed for the workspace.

For the live demo, save or bookmark a Monitoring hub view filtered to the finance workspace and
pipeline items. Open the view before starting the master run so the audience can watch the graph
progress in real time.

## 2. Warehouse audit monitoring

The Warehouse is the durable operational record. Connect to `WH_Finance_Gold` with `sqlcmd`, the
Warehouse SQL editor, or a semantic model.

### Current run status

```sql
SELECT TOP (50)
       PipelineRunId,
       ParentRunId,
       PipelineName,
       EntityName,
       [Status],
       StartTime,
       EndTime,
       DurationSeconds,
       ErrorMessage,
       TriggeredBy
FROM audit.PipelineRunLog
ORDER BY LoggedAt DESC;
```

### Trace one master run

Replace the value with the master pipeline run ID:

```sql
DECLARE @MasterRunId VARCHAR(100) = '<master-run-id>';

SELECT PipelineName,
       EntityName,
       [Status],
       StartTime,
       EndTime,
       DurationSeconds,
       ErrorMessage
FROM audit.PipelineRunLog
WHERE PipelineRunId = @MasterRunId
   OR ParentRunId = @MasterRunId
ORDER BY LoggedAt;
```

The expected shape is:

```text
PL_MASTER_ORCHESTRATOR  ALL           Succeeded
PL_BRONZE_INGEST        Customers     Succeeded
PL_BRONZE_INGEST        Invoices      Succeeded
PL_BRONZE_INGEST        InvoiceLines  Succeeded
PL_BRONZE_INGEST        Payments      Succeeded
PL_BRONZE_INGEST        ExchangeRates Succeeded
PL_BRONZE_INGEST        GLAccounts    Succeeded
PL_SILVER_LOAD          <six entities> Succeeded
PL_GOLD_LOAD            ALL           Succeeded
```

The child rows use `ParentRunId` to connect the activity-level pipeline runs to the master run.

## 3. Row-count reconciliation

`PL_SILVER_LOAD` records source, target, and rejected counts through
`audit.SP_LogRowCounts`.

```sql
SELECT PipelineRunId,
       EntityName,
       SourceRowCount,
       TargetRowCount,
       RejectedRowCount,
       CASE
           WHEN SourceRowCount = TargetRowCount THEN 'Pass'
           ELSE 'Investigate'
       END AS ReconciliationStatus
FROM audit.PipelineRunLog
WHERE PipelineName = 'PL_SILVER_LOAD'
ORDER BY LoggedAt DESC;
```

Expected source snapshot counts for the generated data are:

| Entity | Bronze/Silver rows | Expected rejected rows |
|---|---:|---:|
| Customers | 124 | 5 |
| Invoices | 1,020 | 70 |
| InvoiceLines | 2,973 | 250 |
| Payments | 831 | 51 |
| ExchangeRates | 2,069 | 41 |
| GLAccounts | 21 | 3 |

The Silver target count equals the source count in this implementation because the pipeline copies
the complete Bronze table and writes the DQ classification separately to `silver_rejects.*`.
This is intentional and documented in [lessons-learned.md](lessons-learned.md).

## 4. Data-quality monitoring

Each Silver run writes rejected rows to a Warehouse table named `silver_rejects.<Entity>`.
Rows are tagged with `RunId`, `RejectedAtUtc`, and `RuleCode`.

```sql
SELECT 'Customers' AS EntityName, RuleCode, COUNT_BIG(*) AS RejectedRows
FROM silver_rejects.Customers
GROUP BY RuleCode
UNION ALL
SELECT 'Invoices', RuleCode, COUNT_BIG(*)
FROM silver_rejects.Invoices
GROUP BY RuleCode
UNION ALL
SELECT 'InvoiceLines', RuleCode, COUNT_BIG(*)
FROM silver_rejects.InvoiceLines
GROUP BY RuleCode
UNION ALL
SELECT 'Payments', RuleCode, COUNT_BIG(*)
FROM silver_rejects.Payments
GROUP BY RuleCode
UNION ALL
SELECT 'ExchangeRates', RuleCode, COUNT_BIG(*)
FROM silver_rejects.ExchangeRates
GROUP BY RuleCode
UNION ALL
SELECT 'GLAccounts', RuleCode, COUNT_BIG(*)
FROM silver_rejects.GLAccounts
GROUP BY RuleCode
ORDER BY EntityName, RuleCode;
```

For a specific run:

```sql
SELECT RunId,
       RuleCode,
       COUNT_BIG(*) AS RowsRejected,
       MIN(RejectedAtUtc) AS FirstRejectedAtUtc,
       MAX(RejectedAtUtc) AS LastRejectedAtUtc
FROM silver_rejects.Invoices
WHERE RunId = '<silver-run-id>'
GROUP BY RunId, RuleCode;
```

## 5. Gold validation monitoring

`PL_GOLD_LOAD` calls `audit.SP_RunGoldValidation`, which records Gold validation results in
`audit.ValidationLog`.

```sql
SELECT TOP (30)
       PipelineRunId,
       RuleName,
       RuleCategory,
       Severity,
       Expected,
       Actual,
       [Result],
       CheckedAt
FROM audit.ValidationLog
ORDER BY CheckedAt DESC;
```

The current validation rules are:

- No null dimension keys in `gold.FactRevenue`.
- No duplicate invoice lines in the Gold fact.
- No negative revenue amounts.

The duplicate-invoice-line rule can legitimately fail for this practice dataset because duplicate
invoice IDs are intentionally injected into the generated source data. That failure is useful in
the demo: Monitoring hub shows the pipeline completed, while `audit.ValidationLog` shows a real data
quality finding that needs investigation.

## 6. Gold table health checks

```sql
SELECT COUNT(*) AS CurrentCustomerRows
FROM gold.DimCustomer
WHERE IsCurrent = 1;

SELECT COUNT(*) AS GLAccountRows
FROM gold.DimGLAccount;

SELECT COUNT(*) AS RevenueRows,
       SUM(LineAmountUSD) AS RevenueAmountUSD,
       MIN(LoadRunId) AS FirstLoadRunId,
       MAX(LoadRunId) AS LastLoadRunId
FROM gold.FactRevenue;
```

A successful demo run should show populated dimensions and a populated `FactRevenue` table. Always
check row counts rather than relying only on the pipeline job status.

## 7. Failure monitoring and troubleshooting

## 7a. Granular activity-run monitoring

The pipelines now write dedicated rows to `audit.ActivityRun` for the key activity boundaries:

| Pipeline | Activity rows currently logged |
|---|---|
| `PL_BRONZE_INGEST` | `PipelineStart`, `LKP_Config`, `Copy_Bronze`, `PipelineEnd` |
| `PL_SILVER_LOAD` | `PipelineStart`, `Copy_Bronze_To_Silver`, `SCR_Classify_Rejects`, `PipelineEnd` |
| `PL_GOLD_LOAD` | `PipelineStart`, `SP_Upsert_DimCustomer`, `SP_Upsert_DimGLAccount`, `SP_Load_FactRevenue`, `PipelineEnd` |

Example query:

```sql
SELECT PipelineRunId,
       PipelineName,
       ActivityName,
       ActivityType,
       EntityName,
       Layer,
       [Status],
       RowsRead,
       RowsWritten,
       RowsRejected,
       StartTimeUtc,
       EndTimeUtc,
       DurationSeconds,
       ErrorMessage
FROM audit.ActivityRun
ORDER BY LoggedAtUtc DESC;
```

This level is intentionally focused on meaningful operational units: Lookup config resolution,
Copy movement, DQ classification, and Gold stored-procedure work. You can extend the same
`audit.sp_log_activity` pattern to also log `Wait` and `ExecutePipeline` wrapper activities if you
want every single canvas node represented, but the current setup already supports practical
debugging of row movement, DQ classification, and Gold processing.

### Failure branch behavior

Each child pipeline has the following pattern:

```text
Copy/Script failure
    -> SP_Log_End_Failure
    -> Fail_<Layer>
    -> parent ExecutePipeline fails
```

The failure procedure writes the Fabric activity error to `audit.PipelineRunLog.ErrorMessage` before
the `Fail` activity re-raises the failure to the parent pipeline.

### Find recent failures

```sql
SELECT TOP (20)
       PipelineRunId,
       ParentRunId,
       PipelineName,
       EntityName,
       StartTime,
       EndTime,
       ErrorMessage
FROM audit.PipelineRunLog
WHERE [Status] = 'Failed'
ORDER BY LoggedAt DESC;
```

### Common symptoms

| Symptom | First check | Likely cause |
|---|---|---|
| Job says `Completed`, but no table/rows exist | Lakehouse Items API and `COUNT(*)` | Copy matched zero files |
| `PathNotFound` | Copy `wildcardFolderPath` | Incorrect `Files/` prefix or duplicated folder path |
| `Invalid object name` after Silver Copy | Wait and retry SQL query | Lakehouse SQL endpoint metadata lag |
| Stale parquet file URL | Silver `LKP_Counts` activity | SQL endpoint still references the previous Delta snapshot |
| `Cannot find data set in the activity` | Lookup JSON definition | `datasetSettings` nested inside `source` instead of beside it |
| Repeated row counts after reruns | `control.SourceConfig.LoadMode` | Append/Incremental used without watermark filtering |
| Gold validation fails on duplicate lines | `audit.ValidationLog` | Deliberate duplicate invoice IDs in generated data |

See [lessons-learned.md](lessons-learned.md) for the full explanation and fixes.

## 8. Custom monitoring dashboard

For a reusable dashboard, create a semantic model over `WH_Finance_Gold` with these tables:

- `audit.PipelineRunLog`
- `audit.ValidationLog`
- `control.SourceConfig`
- `silver_rejects.Customers`
- `silver_rejects.Invoices`
- `silver_rejects.InvoiceLines`
- `silver_rejects.Payments`
- `silver_rejects.ExchangeRates`
- `silver_rejects.GLAccounts`

Recommended report pages:

1. **Executive status** — latest master status, last successful run, duration, Gold row count.
2. **Pipeline timeline** — child start/end times grouped by `ParentRunId`.
3. **Reconciliation** — source vs target vs rejected rows by entity.
4. **Data quality** — rejected rows by entity and rule code.
5. **Validation** — Pass/Fail results from `audit.ValidationLog`.

Example measure:

```DAX
Pipeline Success Rate % =
DIVIDE(
    CALCULATE(
        COUNTROWS('PipelineRunLog'),
        'PipelineRunLog'[Status] = "Succeeded"
    ),
    COUNTROWS('PipelineRunLog')
)
```

## 9. Alerting options

### Fabric portal alerting

For a customer demo, use the Fabric portal's monitoring experience to configure an alert from a
failed pipeline run when the tenant/workspace UI exposes that option. This is the most direct
interactive route and avoids hardcoding notification credentials in the repository.

### Teams Web Activity

For a deterministic notification path, add a Web Activity to each `SP_Log_End_Failure` branch:

1. Create a Teams incoming webhook or approved notification endpoint.
2. Store the endpoint securely; do not commit it to this repository.
3. POST a message containing `pipeline().Pipeline`, `pipeline().RunId`, entity name, and the
   activity error.
4. Keep the existing audit procedure before the Web Activity so the failure is recorded even if
   notification delivery fails.

### Activator / Reflex

The practice repo does not hand-author an Activator definition. Fabric workspace lifecycle events
are not the same as pipeline job-failure events, so a generic workspace-event Reflex is not a
reliable substitute for a pipeline failure alert. Configure Activator through the Fabric portal or
use a supported event/query source after confirming the source returns pipeline-run failures.

Never commit Teams URLs, API keys, or other notification credentials.

## 10. Demo sequence

1. Open Monitoring hub filtered to the finance pipelines.
2. Start `PL_MASTER_ORCHESTRATOR` with `p_load_type=Full`.
3. Show the six Bronze child runs beginning in parallel.
4. Show each Silver child starting after its Bronze predecessor and synchronization wait.
5. Show `LKP_Config` in a child pipeline resolving the entity metadata.
6. Query `audit.PipelineRunLog` while the run is still active.
7. Show Silver rejected-row counts from `silver_rejects.*`.
8. Show Gold `FactRevenue` loading.
9. Show `audit.ValidationLog`, including the deliberate duplicate-line finding.
10. Optionally break a landing path, rerun one child, and show the failure branch plus audit error.
