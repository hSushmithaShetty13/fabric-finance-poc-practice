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
        ErrorCode        VARCHAR(100) NULL,
        ErrorMessage     VARCHAR(4000) NULL,
        LoggedAtUtc      DATETIME2(3) NOT NULL
    );
END
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
    @RowsRejected BIGINT = NULL, @ErrorCode VARCHAR(100) = NULL, @ErrorMessage VARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO audit.ActivityRun
    (ActivityRunId,PipelineRunId,PipelineName,ActivityName,ActivityType,EntityName,Layer,
     StartTimeUtc,EndTimeUtc,DurationSeconds,[Status],RowsRead,RowsWritten,RowsRejected,
     ErrorCode,ErrorMessage,LoggedAtUtc)
    VALUES
    (@ActivityRunId,@PipelineRunId,@PipelineName,@ActivityName,@ActivityType,@EntityName,@Layer,
     @StartTimeUtc,@EndTimeUtc,CASE WHEN @StartTimeUtc IS NULL OR @EndTimeUtc IS NULL THEN NULL ELSE DATEDIFF(SECOND,@StartTimeUtc,@EndTimeUtc) END,
     @Status,@RowsRead,@RowsWritten,@RowsRejected,@ErrorCode,@ErrorMessage,SYSUTCDATETIME());
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
    DECLARE @VariancePct DECIMAL(18,4) = CASE WHEN @SourceRowCount=0 THEN 0 ELSE @VarianceRows * 100.0 / @SourceRowCount END;
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

PRINT 'Dedicated audit tables and procedures created.';
