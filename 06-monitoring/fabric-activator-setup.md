# Fabric Activator Monitoring Setup

This guide configures Activator-style operational alerts over the Warehouse monitoring views.
The views are created by [03-sql/07_monitoring_dashboard_views.sql](../03-sql/07_monitoring_dashboard_views.sql).

## Prerequisite

Run this SQL first against `WH_Finance_Gold`:

```powershell
sqlcmd -S "<warehouse-sql-endpoint>.datawarehouse.fabric.microsoft.com" `
  -d "WH_Finance_Gold" -G `
  -i "03-sql/07_monitoring_dashboard_views.sql"
```

Then confirm the alert source views return rows or zero rows without errors:

```sql
SELECT * FROM audit.vw_alert_pipeline_failures;
SELECT * FROM audit.vw_alert_reconciliation_breaches;
SELECT * FROM audit.vw_alert_rejected_row_spikes;
```

## Activator item

Create one Reflex / Activator item in the same workspace:

- Name: `RA_Finance_Operations_Monitoring`
- Workspace: `WS_Finance_POC`
- Source: Warehouse query against `WH_Finance_Gold`

## Rule A — Pipeline failure

**Purpose**: alert when a pipeline has failed in the last 15 minutes.

Source query:

```sql
SELECT
    run_id,
    parent_run_id,
    pipeline_name,
    entity_name,
    status,
    error_message,
    end_time_utc
FROM audit.vw_alert_pipeline_failures;
```

Rule configuration:

| Setting | Value |
|---|---|
| Evaluation | Every 5 minutes |
| Condition | Row count > 0 |
| Severity | Error |
| Group by | `run_id`, `pipeline_name`, `entity_name` |
| Action | Teams message and/or email |

Suggested Teams message:

```text
Finance pipeline failure detected
Pipeline: {pipeline_name}
Entity: {entity_name}
Run: {run_id}
Ended: {end_time_utc}
Error: {error_message}
```

## Rule B — Reconciliation breach

**Purpose**: alert when source/target variance exceeds tolerance.

Source query:

```sql
SELECT
    run_id,
    entity_name,
    variance_pct,
    tolerance_pct,
    checked_at_utc
FROM audit.vw_alert_reconciliation_breaches;
```

Rule configuration:

| Setting | Value |
|---|---|
| Evaluation | Every 5 minutes |
| Condition | Row count > 0 |
| Severity | Error |
| Group by | `run_id`, `entity_name` |
| Action | Teams message and/or email |

Suggested Teams message:

```text
Finance reconciliation breach
Entity: {entity_name}
Run: {run_id}
Variance: {variance_pct}%
Tolerance: {tolerance_pct}%
Checked: {checked_at_utc}
```

## Rule C — Rejected-row spike

**Purpose**: warn when rejected rows exceed the demo threshold in the last 24 hours.

Source query:

```sql
SELECT
    entity_name,
    rows_failed_last_24h,
    last_detected_at_utc
FROM audit.vw_alert_rejected_row_spikes;
```

Rule configuration:

| Setting | Value |
|---|---|
| Evaluation | Every 30 minutes |
| Condition | Row count > 0 |
| Severity | Warning |
| Group by | `entity_name` |
| Action | Teams message or email |

Suggested Teams message:

```text
Rejected-row spike detected
Entity: {entity_name}
Rejected rows in last 24h: {rows_failed_last_24h}
Last detected: {last_detected_at_utc}
```

## Portal setup steps

1. Open Fabric workspace `WS_Finance_POC`.
2. Create or open `RA_Finance_Operations_Monitoring`.
3. Add a Warehouse query source for `WH_Finance_Gold`.
4. Paste Rule A's query and validate the result schema.
5. Configure the row-count condition and notification action.
6. Repeat for Rule B and Rule C.
7. Trigger a test failure or insert a smoke-test row to verify delivery.

## Smoke-test queries

Use these only in a demo/test workspace.

### Simulate a failure alert

```sql
EXEC audit.SP_LogPipelineStart
    @PipelineRunId = 'activator-failure-smoke',
    @ParentRunId = NULL,
    @PipelineName = 'PL_MASTER_ORCHESTRATOR',
    @Environment = 'POC',
    @LoadType = 'Full',
    @EntityName = 'ALL',
    @SourceSystem = 'SmokeTest',
    @RunDate = '2026-08-11',
    @TriggeredBy = 'Manual';

EXEC audit.SP_LogPipelineEnd
    @PipelineRunId = 'activator-failure-smoke',
    @EntityName = 'ALL',
    @Status = 'Failed',
    @ErrorMessage = 'Smoke test failure for Activator rule validation';

SELECT * FROM audit.vw_alert_pipeline_failures;
```

### Simulate reconciliation breach

```sql
EXEC audit.SP_LogReconciliation
    @PipelineRunId = 'activator-recon-smoke',
    @EntityName = 'Customers',
    @SourceRowCount = 1000,
    @TargetRowCount = 900,
    @RejectedRowCount = 0;

SELECT * FROM audit.vw_alert_reconciliation_breaches;
```

## Notes and limitations

- Activator must be configured in the Fabric portal or via a known-good Reflex definition. This repo
  provides the Warehouse source queries and views, which are the stable part of the monitoring
  contract.
- Do not commit Teams webhook URLs, email addresses for real on-call lists, service principal
  secrets, or API tokens.
- If your tenant supports portal-generated pipeline alerts directly from Monitoring hub, that is
  the simplest setup for live notifications. The Warehouse-query approach here is better for
  teaching because it is transparent and reproducible.
