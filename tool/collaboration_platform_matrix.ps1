$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $repoRoot 'output/collaboration-matrix'
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$runRoot = Join-Path $artifactRoot $runId
$tests = @(
  'test/features/collaboration/collaboration_two_client_test.dart',
  'test/features/collaboration/screen_tracking_service_test.dart'
)
$targets = @(
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

  Push-Location $repoRoot
  try {
    & flutter test --no-pub -d $target.Device @tests 2>&1 |
      Tee-Object -FilePath $logPath
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
  flutterVersion = $flutterVersion
  tests = $tests
  runtimeTargetResults = $results
  productionCrossPlatformMatrix = @(
    [ordered]@{
      host = 'Windows'
      guest = 'Chrome'
      status = 'pending'
      reason = 'Requires two authorized Supabase sessions and an interactive Windows plus Chrome run.'
    }
    [ordered]@{
      host = 'Chrome'
      guest = 'Windows'
      status = 'pending'
      reason = 'Requires two authorized Supabase sessions and an interactive Chrome plus Windows run.'
    }
  )
  limitations = @(
    'The runtime target suite uses the local Realtime test backend.'
    'It proves target-specific transport behavior, not production Supabase RLS or network reliability.'
    'No account, room, credential, or personal browser profile is created or reused by this script.'
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
# Collaboration Platform Matrix - $runId

Generated: $($report.generatedAt)

## Runtime Target Suite

The suite runs the local Realtime transport harness on each supported runtime.
It is not evidence of two authorized clients connected to the production Supabase project.

| Runtime | Result | Log |
| --- | --- | --- |
$resultRows

## Production Cross-Platform Matrix

| Host | Guest | Result | Required evidence |
| --- | --- | --- | --- |
| Windows | Chrome | Pending | Two authorized sessions, shared room, bidirectional edit, reconnect, revoke, duplicate-operation, and presence cleanup screenshots/logs. |
| Chrome | Windows | Pending | Two authorized sessions, shared room, bidirectional edit, reconnect, revoke, duplicate-operation, and presence cleanup screenshots/logs. |

## Limitations

- Local Realtime emulation only; production Supabase RLS, auth, and network reliability are not covered.
- The script does not create accounts, reuse personal browser profiles, or transmit credentials.
- Screen-capture consent and media delivery still require an interactive OS/browser run.
"@ | Set-Content -Path $markdownPath -Encoding utf8

Write-Output "Matrix report: $markdownPath"
Write-Output "Matrix JSON: $jsonPath"

if ($results | Where-Object { $_.status -ne 'passed' }) {
  exit 1
}
