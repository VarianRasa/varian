param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('windows', 'macos', 'linux', 'android', 'ios')]
  [string]$Platform,
  [Parameter(Mandatory = $true)]
  [string]$BundleRoot,
  [string]$ExpectedSha256,
  [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'tool/media_codecs/manifest.json'
$manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
$target = $manifest.targets.$Platform
if ($null -eq $target) { throw "Codec target '$Platform' is not declared in $manifestPath." }

$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $repoRoot "output/media-codec/$Platform/$runId.json"
}
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null

$result = [ordered]@{
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  platform = $Platform
  bundleRoot = (Resolve-Path -LiteralPath $BundleRoot).Path
  kind = $target.kind
  status = 'failed'
  executable = $null
  sha256 = $null
  version = $null
  reason = $null
}

if ($target.kind -ne 'process') {
  $result.reason = 'This target requires a native bridge validation on its own device runtime; no desktop process binary is accepted.'
  $result | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding utf8
  Write-Output "Codec bundle report: $OutputPath"
  exit 2
}

$candidates = @($target.relativePaths | ForEach-Object { Join-Path $BundleRoot ($_ -replace '/', [IO.Path]::DirectorySeparatorChar) })
$executable = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ($null -eq $executable) {
  $result.reason = "Bundled $($target.executable) was not found."
} else {
  $hash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
  $expected = if ($ExpectedSha256) { $ExpectedSha256.Trim().ToLowerInvariant() } else { $target.sha256 }
  if ([string]::IsNullOrWhiteSpace($expected)) {
    $result.reason = 'A SHA-256 pin is required; pass -ExpectedSha256 or set it in tool/media_codecs/manifest.json.'
  } elseif ($hash -ne $expected) {
    $result.reason = "SHA-256 mismatch. Expected $expected, got $hash."
  } else {
    $versionOutput = & $executable -version 2>&1 | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($versionOutput)) {
      $result.reason = 'Bundled encoder did not answer to -version.'
    } else {
      $result.status = 'passed'
      $result.executable = (Resolve-Path -LiteralPath $executable).Path
      $result.sha256 = $hash
      $result.version = [string]$versionOutput
      $result.reason = 'Hash-pinned bundled encoder answered to -version.'
    }
  }
}

$result | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding utf8
Write-Output "Codec bundle report: $OutputPath"
if ($result.status -ne 'passed') { exit 1 }
