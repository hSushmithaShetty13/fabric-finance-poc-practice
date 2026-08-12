-------------------------------------------------------------------------------
-- 03_gold_warehouse_schema.sql
-- Target: WH_Finance_Gold (workspace WS_Finance_POC), Microsoft Fabric Warehouse, T-SQL
--
-- Gold-layer star schema. Bronze + Silver live as flat Delta tables in the
-- LH_Finance Lakehouse (no schema-enablement), written by PL_BRONZE_INGEST /
-- PL_SILVER_LOAD. The Gold load procedure reads Silver via a three-part
-- cross-database query: LH_Finance.dbo.Silver_<Entity> (same workspace, no
-- shortcut/mirroring required - Warehouse and Lakehouse SQL analytics
-- endpoints share the same underlying server).
-------------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
    EXEC ('CREATE SCHEMA gold');
GO

IF OBJECT_ID('gold.DimDate') IS NOT NULL DROP TABLE gold.DimDate;
GO
CREATE TABLE gold.DimDate
(
    DateKey      INT          NOT NULL,
    [Date]       DATE         NOT NULL,
    [Year]       SMALLINT     NOT NULL,
    [Quarter]    SMALLINT     NOT NULL,
    [Month]      SMALLINT     NOT NULL,
    MonthName    VARCHAR(20)  NOT NULL,
    [Day]        SMALLINT     NOT NULL,
    IsWeekend    BIT          NOT NULL
);
GO

IF OBJECT_ID('gold.DimCustomer') IS NOT NULL DROP TABLE gold.DimCustomer;
GO
CREATE TABLE gold.DimCustomer
(
    CustomerKey   INT          NOT NULL,
    CustomerID    INT          NOT NULL,
    CustomerName  VARCHAR(200) NOT NULL,
    CountryCode   VARCHAR(10)  NULL,
    Currency      CHAR(3)      NULL,
    CreditLimit   DECIMAL(18,2) NULL,
    IsActive      BIT          NOT NULL,
    ValidFromUtc  DATETIME2(3) NOT NULL,
    ValidToUtc    DATETIME2(3) NULL,      -- NULL = current (SCD2)
    IsCurrent     BIT          NOT NULL
);
GO

IF OBJECT_ID('gold.DimGLAccount') IS NOT NULL DROP TABLE gold.DimGLAccount;
GO
CREATE TABLE gold.DimGLAccount
(
    GLAccountKey  INT          NOT NULL,
    GLAccountID   INT          NOT NULL,
    AccountName   VARCHAR(200) NOT NULL,
    AccountType   VARCHAR(50)  NOT NULL,
    IsActive      BIT          NOT NULL
);
GO

IF OBJECT_ID('gold.FactRevenue') IS NOT NULL DROP TABLE gold.FactRevenue;
GO
CREATE TABLE gold.FactRevenue
(
    RevenueKey       BIGINT        NOT NULL,
    DateKey          INT           NOT NULL,
    CustomerKey      INT           NOT NULL,
    GLAccountKey     INT           NOT NULL,
    InvoiceID        INT           NOT NULL,
    LineID           INT           NOT NULL,
    Quantity         INT           NOT NULL,
    UnitPrice        DECIMAL(18,2) NOT NULL,
    LineAmount       DECIMAL(18,2) NOT NULL,
    ExchangeRate     DECIMAL(18,6) NOT NULL,
    LineAmountUSD    DECIMAL(18,2) NOT NULL,
    SourceCurrency   CHAR(3)       NOT NULL,
    LoadRunId        VARCHAR(50)   NOT NULL
);
GO

IF OBJECT_ID('gold.FactRevenue_Quarantine') IS NOT NULL DROP TABLE gold.FactRevenue_Quarantine;
GO
CREATE TABLE gold.FactRevenue_Quarantine
(
    LoadRunId     VARCHAR(50)   NOT NULL,
    InvoiceID     INT           NULL,
    LineID        INT           NULL,
    RejectReason  VARCHAR(400)  NOT NULL,
    RawPayload    VARCHAR(4000) NULL,
    QuarantinedAt DATETIME2(3)  NOT NULL
);
GO

-------------------------------------------------------------------------------
-- SCD2 upsert for DimCustomer, reading Silver from the Lakehouse cross-DB.
-------------------------------------------------------------------------------
IF OBJECT_ID('gold.SP_UpsertDimCustomer') IS NOT NULL DROP PROCEDURE gold.SP_UpsertDimCustomer;
GO
CREATE PROCEDURE gold.SP_UpsertDimCustomer
    @PipelineRunId VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StartTimeUtc DATETIME2(3)=SYSUTCDATETIME();
    DECLARE @ActivityRunId VARCHAR(100)=CONCAT(@PipelineRunId,'-dc');
    DECLARE @RowsInserted BIGINT=0;
    DECLARE @RowsUpdated BIGINT=0;

    ;WITH dedup AS (
        SELECT s.*, ROW_NUMBER() OVER (PARTITION BY s.CustomerID ORDER BY s.CreatedDate DESC) AS rn
        FROM LH_Finance.dbo.Silver_Customers s
        WHERE s.CustomerName IS NOT NULL AND LEN(s.Country) = 2
    ),
    src AS (
        SELECT CustomerID, CustomerName, Country AS CountryCode, Currency,
               CAST(TRY_CAST(IsActive AS INT) AS BIT) AS IsActive,
               TRY_CAST(CreditLimit AS DECIMAL(18,2)) AS CreditLimit
        FROM dedup WHERE rn = 1
    )
    UPDATE tgt
    SET IsCurrent = 0, ValidToUtc = SYSUTCDATETIME()
    FROM gold.DimCustomer tgt
    JOIN src ON src.CustomerID = tgt.CustomerID AND tgt.IsCurrent = 1
    WHERE HASHBYTES('SHA1', CONCAT_WS('|', tgt.CustomerName, tgt.CountryCode, tgt.Currency, tgt.IsActive))
       <> HASHBYTES('SHA1', CONCAT_WS('|', src.CustomerName, src.CountryCode, src.Currency, src.IsActive));
    SET @RowsUpdated=@@ROWCOUNT;

    ;WITH dedup AS (
        SELECT s.*, ROW_NUMBER() OVER (PARTITION BY s.CustomerID ORDER BY s.CreatedDate DESC) AS rn
        FROM LH_Finance.dbo.Silver_Customers s
        WHERE s.CustomerName IS NOT NULL AND LEN(s.Country) = 2
    )
    INSERT INTO gold.DimCustomer
        (CustomerKey, CustomerID, CustomerName, CountryCode, Currency, CreditLimit, IsActive,
         ValidFromUtc, ValidToUtc, IsCurrent)
    SELECT
        ISNULL((SELECT MAX(CustomerKey) FROM gold.DimCustomer), 0) + ROW_NUMBER() OVER (ORDER BY s.CustomerID),
        s.CustomerID, s.CustomerName, s.Country, s.Currency, TRY_CAST(s.CreditLimit AS DECIMAL(18,2)),
        CAST(TRY_CAST(s.IsActive AS INT) AS BIT), SYSUTCDATETIME(), NULL, 1
    FROM dedup s
    WHERE s.rn = 1
      AND NOT EXISTS (
        SELECT 1 FROM gold.DimCustomer d WHERE d.CustomerID = s.CustomerID AND d.IsCurrent = 1);
        SET @RowsInserted=@@ROWCOUNT;
        DECLARE @EndTimeUtc DATETIME2(3)=SYSUTCDATETIME();

        EXEC audit.SP_LogDedicatedActivity
                @ActivityRunId=@ActivityRunId,@PipelineRunId=@PipelineRunId,
                @PipelineName='PL_GOLD_LOAD',@ActivityName='SP_Upsert_DimCustomer',
                @ActivityType='StoredProcedure',@EntityName='ALL',@Layer='Gold',
                @StartTimeUtc=@StartTimeUtc,@EndTimeUtc=@EndTimeUtc,@Status='Succeeded',
                @RowsInserted=@RowsInserted,@RowsUpdated=@RowsUpdated;
END
GO

-------------------------------------------------------------------------------
-- Full-refresh upsert for DimGLAccount (reference data, no SCD needed)
-------------------------------------------------------------------------------
IF OBJECT_ID('gold.SP_UpsertDimGLAccount') IS NOT NULL DROP PROCEDURE gold.SP_UpsertDimGLAccount;
GO
CREATE PROCEDURE gold.SP_UpsertDimGLAccount
    @PipelineRunId VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StartTimeUtc DATETIME2(3)=SYSUTCDATETIME();
    DECLARE @ActivityRunId VARCHAR(100)=CONCAT(@PipelineRunId,'-dg');
    DECLARE @RowsInserted BIGINT=0;

    DELETE FROM gold.DimGLAccount;
    INSERT INTO gold.DimGLAccount (GLAccountKey, GLAccountID, AccountName, AccountType, IsActive)
    SELECT ROW_NUMBER() OVER (ORDER BY GLAccountID), GLAccountID,
           ISNULL(NULLIF(AccountName,''), CONCAT('Account ', GLAccountID)), AccountType,
           CAST(TRY_CAST(IsActive AS INT) AS BIT)
    FROM LH_Finance.dbo.Silver_GLAccounts;
    SET @RowsInserted=@@ROWCOUNT;
    DECLARE @EndTimeUtc DATETIME2(3)=SYSUTCDATETIME();

    EXEC audit.SP_LogDedicatedActivity
        @ActivityRunId=@ActivityRunId,@PipelineRunId=@PipelineRunId,
        @PipelineName='PL_GOLD_LOAD',@ActivityName='SP_Upsert_DimGLAccount',
        @ActivityType='StoredProcedure',@EntityName='ALL',@Layer='Gold',
        @StartTimeUtc=@StartTimeUtc,@EndTimeUtc=@EndTimeUtc,@Status='Succeeded',
        @RowsInserted=@RowsInserted,@RowsUpdated=0;
END
GO

-------------------------------------------------------------------------------
-- Gold fact load: reads Silver Invoices/InvoiceLines/ExchangeRates via cross-DB
-------------------------------------------------------------------------------
IF OBJECT_ID('gold.SP_LoadFactRevenue') IS NOT NULL DROP PROCEDURE gold.SP_LoadFactRevenue;
GO
CREATE PROCEDURE gold.SP_LoadFactRevenue
    @LoadRunId VARCHAR(50),
    @LoadType  VARCHAR(20) = 'Full'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StartTimeUtc DATETIME2(3)=SYSUTCDATETIME();
    DECLARE @ActivityRunId VARCHAR(100)=CONCAT(@LoadRunId,'-fr');
    DECLARE @RowsInserted BIGINT=0;

    IF @LoadType = 'Full'
        DELETE FROM gold.FactRevenue;

    ;WITH src AS (
        SELECT
            l.LineID, l.InvoiceID, i.CustomerID, l.GLAccountID,
            TRY_CAST(i.InvoiceDate AS DATE) AS InvoiceDate,
            i.Currency AS SourceCurrency,
            TRY_CAST(l.Quantity AS INT) AS Quantity,
            TRY_CAST(l.UnitPrice AS DECIMAL(18,2)) AS UnitPrice,
            ISNULL(TRY_CAST(fx.Rate AS DECIMAL(18,6)), 1.0) AS ExchangeRate
        FROM   LH_Finance.dbo.Silver_InvoiceLines AS l
        JOIN   LH_Finance.dbo.Silver_Invoices     AS i ON i.InvoiceID = l.InvoiceID
        LEFT JOIN LH_Finance.dbo.Silver_ExchangeRates AS fx
               ON fx.FromCurrency = i.Currency
              AND TRY_CAST(fx.RateDate AS DATE) = TRY_CAST(i.InvoiceDate AS DATE)
        WHERE TRY_CAST(i.InvoiceDate AS DATE) IS NOT NULL
    )
    INSERT INTO gold.FactRevenue
        (RevenueKey, DateKey, CustomerKey, GLAccountKey, InvoiceID, LineID,
         Quantity, UnitPrice, LineAmount, ExchangeRate, LineAmountUSD,
         SourceCurrency, LoadRunId)
    SELECT
        ROW_NUMBER() OVER (ORDER BY s.InvoiceID, s.LineID)
            + ISNULL((SELECT MAX(RevenueKey) FROM gold.FactRevenue), 0),
        CONVERT(INT, CONVERT(VARCHAR(8), s.InvoiceDate, 112)),
        dc.CustomerKey, dg.GLAccountKey, s.InvoiceID, s.LineID,
        s.Quantity, s.UnitPrice, s.Quantity * s.UnitPrice, s.ExchangeRate,
        CONVERT(DECIMAL(18,2), s.Quantity * s.UnitPrice * s.ExchangeRate),
        s.SourceCurrency, @LoadRunId
    FROM src AS s
    JOIN gold.DimCustomer  AS dc ON dc.CustomerID = s.CustomerID AND dc.IsCurrent = 1
    JOIN gold.DimGLAccount AS dg ON dg.GLAccountID = s.GLAccountID
    WHERE s.InvoiceDate IS NOT NULL AND s.Quantity > 0 AND s.UnitPrice IS NOT NULL;
    SET @RowsInserted=@@ROWCOUNT;
    DECLARE @EndTimeUtc DATETIME2(3)=SYSUTCDATETIME();

    EXEC audit.SP_LogDedicatedActivity
        @ActivityRunId=@ActivityRunId,@PipelineRunId=@LoadRunId,
        @PipelineName='PL_GOLD_LOAD',@ActivityName='SP_Load_FactRevenue',
        @ActivityType='StoredProcedure',@EntityName='ALL',@Layer='Gold',
        @StartTimeUtc=@StartTimeUtc,@EndTimeUtc=@EndTimeUtc,@Status='Succeeded',
        @RowsInserted=@RowsInserted,@RowsUpdated=0;
END
GO

-------------------------------------------------------------------------------
-- Seed DimDate (2025-01-01 .. 2026-12-31) -- static calendar, no pipeline needed
-------------------------------------------------------------------------------
;WITH d0 AS (SELECT n FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) t(n)),
 nums AS (SELECT a.n + b.n*10 + c.n*100 AS num FROM d0 a CROSS JOIN d0 b CROSS JOIN d0 c),
 days AS (SELECT DATEADD(DAY, num, CAST('2025-01-01' AS DATE)) AS dt FROM nums WHERE num BETWEEN 0 AND 729)
INSERT INTO gold.DimDate (DateKey, [Date], [Year], [Quarter], [Month], MonthName, [Day], IsWeekend)
SELECT CONVERT(INT, CONVERT(VARCHAR(8), dt, 112)), dt,
       DATEPART(YEAR, dt), DATEPART(QUARTER, dt), DATEPART(MONTH, dt),
       DATENAME(MONTH, dt), DATEPART(DAY, dt),
       CASE WHEN DATENAME(WEEKDAY, dt) IN ('Saturday','Sunday') THEN 1 ELSE 0 END
FROM days;
GO

PRINT 'Gold star schema provisioned: DimDate, DimCustomer(SCD2), DimGLAccount, FactRevenue (+ quarantine, SCD2 + load procs).';
