$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host '=== Zapret GUI production build ===' -ForegroundColor Cyan

if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -and $env:PROCESSOR_ARCHITEW6432 -ne 'AMD64') {
    throw 'Сборка установщика рассчитана на Windows x64.'
}

python -m pip install --upgrade pip
python -m pip install -r requirements-build.txt

Remove-Item -Recurse -Force build, dist -ErrorAction SilentlyContinue

$pyinstallerArgs = @(
    '-m', 'PyInstaller', '--noconfirm', '--clean', '--onedir', '--windowed',
    '--name', 'ZapretGUI', 'main.py'
)

if (Test-Path 'icon.ico') {
    $pyinstallerArgs += @('--icon', 'icon.ico')
}

Write-Host 'Запускаю PyInstaller...' -ForegroundColor Cyan
python @pyinstallerArgs

$runtime = Join-Path $PSScriptRoot 'dist\ZapretGUI'
if (-not (Test-Path (Join-Path $runtime 'ZapretGUI.exe'))) {
    throw 'PyInstaller не создал ZapretGUI.exe.'
}

# PyInstaller bundles Python modules, но не знает о BAT/PS1/текстовых списках,
# которые GUI может использовать во время работы. Переносим runtime-ресурсы.
$skip = @('.git', '.idea', '.venv', 'venv', '__pycache__', 'build', 'dist', 'installer')
$extensions = @('.bat', '.cmd', '.ps1', '.txt', '.bin', '.dll', '.sys', '.ico', '.png', '.jpg', '.json')

Get-ChildItem -Path $PSScriptRoot -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($PSScriptRoot.Length).TrimStart('\')
    $parts = $relative -split '\\'
    if ($parts | Where-Object { $skip -contains $_ }) { return }
    if ($_.Extension.ToLowerInvariant() -notin $extensions) { return }
    if ($_.Name -in @('requirements-build.txt')) { return }

    $dest = Join-Path $runtime $relative
    $parent = Split-Path $dest -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item $_.FullName $dest -Force
}

# Production sanity checks.
python -m py_compile main.py dependency_installer.py config.py gui.py worker.py utils.py
if (-not (Test-Path (Join-Path $runtime 'dependency_installer.py'))) {
    # This file is normally bundled by PyInstaller; keep the source copy only
    # when a future dynamic import requires it.
    Copy-Item 'dependency_installer.py' $runtime -Force
}

$iss = Join-Path $PSScriptRoot 'installer\ZapretGUI.iss'
$issc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($issc) {
    & $issc.Source $iss
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup завершился с кодом $LASTEXITCODE" }
    Write-Host 'Installer created:' -ForegroundColor Green
    Get-ChildItem 'installer\Output\*.exe' | Select-Object FullName, Length
} else {
    Write-Host 'PyInstaller build finished.' -ForegroundColor Green
    Write-Host 'Для создания Setup.exe установите Inno Setup и снова запустите этот скрипт.' -ForegroundColor Yellow
}
