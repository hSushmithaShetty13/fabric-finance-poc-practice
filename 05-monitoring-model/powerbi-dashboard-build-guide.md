# Power BI Monitoring Dashboard Build Guide

Build this report in the same workspace as the PoC (`WS_Finance_POC`) using the semantic model
`SM_Finance_Operations_Monitoring` (`7661cb57-8c49-4e1b-a32c-f49661b4e5f6`) in
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

Use the measure logic below when building manually. The same definitions are also available in
[monitoring-measures.dax](monitoring-measures.dax).

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
- `RootRunId`
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
- `RowsRead`, `RowsWritten`, `RowsRejected`, `RowsInserted`, `RowsUpdated`
- `RuleCode`, `RuleDescription`, `Severity`, `RowsFailed`
- `VariancePct`, `TolerancePct`, `Passed`

## Measure logic

Create these explicit measures on the `Pipeline Runs` table unless noted otherwise.

### Success Rate %

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

Format: Percentage, 2 decimal places.

### Runs Today

```DAX
Runs Today =
CALCULATE(
	COUNTROWS('Pipeline Runs'),
	FILTER(
		'Pipeline Runs',
		DATEVALUE('Pipeline Runs'[StartTimeUtc]) = TODAY()
	)
)
```

Format: Whole number.

### Failed Runs

```DAX
Failed Runs =
CALCULATE(
	COUNTROWS('Pipeline Runs'),
	'Pipeline Runs'[Status] = "Failed"
)
```

Format: Whole number.

### In Progress Runs

```DAX
In Progress Runs =
CALCULATE(
	COUNTROWS('Pipeline Runs'),
	'Pipeline Runs'[Status] = "Running"
		|| 'Pipeline Runs'[Status] = "InProgress"
		|| 'Pipeline Runs'[Status] = "Started"
)
```

Format: Whole number.

### Total Rows Read

```DAX
Total Rows Read =
SUM('Activity Runs'[RowsRead])
```

Format: Whole number with thousands separator.

### Total Rows Written

```DAX
Total Rows Written =
SUM('Activity Runs'[RowsWritten])
```

Format: Whole number with thousands separator.

### Total Rows Processed

```DAX
Total Rows Processed =
SUM('Reconciliation'[TargetRowCount])
```

Format: Whole number with thousands separator.

### Total Rows Rejected

```DAX
Total Rows Rejected =
SUM('Data Quality'[RowsFailed])
```

Format: Whole number with thousands separator.

### Average Duration Seconds

```DAX
Average Duration Seconds =
AVERAGE('Pipeline Runs'[DurationSeconds])
```

Format: Decimal number, 1 decimal place.

### Average Activity Duration Seconds

```DAX
Average Activity Duration Seconds =
AVERAGE('Activity Runs'[DurationSeconds])
```

Format: Decimal number, 1 decimal place.

### Reconciliation Variance %

```DAX
Reconciliation Variance % =
DIVIDE(
	SUM('Reconciliation'[VarianceRows]),
	SUM('Reconciliation'[SourceRowCount])
)
```

Format: Percentage, 2 decimal places.

### Reconciliation Breaches

```DAX
Reconciliation Breaches =
CALCULATE(
	COUNTROWS('Reconciliation'),
	'Reconciliation'[Passed] = FALSE()
)
```

Format: Whole number.

### DQ Failure Rows

Create this measure on the `Data Quality` table.

```DAX
DQ Failure Rows =
SUM('Data Quality'[RowsFailed])
```

Format: Whole number with thousands separator.

### DQ Rules Triggered

Create this measure on the `Data Quality` table.

```DAX
DQ Rules Triggered =
DISTINCTCOUNT('Data Quality'[RuleCode])
```

Format: Whole number.

### Rejected Row Rate %

Create this measure on the `Data Quality` table.

```DAX
Rejected Row Rate % =
DIVIDE(
	[Total Rows Rejected],
	[Total Rows Processed]
)
```

Format: Percentage, 2 decimal places.

### Gold Validation Failures

```DAX
Gold Validation Failures =
CALCULATE(
	COUNTROWS('Data Quality'),
	CONTAINSSTRING('Data Quality'[RuleCode], "Gold")
)
```

Format: Whole number.

### Pipeline Health Status

```DAX
Pipeline Health Status =
SWITCH(
	TRUE(),
	[Failed Runs] > 0, "Failed",
	[Reconciliation Breaches] > 0, "Needs Review",
	[DQ Failure Rows] > 0, "DQ Findings",
	"Healthy"
)
```

Format: Text.

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
