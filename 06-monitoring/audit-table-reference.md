# Audit Table Reference

This reference explains the Finance PoC audit model in business-friendly terms. The audit tables
answer four questions: what ran, what happened inside it, did row counts reconcile, and were any
data-quality rules breached?

## Run identifiers

| Identifier | Meaning | Expected consistency |
|---|---|---|
| `RootRunId` | The master orchestration run ID. | The same value across every master, Bronze, Silver, and Gold activity in one end-to-end run. |
| `PipelineRunId` | One pipeline execution. Child pipelines use a derived ID such as `<master>-b-Customer` or `<master>-s-Customer`. | The same value for all activities inside that child pipeline, but intentionally different between master, Bronze, Silver, and Gold executions. |
| `ActivityRunId` | One logged activity event. Suffixes identify the activity, such as `-start`, `-end`, `-copy`, `-dq`, `-dc`, `-dg`, or `-fr`. | Unique for each activity within a pipeline run. |

Use `RootRunId` when a user wants the complete story for one master run. Use `PipelineRunId` when
debugging one entity and layer. Use `ActivityRunId` when diagnosing one operation.

Older `activity-granular-*` rows are synthetic validation records created before live pipeline
logging was enabled. Historical `PipelineStart` and `PipelineEnd` rows may also share an activity
ID; new runs use the unique `-start` and `-end` suffixes.

## Table overview

| Table | Grain | Purpose and significance |
|---|---|---|
| `audit.PipelineRun` | One row per pipeline execution and entity. | Current operational run header used by the Direct Lake monitoring model. Shows parent/child lineage, status, duration, entity, load type, and error. |
| `audit.ActivityRun` | One row per meaningful activity. | Detailed timeline for Lookup, Copy, Script, stored-procedure, and pipeline-boundary events. Use it to identify the slow or failed step and inspect row movement or DML impact. |
| `audit.Reconciliation` | One row per pipeline/entity count check. | Compares source and target counts, calculates variance, applies the configured tolerance, and records pass/fail. |
| `audit.DataQuality` | One row per rule result and entity. | Records how many rows failed a named DQ rule, its severity, and the reject table containing the affected records. |
| `audit.PipelineRunLog` | One row per pipeline execution and entity. | Backward-compatible operational log used by the original procedures and SQL examples. `audit.PipelineRun` is the preferred dashboard table. |
| `audit.ValidationLog` | One row per legacy validation rule result. | Stores detailed Gold validation outcomes such as null keys, duplicate invoice lines, and negative revenue. |
| `control.SourceConfig` | One row per source entity. | Drives metadata-based ingestion and holds the entity's reconciliation tolerance and reject predicate. It is configuration, not execution history. |
| `control.Watermark` | One row per incremental entity. | Stores the last successfully processed high-watermark value. Full-load entities may have no meaningful watermark. |
| `silver_rejects.<Entity>` | One row per rejected source record. | Quarantine detail used to investigate the rows counted in `audit.DataQuality`. |

## Activity row metrics

| Metric | Used for | Interpretation |
|---|---|---|
| `RowsRead` | Copy | Rows read from the source by the Copy activity. |
| `RowsWritten` | Copy | Rows written to the Bronze or Silver target by the Copy activity. |
| `RowsRejected` | Copy or classification when available. | Rows rejected by that operation. Detailed DQ rejects are also recorded in `audit.DataQuality`. |
| `RowsInserted` | Gold stored procedure | Rows inserted into a Gold dimension or fact table. |
| `RowsUpdated` | Gold stored procedure | Rows updated by a Gold procedure. For `DimCustomer`, this is the count of prior SCD2 versions closed. |

A null metric means "not applicable or not emitted." For example, Lookup and pipeline start/end
activities do not move rows, so their row metrics are null. A recorded zero means the operation
supports that metric and affected zero rows.

## Reconciliation tolerance

Tolerance is the maximum allowed percentage difference between source and target row counts:

$$
\text{VarianceRows} = |\text{SourceRowCount} - \text{TargetRowCount}|
$$

$$
\text{VariancePct} = \frac{\text{VarianceRows}}{\text{SourceRowCount}} \times 100
$$

The check passes when `VariancePct <= TolerancePct`. If both counts are zero, variance is 0%. If
the source is zero and the target is nonzero, variance is 100%.

Configured tolerances are:

| Entity | Tolerance | Meaning |
|---|---:|---|
| Customers | 0.5% | Up to 0.5% source-to-target count variance is accepted. |
| Invoices | 1.0% | Up to 1.0% variance is accepted. |
| InvoiceLines | 1.0% | Up to 1.0% variance is accepted. |
| Payments | 1.0% | Up to 1.0% variance is accepted. |
| ExchangeRates | 2.0% | Up to 2.0% variance is accepted. |
| GLAccounts | 0.0% | Exact source and target counts are required. |

Example: 1,000 source rows and 990 target rows produce 1.0% variance. That passes a 1.0%
tolerance. A target count of 980 produces 2.0% variance and fails the same tolerance.

In this PoC, Silver copies all Bronze rows and classifies bad rows separately. Therefore,
reconciliation measures transport completeness; it is not the reject-rate threshold. DQ severity
and rejected-row counts are evaluated through `audit.DataQuality` and `silver_rejects.*`.

## Trace one end-to-end run

```sql
DECLARE @RootRunId VARCHAR(100) = '<master-run-id>';

SELECT RootRunId,
       PipelineRunId,
       ActivityRunId,
       PipelineName,
       ActivityName,
       EntityName,
       [Status],
       RowsRead,
       RowsWritten,
       RowsInserted,
       RowsUpdated,
       StartTimeUtc,
       EndTimeUtc,
       ErrorMessage
FROM audit.ActivityRun
WHERE RootRunId = @RootRunId
ORDER BY StartTimeUtc, LoggedAtUtc;
```
