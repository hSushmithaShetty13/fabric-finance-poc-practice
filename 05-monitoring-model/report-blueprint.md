# Finance Operations Monitoring — Direct Lake Report Blueprint

Semantic model: `SM_Finance_Operations_Monitoring`
Model ID: `7661cb57-8c49-4e1b-a32c-f49661b4e5f6`
Storage mode: Direct Lake

Use physical Warehouse tables as the Direct Lake source:

- `audit.PipelineRun` -> `Pipeline Runs`
- `audit.ActivityRun` -> `Activity Runs`
- `audit.DataQuality` -> `Data Quality`
- `audit.Reconciliation` -> `Reconciliation`
- `control.SourceConfig` -> `Source Config`
- `control.Watermark` -> `Watermarks`

Do not use SQL views for Direct Lake. The lowercase views (`audit.pipeline_run`, etc.) exist for
SQL convenience and Fabric Activator source queries only.

## Page 1 — Executive KPIs

Cards:

- `[Success Rate %]`
- `[Runs Today]`
- `[Failed Runs]`
- `[Total Rows Processed]`
- `[Total Rows Rejected]`
- `[Average Duration Seconds]`
- `[Pipeline Health Status]`

Supporting visuals:

- Column chart: `Pipeline Runs[Status]` by count of `Pipeline Runs[RunId]`
- Table: `PipelineName`, `EntityName`, `Status`, `StartTimeUtc`, `EndTimeUtc`, `DurationSeconds`, `ErrorMessage`
- Slicers: `PipelineName`, `EntityName`, `Status`, `RunDate`

## Page 2 — Runs Timeline

Recommended visual: Gantt custom visual.

Mapping:

- Task: `Activity Runs[ActivityName]`
- Parent/group: `Activity Runs[PipelineName]`
- Start: `Activity Runs[StartTimeUtc]`
- End: `Activity Runs[EndTimeUtc]`
- Legend: `Activity Runs[Status]`
- Tooltip: `EntityName`, `Layer`, `DurationSeconds`, `RowsRead`, `RowsWritten`, `RowsInserted`, `RowsUpdated`, `ErrorMessage`

Fallback: table visual over the same fields.

## Page 3 — Data Quality

Visuals:

- Bar chart: `Data Quality[EntityName]` by `[DQ Failure Rows]`
- Bar chart: `Data Quality[RuleCode]` by `[DQ Failure Rows]`
- Cards: `[DQ Rules Triggered]`, `[Rejected Row Rate %]`
- Table: `EntityName`, `RuleCode`, `RuleDescription`, `Severity`, `RowsFailed`, `RejectTable`, `CheckedAtUtc`

## Page 4 — Reconciliation

Visuals:

- Combo chart: axis `Reconciliation[EntityName]`; columns `SourceRowCount`, `TargetRowCount`; line `[Reconciliation Variance %]`
- Line chart: axis `Reconciliation[EntityName]`; values `VariancePct`, `TolerancePct`
- Card: `[Reconciliation Breaches]`
- Table: `PipelineRunId`, `EntityName`, `SourceRowCount`, `TargetRowCount`, `RejectedRowCount`, `VariancePct`, `TolerancePct`, `Passed`, `CheckedAtUtc`

## Page 5 — Activity Diagnostics

Visuals:

- Bar chart: `Activity Runs[ActivityName]` by `[Average Activity Duration Seconds]`
- Matrix: rows `PipelineName`, `ActivityName`; columns `Status`; values count of `ActivityRunId`
- Table: `RootRunId`, `PipelineRunId`, `PipelineName`, `ActivityName`, `ActivityType`, `EntityName`, `Layer`, `Status`, `RowsRead`, `RowsWritten`, `RowsRejected`, `RowsInserted`, `RowsUpdated`, `ErrorCode`, `ErrorMessage`

Use `RootRunId` to filter one complete master orchestration. Use `PipelineRunId` to isolate one
Bronze, Silver, Gold, or master pipeline execution within that orchestration.

## Direct Lake validation checklist

- Model table partitions use `mode: directLake`.
- No table partition uses `Sql.Database`.
- `model.tmdl` contains the `DL_WH_Finance_Gold` `AzureStorage.DataLake(...)` expression.
- The report uses physical table names, not the lowercase SQL views.
- Activator rules originate from card visuals using `[Failed Runs]`,
  `[Reconciliation Breaches]`, and `[DQ Failure Rows]`.
