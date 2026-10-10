[CmdletBinding()]
param(
  [ValidateSet('windows', 'web')]
  [string]$Target = 'windows',
  [ValidateSet('chrome', 'edge', 'web-server')]
  [string]$WebDevice = 'chrome',
  [ValidateSet('triposr', 'demo', 'trellis', 'hunyuan3d', 'comfyui')]
  [string]$Provider = 'triposr',
  [ValidateRange(1, 65535)]
  [int]$Port = 20130,
  [ValidateRange(5, 600)]
  [int]$StartupTimeoutSeconds = 90,
  [string]$HostAddress = '127.0.0.1',
  [string]$PythonExecutable = 'python',
  [string]$RuntimeRoot = '',
  [string]$TripoSRRoot = '',
  [string]$TripoSRModel = '',
  [string]$TripoSRChunkSize = '',
  [string]$BlenderBin = '',
  [string]$WorkerToken = '',
  [switch]$KeepWorker,
  [switch]$SkipWorker
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workerModule = 'tool.ai_3d_worker.app:app'
$logDirectory = Join-Path $root 'output\ai-3d-worker'
$workerLog = Join-Path $logDirectory 'worker.log'
$workerErrorLog = Join-Path $logDirectory 'worker-error.log'
$defaultRuntimeRoot = Join-Path $root 'output\ai-3d-triposr-runtime'
$effectiveRuntimeRoot = $RuntimeRoot
if ([string]::IsNullOrWhiteSpace($effectiveRuntimeRoot) -and
    (Test-Path -LiteralPath $defaultRuntimeRoot)) {
  $effectiveRuntimeRoot = $defaultRuntimeRoot
}
$effectivePythonExecutable = $PythonExecutable
$effectiveTripoSRRoot = $TripoSRRoot
$autoDetectedRuntime = $false
if ($Provider -eq 'triposr' -and $PythonExecutable -eq 'python' -and
    -not [string]::IsNullOrWhiteSpace($effectiveRuntimeRoot)) {
  $runtimePython = Join-Path $effectiveRuntimeRoot '.venv\Scripts\python.exe'
  $runtimeTripoSRRoot = Join-Path $effectiveRuntimeRoot 'TripoSR'
  if (Test-Path -LiteralPath $runtimePython) {
    $effectivePythonExecutable = $runtimePython
    $autoDetectedRuntime = $true
  }
  if ([string]::IsNullOrWhiteSpace($effectiveTripoSRRoot) -and
      (Test-Path -LiteralPath $runtimeTripoSRRoot)) {
    $effectiveTripoSRRoot = $runtimeTripoSRRoot
    $autoDetectedRuntime = $true
  }
}

function Resolve-CommandPath {
  param([Parameter(Mandatory = $true)][string]$Name)

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    throw "Command '$Name' was not found in PATH."
  }
  if (-not [string]::IsNullOrWhiteSpace($command.Source)) {
    return $command.Source
  }
  return $command.Path
}

function Set-ProcessEnvironmentValue {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowNull()][string]$Value
  )

  if ($null -eq $Value) {
    Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
    return
  }
  Set-Item "Env:$Name" $Value
}

function Test-WorkerHealth {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$Token
  )

  try {
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
      $headers.Authorization = "Bearer $Token"
    }
    $response = Invoke-WebRequest -Uri $Url -Headers $headers -TimeoutSec 3
    return $response.StatusCode -eq 200
  } catch {
    return $false
  }
}

function Show-WorkerFailure {
  if (Test-Path -LiteralPath $workerErrorLog) {
    Write-Error (Get-Content -LiteralPath $workerErrorLog -Tail 40 -ErrorAction SilentlyContinue | Out-String)
  }
  if (Test-Path -LiteralPath $workerLog) {
    Write-Error (Get-Content -LiteralPath $workerLog -Tail 40 -ErrorAction SilentlyContinue | Out-String)
  }
}

$workerProcess = $null
$workerStarted = $false
$healthHost = if ($HostAddress -eq '0.0.0.0' -or $HostAddress -eq '::') {
  '127.0.0.1'
} else {
  $HostAddress
}
$healthUrl = "http://$healthHost`:$Port/v1/health"

try {
  if (-not $SkipWorker) {
    if (-not (Test-WorkerHealth -Url $healthUrl -Token $WorkerToken)) {
      $pythonPath = Resolve-CommandPath -Name $effectivePythonExecutable
      $workerScript = Join-Path $root 'tool\ai_3d_worker\start_worker.ps1'
      if (-not (Test-Path -LiteralPath $workerScript)) {
        throw "Worker launcher was not found at '$workerScript'."
      }

      New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
      Remove-Item -LiteralPath $workerLog, $workerErrorLog -Force -ErrorAction SilentlyContinue

      $previousEnvironment = @{
        AI_3D_DEFAULT_PROVIDER = [Environment]::GetEnvironmentVariable('AI_3D_DEFAULT_PROVIDER', 'Process')
        PYTHONPATH = [Environment]::GetEnvironmentVariable('PYTHONPATH', 'Process')
        TRIPOSR_ROOT = [Environment]::GetEnvironmentVariable('TRIPOSR_ROOT', 'Process')
        TRIPOSR_MODEL = [Environment]::GetEnvironmentVariable('TRIPOSR_MODEL', 'Process')
        TRIPOSR_CHUNK_SIZE = [Environment]::GetEnvironmentVariable('TRIPOSR_CHUNK_SIZE', 'Process')
        BLENDER_BIN = [Environment]::GetEnvironmentVariable('BLENDER_BIN', 'Process')
        VARIAN_3D_WORKER_TOKEN = [Environment]::GetEnvironmentVariable('VARIAN_3D_WORKER_TOKEN', 'Process')
      }

      try {
        Set-ProcessEnvironmentValue -Name 'AI_3D_DEFAULT_PROVIDER' -Value $Provider
        $existingPythonPath = $previousEnvironment.PYTHONPATH
        $pythonPathValue = if ([string]::IsNullOrWhiteSpace($existingPythonPath)) {
          $root
        } else {
          "$root;$existingPythonPath"
        }
        Set-ProcessEnvironmentValue -Name 'PYTHONPATH' -Value $pythonPathValue
        if (-not [string]::IsNullOrWhiteSpace($effectiveTripoSRRoot)) {
          Set-ProcessEnvironmentValue -Name 'TRIPOSR_ROOT' -Value $effectiveTripoSRRoot
        }
        if (-not [string]::IsNullOrWhiteSpace($TripoSRModel)) {
          Set-ProcessEnvironmentValue -Name 'TRIPOSR_MODEL' -Value $TripoSRModel
        }
        if (-not [string]::IsNullOrWhiteSpace($TripoSRChunkSize)) {
          Set-ProcessEnvironmentValue -Name 'TRIPOSR_CHUNK_SIZE' -Value $TripoSRChunkSize
        } elseif ($autoDetectedRuntime -and
            [string]::IsNullOrWhiteSpace($previousEnvironment.TRIPOSR_CHUNK_SIZE)) {
          Set-ProcessEnvironmentValue -Name 'TRIPOSR_CHUNK_SIZE' -Value '4096'
        }
        if (-not [string]::IsNullOrWhiteSpace($BlenderBin)) {
          Set-ProcessEnvironmentValue -Name 'BLENDER_BIN' -Value $BlenderBin
        }
        if (-not [string]::IsNullOrWhiteSpace($WorkerToken)) {
          Set-ProcessEnvironmentValue -Name 'VARIAN_3D_WORKER_TOKEN' -Value $WorkerToken
        }

        $workerProcess = Start-Process `
          -FilePath $pythonPath `
          -ArgumentList @('-m', 'uvicorn', $workerModule, '--host', $HostAddress, '--port', $Port.ToString()) `
          -WorkingDirectory $root `
          -WindowStyle Hidden `
          -RedirectStandardOutput $workerLog `
          -RedirectStandardError $workerErrorLog `
          -PassThru
      } finally {
        foreach ($name in $previousEnvironment.Keys) {
          Set-ProcessEnvironmentValue -Name $name -Value $previousEnvironment[$name]
        }
      }
      $workerStarted = $true
      if ($autoDetectedRuntime) {
        Write-Host "Using TripoSR runtime at $effectiveRuntimeRoot."
      }

      $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
      $healthy = $false
      while ((Get-Date) -lt $deadline) {
        if (Test-WorkerHealth -Url $healthUrl -Token $WorkerToken) {
          $healthy = $true
          break
        }
        $workerProcess.Refresh()
        if ($workerProcess.HasExited) {
          Show-WorkerFailure
          throw "3D worker exited before becoming healthy."
        }
        Start-Sleep -Seconds 2
      }
      if (-not $healthy) {
        Show-WorkerFailure
        throw "3D worker did not become healthy within $StartupTimeoutSeconds seconds."
      }
      Write-Host "3D worker ready at $healthUrl using provider '$Provider'."
    } else {
      Write-Host "3D worker already healthy at $healthUrl."
    }
  }

  $flutterPath = Resolve-CommandPath -Name 'flutter'
  $flutterArguments = if ($Target -eq 'windows') {
    @('run', '-d', 'windows')
  } else {
    @('run', '-d', $WebDevice)
  }

  Write-Host "Starting Flutter target '$Target'."
  & $flutterPath @flutterArguments
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  if ($workerStarted -and -not $KeepWorker -and $null -ne $workerProcess) {
    $workerProcess.Refresh()
    if (-not $workerProcess.HasExited) {
      Stop-Process -Id $workerProcess.Id -Force -ErrorAction SilentlyContinue
      Write-Host '3D worker stopped.'
    }
  } elseif ($workerStarted -and $KeepWorker) {
    Write-Host "3D worker left running at $healthUrl."
  }
}
