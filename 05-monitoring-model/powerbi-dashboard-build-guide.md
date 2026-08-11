# Power BI Monitoring Dashboard Build Guide

Build this report in the same workspace as the PoC (`WS_Finance_POC`) using the semantic model
`Finance Operations Monitoring` or a new DirectQuery/Import model over these Warehouse views:

- `audit.pipeline_run`
- `audit.activity_run`
- `audit.data_quality`
- `audit.reconciliation`
- `control.Watermark`

Use [monitoring-measures.dax](monitoring-measures.dax) for explicit measures.

## Model setup

Recommended relationships:

| From | To | Cardinality | Direction |
|---|---|---|---|
| `activity_run[run_id]` | `pipeline_run[run_id]` | Many-to-one | Single |
| `data_quality[run_id]` | `pipeline_run[run_id]` | Many-to-one | Single |
| `reconciliation[run_id]` | `pipeline_run[run_id]` | Many-to-one | Single |
| `reconciliation[entity_name]` | `Source Config[EntityName]` | Many-to-one | Single |
| `Watermark[EntityName]` | `Source Config[EntityName]` | One-to-one or many-to-one | Single |

Hide technical IDs after relationships are created:

- `run_id`
- `parent_run_id`
- `activity_run_id`

Keep these business fields visible:

- `pipeline_name`
- `activity_name`
- `activity_type`
- `entity_name`
- `layer`
- `status`
- `start_time_utc`
- `end_time_utc`
- `duration_sec`
- `rows_read`, `rows_written`, `rows_rejected`
- `rule_code`, `rule_description`, `severity`, `rows_failed`
- `variance_pct`, `tolerance_pct`, `passed`

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
| Column chart | Axis: `pipeline_run[status]`; Values: count of `pipeline_run[run_id]` |
| Table | `pipeline_name`, `entity_name`, `status`, `start_time_utc`, `end_time_utc`, `duration_sec`, `error_message` |

Recommended filters:

- Last 24 hours on `pipeline_run[start_time_utc]`
- `pipeline_name` slicer
- `status` slicer

## Page 2 — Runs Timeline

Purpose: show orchestration ordering, parallelism, and slow steps.

Best visual: Gantt custom visual. If custom visuals are not allowed, use a matrix/table.

Gantt mapping:

| Role | Field |
|---|---|
| Task | `activity_run[activity_name]` |
| Parent/group | `activity_run[pipeline_name]` |
| Start | `activity_run[start_time_utc]` |
| End | `activity_run[end_time_utc]` |
| Legend | `activity_run[status]` |
| Tooltip | `entity_name`, `layer`, `duration_sec`, `rows_read`, `rows_written`, `error_message` |

Fallback table:

- `pipeline_name`
- `activity_name`
- `activity_type`
- `entity_name`
- `layer`
- `status`
- `start_time_utc`
- `end_time_utc`
- `duration_sec`
- `rows_read`
- `rows_written`
- `error_message`

## Page 3 — Data Quality

Purpose: show where rows were rejected and why.

| Visual | Fields / measures |
|---|---|
| Clustered bar chart | Axis: `data_quality[entity_name]`; Values: `[DQ Failure Rows]` |
| Clustered bar chart | Axis: `data_quality[rule_code]`; Values: `[DQ Failure Rows]` |
| Card | `[DQ Rules Triggered]` |
| Card | `[Rejected Row Rate %]` |
| Table | `entity_name`, `rule_code`, `rule_description`, `severity`, `rows_failed`, `reject_table`, `detected_at_utc` |

Recommended drill-through page:

- Drill through on `entity_name`
- Show all `data_quality` rows for the selected entity
- Add a link/note to inspect the physical `silver_rejects.<Entity>` table in the Warehouse

## Page 4 — Reconciliation

Purpose: compare Bronze/Silver/Gold counts and tolerance thresholds.

| Visual | Fields / measures |
|---|---|
| Line and clustered column chart | Axis: `reconciliation[entity_name]`; Columns: `bronze_count`, `silver_count`; Line: `[Reconciliation Variance %]` |
| Line chart | Axis: `reconciliation[entity_name]`; Values: `variance_pct`, `tolerance_pct` |
| Card | `[Reconciliation Breaches]` |
| Table | `run_id`, `entity_name`, `bronze_count`, `silver_count`, `gold_count`, `rejected_count`, `variance_pct`, `tolerance_pct`, `passed`, `checked_at_utc` |

Conditional formatting:

- `passed = TRUE`: green
- `passed = FALSE`: red
- `variance_pct > tolerance_pct`: red data bar or warning icon

## Page 5 — Activity Diagnostics

Purpose: quickly debug failures and slow activities.

| Visual | Fields / measures |
|---|---|
| Bar chart | Axis: `activity_run[activity_name]`; Values: `[Average Activity Duration Seconds]` |
| Matrix | Rows: `pipeline_name`, `activity_name`; Columns: `status`; Values: count of `activity_run_id` |
| Table | `run_id`, `pipeline_name`, `activity_name`, `activity_type`, `entity_name`, `status`, `rows_read`, `rows_written`, `rows_rejected`, `error_code`, `error_message` |

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
