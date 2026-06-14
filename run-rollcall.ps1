param(
    [switch]$ResetCookies
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $AppDir

function New-Candidate {
    param([string[]]$Parts)
    return ,$Parts
}

function Get-BaseArgs {
    param([string[]]$Candidate)
    if ($Candidate.Count -le 1) {
        return @()
    }
    return $Candidate[1..($Candidate.Count - 1)]
}

function Invoke-CandidatePython {
    param(
        [string[]]$Candidate,
        [string[]]$Arguments
    )
    $cmd = $Candidate[0]
    $baseArgs = Get-BaseArgs $Candidate
    & $cmd @baseArgs @Arguments
}

function Test-CandidatePython {
    param([string[]]$Candidate)
    try {
        $cmd = $Candidate[0]
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $cmd)) {
            return $false
        }
        Invoke-CandidatePython $Candidate @("-c", "import sys; print(sys.executable)") *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

$candidates = New-Object System.Collections.Generic.List[string[]]

if ($env:TRON_PYTHON) {
    $candidates.Add(@($env:TRON_PYTHON))
}

$localPythonRoots = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Python"),
    (Join-Path $env:LOCALAPPDATA "Python")
)
foreach ($root in $localPythonRoots) {
    if (Test-Path -LiteralPath $root) {
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object {
                $exe = Join-Path $_.FullName "python.exe"
                if (Test-Path -LiteralPath $exe) {
                    $candidates.Add(@($exe))
                }
            }
    }
}

$candidates.Add(@("py", "-3"))
$candidates.Add(@("python"))
$candidates.Add(@("python3"))

$Python = $null
foreach ($candidate in $candidates) {
    if (Test-CandidatePython $candidate) {
        $Python = $candidate
        break
    }
}

if (-not $Python) {
    Write-Host "Python 3 was not found."
    Write-Host "Install Python 3, then run this file again."
    return
}

$pythonText = ($Python -join " ")
Write-Host "Using Python: $pythonText"

$dependencyCheck = @"
import importlib.util
missing = [name for name in ("aiohttp", "yaml", "nacl", "ddddocr") if importlib.util.find_spec(name) is None]
raise SystemExit(1 if missing else 0)
"@

Invoke-CandidatePython $Python @("-c", $dependencyCheck) *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing required Python packages..."
    Invoke-CandidatePython $Python @("-m", "pip", "install", "-e", ".")
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Dependency installation failed. Run this command manually in this folder:"
        Write-Host "python -m pip install -e ."
        return
    }
}

if ($ResetCookies) {
    if (Test-Path ".\state\cookies") {
        Remove-Item -Path ".\state\cookies\*.json" -Force -ErrorAction SilentlyContinue
        Write-Host "Cookie cache cleared."
    } else {
        Write-Host "No cookie cache folder found."
    }
}

Invoke-CandidatePython $Python @("-m", "troTHU.tron")

Write-Host ""
Write-Host "Program ended. You can close this PowerShell window."
