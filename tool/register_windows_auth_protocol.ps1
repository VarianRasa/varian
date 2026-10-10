param(
  [Parameter(Mandatory = $true)]
  [string]$ExecutablePath
)

$resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath).Path
$scheme = 'io.canvascreative'
$schemeKey = "HKCU:\Software\Classes\$scheme"
$commandKey = Join-Path $schemeKey 'shell\open\command'

New-Item -Path $commandKey -Force | Out-Null
Set-ItemProperty -Path $schemeKey -Name '(Default)' -Value 'URL:Creative Canvas Auth'
New-ItemProperty -Path $schemeKey -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
Set-ItemProperty -Path $commandKey -Name '(Default)' -Value ('"{0}" "%1"' -f $resolvedExecutable)

Write-Output "Registered $scheme://auth/callback for $resolvedExecutable"
