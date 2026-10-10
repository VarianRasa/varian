$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$outputRoot = if ($env:COLLAB_PROBE_OUTPUT_ROOT) { $env:COLLAB_PROBE_OUTPUT_ROOT } else { Join-Path $repoRoot 'output/collaboration-production' }
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$runRoot = Join-Path $outputRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$required = @(
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'COLLAB_HOST_ACCESS_TOKEN',
  'COLLAB_GUEST_ACCESS_TOKEN',
  'COLLAB_PROJECT_ID',
  'COLLAB_ROOM_CODE'
)
$missing = @($required | Where-Object { [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) })
if ($missing.Count -gt 0) {
  throw "Production collaboration probe requires explicit environment variables: $($missing -join ', '). No account or credential is created by this script."
}

$jsonPath = Join-Path $runRoot 'probe.json'
$logPath = Join-Path $runRoot 'probe.log'
Push-Location $repoRoot
try {
  & npx --yes deno-bin run --allow-env --allow-net tool/collaboration_production_probe.ts 2>&1 |
    Tee-Object -FilePath $logPath
  $exitCode = $LASTEXITCODE
} finally {
  Pop-Location
}

$raw = Get-Content -Raw $logPath
$json = $raw | ConvertFrom-Json
$json | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding utf8
Write-Output "Production collaboration report: $jsonPath"
Write-Output "Production collaboration log: $logPath"
if ($exitCode -ne 0) { exit $exitCode }
