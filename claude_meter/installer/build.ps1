# Genera el instalador: build\installer_output\ClaudeMeter-Setup-<versión>.exe
# Requisitos: Flutter, Visual Studio (C++) e Inno Setup 6.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

flutter build windows --release
if ($LASTEXITCODE) { throw 'Falló flutter build' }

$extra = Join-Path $root 'build\installer'
New-Item -ItemType Directory -Force $extra | Out-Null

# Runtime de Visual C++ (se toma de la instalación de Visual Studio).
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -property installationPath
$crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory |
    Sort-Object FullName | Select-Object -Last 1
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    Copy-Item (Join-Path $crt.FullName $dll) $extra -Force
}

$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'No se encontró Inno Setup 6 (winget install JRSoftware.InnoSetup)' }
& $iscc (Join-Path $PSScriptRoot 'claude_meter.iss')
if ($LASTEXITCODE) { throw 'Falló ISCC' }
