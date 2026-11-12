# =============================================
# test zapret.ps1 - БЫСТРАЯ ОПТИМИЗИРОВАННАЯ ВЕРСИЯ
# =============================================

$ErrorActionPreference = "Continue"

# Paths
$rootDir = Split-Path -Parent $PSScriptRoot
$listsDir = Join-Path $rootDir "lists"
$utilsDir = Join-Path $rootDir "utils"
$resultsDir = Join-Path $utilsDir "test results"

if (-not (Test-Path $resultsDir)) { 
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

# =============================================
# FUNCTIONS
# =============================================

function Stop-Zapret {
    Get-Process -Name "winws" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Get-IpsetStatus {
    $listFile = Join-Path $listsDir "ipset-all.txt"
    if (-not (Test-Path $listFile)) { return "none" }
    $lineCount = (Get-Content $listFile | Measure-Object -Line).Lines
    if ($lineCount -eq 0) { return "any" }
    $hasDummy = Get-Content $listFile | Select-String -Pattern "203\.0\.113\.113/32" -Quiet
    if ($hasDummy) { return "none" } else { return "loaded" }
}

function Set-IpsetMode {
    param([string]$mode)
    $listFile = Join-Path $listsDir "ipset-all.txt"
    $backupFile = Join-Path $listsDir "ipset-all.test-backup.txt"
    if ($mode -eq "any") {
        if (Test-Path $listFile) {
            Copy-Item $listFile $backupFile -Force -ErrorAction SilentlyContinue
        } else {
            "" | Out-File $backupFile -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        "" | Out-File $listFile -Encoding UTF8 -ErrorAction SilentlyContinue
    } elseif ($mode -eq "restore") {
        if (Test-Path $backupFile) {
            Move-Item $backupFile $listFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-WinwsSnapshot {
    try {
        return Get-CimInstance Win32_Process -Filter "Name='winws.exe'" -ErrorAction SilentlyContinue |
            Select-Object ProcessId, CommandLine, ExecutablePath
    } catch {
        return @()
    }
}

function Restore-WinwsSnapshot {
    param($snapshot)
    if (-not $snapshot -or $snapshot.Count -eq 0) { return }
    $current = @()
    try { $current = (Get-WinwsSnapshot).CommandLine } catch { $current = @() }
    foreach ($p in $snapshot) {
        if (-not $p.ExecutablePath) { continue }
        if ($current -and $current -contains $p.CommandLine) { continue }
        $exe = $p.ExecutablePath
        $processArgs = ""
        if ($p.CommandLine) {
            $quotedExe = '"' + $exe + '"'
            if ($p.CommandLine.StartsWith($quotedExe)) {
                $processArgs = $p.CommandLine.Substring($quotedExe.Length).Trim()
            } elseif ($p.CommandLine.StartsWith($exe)) {
                $processArgs = $p.CommandLine.Substring($exe.Length).Trim()
            }
        }
        Start-Process -FilePath $exe -ArgumentList $processArgs -WorkingDirectory (Split-Path $exe -Parent) -WindowStyle Minimized | Out-Null
    }
}

function Get-Targets {
    $targetsFile = Join-Path $utilsDir "targets.txt"
    $targets = @()
    
    $defaultTargets = @(
        @{Name="Discord"; Value="https://discord.com"},
        @{Name="YouTube"; Value="https://www.youtube.com"},
        @{Name="Telegram"; Value="https://telegram.org"},
        @{Name="Cloudflare"; Value="https://www.cloudflare.com"},
        @{Name="Google"; Value="https://www.google.com"},
        @{Name="GitHub"; Value="https://github.com"}
    )
    
    if (Test-Path $targetsFile) {
        $raw = Get-Content $targetsFile -ErrorAction SilentlyContinue
        foreach ($line in $raw) {
            if ($line -match '^\s*(\w+)\s*=\s*"(.+)"\s*$') {
                $targets += @{Name=$matches[1]; Value=$matches[2]}
            }
        }
    }
    
    if ($targets.Count -eq 0) {
        $targets = $defaultTargets
    }
    
    return $targets
}

# =============================================
# CHECK ADMIN
# =============================================

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Run as Administrator!" -ForegroundColor Red
    exit 1
}

# =============================================
# GET CONFIGS
# =============================================

$targetDir = $rootDir
$excludedBatNames = @("launch_zapret.bat", "service.bat")
$batFiles = Get-ChildItem -Path $targetDir -Filter "*.bat" -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -notlike "*test*" -and $excludedBatNames -notcontains $_.Name } | 
    Sort-Object Name

if ($batFiles.Count -eq 0) {
    Write-Host "[ERROR] No configs found!" -ForegroundColor Red
    exit 1
}

# =============================================
# RUN TESTS (ОПТИМИЗИРОВАННЫЙ)
# =============================================

$targets = Get-Targets
$originalIpsetStatus = Get-IpsetStatus
$originalWinws = Get-WinwsSnapshot
$globalResults = @()
$env:NO_UPDATE_CHECK = "1"

# Убираем пинг-проверки для скорости (только HTTP)
# Добавляем Telegram вместо Google для важности

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "           ZAPRET FAST TESTING" -ForegroundColor Cyan
Write-Host "           Configs: $($batFiles.Count)" -ForegroundColor Cyan
Write-Host "           Targets: $($targets.Count)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

try {
    $configNum = 0
    foreach ($file in $batFiles) {
        $configNum++
        Write-Host ""
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host "  [$configNum/$($batFiles.Count)] $($file.Name)" -ForegroundColor Yellow
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
        
        Stop-Zapret
        Start-Sleep -Milliseconds 500
        
        Write-Host "  > Starting..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$($file.FullName)`"" -WorkingDirectory $targetDir -PassThru -WindowStyle Minimized
        Start-Sleep -Seconds 3  # Уменьшено до 3 секунд для скорости
        
        $configResults = @()
        
        # Параллельная проверка через runspace pool
        $maxParallel = 6
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxParallel)
        $runspacePool.Open()
        
        $scriptBlock = {
            param($target)
            
            $name = $target.Name
            $url = $target.Value
            
            try {
                $curlArgs = @("-I", "-s", "-m", "3", "-o", "NUL", "-w", "%{http_code}", "--show-error")
                $output = & curl.exe @curlArgs $url 2>&1
                $code = ($output | Out-String).Trim()
                
                if ($code -match "^\d{3}$" -and $code -ne "000") {
                    $status = "OK"
                    $httpCode = $code
                } else {
                    $status = "FAIL"
                    $httpCode = "ERR"
                }
            } catch {
                $status = "ERROR"
                $httpCode = "ERR"
            }
            
            return @{
                Name = $name
                Status = $status
                HttpCode = $httpCode
            }
        }
        
        $runspaces = @()
        foreach ($target in $targets) {
            $ps = [powershell]::Create().AddScript($scriptBlock)
            [void]$ps.AddArgument($target)
            $ps.RunspacePool = $runspacePool
            
            $runspaces += [PSCustomObject]@{
                Powershell = $ps
                Handle = $ps.BeginInvoke()
                Name = $target.Name
            }
        }
        
        Write-Host "  > Testing..." -ForegroundColor DarkGray
        
        $targetResults = @()
        foreach ($rs in $runspaces) {
            try {
                $handle = $rs.Handle
                if ($handle -and $handle.AsyncWaitHandle) {
                    $handle.AsyncWaitHandle.WaitOne(5000) | Out-Null
                }
            } catch {}
            
            try {
                $targetResults += $rs.Powershell.EndInvoke($rs.Handle)
            } catch {
                $targetResults += @{
                    Name = $rs.Name
                    Status = "ERROR"
                    HttpCode = "ERR"
                }
            }
            $rs.Powershell.Dispose()
        }
        
        $runspacePool.Close()
        $runspacePool.Dispose()
        
        # Вывод и сохранение результатов
        $okCount = 0
        foreach ($res in $targetResults) {
            $color = if ($res.Status -eq "OK") { "Green" } else { "Red" }
            $statusText = if ($res.Status -eq "OK") { $res.HttpCode } else { "❌" }
            Write-Host "    $($res.Name.PadRight(15)) $statusText" -ForegroundColor $color
            
            if ($res.Status -eq "OK") { $okCount++ }
            
            $configResults += @{
                Name = $res.Name
                Http = $res.HttpCode
                Status = $res.Status
            }
        }
        
        $totalTargets = $targetResults.Count
        $score = [math]::Round(($okCount / $totalTargets) * 100, 0)
        Write-Host "  > Score: $okCount/$totalTargets ($score%)" -ForegroundColor Cyan
        
        $globalResults += @{
            Config = $file.Name
            Results = $configResults
            Score = $score
            OK = $okCount
            Total = $totalTargets
        }
        
        Stop-Zapret
        if (-not $proc.HasExited) { 
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue 
        }
        Start-Sleep -Milliseconds 500
    }

    # =============================================
    # АНАЛИТИКА
    # =============================================
    
    Write-Host ""
    Write-Host "=== ANALYTICS ===" -ForegroundColor Cyan
    
    $bestConfig = $null
    $bestScore = -1
    
    foreach ($res in $globalResults) {
        $line = "$($res.Config.PadRight(40)) Score: $($res.OK)/$($res.Total) ($($res.Score)%)"
        Write-Host $line -ForegroundColor Yellow
        
        if ($res.Score -gt $bestScore) {
            $bestScore = $res.Score
            $bestConfig = $res.Config
        }
    }
    
    Write-Host ""
    Write-Host "Best strategy: $bestConfig" -ForegroundColor Green
    
    # =============================================
    # СОХРАНЕНИЕ
    # =============================================
    
    $dateStr = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $resultFile = Join-Path $resultsDir "test_results_$dateStr.txt"
    
    "" | Out-File $resultFile -Encoding UTF8
    Add-Content $resultFile "=== ZAPRET FAST TEST RESULTS ==="
    Add-Content $resultFile "Date: $(Get-Date)"
    Add-Content $resultFile ""
    
    foreach ($res in $globalResults) {
        Add-Content $resultFile "Config: $($res.Config) (Score: $($res.OK)/$($res.Total) - $($res.Score)%)"
        foreach ($target in $res.Results) {
            Add-Content $resultFile "  $($target.Name.PadRight(15)) HTTP: $($target.Http)"
        }
        Add-Content $resultFile ""
    }
    
    Add-Content $resultFile "=== RESULT ==="
    Add-Content $resultFile "Best strategy: $bestConfig"
    
    Write-Host ""
    Write-Host "Results saved to $resultFile" -ForegroundColor Green
    
} catch {
    Write-Host "[ERROR] $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
} finally {
    Stop-Zapret
    Restore-WinwsSnapshot -snapshot $originalWinws
    if ($originalIpsetStatus -ne "any") {
        Set-IpsetMode -mode "restore"
    }
}

Write-Host ""
Write-Host "Testing completed." -ForegroundColor Yellow
exit 0