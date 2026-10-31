$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repositoryRoot
try {
    if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
        throw 'Supabase CLI is required. Install it before running this local QA path.'
    }
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'Flutter is required. Install it before running this local QA path.'
    }

    Write-Host 'Starting the local Supabase stack without resetting its database.'
    # The CLI writes informational warnings to stderr on PowerShell 5.1.
    # Suppress its credential-bearing output and use the process exit code.
    $ErrorActionPreference = 'Continue'
    & supabase start *> $null
    $startExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($startExitCode -ne 0) {
        throw "supabase start failed with exit code $startExitCode."
    }

    $ErrorActionPreference = 'Continue'
    $statusJson = & supabase status --output json 2>$null
    $statusExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($statusExitCode -ne 0) {
        throw "supabase status failed with exit code $statusExitCode."
    }
    $localStatus = ($statusJson -join [Environment]::NewLine) | ConvertFrom-Json
    $apiUrl = [string]$localStatus.API_URL
    $publishableKey = [string]$localStatus.PUBLISHABLE_KEY
    $apiUri = [Uri]$apiUrl
    if (-not $apiUri.IsLoopback) {
        throw "Refusing non-local Supabase URL: $apiUrl"
    }
    if ([string]::IsNullOrWhiteSpace($publishableKey)) {
        throw 'Local Supabase did not report a publishable client key.'
    }

    Write-Host "Launching Flutter against local Supabase at $apiUrl."
    Write-Host 'Open http://127.0.0.1:20131 in an isolated Chrome profile for local QA.'
    Write-Host 'Use Sign up to create a disposable local account; confirm it in the local Mailpit inbox, then sign in and create a sample workspace/project.'
    Write-Host 'Mailpit: http://127.0.0.1:54333. No production credentials or auth bypass are used.'

    $flutterArguments = @(
        'run',
        '-d', 'web-server',
        '--web-hostname=127.0.0.1',
        '--web-port=20131',
        "--dart-define=SUPABASE_URL=$apiUrl",
        "--dart-define=SUPABASE_PUBLISHABLE_KEY=$publishableKey"
    )
    & flutter @flutterArguments
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
