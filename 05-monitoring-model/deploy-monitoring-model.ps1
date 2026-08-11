param(
  [Parameter(Mandatory=$true)][string]$WorkspaceId,
  [string]$DisplayName = "Finance Operations Monitoring",
  [string]$ModelRoot = $PSScriptRoot
)
$ErrorActionPreference = "Stop"
$resource = "https://api.fabric.microsoft.com"
$api = "$resource/v1"
$definitionRoot = Join-Path $ModelRoot "definition"

function Convert-FileToBase64([string]$Path) {
    return [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
}

$parts = @(
    @{ path = "definition.pbism"; payload = Convert-FileToBase64 (Join-Path $ModelRoot "definition.pbism"); payloadType = "InlineBase64" },
    @{ path = "definition/database.tmdl"; payload = Convert-FileToBase64 (Join-Path $definitionRoot "database.tmdl"); payloadType = "InlineBase64" },
    @{ path = "definition/model.tmdl"; payload = Convert-FileToBase64 (Join-Path $definitionRoot "model.tmdl"); payloadType = "InlineBase64" },
    @{ path = "definition/relationships.tmdl"; payload = Convert-FileToBase64 (Join-Path $definitionRoot "relationships.tmdl"); payloadType = "InlineBase64" }
)

Get-ChildItem (Join-Path $definitionRoot "tables") -Filter "*.tmdl" | ForEach-Object {
    $parts += @{ path = "definition/tables/$($_.Name)"; payload = Convert-FileToBase64 $_.FullName; payloadType = "InlineBase64" }
}

$body = @{
    displayName = $DisplayName
    definition = @{ format = "TMDL"; parts = $parts }
} | ConvertTo-Json -Depth 20 -Compress

$bodyFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($bodyFile, $body, [System.Text.UTF8Encoding]::new($false))
try {
    Write-Output "Creating semantic model '$DisplayName'..."
    az rest --method post --resource $resource --url "$api/workspaces/$WorkspaceId/semanticModels" --headers "Content-Type=application/json" --body "@$bodyFile"
}
finally {
    Remove-Item $bodyFile -ErrorAction SilentlyContinue
}
