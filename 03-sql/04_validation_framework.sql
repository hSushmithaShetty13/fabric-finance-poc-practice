-------------------------------------------------------------------------------
-- 04_validation_framework.sql
-- Target: WH_Finance_Gold (workspace WS_Finance_POC), Microsoft Fabric Warehouse, T-SQL
--
-- Rules-driven validation + row-count reconciliation, called by
-- NB_ROW_RECONCILIATION / PL_GOLD_LOAD after each entity's Silver load.
-- Each rule writes a Pass/Fail row to audit.ValidationLog.
-------------------------------------------------------------------------------

IF OBJECT_ID('audit.SP_RunValidation') IS NOT NULL DROP PROCEDURE audit.SP_RunValidation;
GO
CREATE PROCEDURE audit.SP_RunValidation
    @PipelineRunId VARCHAR(50),
    @EntityName    VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM audit.ValidationLog WHERE PipelineRunId = @PipelineRunId AND RuleName LIKE @EntityName + ':%';

    DECLARE @now DATETIME2(3) = SYSUTCDATETIME();

    ---------------------------------------------------------------------------
    -- RULE (RowCount): Bronze vs Silver row-count reconciliation, tolerance
    -- pulled from control.SourceConfig (this IS audit.reconciliation in effect)
    ---------------------------------------------------------------------------
    DECLARE @bronze BIGINT = 0, @silver BIGINT = 0, @tolerance DECIMAL(9,4) = 1.0;

    SELECT @tolerance = TolerancePct FROM control.SourceConfig WHERE EntityName = @EntityName;

    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT @b = (SELECT COUNT_BIG(*) FROM LH_Finance.dbo.' + QUOTENAME(@EntityName) + N'),
               @s = (SELECT COUNT_BIG(*) FROM LH_Finance.dbo.' + QUOTENAME('Silver_' + @EntityName) + N')';
    EXEC sp_executesql @sql, N'@b BIGINT OUTPUT, @s BIGINT OUTPUT', @b=@bronze OUTPUT, @s=@silver OUTPUT;

    DECLARE @variance DECIMAL(9,4) = CASE WHEN @bronze = 0 THEN 0 ELSE ABS(@bronze - @silver) * 100.0 / @bronze END;

    INSERT INTO audit.ValidationLog (PipelineRunId, RuleName, RuleCategory, Severity, Expected, Actual, [Result], CheckedAt)
    VALUES (@PipelineRunId, @EntityName + ': Bronze-Silver row reconciliation', 'RowCount', 'Error',
            CONCAT('variance<=', @tolerance, '%'), CONCAT(FORMAT(@variance,'N4'), '% (bronze=', @bronze, ', silver=', @silver, ')'),
            CASE WHEN @variance <= @tolerance THEN 'Pass' ELSE 'Fail' END, @now);

    ---------------------------------------------------------------------------
    -- Overall status for this entity: FAIL if any Error-severity rule failed.
    ---------------------------------------------------------------------------
    DECLARE @errorFails INT = (SELECT COUNT(*) FROM audit.ValidationLog
        WHERE PipelineRunId = @PipelineRunId AND RuleName LIKE @EntityName + ':%' AND Severity = 'Error' AND [Result] = 'Fail');

    SELECT CASE WHEN @errorFails = 0 THEN 'Pass' ELSE 'Fail' END AS ValidationStatus,
           @errorFails AS FailedErrorRules, @bronze AS BronzeCount, @silver AS SilverCount, @variance AS VariancePct;
END
GO

-------------------------------------------------------------------------------
-- Gold-level validation: no null dim keys / no dupes / non-negative amounts
-------------------------------------------------------------------------------
IF OBJECT_ID('audit.SP_RunGoldValidation') IS NOT NULL DROP PROCEDURE audit.SP_RunGoldValidation;
GO
CREATE PROCEDURE audit.SP_RunGoldValidation
    @PipelineRunId VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(3) = SYSUTCDATETIME();

    DECLARE @nullKeys BIGINT = (SELECT COUNT(*) FROM gold.FactRevenue
        WHERE LoadRunId = @PipelineRunId AND (CustomerKey IS NULL OR GLAccountKey IS NULL OR DateKey IS NULL));
    INSERT INTO audit.ValidationLog (PipelineRunId, RuleName, RuleCategory, Severity, Expected, Actual, [Result], CheckedAt)
    VALUES (@PipelineRunId, 'Gold: No null dimension keys in fact', 'DataQuality', 'Error', '0', CAST(@nullKeys AS VARCHAR(20)),
            CASE WHEN @nullKeys = 0 THEN 'Pass' ELSE 'Fail' END, @now);

    DECLARE @dupes BIGINT = (SELECT COUNT(*) FROM (
        SELECT LineID FROM gold.FactRevenue WHERE LoadRunId = @PipelineRunId GROUP BY LineID HAVING COUNT(*) > 1) d);
    INSERT INTO audit.ValidationLog (PipelineRunId, RuleName, RuleCategory, Severity, Expected, Actual, [Result], CheckedAt)
    VALUES (@PipelineRunId, 'Gold: No duplicate invoice lines', 'DataQuality', 'Error', '0', CAST(@dupes AS VARCHAR(20)),
            CASE WHEN @dupes = 0 THEN 'Pass' ELSE 'Fail' END, @now);

    DECLARE @neg BIGINT = (SELECT COUNT(*) FROM gold.FactRevenue WHERE LoadRunId = @PipelineRunId AND LineAmountUSD < 0);
    INSERT INTO audit.ValidationLog (PipelineRunId, RuleName, RuleCategory, Severity, Expected, Actual, [Result], CheckedAt)
    VALUES (@PipelineRunId, 'Gold: Revenue amounts non-negative', 'BusinessRule', 'Error', '0', CAST(@neg AS VARCHAR(20)),
            CASE WHEN @neg = 0 THEN 'Pass' ELSE 'Fail' END, @now);

    DECLARE @errorFails INT = (SELECT COUNT(*) FROM audit.ValidationLog
        WHERE PipelineRunId = @PipelineRunId AND RuleName LIKE 'Gold:%' AND Severity='Error' AND [Result]='Fail');
    SELECT CASE WHEN @errorFails = 0 THEN 'Pass' ELSE 'Fail' END AS ValidationStatus, @errorFails AS FailedErrorRules;
END
GO

IF OBJECT_ID('audit.vw_ValidationResults') IS NOT NULL DROP VIEW audit.vw_ValidationResults;
GO
CREATE VIEW audit.vw_ValidationResults
AS
SELECT v.PipelineRunId, r.PipelineName, r.Environment, r.EntityName, r.RunDate,
       v.RuleName, v.RuleCategory, v.Severity, v.Expected, v.Actual, v.[Result], v.CheckedAt
FROM audit.ValidationLog v
JOIN audit.PipelineRunLog r ON r.PipelineRunId = v.PipelineRunId;
GO

PRINT 'Validation framework provisioned: SP_RunValidation (per-entity recon), SP_RunGoldValidation, vw_ValidationResults.';
