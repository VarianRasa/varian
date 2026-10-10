param(
  [string]$ProjectName = 'varian-creative-canvas',
  [string]$Branch = 'main',
  [switch]$TestMode
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildOutput = Join-Path $repoRoot 'build\web'
$credentialsFile = Join-Path $repoRoot '.env.cloudflare'

function Invoke-Gate {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  Write-Output "[GATE] $Name"
  & $Action
  if ($LASTEXITCODE -ne 0) {
    throw "Predeploy gate failed: $Name."
  }
}

function Invoke-RequiredTool {
  param([string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Predeploy gate blocked: required tool '$Name' is unavailable."
  }
}

Invoke-RequiredTool 'flutter'
Invoke-RequiredTool 'dart'
Invoke-RequiredTool 'deno'
Invoke-RequiredTool 'supabase'
if (-not $TestMode) {
  Invoke-RequiredTool 'npx'
}

Push-Location $repoRoot
try {
  $global:LASTEXITCODE = 0
  if ($TestMode) {
    Write-Output '[TEST MODE] Validating the fail-closed command gate; Wrangler will not be invoked.'
  }

  $global:LASTEXITCODE = 0
  Invoke-Gate 'Flutter toolchain is available' {
    flutter --version --machine | Out-Null
  }
  Invoke-Gate 'Locked Flutter dependencies resolve without changing pubspec.lock' {
    flutter pub get --enforce-lockfile
  }
  Invoke-Gate 'Flutter static analysis' {
    flutter analyze --no-pub
  }
  Invoke-Gate 'Full Flutter test suite' {
    flutter test --no-pub --concurrency=1
  }
  Invoke-Gate 'Dart dependency advisory audit' {
    throw 'Predeploy gate blocked: `dart pub audit` is unsupported by this Dart SDK.'
  }

  if ($TestMode) {
    Write-Output '[TEST MODE] Stopping after the explicitly blocked Dart advisory gate.'
    return
  }
  $denoLock = Join-Path $repoRoot 'deno.lock'
  if (-not (Test-Path -LiteralPath $denoLock)) {
    throw 'Predeploy gate failed: deno.lock is required for locked Edge Function tests.'
  }
  Invoke-Gate 'Supabase Edge Function tests with locked Deno dependencies' {
    deno test --frozen --allow-env supabase/functions
  }

  Invoke-Gate 'Supabase CLI is available' {
    supabase --version | Out-Null
  }
  Invoke-Gate 'Disposable local Supabase migrations and pgTAP tests' {
    supabase db reset --local --no-seed
  }
  Invoke-Gate 'Local Supabase pgTAP tests' {
    supabase test db --local
  }


  if (-not (Test-Path -LiteralPath $credentialsFile)) {
    throw 'Create .env.cloudflare from .env.cloudflare.example before deploying.'
  }
  if (-not (Select-String -Path $credentialsFile -Pattern '^CLOUDFLARE_API_TOKEN=.+$' -Quiet)) {
    throw 'CLOUDFLARE_API_TOKEN is missing from .env.cloudflare.'
  }
  if (-not (Select-String -Path $credentialsFile -Pattern '^CLOUDFLARE_ACCOUNT_ID=.+$' -Quiet)) {
    throw 'CLOUDFLARE_ACCOUNT_ID is missing from .env.cloudflare.'
  }

  Invoke-Gate 'Release Web build' {
    flutter build web --release --no-wasm-dry-run --output $buildOutput
  }

  npx --yes wrangler@4 --env-file $credentialsFile pages deploy $buildOutput `
    --project-name $ProjectName `
    --branch $Branch
  if ($LASTEXITCODE -ne 0) {
    throw 'Cloudflare Pages deployment failed.'
  }
} finally {
  Pop-Location
}
