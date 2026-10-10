param(
  [string]$Url = '',
  [int]$TimeoutSeconds = 30,
  [string]$ExpectedVersion = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($Url)) {
  $supabaseUrl = $env:SUPABASE_URL
  if ([string]::IsNullOrWhiteSpace($supabaseUrl)) {
    throw 'Provide -Url or set SUPABASE_URL.'
  }
  $Url = $supabaseUrl.TrimEnd('/') + '/functions/v1/workspace-health'
}

$checkedAt = [DateTime]::UtcNow
$httpStatus = 0
$payload = $null
$requestError = $null

try {
  $response = Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing -TimeoutSec $TimeoutSeconds
  $httpStatus = [int]$response.StatusCode
  $payload = $response.Content | ConvertFrom-Json
} catch {
  $requestError = $_.Exception.Message
  if ($_.Exception.Response) {
    $httpStatus = [int]$_.Exception.Response.StatusCode
    try {
      $stream = $_.Exception.Response.GetResponseStream()
      $reader = New-Object System.IO.StreamReader($stream)
      $payload = $reader.ReadToEnd() | ConvertFrom-Json
    } catch {
      $payload = $null
    }
  }
}

$hasPublicContract = $null -ne $payload -and
  @($payload.PSObject.Properties.Name | Sort-Object) -join ',' -eq 'status,version'
$versionMatches = [string]::IsNullOrWhiteSpace($ExpectedVersion) -or
  ($null -ne $payload -and $payload.version -eq $ExpectedVersion)
$healthy = $httpStatus -eq 200 -and
  $hasPublicContract -and
  $payload.status -eq 'healthy' -and
  $versionMatches

$report = [ordered]@{
  checkedAt = $checkedAt.ToString('o')
  url = $Url
  httpStatus = $httpStatus
  status = if ($healthy) { 'passed' } else { 'failed' }
  versionMatches = $versionMatches
  requestError = $requestError
  payload = $payload
}
$json = $report | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $parent = Split-Path -Parent $OutputPath
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  Set-Content -Path $OutputPath -Value $json -Encoding utf8
}
Write-Output $json
if (-not $healthy) { exit 1 }
