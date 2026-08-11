# Finance Operations Monitoring — Report Blueprint

Semantic model: `Finance Operations Monitoring`
Workspace: `WS_Finance_POC`
Model ID: `9fd024e8-0924-4e0b-9fcf-d8b0bc98607b`

The semantic model is deployed in Fabric. Use this blueprint to create the report pages in the
same workspace. The Power BI report layout is a separate artifact from the semantic model.

## Page 1 — Executive KPIs

**Purpose**: answer "Is the pipeline healthy right now?"

| Visual | Fields / measure | Notes |
|---|---|---|
| Card | `[Success Rate %]` | Format as percentage |
| Card | `[Runs Today]` | Count of runs started today |
| Card | `[Total Rows Processed]` | Sum of Silver/Gold target rows |
| Card | `[Total Rows Rejected]` | Sum of Silver rejected rows |
| Card | `[Average Duration Seconds]` | Average completed run duration |
| Column chart | `Pipeline Runs[Status]`, count of `PipelineRunId` | Succeeded/Failed/InProgress |
| Slicer | `Pipeline Runs[PipelineName]` | Master, Bronze, Silver, Gold |
| Slicer | `Pipeline Runs[EntityName]` | Six finance entities |

Suggested page title: `Finance Pipeline Health`.

## Page 2 — Runs Timeline

**Purpose**: show orchestration order, parallelism, duration, and failures.

| Visual | Fields |
|---|---|
| Matrix or timeline visual | `PipelineName`, `EntityName`, `StartTime`, `EndTime`, `Status` |
| Table | `PipelineRunId`, `ParentRunId`, `PipelineName`, `EntityName`, `StartTime`, `EndTime`, `DurationSeconds`, `Status` |
| Slicer | `ParentRunId` or `PipelineRunId` |
| Slicer | `Status` |

For a Gantt custom visual, use:

- Task: `PipelineName` + `EntityName`
- Start: `StartTime`
- End: `EndTime`
- Legend: `Status`
- Parent/group: `ParentRunId`

Use a status color convention:

- Succeeded: green
- InProgress: blue
- Failed: red
- NotStarted: gray

## Page 3 — Data Quality

**Purpose**: show which entities and validation rules need attention.

| Visual | Fields / measure |
|---|---|
| Clustered bar chart | `Validation Results[RuleName]`, `[Failed Rules]` |
| Bar chart | `Pipeline Runs[EntityName]`, `[Total Rows Rejected]` |
| Table | `Validation Results[RuleName]`, `RuleCategory`, `Severity`, `Expected`, `Actual`, `Result`, `CheckedAt` |
| Slicer | `Validation Results[Result]` |
| Slicer | `Validation Results[RuleCategory]` |

For detailed rejected-row breakdowns, add the six `silver_rejects.*` tables to a separate model
extension or create a Warehouse view that unions them into one `Rejected Rows` table. The current
semantic model uses the authoritative aggregate `RejectedRowCount` from `PipelineRunLog` and the
rule-level `ValidationLog` table.

## Page 4 — Reconciliation

**Purpose**: compare source rows with target rows and show the configured tolerance.

| Visual | Fields / measure |
|---|---|
| Line and clustered column chart | Axis: `Pipeline Runs[EntityName]`; columns: `SourceRowCount`, `TargetRowCount`; line: `[Reconciliation Variance %]` |
| Line chart | Axis: `Pipeline Runs[EntityName]`; values: `[Reconciliation Variance %]`, `Source Config[TolerancePct]` |
| Table | `EntityName`, `SourceRowCount`, `TargetRowCount`, `RejectedRowCount`, `[Reconciliation Variance %]`, `Source Config[TolerancePct]` |
| Card | `[Validation Failures]` |

The tolerance values are stored as percentage points in `SourceConfig.TolerancePct`, matching the
pipeline configuration. Keep the variance and tolerance measures on the same percentage-point
scale when formatting the chart.

## Requested success-rate measure

The model contains this explicit measure:

```DAX
Success Rate % =
DIVIDE(
    CALCULATE(
        COUNTROWS('Pipeline Runs'),
        'Pipeline Runs'[Status] = "Succeeded"
    ),
    COUNTROWS('Pipeline Runs')
)
```

Additional measures included in the model:

```DAX
Runs Today =
CALCULATE(
    COUNTROWS('Pipeline Runs'),
    FILTER('Pipeline Runs', DATEVALUE('Pipeline Runs'[StartTime]) = TODAY())
)

Total Rows Processed =
SUM('Pipeline Runs'[TargetRowCount])

Total Rows Rejected =
SUM('Pipeline Runs'[RejectedRowCount])

Average Duration Seconds =
AVERAGE('Pipeline Runs'[DurationSeconds])

Reconciliation Variance % =
DIVIDE(
    ABS(
        SUM('Pipeline Runs'[SourceRowCount])
            - SUM('Pipeline Runs'[TargetRowCount])
    ),
    SUM('Pipeline Runs'[SourceRowCount])
)
```

## Source-table adaptation

The original repository refers to these logical tables:

- `audit.pipeline_run`
- `audit.activity_run`
- `audit.data_quality`
- `audit.reconciliation`
- `control.watermark`

This practice workspace uses the following deployed schema instead:

| Original logical role | Actual model table |
|---|---|
| Pipeline runs | `audit.PipelineRunLog` → `Pipeline Runs` |
| Activity/run validation | `audit.ValidationLog` → `Validation Results` |
| Data-quality/reconciliation aggregates | `audit.PipelineRunLog` counts + `audit.ValidationLog` rules |
| Control metadata | `control.SourceConfig` → `Source Config` |
| Watermarks | `control.Watermark` → `Watermarks` |

No nonexistent tables were added to the model. This keeps the dashboard grounded in the actual
Warehouse schema used by the deployed pipelines.
