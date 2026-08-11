-------------------------------------------------------------------------------
-- 01_audit_framework.sql
-- Target: WH_Finance_Gold (workspace WS_Finance_POC), Microsoft Fabric Warehouse, T-SQL
--
-- Creates the audit schema, the pipeline run-log table, the validation-log
-- table, and the stored procedures the master pipeline calls to log a run.
-------------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'audit')
    EXEC ('CREATE SCHEMA audit');
GO

IF OBJECT_ID('audit.PipelineRunLog') IS NOT NULL
    DROP TABLE audit.PipelineRunLog;
GO

CREATE TABLE audit.PipelineRunLog
(
    PipelineRunId    VARCHAR(50)   NOT NULL,   -- @pipeline().RunId (GUID)
    ParentRunId      VARCHAR(50)   NULL,
    PipelineName     VARCHAR(200)  NOT NULL,
    Environment      VARCHAR(20)   NOT NULL,   -- DEV / TEST / PROD
    LoadType         VARCHAR(20)   NOT NULL,   -- Full / Incremental
    EntityName       VARCHAR(100)  NULL,
    SourceSystem     VARCHAR(100)  NULL,
    RunDate          DATE          NULL,       -- logical business date
    StartTime        DATETIME2(3)  NOT NULL,
    EndTime          DATETIME2(3)  NULL,
    DurationSeconds  INT           NULL,
    [Status]         VARCHAR(20)   NOT NULL,   -- Running / Succeeded / Failed
    SourceRowCount   BIGINT        NULL,
    TargetRowCount   BIGINT        NULL,
    RejectedRowCount BIGINT        NULL,
    ErrorMessage     VARCHAR(4000) NULL,
    TriggeredBy      VARCHAR(100)  NULL,       -- Schedule / Manual / Event
    LoggedAt         DATETIME2(3)  NOT NULL
);
GO

IF OBJECT_ID('audit.ValidationLog') IS NOT NULL
    DROP TABLE audit.ValidationLog;
GO

CREATE TABLE audit.ValidationLog
(
    PipelineRunId  VARCHAR(50)   NOT NULL,
    RuleName       VARCHAR(200)  NOT NULL,
    RuleCategory   VARCHAR(50)   NOT NULL,   -- RowCount / DataQuality / BusinessRule
    Severity       VARCHAR(20)   NOT NULL,   -- Error / Warning
    Expected       VARCHAR(200)  NULL,
    Actual         VARCHAR(200)  NULL,
    [Result]       VARCHAR(10)   NOT NULL,   -- Pass / Fail
    CheckedAt      DATETIME2(3)  NOT NULL
);
GO

IF OBJECT_ID('audit.SP_LogPipelineStart') IS NOT NULL
    DROP PROCEDURE audit.SP_LogPipelineStart;
GO
CREATE PROCEDURE audit.SP_LogPipelineStart
    @PipelineRunId VARCHAR(50),
    @ParentRunId   VARCHAR(50)  = NULL,
    @PipelineName  VARCHAR(200),
    @Environment   VARCHAR(20),
    @LoadType      VARCHAR(20),
    @EntityName    VARCHAR(100) = NULL,
    @SourceSystem  VARCHAR(100) = NULL,
    @RunDate       DATE         = NULL,
    @TriggeredBy   VARCHAR(100) = 'Manual'
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM audit.PipelineRunLog WHERE PipelineRunId = @PipelineRunId AND EntityName = @EntityName;

    INSERT INTO audit.PipelineRunLog
        (PipelineRunId, ParentRunId, PipelineName, Environment, LoadType, EntityName, SourceSystem,
         RunDate, StartTime, [Status], TriggeredBy, LoggedAt)
    VALUES
        (@PipelineRunId, @ParentRunId, @PipelineName, @Environment, @LoadType, @EntityName, @SourceSystem,
         @RunDate, SYSUTCDATETIME(), 'Running', @TriggeredBy, SYSUTCDATETIME());

    SELECT @PipelineRunId AS RunID;
END
GO

IF OBJECT_ID('audit.SP_LogRowCounts') IS NOT NULL
    DROP PROCEDURE audit.SP_LogRowCounts;
GO
CREATE PROCEDURE audit.SP_LogRowCounts
    @PipelineRunId    VARCHAR(50),
    @EntityName       VARCHAR(100) = NULL,
    @SourceRowCount   BIGINT,
    @TargetRowCount   BIGINT,
    @RejectedRowCount BIGINT = 0
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE audit.PipelineRunLog
    SET SourceRowCount   = @SourceRowCount,
        TargetRowCount   = @TargetRowCount,
        RejectedRowCount = @RejectedRowCount
    WHERE PipelineRunId = @PipelineRunId AND (EntityName = @EntityName OR @EntityName IS NULL);
END
GO

IF OBJECT_ID('audit.SP_LogPipelineEnd') IS NOT NULL
    DROP PROCEDURE audit.SP_LogPipelineEnd;
GO
CREATE PROCEDURE audit.SP_LogPipelineEnd
    @PipelineRunId VARCHAR(50),
    @EntityName    VARCHAR(100) = NULL,
    @Status        VARCHAR(20),
    @ErrorMessage  VARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE audit.PipelineRunLog
    SET EndTime         = SYSUTCDATETIME(),
        [Status]        = @Status,
        ErrorMessage    = @ErrorMessage,
        DurationSeconds = DATEDIFF(SECOND, StartTime, SYSUTCDATETIME())
    WHERE PipelineRunId = @PipelineRunId AND (EntityName = @EntityName OR @EntityName IS NULL);
END
GO

IF OBJECT_ID('audit.vw_RunSummary') IS NOT NULL
    DROP VIEW audit.vw_RunSummary;
GO
CREATE VIEW audit.vw_RunSummary
AS
SELECT
    PipelineRunId, ParentRunId, PipelineName, Environment, LoadType, EntityName, RunDate,
    StartTime, EndTime, DurationSeconds, [Status],
    SourceRowCount, TargetRowCount, RejectedRowCount,
    CASE WHEN SourceRowCount IS NULL OR TargetRowCount IS NULL THEN NULL
         WHEN SourceRowCount = (TargetRowCount + ISNULL(RejectedRowCount,0))
              THEN 'Reconciled'
         ELSE 'Mismatch' END AS ReconciliationStatus,
    ErrorMessage
FROM audit.PipelineRunLog;
GO

PRINT 'Audit framework provisioned: audit.PipelineRunLog, audit.ValidationLog, 4 procs, 1 view.';
