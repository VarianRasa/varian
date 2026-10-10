param(
  [Parameter(Mandatory = $true)]
  [string]$SourcePath,
  [Parameter(Mandatory = $true)]
  [string]$TargetRoot,
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
  throw "Codec source does not exist: $SourcePath"
}
$hash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
if ($hash -ine $ExpectedSha256) {
  throw "Codec source SHA-256 mismatch. Expected $ExpectedSha256, got $hash."
}
$probe = & $SourcePath -version 2>&1 | Select-Object -First 1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($probe)) {
  throw 'Codec source did not answer to -version.'
}

$targetDirectory = Join-Path $TargetRoot 'codecs'
New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
$targetPath = Join-Path $targetDirectory (Split-Path -Leaf $SourcePath)
Copy-Item -LiteralPath $SourcePath -Destination $targetPath -Force
Write-Output "Bundled codec: $targetPath"
Write-Output "SHA-256: $hash"
Write-Output "Version: $probe"
