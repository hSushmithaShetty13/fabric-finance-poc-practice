$ErrorActionPreference = "Stop"
$token = (az account get-access-token --resource "https://storage.azure.com" --query accessToken -o tsv)
$wsId = "ad5bf890-cd6e-4786-b69c-15876240823d"
$lhId = "3dfe3fbe-4f9d-4ca2-ab91-f589b7f77533"
$base = "https://onelake.dfs.fabric.microsoft.com/$wsId/$lhId"

$map = @{
  "Customers"     = "customers"
  "Invoices"      = "invoices"
  "InvoiceLines"  = "invoicelines"
  "Payments"      = "payments"
  "ExchangeRates" = "exchangerates"
  "GLAccounts"    = "glaccounts"
}

foreach ($k in $map.Keys) {
    $csvPath = Join-Path $PSScriptRoot "output\$k.csv"
    $folder = $map[$k]
    $remotePath = "Files/landing/$folder/$k.csv"
    $bytes = [System.IO.File]::ReadAllBytes($csvPath)

    $createUrl = "$base/$remotePath`?resource=file"
    $createResp = curl.exe -s -o NUL -w "%{http_code}" -X PUT -H "Authorization: Bearer $token" -H "x-ms-version: 2023-11-03" -H "Content-Length: 0" $createUrl

    $appendUrl = "$base/$remotePath`?action=append&position=0"
    $appendResp = curl.exe -s -o NUL -w "%{http_code}" -X PATCH -H "Authorization: Bearer $token" -H "x-ms-version: 2023-11-03" --data-binary "@$csvPath" $appendUrl

    $flushUrl = "$base/$remotePath`?action=flush&position=$($bytes.Length)"
    $flushResp = curl.exe -s -o NUL -w "%{http_code}" -X PATCH -H "Authorization: Bearer $token" -H "x-ms-version: 2023-11-03" -H "Content-Length: 0" $flushUrl

    Write-Output "$k : create=$createResp append=$appendResp flush=$flushResp bytes=$($bytes.Length)"
}
