param(
  [string]$Url = '',
  [string]$ProjectId = '',
  [int]$TimeoutSeconds = 30,
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($Url)) {
  $supabaseUrl = $env:SUPABASE_URL
  if ([string]::IsNullOrWhiteSpace($supabaseUrl)) {
    throw 'Provide -Url or set SUPABASE_URL.'
  }
  $Url = $supabaseUrl.TrimEnd('/') + '/functions/v1/workspace-retention'
}
if ([string]::IsNullOrWhiteSpace($ProjectId)) {
  throw 'Provide -ProjectId.'
}
$secret = $env:RETENTION_JOB_SECRET
if ([string]::IsNullOrWhiteSpace($secret)) {
  throw 'Set RETENTION_JOB_SECRET in the process environment. The secret is never written to the report.'
}

$checkedAt = [DateTime]::UtcNow
$httpStatus = 0
$payload = $null
$requestError = $null

try {
  $body = @{ projectId = $ProjectId } | ConvertTo-Json -Compress
  $response = Invoke-WebRequest `
    -Uri $Url `
    -Method Post `
    -ContentType 'application/json' `
    -Headers @{ 'x-retention-job-secret' = $secret } `
    -Body $body `
    -UseBasicParsing `
    -TimeoutSec $TimeoutSeconds
  $httpStatus = [int]$response.StatusCode
  $payload = $response.Content | ConvertFrom-Json
} catch {
  $requestError = $_.Exception.Message
  $response = $_.Exception.Response
  if ($null -ne $response) {
    try {
      $httpStatus = [int]$response.StatusCode
      $content = $response.Content.ReadAsStringAsync().Result
      if (-not [string]::IsNullOrWhiteSpace($content)) {
        $payload = $content | ConvertFrom-Json
      }
    } catch {
      $requestError = "$requestError; response body unavailable"
    }
  }
}

$succeeded = $httpStatus -eq 200 -and $null -ne $payload -and
  $payload.projectId -eq $ProjectId -and
  $null -ne $payload.auditDeleted -and
  $null -ne $payload.exportDeleted
$report = [ordered]@{
  checkedAt = $checkedAt.ToString('o')
  url = $Url
  projectId = $ProjectId
  httpStatus = $httpStatus
  status = if ($succeeded) { 'passed' } else { 'failed' }
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
if (-not $succeeded) { exit 1 }
