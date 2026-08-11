param(
  [Parameter(Mandatory=$true)][string]$WorkspaceId,
  [Parameter(Mandatory=$true)][string]$DisplayName,
  [Parameter(Mandatory=$true)][string]$ContentJsonPath,
  [string]$Description = ""
)
$ErrorActionPreference = "Stop"
$resource = "https://api.fabric.microsoft.com"
$api = "$resource/v1"

$contentBytes = [System.IO.File]::ReadAllBytes($ContentJsonPath)
$contentB64 = [Convert]::ToBase64String($contentBytes)

$platform = @{
  "`$schema" = "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json"
  metadata = @{ type = "DataPipeline"; displayName = $DisplayName; description = $Description }
  config = @{ version = "2.0"; logicalId = [guid]::NewGuid().Guid }
} | ConvertTo-Json -Depth 10 -Compress
$platformBytes = [System.Text.Encoding]::UTF8.GetBytes($platform)
$platformB64 = [Convert]::ToBase64String($platformBytes)

$body = @{
  displayName = $DisplayName
  description = $Description
  definition = @{
    parts = @(
      @{ path = "pipeline-content.json"; payload = $contentB64; payloadType = "InlineBase64" }
      @{ path = ".platform"; payload = $platformB64; payloadType = "InlineBase64" }
    )
  }
} | ConvertTo-Json -Depth 20 -Compress

$bodyFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($bodyFile, $body, [System.Text.UTF8Encoding]::new($false))

Write-Output "Creating pipeline '$DisplayName' in workspace $WorkspaceId ..."
$result = az rest --method post --resource $resource --url "$api/workspaces/$WorkspaceId/items" --headers "Content-Type=application/json" --body "@$bodyFile" 2>&1
Remove-Item $bodyFile
Write-Output $result
