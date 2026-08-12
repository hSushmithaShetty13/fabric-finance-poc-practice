# Fabric Activator Monitoring Setup

This guide configures Activator alerts from Power BI card visuals over the finance monitoring
semantic model.

> **Current Fabric limitation:** Activator's **Get data** dialog does not expose Fabric Warehouse
> as a direct data source. Use the Power BI visual-alert route below for this demo.

## Prerequisite

Deploy `Finance Operations Monitoring Direct Lake` and confirm its report can display these
measures:

- `[Failed Runs]`
- `[Reconciliation Breaches]`
- `[DQ Failure Rows]`

## Activator item

Create one Reflex / Activator item in the same workspace:

- Name: `RA_Finance_Operations_Monitoring`
- Workspace: `WS_Finance_POC`
- Source: Power BI card visuals from `Finance Operations Monitoring Direct Lake`

## Rule A — Pipeline failure

**Purpose**: alert when a pipeline has failed in the last 15 minutes.

Source visual: card using `[Failed Runs]`, filtered to the last 15 minutes by
`Pipeline Runs[EndTimeUtc]`.

Rule configuration:

| Setting | Value |
|---|---|
| Condition | `[Failed Runs]` > 0 |
| Severity | Error |
| Action | Teams message and/or email |

Suggested Teams message:

```text
Finance pipeline failure detected in the last 15 minutes.
Open the Finance Operations Monitoring report for run details.
```

## Rule B — Reconciliation breach

**Purpose**: alert when source/target variance exceeds tolerance.

Source visual: card using `[Reconciliation Breaches]`, filtered to the last 15 minutes by
`Reconciliation[CheckedAtUtc]`.

Rule configuration:

| Setting | Value |
|---|---|
| Condition | `[Reconciliation Breaches]` > 0 |
| Severity | Error |
| Action | Teams message and/or email |

Suggested Teams message:

```text
Finance reconciliation breach detected in the last 15 minutes.
Open the Finance Operations Monitoring report for details.
```

## Rule C — Rejected-row spike

**Purpose**: warn when rejected rows exceed the demo threshold in the last 24 hours.

Source visual: card using `[DQ Failure Rows]`, filtered to the last 24 hours by
`Data Quality[CheckedAtUtc]`.

Rule configuration:

| Setting | Value |
|---|---|
| Condition | `[DQ Failure Rows]` >= 100 |
| Severity | Warning |
| Action | Teams message or email |

Suggested Teams message:

```text
At least 100 rejected rows were detected in the last 24 hours.
Open the Finance Operations Monitoring report for details.
```

## Portal setup steps

Do not start from **Activator > Get data** for this route.

1. Open the report connected to `Finance Operations Monitoring Direct Lake`.
2. Add card visuals for `[Failed Runs]`, `[Reconciliation Breaches]`, and `[DQ Failure Rows]`.
3. Apply the required time filter to each visual: last 15 minutes for failed runs, the desired
  reconciliation window, and last 24 hours for rejected rows.
4. On each card, select **...** > **Set alert**. Fabric opens Activator with that visual as the
  source.
5. Set the condition to **greater than 0**, choose Teams or email, save the rule, and select
  **Start** if the rule is not started automatically.
6. Trigger a test failure or insert a smoke-test row, then refresh the semantic model/report data
  if required and verify delivery.

The Warehouse cannot be selected directly in the current **Connect data source** dialog.

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

```

### Simulate reconciliation breach

```sql
EXEC audit.SP_LogReconciliation
    @PipelineRunId = 'activator-recon-smoke',
    @EntityName = 'Customers',
    @SourceRowCount = 1000,
    @TargetRowCount = 900,
    @RejectedRowCount = 0;

```

## Notes and limitations

- Activator is configured from the Power BI card menu, not from **Activator > Get data**.
- Do not commit Teams webhook URLs, email addresses for real on-call lists, service principal
  secrets, or API tokens.
- If your tenant supports portal-generated pipeline alerts directly from Monitoring hub, that is
  another direct option for live pipeline notifications.
