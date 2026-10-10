param(
  [string]$ArchivePath = $env:LIBREOFFICE_ARCHIVE,
  [string]$ExpectedSha256 = $env:LIBREOFFICE_SHA256
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
  throw 'LIBREOFFICE_ARCHIVE or -ArchivePath is required.'
}
if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
  throw 'LIBREOFFICE_SHA256 or -ExpectedSha256 is required.'
}
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
  throw "LibreOffice archive not found: $ArchivePath"
}

$actualSha256 = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash
if ($actualSha256 -ne $ExpectedSha256.ToUpperInvariant()) {
  throw "LibreOffice SHA-256 mismatch. Expected $ExpectedSha256, got $actualSha256."
}

$workspace = Split-Path -Parent $PSScriptRoot
$stageRoot = Join-Path $workspace 'windows\libreoffice\runtime'
$extractRoot = Join-Path $env:TEMP "varian_libreoffice_$([guid]::NewGuid())"
try {
  if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Path $extractRoot | Out-Null
  Expand-Archive -LiteralPath $ArchivePath -DestinationPath $extractRoot -Force
  $soffice = Get-ChildItem -LiteralPath $extractRoot -Filter 'soffice.exe' -Recurse |
    Where-Object { $_.Directory.Name -eq 'program' } |
    Select-Object -First 1
  if ($null -eq $soffice) {
    throw 'Archive does not contain program\soffice.exe.'
  }
  $runtimeRoot = Split-Path -Parent $soffice.Directory.FullName
  $licenseFiles = Get-ChildItem -LiteralPath $runtimeRoot -File -Recurse |
    Where-Object { $_.Name -match '^(LICENSE|NOTICE|COPYING)' }
  if (@($licenseFiles).Count -eq 0) {
    throw 'Archive does not contain LibreOffice license or notices.'
  }
  New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
  Copy-Item -Path (Join-Path $runtimeRoot '*') -Destination $stageRoot -Recurse -Force
  $consoleLauncher = Join-Path $stageRoot 'program\soffice.com'
  $versionLauncher = if (Test-Path -LiteralPath $consoleLauncher) {
    $consoleLauncher
  } else {
    Join-Path $stageRoot 'program\soffice.exe'
  }
  & $versionLauncher --headless --version
  if ($LASTEXITCODE -ne 0) {
    throw 'Staged LibreOffice failed the version check.'
  }
} finally {
  if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
  }
}
