param(
  [int]$Port = 20130,
  [string]$HostAddress = "127.0.0.1",
  [ValidateSet("demo", "triposr", "trellis", "hunyuan3d", "comfyui")]
  [string]$Provider = "demo",
  [string]$PythonExecutable = "python",
  [string]$TripoSRRoot = "",
  [string]$TripoSRModel = "",
  [string]$BlenderBin = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$env:PYTHONPATH = if ($env:PYTHONPATH) { "$root;$env:PYTHONPATH" } else { $root }
$env:AI_3D_DEFAULT_PROVIDER = $Provider
if ($TripoSRRoot) { $env:TRIPOSR_ROOT = $TripoSRRoot }
if ($TripoSRModel) { $env:TRIPOSR_MODEL = $TripoSRModel }
if ($BlenderBin) { $env:BLENDER_BIN = $BlenderBin }
& $PythonExecutable -m uvicorn tool.ai_3d_worker.app:app --host $HostAddress --port $Port
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
