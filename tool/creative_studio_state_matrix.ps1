$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $repoRoot 'output/state-matrix'
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$runRoot = Join-Path $artifactRoot $runId
$tests = @(
  'test/features/export/export_capabilities_test.dart',
  'test/features/export/export_queue_test.dart',
  'test/features/export/export_file_saver_test.dart',
  'test/features/media/media_processing_worker_test.dart',
  'test/features/media/media_processing_queue_test.dart',
  'test/features/ai/ai_governance_test.dart',
  'test/features/collaboration/screen_tracking_service_test.dart',
  'test/features/governance/operability_test.dart',
  'test/features/governance/accessibility_contract_test.dart'
)
$targets = @(
  @{ Name = 'VM'; Device = $null },
  @{ Name = 'Chrome'; Device = 'chrome' },
  @{ Name = 'Windows'; Device = 'windows' }
)

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$flutterVersion = (& flutter --version --machine | Out-String).Trim()
$results = [System.Collections.Generic.List[object]]::new()

foreach ($target in $targets) {
  $logPath = Join-Path $runRoot ("{0}.log" -f $target.Name.ToLowerInvariant())
  $startedAt = (Get-Date).ToUniversalTime()
  $exitCode = 1
  $errorMessage = $null
  $flutterArgs = @('test', '--no-pub')
  if ($null -ne $target.Device) {
    $flutterArgs += @('-d', $target.Device)
  }
  $flutterArgs += $tests

  Push-Location $repoRoot
  try {
    & flutter @flutterArgs 2>&1 | Tee-Object -FilePath $logPath
    $exitCode = $LASTEXITCODE
  } catch {
    $errorMessage = $_.Exception.Message
    $_ | Out-String | Set-Content -Path $logPath -Encoding utf8
  } finally {
    Pop-Location
  }

  $finishedAt = (Get-Date).ToUniversalTime()
  $results.Add([ordered]@{
      platform = $target.Name
      device = $target.Device
      status = if ($exitCode -eq 0) { 'passed' } else { 'failed' }
      startedAt = $startedAt.ToString('o')
      finishedAt = $finishedAt.ToString('o')
      exitCode = $exitCode
      log = (Resolve-Path -Relative $logPath).Replace('\', '/')
      error = $errorMessage
    })
}

$report = [ordered]@{
  schemaVersion = 1
  runId = $runId
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  purpose = 'Deterministic release-gate coverage for unavailable, cancel, retry, offline, health, accessibility, and recovery states.'
  flutterVersion = $flutterVersion
  tests = $tests
  targetResults = $results
  unresolvedGates = @(
    'iOS audio decoder runtime requires an iOS simulator or device.'
    'Video proxy/export still requires a real platform codec encoder.'
    'Production Windows/Chrome collaboration still requires two authorized Supabase sessions.'
  )
}

$jsonPath = Join-Path $runRoot 'matrix.json'
$markdownPath = Join-Path $runRoot 'matrix.md'
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding utf8

$resultRows = ($results | ForEach-Object {
    $log = $_.log
    "| $($_.platform) | $($_.status) | ``$log`` |"
  }) -join [Environment]::NewLine

@"
# Creative Studio State Matrix - $runId

Generated: $($report.generatedAt)

## Scope

$($report.purpose)

| Target | Result | Log |
| --- | --- | --- |
$resultRows

## Unresolved Gates

- iOS audio decoder runtime requires an iOS simulator or device.
- Video proxy/export still requires a real platform codec encoder.
- Production Windows/Chrome collaboration still requires two authorized Supabase sessions.

The matrix does not change those statuses or treat local mocks as production evidence.
"@ | Set-Content -Path $markdownPath -Encoding utf8

Write-Output "State matrix report: $markdownPath"
Write-Output "State matrix JSON: $jsonPath"

if ($results | Where-Object { $_.status -ne 'passed' }) {
  exit 1
}
