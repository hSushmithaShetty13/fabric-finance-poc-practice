-- Power BI / Activator monitoring views.
-- These views expose the original reference repo's lowercase logical table names
-- while preserving the PascalCase physical tables used by the deployed pipelines.

CREATE OR ALTER VIEW audit.pipeline_run
AS
SELECT
    RunId AS run_id,
    ParentRunId AS parent_run_id,
    PipelineName AS pipeline_name,
    TriggeredBy AS trigger_type,
    TriggeredBy AS triggered_by,
    RunDate AS load_date,
    StartTimeUtc AS start_time_utc,
    EndTimeUtc AS end_time_utc,
    DurationSeconds AS duration_sec,
    [Status] AS status,
    CAST(NULL AS VARCHAR(100)) AS error_code,
    ErrorMessage AS error_message,
    CAST(NULL AS BIGINT) AS rows_read,
    CAST(NULL AS BIGINT) AS rows_written,
    CAST(NULL AS BIGINT) AS rows_rejected,
    LoggedAtUtc AS inserted_at_utc,
    EntityName AS entity_name,
    Environment AS environment,
    LoadType AS load_type,
    SourceSystem AS source_system
FROM audit.PipelineRun;
GO

CREATE OR ALTER VIEW audit.activity_run
AS
SELECT
    PipelineRunId AS run_id,
    RootRunId AS root_run_id,
    ActivityRunId AS activity_run_id,
    PipelineName AS pipeline_name,
    ActivityName AS activity_name,
    ActivityType AS activity_type,
    EntityName AS entity_name,
    Layer AS layer,
    StartTimeUtc AS start_time_utc,
    EndTimeUtc AS end_time_utc,
    DurationSeconds AS duration_sec,
    [Status] AS status,
    RowsRead AS rows_read,
    RowsWritten AS rows_written,
    RowsRejected AS rows_rejected,
    RowsInserted AS rows_inserted,
    RowsUpdated AS rows_updated,
    CAST(NULL AS BIGINT) AS rows_skipped,
    ErrorCode AS error_code,
    ErrorMessage AS error_message,
    LoggedAtUtc AS inserted_at_utc
FROM audit.ActivityRun;
GO

CREATE OR ALTER VIEW audit.data_quality
AS
SELECT
    PipelineRunId AS run_id,
    EntityName AS entity_name,
    RuleCode AS rule_code,
    RuleDescription AS rule_description,
    Severity AS severity,
    RowsFailed AS rows_failed,
    RejectTable AS reject_table,
    CheckedAtUtc AS detected_at_utc
FROM audit.DataQuality;
GO

CREATE OR ALTER VIEW audit.reconciliation
AS
SELECT
    PipelineRunId AS run_id,
    EntityName AS entity_name,
    SourceRowCount AS bronze_count,
    TargetRowCount AS silver_count,
    CAST(NULL AS BIGINT) AS gold_count,
    VariancePct AS variance_pct,
    TolerancePct AS tolerance_pct,
    Passed AS passed,
    RejectedRowCount AS rejected_count,
    VarianceRows AS variance_rows,
    CheckedAtUtc AS checked_at_utc
FROM audit.Reconciliation;
GO

DROP VIEW IF EXISTS audit.vw_alert_pipeline_failures;
DROP VIEW IF EXISTS audit.vw_alert_reconciliation_breaches;
DROP VIEW IF EXISTS audit.vw_alert_rejected_row_spikes;
GO

PRINT 'Monitoring dashboard views created; legacy Activator alert views removed.';
