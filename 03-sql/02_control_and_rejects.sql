-------------------------------------------------------------------------------
-- 02_control_and_rejects.sql
-- Target: WH_Finance_Gold (workspace WS_Finance_POC), Microsoft Fabric Warehouse, T-SQL
--
-- Metadata-driven control tables that drive PL_BRONZE_INGEST / PL_MASTER_ORCHESTRATOR,
-- plus the reject-row landing tables written by the Silver Dataflow Gen2 items.
-------------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'control')
    EXEC ('CREATE SCHEMA control');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver_rejects')
    EXEC ('CREATE SCHEMA silver_rejects');
GO

-------------------------------------------------------------------------------
-- control.SourceConfig -- one row per source entity, drives the ForEach
-------------------------------------------------------------------------------
IF OBJECT_ID('control.SourceConfig') IS NOT NULL DROP TABLE control.SourceConfig;
GO
CREATE TABLE control.SourceConfig
(
    EntityName       VARCHAR(100)  NOT NULL,
    SourcePath       VARCHAR(500)  NOT NULL,   -- Files/landing/<entity>/
    FilePattern      VARCHAR(200)  NOT NULL,
    BronzeTable      VARCHAR(200)  NOT NULL,
    SilverTable      VARCHAR(200)  NOT NULL,
    LoadMode         VARCHAR(20)   NOT NULL,   -- Full / Incremental
    WatermarkColumn  VARCHAR(100)  NULL,
    TolerancePct     DECIMAL(9,4)  NOT NULL,
    IsActive         BIT           NOT NULL,
    RejectPredicate  VARCHAR(1000) NULL,       -- SQL boolean expression identifying bad rows
    RejectColumns    VARCHAR(500)  NULL        -- comma list of columns to copy into silver_rejects
);
GO

INSERT INTO control.SourceConfig
    (EntityName, SourcePath, FilePattern, BronzeTable, SilverTable, LoadMode, WatermarkColumn, TolerancePct, IsActive, RejectPredicate, RejectColumns)
VALUES
    ('Customers',     'Files/landing/customers/',      '*.csv', 'Customers',     'Silver_Customers',     'Full',        NULL,          0.5, 1,
     'CustomerName IS NULL OR LEN(Country) <> 2',
     'CustomerID,CustomerName,Country,Currency,CreditLimit,IsActive,CreatedDate'),
    ('Invoices',      'Files/landing/invoices/',        '*.csv', 'Invoices',      'Silver_Invoices',      'Incremental', 'InvoiceDate', 1.0, 1,
     'TRY_CAST(InvoiceDate AS DATE) IS NULL OR TRY_CAST(InvoiceDate AS DATE) > CAST(SYSUTCDATETIME() AS DATE) OR CustomerID NOT IN (SELECT CustomerID FROM LH_Finance.dbo.Customers)',
     'InvoiceID,CustomerID,InvoiceDate,DueDate,Currency,Status'),
    ('InvoiceLines',  'Files/landing/invoicelines/',    '*.csv', 'InvoiceLines',  'Silver_InvoiceLines',  'Full',        NULL,          1.0, 1,
     'TRY_CAST(Quantity AS INT) < 0 OR TRY_CAST(UnitPrice AS DECIMAL(18,2)) IS NULL OR InvoiceID NOT IN (SELECT InvoiceID FROM LH_Finance.dbo.Invoices)',
     'LineID,InvoiceID,LineNumber,GLAccountID,Quantity,UnitPrice'),
    ('Payments',      'Files/landing/payments/',        '*.csv', 'Payments',      'Silver_Payments',      'Incremental', 'PaymentDate', 1.0, 1,
     'PaymentMethod IS NULL OR LTRIM(RTRIM(PaymentMethod))='''' OR TRY_CAST(PaymentDate AS DATE) IS NULL',
     'PaymentID,InvoiceID,PaymentDate,Amount,Currency,PaymentMethod'),
    ('ExchangeRates', 'Files/landing/exchangerates/',   '*.csv', 'ExchangeRates', 'Silver_ExchangeRates', 'Full',        NULL,          2.0, 1,
     'TRY_CAST(Rate AS DECIMAL(18,6)) IS NULL OR TRY_CAST(Rate AS DECIMAL(18,6)) <= 0',
     'RateDate,FromCurrency,ToCurrency,Rate'),
    ('GLAccounts',    'Files/landing/glaccounts/',      '*.csv', 'GLAccounts',    'Silver_GLAccounts',    'Full',        NULL,          0.0, 1,
     'AccountName IS NULL OR LTRIM(RTRIM(AccountName))='''' OR TRY_CAST(IsActive AS INT) = 0',
     'GLAccountID,AccountName,AccountType,IsActive');
GO

-------------------------------------------------------------------------------
-- control.Watermark -- high-watermark for incremental entities
-------------------------------------------------------------------------------
IF OBJECT_ID('control.Watermark') IS NOT NULL DROP TABLE control.Watermark;
GO
CREATE TABLE control.Watermark
(
    EntityName        VARCHAR(100)  NOT NULL,
    WatermarkColumn   VARCHAR(100)  NOT NULL,
    WatermarkValue    VARCHAR(100)  NOT NULL,
    LastUpdatedUtc    DATETIME2(3)  NOT NULL
);
GO

IF OBJECT_ID('control.SP_UpdateWatermark') IS NOT NULL DROP PROCEDURE control.SP_UpdateWatermark;
GO
CREATE PROCEDURE control.SP_UpdateWatermark
    @EntityName      VARCHAR(100),
    @WatermarkColumn VARCHAR(100),
    @WatermarkValue  VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM control.Watermark WHERE EntityName = @EntityName;
    INSERT INTO control.Watermark (EntityName, WatermarkColumn, WatermarkValue, LastUpdatedUtc)
    VALUES (@EntityName, @WatermarkColumn, @WatermarkValue, SYSUTCDATETIME());
END
GO

-------------------------------------------------------------------------------
-- silver_rejects.* -- rejected rows routed here by DF_SILVER_<entity> (Dataflow Gen2)
-------------------------------------------------------------------------------
IF OBJECT_ID('silver_rejects.Customers') IS NOT NULL DROP TABLE silver_rejects.Customers;
GO
CREATE TABLE silver_rejects.Customers
(
    RunId VARCHAR(50), RejectedAtUtc DATETIME2(3), RuleCode VARCHAR(100),
    CustomerID VARCHAR(50), CustomerName VARCHAR(200), Country VARCHAR(50),
    Currency VARCHAR(10), CreditLimit VARCHAR(50), IsActive VARCHAR(10),
    CreatedDate VARCHAR(50), RawRow VARCHAR(4000)
);
GO

IF OBJECT_ID('silver_rejects.Invoices') IS NOT NULL DROP TABLE silver_rejects.Invoices;
GO
CREATE TABLE silver_rejects.Invoices
(
    RunId VARCHAR(50), RejectedAtUtc DATETIME2(3), RuleCode VARCHAR(100),
    InvoiceID VARCHAR(50), CustomerID VARCHAR(50), InvoiceDate VARCHAR(50),
    DueDate VARCHAR(50), Currency VARCHAR(10), [Status] VARCHAR(30), RawRow VARCHAR(4000)
);
GO

IF OBJECT_ID('silver_rejects.InvoiceLines') IS NOT NULL DROP TABLE silver_rejects.InvoiceLines;
GO
CREATE TABLE silver_rejects.InvoiceLines
(
    RunId VARCHAR(50), RejectedAtUtc DATETIME2(3), RuleCode VARCHAR(100),
    LineID VARCHAR(50), InvoiceID VARCHAR(50), LineNumber VARCHAR(50),
    GLAccountID VARCHAR(50), Quantity VARCHAR(50), UnitPrice VARCHAR(50), RawRow VARCHAR(4000)
);
GO

IF OBJECT_ID('silver_rejects.Payments') IS NOT NULL DROP TABLE silver_rejects.Payments;
GO
CREATE TABLE silver_rejects.Payments
(
    RunId VARCHAR(50), RejectedAtUtc DATETIME2(3), RuleCode VARCHAR(100),
    PaymentID VARCHAR(50), InvoiceID VARCHAR(50), PaymentDate VARCHAR(50),
    Amount VARCHAR(50), Currency VARCHAR(10), PaymentMethod VARCHAR(50), RawRow VARCHAR(4000)
);
GO

IF OBJECT_ID('silver_rejects.ExchangeRates') IS NOT NULL DROP TABLE silver_rejects.ExchangeRates;
GO
CREATE TABLE silver_rejects.ExchangeRates
(
    RunId VARCHAR(50), RejectedAtUtc DATETIME2(3), RuleCode VARCHAR(100),
    RateDate VARCHAR(50), FromCurrency VARCHAR(10), ToCurrency VARCHAR(10),
    Rate VARCHAR(50), RawRow VARCHAR(4000)
);
GO

IF OBJECT_ID('silver_rejects.GLAccounts') IS NOT NULL DROP TABLE silver_rejects.GLAccounts;
GO
CREATE TABLE silver_rejects.GLAccounts
(
    RunId VARCHAR(50), RejectedAtUtc DATETIME2(3), RuleCode VARCHAR(100),
    GLAccountID VARCHAR(50), AccountName VARCHAR(200), AccountType VARCHAR(50),
    IsActive VARCHAR(10), RawRow VARCHAR(4000)
);
GO

PRINT 'Control + silver_rejects schemas provisioned: SourceConfig (6 entities), Watermark, 6 reject tables.';
