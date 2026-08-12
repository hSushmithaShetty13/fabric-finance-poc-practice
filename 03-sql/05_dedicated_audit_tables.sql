-- Dedicated monitoring audit surfaces for the Finance Operations dashboard.
-- Existing PipelineRunLog/ValidationLog remain backward-compatible; these tables
-- provide the original repo's pipeline_run/activity_run/data_quality/reconciliation contract.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'audit')
    EXEC ('CREATE SCHEMA audit');
GO

IF OBJECT_ID('audit.PipelineRun') IS NULL
BEGIN
    CREATE TABLE audit.PipelineRun
    (
        RunId            VARCHAR(100) NOT NULL,
        ParentRunId      VARCHAR(100) NULL,
        PipelineName     VARCHAR(200) NOT NULL,
        Environment      VARCHAR(20) NOT NULL,
        LoadType         VARCHAR(20) NOT NULL,
        EntityName       VARCHAR(100) NULL,
        SourceSystem     VARCHAR(100) NULL,
        RunDate          DATE NULL,
        StartTimeUtc     DATETIME2(3) NOT NULL,
        EndTimeUtc       DATETIME2(3) NULL,
        DurationSeconds  INT NULL,
        [Status]         VARCHAR(20) NOT NULL,
        ErrorMessage     VARCHAR(4000) NULL,
        TriggeredBy      VARCHAR(100) NULL,
        LoggedAtUtc      DATETIME2(3) NOT NULL
    );
END
GO

IF OBJECT_ID('audit.ActivityRun') IS NULL
BEGIN
    CREATE TABLE audit.ActivityRun
    (
        ActivityRunId    VARCHAR(100) NOT NULL,
        PipelineRunId    VARCHAR(100) NOT NULL,
        RootRunId        VARCHAR(100) NOT NULL,
        PipelineName     VARCHAR(200) NOT NULL,
        ActivityName     VARCHAR(200) NOT NULL,
        ActivityType     VARCHAR(100) NOT NULL,
        EntityName       VARCHAR(100) NULL,
        Layer            VARCHAR(30) NULL,
        StartTimeUtc     DATETIME2(3) NULL,
        EndTimeUtc       DATETIME2(3) NULL,
        DurationSeconds  INT NULL,
        [Status]         VARCHAR(20) NOT NULL,
        RowsRead         BIGINT NULL,
        RowsWritten      BIGINT NULL,
        RowsRejected     BIGINT NULL,
        RowsInserted     BIGINT NULL,
        RowsUpdated      BIGINT NULL,
        ErrorCode        VARCHAR(100) NULL,
        ErrorMessage     VARCHAR(4000) NULL,
        LoggedAtUtc      DATETIME2(3) NOT NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('audit.ActivityRun') AND name='RootRunId')
    ALTER TABLE audit.ActivityRun ADD RootRunId VARCHAR(100) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('audit.ActivityRun') AND name='RowsInserted')
    ALTER TABLE audit.ActivityRun ADD RowsInserted BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('audit.ActivityRun') AND name='RowsUpdated')
    ALTER TABLE audit.ActivityRun ADD RowsUpdated BIGINT NULL;
GO

UPDATE ar
SET RootRunId=COALESCE(NULLIF(pr.ParentRunId,''),ar.PipelineRunId)
FROM audit.ActivityRun ar
LEFT JOIN audit.PipelineRun pr ON pr.RunId=ar.PipelineRunId
WHERE ar.RootRunId IS NULL;
GO

IF OBJECT_ID('audit.DataQuality') IS NULL
BEGIN
    CREATE TABLE audit.DataQuality
    (
        DataQualityId    BIGINT NOT NULL,
        PipelineRunId    VARCHAR(100) NOT NULL,
        EntityName       VARCHAR(100) NOT NULL,
        RuleCode         VARCHAR(200) NOT NULL,
        RuleDescription  VARCHAR(500) NULL,
        Severity         VARCHAR(20) NOT NULL,
        RowsFailed       BIGINT NOT NULL,
        RejectTable      VARCHAR(200) NULL,
        CheckedAtUtc     DATETIME2(3) NOT NULL
    );
END
GO

IF OBJECT_ID('audit.Reconciliation') IS NULL
BEGIN
    CREATE TABLE audit.Reconciliation
    (
        ReconciliationId BIGINT NOT NULL,
        PipelineRunId    VARCHAR(100) NOT NULL,
        EntityName       VARCHAR(100) NOT NULL,
        SourceRowCount   BIGINT NOT NULL,
        TargetRowCount   BIGINT NOT NULL,
        RejectedRowCount BIGINT NOT NULL,
        VarianceRows     BIGINT NOT NULL,
        VariancePct      DECIMAL(18,4) NOT NULL,
        TolerancePct     DECIMAL(18,4) NOT NULL,
        Passed           BIT NOT NULL,
        CheckedAtUtc     DATETIME2(3) NOT NULL
    );
END
GO

CREATE OR ALTER PROCEDURE audit.SP_LogDedicatedPipelineRun
    @RunId VARCHAR(100), @ParentRunId VARCHAR(100) = NULL, @PipelineName VARCHAR(200),
    @Environment VARCHAR(20), @LoadType VARCHAR(20), @EntityName VARCHAR(100) = NULL,
    @SourceSystem VARCHAR(100) = NULL, @RunDate DATE = NULL, @Status VARCHAR(20),
    @StartTimeUtc DATETIME2(3), @EndTimeUtc DATETIME2(3) = NULL,
    @ErrorMessage VARCHAR(4000) = NULL, @TriggeredBy VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM audit.PipelineRun WHERE RunId = @RunId AND ISNULL(EntityName,'') = ISNULL(@EntityName,'');
    INSERT INTO audit.PipelineRun
    (RunId,ParentRunId,PipelineName,Environment,LoadType,EntityName,SourceSystem,RunDate,
     StartTimeUtc,EndTimeUtc,DurationSeconds,[Status],ErrorMessage,TriggeredBy,LoggedAtUtc)
    VALUES
    (@RunId,@ParentRunId,@PipelineName,@Environment,@LoadType,@EntityName,@SourceSystem,@RunDate,
     @StartTimeUtc,@EndTimeUtc,CASE WHEN @EndTimeUtc IS NULL THEN NULL ELSE DATEDIFF(SECOND,@StartTimeUtc,@EndTimeUtc) END,
     @Status,@ErrorMessage,@TriggeredBy,SYSUTCDATETIME());
END
GO

CREATE OR ALTER PROCEDURE audit.SP_LogDedicatedActivity
    @ActivityRunId VARCHAR(100), @PipelineRunId VARCHAR(100), @PipelineName VARCHAR(200),
    @ActivityName VARCHAR(200), @ActivityType VARCHAR(100), @EntityName VARCHAR(100) = NULL,
    @Layer VARCHAR(30) = NULL, @StartTimeUtc DATETIME2(3) = NULL, @EndTimeUtc DATETIME2(3) = NULL,
    @Status VARCHAR(20), @RowsRead BIGINT = NULL, @RowsWritten BIGINT = NULL,
    @RowsRejected BIGINT = NULL, @RowsInserted BIGINT = NULL, @RowsUpdated BIGINT = NULL,
    @ErrorCode VARCHAR(100) = NULL, @ErrorMessage VARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @RootRunId VARCHAR(100)=COALESCE(
        (SELECT TOP 1 NULLIF(ParentRunId,'') FROM audit.PipelineRun WHERE RunId=@PipelineRunId),
        @PipelineRunId);
    DECLARE @ExistingRowsRead BIGINT=(SELECT MAX(RowsRead) FROM audit.ActivityRun WHERE ActivityRunId=@ActivityRunId);
    DECLARE @ExistingRowsWritten BIGINT=(SELECT MAX(RowsWritten) FROM audit.ActivityRun WHERE ActivityRunId=@ActivityRunId);
    DECLARE @ExistingRowsRejected BIGINT=(SELECT MAX(RowsRejected) FROM audit.ActivityRun WHERE ActivityRunId=@ActivityRunId);
    DECLARE @ExistingRowsInserted BIGINT=(SELECT MAX(RowsInserted) FROM audit.ActivityRun WHERE ActivityRunId=@ActivityRunId);
    DECLARE @ExistingRowsUpdated BIGINT=(SELECT MAX(RowsUpdated) FROM audit.ActivityRun WHERE ActivityRunId=@ActivityRunId);

    DELETE FROM audit.ActivityRun WHERE ActivityRunId=@ActivityRunId;
    INSERT INTO audit.ActivityRun
    (ActivityRunId,PipelineRunId,RootRunId,PipelineName,ActivityName,ActivityType,EntityName,Layer,
     StartTimeUtc,EndTimeUtc,DurationSeconds,[Status],RowsRead,RowsWritten,RowsRejected,RowsInserted,RowsUpdated,
     ErrorCode,ErrorMessage,LoggedAtUtc)
    VALUES
    (@ActivityRunId,@PipelineRunId,@RootRunId,@PipelineName,@ActivityName,@ActivityType,@EntityName,@Layer,
     @StartTimeUtc,@EndTimeUtc,CASE WHEN @StartTimeUtc IS NULL OR @EndTimeUtc IS NULL THEN NULL ELSE DATEDIFF(SECOND,@StartTimeUtc,@EndTimeUtc) END,
     @Status,COALESCE(@RowsRead,@ExistingRowsRead),COALESCE(@RowsWritten,@ExistingRowsWritten),
     COALESCE(@RowsRejected,@ExistingRowsRejected),COALESCE(@RowsInserted,@ExistingRowsInserted),
     COALESCE(@RowsUpdated,@ExistingRowsUpdated),@ErrorCode,@ErrorMessage,SYSUTCDATETIME());
END
GO

CREATE OR ALTER PROCEDURE audit.SP_LogReconciliation
    @PipelineRunId VARCHAR(100), @EntityName VARCHAR(100), @SourceRowCount BIGINT,
    @TargetRowCount BIGINT, @RejectedRowCount BIGINT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TolerancePct DECIMAL(18,4) = ISNULL((SELECT TolerancePct FROM control.SourceConfig WHERE EntityName=@EntityName),0);
    DECLARE @VarianceRows BIGINT = ABS(@SourceRowCount - @TargetRowCount);
    DECLARE @VariancePct DECIMAL(18,4) = CASE
        WHEN @SourceRowCount=0 AND @TargetRowCount=0 THEN 0
        WHEN @SourceRowCount=0 THEN 100
        ELSE @VarianceRows * 100.0 / @SourceRowCount
    END;
    INSERT INTO audit.Reconciliation
    (ReconciliationId,PipelineRunId,EntityName,SourceRowCount,TargetRowCount,RejectedRowCount,
     VarianceRows,VariancePct,TolerancePct,Passed,CheckedAtUtc)
    VALUES
    (ABS(CHECKSUM(NEWID())),@PipelineRunId,@EntityName,@SourceRowCount,@TargetRowCount,@RejectedRowCount,
     @VarianceRows,@VariancePct,@TolerancePct,CASE WHEN @VariancePct <= @TolerancePct THEN 1 ELSE 0 END,SYSUTCDATETIME());
END
GO

CREATE OR ALTER PROCEDURE audit.SP_LogDataQuality
    @PipelineRunId VARCHAR(100), @EntityName VARCHAR(100), @RuleCode VARCHAR(200),
    @RowsFailed BIGINT, @RuleDescription VARCHAR(500) = NULL, @Severity VARCHAR(20) = 'Reject',
    @RejectTable VARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO audit.DataQuality
    (DataQualityId,PipelineRunId,EntityName,RuleCode,RuleDescription,Severity,RowsFailed,RejectTable,CheckedAtUtc)
    VALUES
    (ABS(CHECKSUM(NEWID())),@PipelineRunId,@EntityName,@RuleCode,@RuleDescription,@Severity,@RowsFailed,@RejectTable,SYSUTCDATETIME());
END
GO

CREATE OR ALTER PROCEDURE audit.sp_log_activity
    @run_id VARCHAR(100), @activity_run_id VARCHAR(100), @pipeline_name VARCHAR(200),
    @activity_name VARCHAR(200), @activity_type VARCHAR(100), @entity_name VARCHAR(100) = NULL,
    @layer VARCHAR(30) = NULL, @start_time_utc DATETIME2(3), @end_time_utc DATETIME2(3) = NULL,
    @status VARCHAR(20), @rows_read BIGINT = NULL, @rows_written BIGINT = NULL,
    @rows_rejected BIGINT = NULL, @rows_inserted BIGINT = NULL, @rows_updated BIGINT = NULL,
    @rows_skipped BIGINT = NULL, @error_code VARCHAR(100) = NULL, @error_message VARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC audit.SP_LogDedicatedActivity @ActivityRunId=@activity_run_id,@PipelineRunId=@run_id,
        @PipelineName=@pipeline_name,@ActivityName=@activity_name,@ActivityType=@activity_type,
        @EntityName=@entity_name,@Layer=@layer,@StartTimeUtc=@start_time_utc,@EndTimeUtc=@end_time_utc,
        @Status=@status,@RowsRead=@rows_read,@RowsWritten=@rows_written,@RowsRejected=@rows_rejected,
        @RowsInserted=@rows_inserted,@RowsUpdated=@rows_updated,@ErrorCode=@error_code,@ErrorMessage=@error_message;
END
GO

CREATE OR ALTER PROCEDURE audit.sp_log_dq
    @run_id VARCHAR(100), @entity_name VARCHAR(100), @rule_code VARCHAR(200),
    @rule_description VARCHAR(500), @severity VARCHAR(20), @rows_failed BIGINT,
    @reject_table VARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC audit.SP_LogDataQuality @PipelineRunId=@run_id,@EntityName=@entity_name,@RuleCode=@rule_code,
        @RuleDescription=@rule_description,@Severity=@severity,@RowsFailed=@rows_failed,@RejectTable=@reject_table;
END
GO

CREATE OR ALTER PROCEDURE audit.sp_log_reconciliation
    @run_id VARCHAR(100), @entity_name VARCHAR(100), @bronze_count BIGINT,
    @silver_count BIGINT, @gold_count BIGINT = NULL, @tolerance_pct DECIMAL(18,4)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC audit.SP_LogReconciliation @PipelineRunId=@run_id,@EntityName=@entity_name,
        @SourceRowCount=@bronze_count,@TargetRowCount=@silver_count,@RejectedRowCount=0;
END
GO

PRINT 'Dedicated audit tables and procedures created.';
