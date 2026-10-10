[CmdletBinding()]
param(
  # Safe local mode is the default: an explicitly disabled meeting does not
  # need provider secrets. Use this switch for a configured release gate.
  [switch]$RequireServerConfiguration
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$meetingConfigurationPath = Join-Path $repoRoot 'lib/features/meeting/data/meeting_configuration.dart'
$meetingFunctionPath = Join-Path $repoRoot 'supabase/functions/meeting-token/index.ts'
$meetingRemovalFunctionPath = Join-Path $repoRoot 'supabase/functions/meeting-remove-participant/index.ts'
$supabaseConfigPath = Join-Path $repoRoot 'supabase/config.toml'
$readmePath = Join-Path $repoRoot 'README.md'

$serverEnvironmentNames = @(
  'LIVEKIT_URL',
  'LIVEKIT_API_KEY',
  'LIVEKIT_API_SECRET',
  'ALLOWED_ORIGINS'
)
$clientEnvironmentNames = @(
  'VIDEO_MEETING_ENABLED',
  'LIVEKIT_URL',
  'VIDEO_MEETING_MAX_PARTICIPANTS'
)

function Read-ContractFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required meeting contract file is missing: $Path"
  }
  return (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
}

function Assert-ContractText {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Content,
    [Parameter(Mandatory = $true)]
    [string]$Needle,
    [Parameter(Mandatory = $true)]
    [string]$Location
  )

  if (-not $Content.Contains($Needle)) {
    throw "Meeting release contract is missing '$Needle' in $Location."
  }
}

function Get-ProcessEnvironmentValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if ($null -eq $value) {
    return ''
  }
  return [string]$value
}

function Invoke-GateStep {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [string]$Command,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  Write-Output "[$Name] running"
  & $Command @Arguments
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "[$Name] failed with exit code $exitCode."
  }
  Write-Output "[$Name] passed"
}

try {
  # This gate checks names and statuses only; it never prints environment values.
  $meetingConfiguration = Read-ContractFile -Path $meetingConfigurationPath
  $meetingTokenFunction = Read-ContractFile -Path $meetingFunctionPath
  $meetingRemovalFunction = Read-ContractFile -Path $meetingRemovalFunctionPath
  $readme = Read-ContractFile -Path $readmePath
  $supabaseConfig = Read-ContractFile -Path $supabaseConfigPath

  foreach ($name in $serverEnvironmentNames) {
    Assert-ContractText -Content $meetingTokenFunction -Needle $name -Location 'supabase/functions/meeting-token/index.ts'
    Assert-ContractText -Content $meetingRemovalFunction -Needle $name -Location 'supabase/functions/meeting-remove-participant/index.ts'
    Assert-ContractText -Content $readme -Needle $name -Location 'README.md'
    Assert-ContractText -Content $supabaseConfig -Needle $name -Location 'supabase/config.toml'
  }
  foreach ($name in $clientEnvironmentNames) {
    Assert-ContractText -Content $meetingConfiguration -Needle $name -Location 'meeting_configuration.dart'
    Assert-ContractText -Content $readme -Needle $name -Location 'README.md'
  }

  Assert-ContractText -Content $readme -Needle 'meeting-token' -Location 'README.md'
  Assert-ContractText -Content $readme -Needle 'meeting-remove-participant' -Location 'README.md'
  Assert-ContractText -Content $supabaseConfig -Needle "[functions.meeting-token]`nverify_jwt = false" -Location 'supabase/config.toml'
  Assert-ContractText -Content $supabaseConfig -Needle "[functions.meeting-remove-participant]`nverify_jwt = false" -Location 'supabase/config.toml'
  Assert-ContractText -Content $readme -Needle 'supabase functions deploy meeting-token --use-api' -Location 'README.md'
  Assert-ContractText -Content $readme -Needle 'supabase functions deploy meeting-remove-participant --use-api' -Location 'README.md'
  Assert-ContractText -Content $readme -Needle 'tool/video_meeting_platform_matrix.ps1' -Location 'README.md'
  Assert-ContractText -Content $meetingConfiguration -Needle "defaultValue: 'false'" -Location 'meeting_configuration.dart'

  $flagValue = (Get-ProcessEnvironmentValue -Name 'VIDEO_MEETING_ENABLED').Trim().ToLowerInvariant()
  if ($flagValue -eq '') {
    $meetingEnabled = $false
  } elseif ($flagValue -eq 'false') {
    $meetingEnabled = $false
  } elseif ($flagValue -eq 'true') {
    $meetingEnabled = $true
  } else {
    throw 'VIDEO_MEETING_ENABLED must be unset, false, or true.'
  }

  $missingServerNames = @(
    $serverEnvironmentNames | Where-Object {
      [string]::IsNullOrWhiteSpace((Get-ProcessEnvironmentValue -Name $_))
    }
  )
  if ($meetingEnabled -or $RequireServerConfiguration) {
    if ($missingServerNames.Count -gt 0) {
      $missing = $missingServerNames -join ', '
      throw "Required meeting environment variable(s) are missing: $missing."
    }
  }

  if ($meetingEnabled) {
    Write-Output 'Meeting configuration is enabled and complete.'
  } elseif ($RequireServerConfiguration) {
    Write-Output 'Meeting configuration is disabled; required server environment names are present.'
  } else {
    Write-Output 'Safe local gate mode: meeting is disabled; provider secret values are not required.'
  }

  Push-Location $repoRoot
  try {
    Invoke-GateStep -Name 'Meeting tests' -Command 'flutter' -Arguments @(
      'test',
      '--no-pub',
      'test/features/meeting'
    )
    Invoke-GateStep -Name 'Analyzer' -Command 'flutter' -Arguments @(
      'analyze',
      '--no-pub'
    )
    Invoke-GateStep -Name 'Web release build' -Command 'flutter' -Arguments @(
      'build',
      'web',
      '--release'
    )
    Invoke-GateStep -Name 'Windows release build' -Command 'flutter' -Arguments @(
      'build',
      'windows',
      '--release'
    )
  } finally {
    Pop-Location
  }

  Write-Output 'Video meeting platform release gate passed.'
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
