param(
    [string]$PythonLauncher = "py -3.11"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$BackendDir = Join-Path $ProjectRoot "backend"
$FrontendDir = Join-Path $ProjectRoot "frontend"
$BuildVenv = Join-Path $BackendDir ".venv-packaging"

function Invoke-Checked([string]$Command) {
    Write-Host "> $Command" -ForegroundColor Cyan
    Invoke-Expression $Command
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter is not available on PATH. Install Flutter before building Windows."
}

Push-Location $ProjectRoot
try {
    if (-not (Test-Path $BuildVenv)) {
        Invoke-Checked "$PythonLauncher -m venv `"$BuildVenv`""
    }

    $BuildPython = Join-Path $BuildVenv "Scripts\python.exe"
    Invoke-Checked "`"$BuildPython`" -m pip install -r `"$BackendDir\requirements-packaging.txt`""
    Invoke-Checked "`"$BuildPython`" -m PyInstaller --noconfirm --clean --onefile --name medivision_backend --paths `"$BackendDir`" `"$BackendDir\standalone_server.py`""

    if (-not (Test-Path (Join-Path $FrontendDir "windows"))) {
        Invoke-Checked "flutter create --platforms=windows `"$FrontendDir`""
    }
    Invoke-Checked "flutter build windows --release --dart-define=API_BASE_URL=http://127.0.0.1:8000/api"

    $ReleaseDir = Join-Path $FrontendDir "build\windows\x64\runner\Release"
    $BackendReleaseDir = Join-Path $ReleaseDir "backend"
    New-Item -ItemType Directory -Force -Path $BackendReleaseDir | Out-Null
    Copy-Item (Join-Path $ProjectRoot "backend\dist\medivision_backend.exe") $BackendReleaseDir -Force
    Write-Host "Standalone Windows build created at: $ReleaseDir" -ForegroundColor Green
}
finally {
    Pop-Location
}
