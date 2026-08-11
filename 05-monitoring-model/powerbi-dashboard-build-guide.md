# Power BI Monitoring Dashboard Build Guide

Build this report in the same workspace as the PoC (`WS_Finance_POC`) using the semantic model
`Finance Operations Monitoring Direct Lake` (`a1258c49-b4ba-4612-9034-c45ad1401857`) in
**Direct Lake** mode over the physical Warehouse tables:

- `audit.PipelineRun`
- `audit.ActivityRun`
- `audit.DataQuality`
- `audit.Reconciliation`
- `control.SourceConfig`
- `control.Watermark`

The lowercase SQL views (`audit.pipeline_run`, `audit.activity_run`, etc.) are retained for
Activator and SQL-query convenience. Do not use those views for Direct Lake; Direct Lake must point
to physical Delta-backed tables.

Use [monitoring-measures.dax](monitoring-measures.dax) for explicit measures.

## Model setup

Recommended relationships:

| From | To | Cardinality | Direction |
|---|---|---|---|
| `Activity Runs[PipelineRunId]` | `Pipeline Runs[RunId]` | Many-to-one | Single |
| `Data Quality[PipelineRunId]` | `Pipeline Runs[RunId]` | Many-to-one | Single |
| `Reconciliation[PipelineRunId]` | `Pipeline Runs[RunId]` | Many-to-one | Single |
| `Reconciliation[EntityName]` | `Source Config[EntityName]` | Many-to-one | Single |
| `Watermark[EntityName]` | `Source Config[EntityName]` | One-to-one or many-to-one | Single |

Hide technical IDs after relationships are created:

- `RunId`
- `ParentRunId`
- `ActivityRunId`

Keep these business fields visible:

- `PipelineName`
- `ActivityName`
- `ActivityType`
- `EntityName`
- `Layer`
- `Status`
- `StartTimeUtc`
- `EndTimeUtc`
- `DurationSeconds`
- `RowsRead`, `RowsWritten`, `RowsRejected`
- `RuleCode`, `RuleDescription`, `Severity`, `RowsFailed`
- `VariancePct`, `TolerancePct`, `Passed`

## Page 1 — Executive KPIs

Purpose: show the operational health of the entire finance pipeline.

| Visual | Fields / measures |
|---|---|
| Card | `[Success Rate %]` |
| Card | `[Runs Today]` |
| Card | `[Failed Runs]` |
| Card | `[Total Rows Processed]` |
| Card | `[Total Rows Rejected]` |
| Card | `[Average Duration Seconds]` |
| Multi-row card | `[Pipeline Health Status]` |
| Column chart | Axis: `Pipeline Runs[Status]`; Values: count of `Pipeline Runs[RunId]` |
| Table | `PipelineName`, `EntityName`, `Status`, `StartTimeUtc`, `EndTimeUtc`, `DurationSeconds`, `ErrorMessage` |

Recommended filters:

- Last 24 hours on `Pipeline Runs[StartTimeUtc]`
- `PipelineName` slicer
- `Status` slicer

## Page 2 — Runs Timeline

Purpose: show orchestration ordering, parallelism, and slow steps.

Best visual: Gantt custom visual. If custom visuals are not allowed, use a matrix/table.

Gantt mapping:

| Role | Field |
|---|---|
| Task | `Activity Runs[ActivityName]` |
| Parent/group | `Activity Runs[PipelineName]` |
| Start | `Activity Runs[StartTimeUtc]` |
| End | `Activity Runs[EndTimeUtc]` |
| Legend | `Activity Runs[Status]` |
| Tooltip | `EntityName`, `Layer`, `DurationSeconds`, `RowsRead`, `RowsWritten`, `ErrorMessage` |

Fallback table:

- `PipelineName`
- `ActivityName`
- `ActivityType`
- `EntityName`
- `Layer`
- `Status`
- `StartTimeUtc`
- `EndTimeUtc`
- `DurationSeconds`
- `RowsRead`
- `RowsWritten`
- `ErrorMessage`

## Page 3 — Data Quality

Purpose: show where rows were rejected and why.

| Visual | Fields / measures |
|---|---|
| Clustered bar chart | Axis: `Data Quality[EntityName]`; Values: `[DQ Failure Rows]` |
| Clustered bar chart | Axis: `Data Quality[RuleCode]`; Values: `[DQ Failure Rows]` |
| Card | `[DQ Rules Triggered]` |
| Card | `[Rejected Row Rate %]` |
| Table | `EntityName`, `RuleCode`, `RuleDescription`, `Severity`, `RowsFailed`, `RejectTable`, `CheckedAtUtc` |

Recommended drill-through page:

- Drill through on `entity_name`
- Show all `data_quality` rows for the selected entity
- Add a link/note to inspect the physical `silver_rejects.<Entity>` table in the Warehouse

## Page 4 — Reconciliation

Purpose: compare Bronze/Silver/Gold counts and tolerance thresholds.

| Visual | Fields / measures |
|---|---|
| Line and clustered column chart | Axis: `Reconciliation[EntityName]`; Columns: `SourceRowCount`, `TargetRowCount`; Line: `[Reconciliation Variance %]` |
| Line chart | Axis: `Reconciliation[EntityName]`; Values: `VariancePct`, `TolerancePct` |
| Card | `[Reconciliation Breaches]` |
| Table | `PipelineRunId`, `EntityName`, `SourceRowCount`, `TargetRowCount`, `RejectedRowCount`, `VariancePct`, `TolerancePct`, `Passed`, `CheckedAtUtc` |

Conditional formatting:

- `Passed = TRUE`: green
- `Passed = FALSE`: red
- `VariancePct > TolerancePct`: red data bar or warning icon

## Page 5 — Activity Diagnostics

Purpose: quickly debug failures and slow activities.

| Visual | Fields / measures |
|---|---|
| Bar chart | Axis: `Activity Runs[ActivityName]`; Values: `[Average Activity Duration Seconds]` |
| Matrix | Rows: `PipelineName`, `ActivityName`; Columns: `Status`; Values: count of `ActivityRunId` |
| Table | `PipelineRunId`, `PipelineName`, `ActivityName`, `ActivityType`, `EntityName`, `Status`, `RowsRead`, `RowsWritten`, `RowsRejected`, `ErrorCode`, `ErrorMessage` |

Use this page during demos after a simulated failure. The `error_message` column should contain the
underlying Fabric activity error captured by the failure branch.

## Suggested report theme

Use quiet operational colors:

- Success: `#107C10`
- Failed: `#D13438`
- Running: `#0078D4`
- Warning / DQ: `#FFB900`
- Neutral background: `#F8F9FA`

## Dashboard demo flow

1. Start on Executive KPIs: health, success rate, row totals.
2. Move to Runs Timeline: show Bronze parallelism, Silver sequencing, Gold dependency.
3. Move to Data Quality: explain rejected rows by entity/rule.
4. Move to Reconciliation: explain variance and tolerance.
5. Move to Activity Diagnostics: drill into Copy/Script/Stored Procedure activity rows.
