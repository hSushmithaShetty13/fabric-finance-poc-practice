# Manual CSV Upload to the Lakehouse

Use this option when you do not want to run `upload_to_onelake.ps1`. The six generated CSV files are
already included in [output/](output/) and can be uploaded through the Fabric portal.

## Target folders

Upload each file to its matching folder under `LH_Finance > Files > landing`:

| Local CSV | Lakehouse folder |
|---|---|
| `output/Customers.csv` | `Files/landing/customers/` |
| `output/Invoices.csv` | `Files/landing/invoices/` |
| `output/InvoiceLines.csv` | `Files/landing/invoicelines/` |
| `output/Payments.csv` | `Files/landing/payments/` |
| `output/ExchangeRates.csv` | `Files/landing/exchangerates/` |
| `output/GLAccounts.csv` | `Files/landing/glaccounts/` |

Folder names are lowercase and must match this table because `control.SourceConfig` and the Bronze
pipeline use these exact paths.

## Upload in Fabric

1. Open workspace `WS_Finance_POC` in the Fabric portal.
2. Open the `LH_Finance` Lakehouse.
3. In the **Explorer** pane, expand **Files**.
4. Create a folder named `landing` if it does not exist.
5. Under `landing`, create these six folders:
   `customers`, `invoices`, `invoicelines`, `payments`, `exchangerates`, and `glaccounts`.
6. Open the `customers` folder, select **...** or **Upload**, choose **Upload files**, and select
   `02-data/output/Customers.csv` from this repository.
7. Repeat for the other five files using the target-folder table above.
8. Confirm every folder contains one CSV with the original filename.

Do not upload all six CSVs into the same folder. The Bronze pipeline reads one entity-specific
folder at a time using `Files/landing/<entity>/`.

## Verify before running the pipeline

The Lakehouse Explorer should show this structure:

```text
Files/
└── landing/
    ├── customers/Customers.csv
    ├── invoices/Invoices.csv
    ├── invoicelines/InvoiceLines.csv
    ├── payments/Payments.csv
    ├── exchangerates/ExchangeRates.csv
    └── glaccounts/GLAccounts.csv
```

Expected data-row counts, excluding each CSV header:

| File | Rows |
|---|---:|
| `Customers.csv` | 124 |
| `Invoices.csv` | 1,020 |
| `InvoiceLines.csv` | 2,973 |
| `Payments.csv` | 831 |
| `ExchangeRates.csv` | 2,069 |
| `GLAccounts.csv` | 21 |

After verifying the files, run `PL_MASTER_ORCHESTRATOR` or begin with `PL_BRONZE_INGEST` for one
entity.

## Regenerate the files optionally

The committed CSVs are ready to use. To recreate the same deterministic dataset later, run:

```powershell
python .\02-data\generate_finance_data.py
```

The generator uses seed `42`, so it recreates the same row counts and intended data-quality issues.
