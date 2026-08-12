param(
    [Parameter(Mandatory=$true)][string]$WorkspaceId,
    [Parameter(Mandatory=$true)][string]$DisplayName,
    [Parameter(Mandatory=$true)][string]$ModelRoot
)

$ErrorActionPreference = "Stop"
$resource = "https://api.fabric.microsoft.com"
$api = "$resource/v1"

function Convert-FileToBase64([string]$Path) {
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
}

$parts = @()
Get-ChildItem $ModelRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relativePath = [IO.Path]::GetRelativePath($ModelRoot, $_.FullName).Replace('\', '/')
    $parts += @{
        path = $relativePath
        payload = Convert-FileToBase64 $_.FullName
        payloadType = "InlineBase64"
    }
}

$body = @{
    displayName = $DisplayName
    definition = @{ format = "TMDL"; parts = $parts }
} | ConvertTo-Json -Depth 20 -Compress

$bodyFile = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($bodyFile, $body, [Text.UTF8Encoding]::new($false))
try {
    $token = az account get-access-token --resource $resource --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to acquire a Fabric API access token."
    }

    $response = Invoke-WebRequest `
        -Method Post `
        -Uri "$api/workspaces/$WorkspaceId/semanticModels" `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "application/json" `
        -InFile $bodyFile `
        -SkipHttpErrorCheck

    if ($response.StatusCode -ge 400) {
        throw "Fabric create failed with HTTP $($response.StatusCode): $($response.Content)"
    }

    [pscustomobject]@{
        StatusCode = $response.StatusCode
        OperationUrl = $response.Headers.Location | Select-Object -First 1
        ResponseBody = $response.Content
    }
}
finally {
    Remove-Item $bodyFile -ErrorAction SilentlyContinue
}
