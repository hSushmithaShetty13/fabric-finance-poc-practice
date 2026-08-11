# Lessons Learned — Real Bugs Hit While Building This (and the Fixes)

Every one of these was a genuine failure encountered while building and testing this pipeline
against a live Fabric workspace. Read this before you rebuild — it'll save you the same debugging
time.

## 1. Trigger-time pipeline parameters must be FLAT JSON, not `{value, type}`

When triggering a pipeline run via
`POST /v1/workspaces/{ws}/items/{itemId}/jobs/instances?jobType=Pipeline`, the
`executionData.parameters` object must be **flat key:value pairs**:

```json
{"executionData":{"parameters":{"p_entity_name":"Customers","p_run_date":"2026-08-11"}}}
```

**Not** the ADF-classic `{"value":"Customers","type":"String"}` wrapper. Using the wrapper at
trigger time silently mis-serializes the value and causes cryptic downstream errors — e.g. a
stored-procedure activity receiving a `date` parameter fails with:

```
Error converting data type nvarchar to date.
```

even though the value you sent "looks" like a valid date string. The nested `{value:{value:
"@pipeline().parameters.X", type:"Expression"}, type:"String"}` form is still correct **inside**
the pipeline definition JSON itself (e.g. `storedProcedureParameters`) — this only applies to the
trigger-time `executionData.parameters` payload.

## 2. Copy activity + Lakehouse: don't double up on `Files/` in the folder path

`datasetSettings.typeProperties.location.folderPath` for `LakehouseLocation` is **already relative
to the Lakehouse's `Files/` root**. Two ways to get this wrong:

- Set `location.folderPath = "landing"` **and** `storeSettings.wildcardFolderPath =
  "landing/customers"` → Copy silently matches **0 files** (looks like `Files/landing/landing/
  customers`) and the pipeline reports `Completed` with **no error and no table created**. Job
  status "Completed" does **not** mean data moved — always verify the table exists and has rows.
- Set `location.folderPath = ""` and `wildcardFolderPath = "Files/landing/customers"` → 404
  `PathNotFound` (looks like `Files/Files/landing/customers`).

**Correct**: `location.folderPath = ""`, `wildcardFolderPath = "landing/customers"` (no `Files/`
prefix, no double nesting).

## 3. Lakehouse SQL analytics endpoint metadata sync lag (race condition)

After a Copy activity does an `Overwrite` into a Lakehouse Delta table, the table is immediately
visible via the Items API (`GET /v1/workspaces/{ws}/lakehouses/{id}/tables`) but can take
**30–90 seconds** to become queryable via the SQL analytics endpoint. Querying too soon gives
either:

```
Invalid object name 'TableName'.
```

or, more insidiously, a **stale parquet file reference**:

```
Failed to complete the command because the underlying location does not exist.
... file 'https://onelake.dfs.fabric.microsoft.com/.../Tables/GLAccounts/<old-guid>.parquet'.
```

**Fix**: add a `Wait` activity (60s) between any Copy-into-Lakehouse step and any subsequent
Script/Lookup activity that reads that table back via the SQL endpoint. This repo's pipelines have
these waits already built in (`Wait_SqlEndpointSync` in `PL_SILVER_LOAD`, and `Wait_<Entity>` /
`Wait_Before_Gold` in `PL_MASTER_ORCHESTRATOR`). If you still hit this intermittently, increase the
wait or add a retry-with-backoff on the reading activity.

## 4. Fabric Warehouse doesn't support `ALTER COLUMN` for type/length changes

```sql
ALTER TABLE audit.PipelineRunLog ALTER COLUMN PipelineRunId VARCHAR(100) NOT NULL;
-- Msg 24845: The specified ALTER COLUMN operation requires data validation or rewrite,
-- so it is currently not supported in this edition of SQL Server.
```

Fabric's Warehouse engine doesn't support in-place `ALTER COLUMN` for type changes (unlike Azure
SQL DB). If a generated ID (e.g. `pipeline().RunId` + a descriptive prefix) is too long for a
`VARCHAR(50)` column, don't try to widen the column — **shorten the generated value** instead
(e.g. use 2-letter stage suffixes: `@concat(pipeline().RunId, '-bc')` instead of
`@concat('bronze-customers-', pipeline().RunId)`). If you truly need a wider column, you'd have to
create a new column, copy data, drop the old one, and rename — not a simple `ALTER`.

## 5. Lookup activity: `datasetSettings` is a sibling of `source`, not nested inside it

```json
"typeProperties": {
  "source": { "type": "DataWarehouseSource", "sqlReaderQuery": {...} },
  "datasetSettings": { ... },   // <-- SIBLING of "source", not inside it
  "firstRowOnly": true
}
```

Nesting `datasetSettings` inside `source` gives:

```
Operation on target LKP_Counts failed: Cannot find data set in the activity.
```

## 6. Gold stored procedures must match your actual table naming

If you (like this repo) chose **flat Lakehouse table names** (`Silver_Customers`) instead of a
schema-enabled Lakehouse (`silver.Customers`), every stored procedure and Lookup query that
references Silver data must use `LH_Finance.dbo.Silver_<Entity>` — not `LH_Finance.silver.<Entity>`.
Mixing the two conventions produces `Invalid object name` errors that are easy to misdiagnose as a
sync-lag issue (see #3) when they're actually just a wrong table reference.

## 7. Silver can't be "purged" of DQ-violating rows via T-SQL

The Lakehouse SQL analytics endpoint is **read-only**. A pipeline can COPY conforming + rejected
rows into Silver (via Copy activity), and can INSERT rejected rows into a Warehouse quarantine
table (via Script activity, since Warehouse is writable) — but it **cannot** run `DELETE FROM
LH_Finance.dbo.Silver_X WHERE ...` to remove bad rows from Silver itself, because that would be a
write against the read-only SQL endpoint.

**Consequence**: Silver tables in this design contain the full Bronze row set (including
DQ-violating rows), while `silver_rejects.<Entity>` separately tracks which rows are known-bad.
Gold load procedures must **defensively re-filter** (`WHERE CustomerName IS NOT NULL`, dedup via
`ROW_NUMBER()`, etc.) rather than assuming Silver is already clean. This is a deliberate,
documented trade-off — not a bug — and it's actually a good demo talking point: it shows real
validation catching real problems (see `audit.SP_RunGoldValidation`'s genuine "duplicate invoice
lines" failure from source-data duplicates that the Silver DQ rule for Invoices doesn't check for).

## 8. `ExecutePipeline` activities: keep child pipelines self-configuring

Early version of `PL_MASTER_ORCHESTRATOR` passed `p_source_folder`, `p_bronze_table`,
`p_reject_predicate`, etc. explicitly for every one of the 6 entities — 6 nearly-identical, long
parameter blocks per pipeline stage. Moving that configuration into `control.SourceConfig` (read via
a `LKP_Config` Lookup inside `PL_BRONZE_INGEST`/`PL_SILVER_LOAD`) means the master orchestrator only
needs to pass `p_entity_name` + run-control parameters per child — much shorter, and adding a 7th
entity requires **zero** pipeline changes, just one new row in `control.SourceConfig`.

## 9. Don't use `LoadMode='Incremental'` (Append) without real watermark filtering

`control.SourceConfig.LoadMode` drives `Copy_Bronze`'s `tableActionOption`
(`Full`→`Overwrite`, `Incremental`→`Append`) in `PL_BRONZE_INGEST`. If you mark an entity
`Incremental` but the pipeline doesn't actually filter the source CSV by a watermark (this repo's
`Copy_Bronze` copies the *entire* CSV every time, unfiltered), every re-run **appends the same
rows again** — row counts multiply by the number of times you've run it (we caught this when
`Payments` grew from 831 to 3,324 rows — exactly 4× — after 4 test runs). **This repo sets
`LoadMode='Full'` for every entity** to keep re-runs idempotent, since the generated CSVs are
static snapshots, not genuinely incremental daily extracts. If you want true incremental loading,
you'll need to add a `WHERE <WatermarkColumn> > @LastWatermarkValue` filter to the Copy source
(e.g. via a `LKP_Watermark` Lookup against `control.Watermark`) and update the watermark after a
successful load — `control.SP_UpdateWatermark` in this repo's SQL is the starting point for that,
but is not currently wired into any pipeline.

