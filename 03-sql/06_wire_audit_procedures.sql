-- Wire existing pipeline audit procedures to the dedicated dashboard tables.
-- Existing PipelineRunLog/ValidationLog writes are intentionally preserved.

CREATE OR ALTER PROCEDURE audit.SP_LogPipelineStart
    @PipelineRunId VARCHAR(100), @ParentRunId VARCHAR(100) = NULL, @PipelineName VARCHAR(200),
    @Environment VARCHAR(20), @LoadType VARCHAR(20), @EntityName VARCHAR(100) = NULL,
    @SourceSystem VARCHAR(100) = NULL, @RunDate DATE = NULL, @TriggeredBy VARCHAR(100) = 'Manual'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StartTimeUtc DATETIME2(3)=SYSUTCDATETIME();
    DELETE FROM audit.PipelineRunLog WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL);
    INSERT INTO audit.PipelineRunLog
    (PipelineRunId,ParentRunId,PipelineName,Environment,LoadType,EntityName,SourceSystem,RunDate,StartTime,[Status],TriggeredBy,LoggedAt)
    VALUES (@PipelineRunId,@ParentRunId,@PipelineName,@Environment,@LoadType,@EntityName,@SourceSystem,@RunDate,@StartTimeUtc,'Running',@TriggeredBy,@StartTimeUtc);

    EXEC audit.SP_LogDedicatedPipelineRun @RunId=@PipelineRunId,@ParentRunId=@ParentRunId,@PipelineName=@PipelineName,
        @Environment=@Environment,@LoadType=@LoadType,@EntityName=@EntityName,@SourceSystem=@SourceSystem,
        @RunDate=@RunDate,@Status='Running',@StartTimeUtc=@StartTimeUtc,@TriggeredBy=@TriggeredBy;
    EXEC audit.SP_LogDedicatedActivity @ActivityRunId=@PipelineRunId,@PipelineRunId=@PipelineRunId,
        @PipelineName=@PipelineName,@ActivityName='PipelineStart',@ActivityType='Pipeline',@EntityName=@EntityName,
        @Layer=NULL,@StartTimeUtc=@StartTimeUtc,@EndTimeUtc=@StartTimeUtc,@Status='Succeeded';
    SELECT @PipelineRunId AS RunID;
END
GO

CREATE OR ALTER PROCEDURE audit.SP_LogRowCounts
    @PipelineRunId VARCHAR(100), @EntityName VARCHAR(100) = NULL,
    @SourceRowCount BIGINT, @TargetRowCount BIGINT, @RejectedRowCount BIGINT = 0
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE audit.PipelineRunLog
    SET SourceRowCount=@SourceRowCount,TargetRowCount=@TargetRowCount,RejectedRowCount=@RejectedRowCount
    WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL);

    IF @EntityName IS NOT NULL
        EXEC audit.SP_LogReconciliation @PipelineRunId=@PipelineRunId,@EntityName=@EntityName,
            @SourceRowCount=@SourceRowCount,@TargetRowCount=@TargetRowCount,@RejectedRowCount=@RejectedRowCount;
END
GO

CREATE OR ALTER PROCEDURE audit.SP_LogPipelineEnd
    @PipelineRunId VARCHAR(100), @EntityName VARCHAR(100) = NULL,
    @Status VARCHAR(20), @ErrorMessage VARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EndTime DATETIME2(3)=SYSUTCDATETIME();
    UPDATE audit.PipelineRunLog
    SET EndTime=@EndTime,[Status]=@Status,ErrorMessage=@ErrorMessage,
        DurationSeconds=DATEDIFF(SECOND,StartTime,@EndTime)
    WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL);

    DECLARE @StartTime DATETIME2(3)=(SELECT TOP 1 StartTime FROM audit.PipelineRunLog WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL));
    DECLARE @PipelineName VARCHAR(200)=(SELECT TOP 1 PipelineName FROM audit.PipelineRunLog WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL));
    DECLARE @ParentRunId VARCHAR(100)=(SELECT TOP 1 ParentRunId FROM audit.PipelineRunLog WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL));
    DECLARE @Environment VARCHAR(20)=(SELECT TOP 1 Environment FROM audit.PipelineRunLog WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL));
    DECLARE @LoadType VARCHAR(20)=(SELECT TOP 1 LoadType FROM audit.PipelineRunLog WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL));
    DECLARE @SourceSystem VARCHAR(100)=(SELECT TOP 1 SourceSystem FROM audit.PipelineRunLog WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL));
    DECLARE @RunDate DATE=(SELECT TOP 1 RunDate FROM audit.PipelineRunLog WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL));
    DECLARE @TriggeredBy VARCHAR(100)=(SELECT TOP 1 TriggeredBy FROM audit.PipelineRunLog WHERE PipelineRunId=@PipelineRunId AND (EntityName=@EntityName OR @EntityName IS NULL));
    DECLARE @EffectiveStartTime DATETIME2(3)=ISNULL(@StartTime,@EndTime);
    SET @Environment=ISNULL(@Environment,'POC');
    SET @LoadType=ISNULL(@LoadType,'Full');
    EXEC audit.SP_LogDedicatedPipelineRun @RunId=@PipelineRunId,@ParentRunId=@ParentRunId,@PipelineName=@PipelineName,
        @Environment=@Environment,@LoadType=@LoadType,@EntityName=@EntityName,
        @SourceSystem=@SourceSystem,@RunDate=@RunDate,@Status=@Status,@StartTimeUtc=@EffectiveStartTime,
        @EndTimeUtc=@EndTime,@ErrorMessage=@ErrorMessage,@TriggeredBy=@TriggeredBy;
    EXEC audit.SP_LogDedicatedActivity @ActivityRunId=@PipelineRunId,@PipelineRunId=@PipelineRunId,
        @PipelineName=@PipelineName,@ActivityName='PipelineEnd',@ActivityType='Pipeline',@EntityName=@EntityName,
        @StartTimeUtc=@EffectiveStartTime,@EndTimeUtc=@EndTime,@Status=@Status,@ErrorMessage=@ErrorMessage;
END
GO

PRINT 'Existing audit procedures now populate dedicated audit tables.';
