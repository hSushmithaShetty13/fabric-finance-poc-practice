param(
  [Parameter(Mandatory=$true)][string]$WorkspaceId,
  [Parameter(Mandatory=$true)][string]$ItemId,
  [Parameter(Mandatory=$true)][string]$ParametersJson
)
$ErrorActionPreference = "Stop"
$resource = "https://api.fabric.microsoft.com"
$api = "$resource/v1"

$body = "{`"executionData`":{`"parameters`":$ParametersJson}}"
$bodyFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($bodyFile, $body, [System.Text.UTF8Encoding]::new($false))

$headerFile = [System.IO.Path]::GetTempFileName()
$token = (az account get-access-token --resource $resource --query accessToken -o tsv)
$resp = curl.exe -s -D $headerFile -o NUL -w "%{http_code}" -X POST `
  -H "Authorization: Bearer $token" -H "Content-Type: application/json" `
  --data "@$bodyFile" `
  "$api/workspaces/$WorkspaceId/items/$ItemId/jobs/instances?jobType=Pipeline"

Write-Output "HTTP status: $resp"
$headers = Get-Content $headerFile -Raw
Write-Output $headers
Remove-Item $bodyFile, $headerFile
