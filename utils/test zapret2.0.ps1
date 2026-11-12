# =============================================
# test zapret.ps1 - БЫСТРАЯ ВЕРСИЯ (ПАРАЛЛЕЛЬНАЯ)
# =============================================

# Windows PowerShell 5.1: keep Cyrillic output readable.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {} 

$hasErrors = $false
$ErrorActionPreference = "Continue"

# Paths
$rootDir = Split-Path -Parent $PSScriptRoot
$listsDir = Join-Path $rootDir "lists"
$utilsDir = Join-Path $rootDir "utils"
$resultsDir = Join-Path $utilsDir "test results"

if (-not (Test-Path $resultsDir)) { 
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

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

function Get-PingResult {
    param([string]$Hostname)
    
    try {
        $pingResultRaw = ping -n 2 -w 2000 $Hostname 2>&1
        $pingOutput = $pingResultRaw | Out-String
        
        if ($pingOutput -match [char]0x0421 + [char]0x0440 + [char]0x0435 + [char]0x0434 + [char]0x043D + [char]0x0435 + [char]0x0435 + '\s*=\s*(\d+)\s*' + [char]0x043C + [char]0x0441 + [char]0x0435 + [char]0x043A) {
            return "$($matches[1]) ms"
        }
        if ($pingOutput -match 'Average\s*=\s*(\d+)ms') {
            return "$($matches[1]) ms"
        }
        if ($pingOutput -match [char]0x0432 + [char]0x0440 + [char]0x0435 + [char]0x043C + [char]0x044F + '=(\d+)' + [char]0x043C + [char]0x0441) {
            return "$($matches[1]) ms"
        }
        if ($pingOutput -match 'time[=<](\d+)ms') {
            return "$($matches[1]) ms"
        }
        if ($pingOutput -match 'Reply from' -or $pingOutput -match [char]0x041E + [char]0x0442 + [char]0x0432 + [char]0x0435 + [char]0x0442 + [char]0x0020 + [char]0x043E + [char]0x0442) {
            return "OK"
        }
        return "Timeout"
    } catch {
        return "Timeout"
    }
}

function Get-Targets {
    $targetsFile = Join-Path $utilsDir "targets.txt"
    $targets = @()
    
    $defaultTargets = @(
        @{Name="Discord Main"; Value="https://discord.com"},
        @{Name="Discord Gateway"; Value="https://gateway.discord.gg"},
        @{Name="Discord CDN"; Value="https://cdn.discordapp.com"},
        @{Name="Discord Updates"; Value="https://updates.discord.com"},
        @{Name="YouTube Web"; Value="https://www.youtube.com"},
        @{Name="YouTube Short"; Value="https://youtu.be"},
        @{Name="YouTube Image"; Value="https://i.ytimg.com"},
        @{Name="YouTube Video Redirect"; Value="https://redirector.googlevideo.com"},
        @{Name="Google Main"; Value="https://www.google.com"},
        @{Name="Google Gstatic"; Value="https://www.gstatic.com"},
        @{Name="Cloudflare Web"; Value="https://www.cloudflare.com"},
        @{Name="Cloudflare CDN"; Value="https://cdnjs.cloudflare.com"},
        @{Name="Cloudflare DNS"; Value="PING:1.1.1.1"},
        @{Name="Cloudflare DNS 1.0.0.1"; Value="PING:1.0.0.1"},
        @{Name="Google DNS 8.8.8.8"; Value="PING:8.8.8.8"},
        @{Name="Google DNS 8.8.4.4"; Value="PING:8.8.4.4"},
        @{Name="Quad9 DNS 9.9.9.9"; Value="PING:9.9.9.9"}
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

function Get-HostFromUrl {
    param([string]$url)
    if ($url -match '^https?://([^/]+)') {
        return $matches[1]
    }
    return $null
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
    Sort-Object { [Regex]::Replace($_.Name, "(\d+)", { $args[0].Value.PadLeft(8, "0") }) }

if ($batFiles.Count -eq 0) {
    Write-Host "[ERROR] No configs found!" -ForegroundColor Red
    exit 1
}

# =============================================
# RUN TESTS
# =============================================

$targets = Get-Targets
$originalIpsetStatus = Get-IpsetStatus
$originalWinws = Get-WinwsSnapshot
$globalResults = @()
$env:NO_UPDATE_CHECK = "1"

$maxNameLen = ($targets | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
if (-not $maxNameLen -or $maxNameLen -lt 20) { $maxNameLen = 20 }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "                 ZAPRET TESTING (Detail)" -ForegroundColor Cyan
Write-Host "                 Configs: $($batFiles.Count)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

try {
    foreach ($file in $batFiles) {
        Write-Host ""
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host "  Testing: $($file.Name)" -ForegroundColor Yellow
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
        
        Stop-Zapret
        
        Write-Host "  > Starting config..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$($file.FullName)`"" -WorkingDirectory $targetDir -PassThru -WindowStyle Minimized
        Start-Sleep -Seconds 4
        
        Write-Host "  > Running parallel tests..." -ForegroundColor DarkGray
        
        # =============================================
        # ПАРАЛЛЕЛЬНАЯ ПРОВЕРКА (ускорение)
        # =============================================
        $maxParallel = 10
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxParallel)
        $runspacePool.Open()
        
        $scriptBlock = {
            param($target, $maxNameLen)
            
            $name = $target.Name
            $value = $target.Value
            $pingResult = "n/a"
            $httpResults = @()
            $isPingOnly = $false
            
            if ($value -like "PING:*") {
                $isPingOnly = $true
                $pingHost = $value -replace '^PING:\s*', ''
                
                try {
                    $pingResultRaw = ping -n 2 -w 2000 $pingHost 2>&1
                    $pingOutput = $pingResultRaw | Out-String
                    
                    if ($pingOutput -match [char]0x0421 + [char]0x0440 + [char]0x0435 + [char]0x0434 + [char]0x043D + [char]0x0435 + [char]0x0435 + '\s*=\s*(\d+)\s*' + [char]0x043C + [char]0x0441 + [char]0x0435 + [char]0x043A) {
                        $pingResult = "$($matches[1]) ms"
                    } elseif ($pingOutput -match 'Average\s*=\s*(\d+)ms') {
                        $pingResult = "$($matches[1]) ms"
                    } elseif ($pingOutput -match [char]0x0432 + [char]0x0440 + [char]0x0435 + [char]0x043C + [char]0x044F + '=(\d+)' + [char]0x043C + [char]0x0441) {
                        $pingResult = "$($matches[1]) ms"
                    } elseif ($pingOutput -match 'time[=<](\d+)ms') {
                        $pingResult = "$($matches[1]) ms"
                    } elseif ($pingOutput -match 'Reply from' -or $pingOutput -match [char]0x041E + [char]0x0442 + [char]0x0432 + [char]0x0435 + [char]0x0442 + [char]0x0020 + [char]0x043E + [char]0x0442) {
                        $pingResult = "OK"
                    } else {
                        $pingResult = "Timeout"
                    }
                } catch {
                    $pingResult = "Timeout"
                }
            } else {
                $protocols = @(
                    @{Label="HTTP"; Args=@("--http1.1")},
                    @{Label="TLS1.2"; Args=@("--tlsv1.2", "--tls-max", "1.2")},
                    @{Label="TLS1.3"; Args=@("--tlsv1.3", "--tls-max", "1.3")}
                )
                
                foreach ($proto in $protocols) {
                    try {
                        $curlArgs = @("-I", "-s", "-m", "3", "-o", "NUL", "-w", "%{http_code}", "--show-error") + $proto.Args
                        $output = & curl.exe @curlArgs $value 2>&1
                        $httpCode = ($output | Out-String).Trim()
                        
                        if ($httpCode -match "^\d{3}$" -and $httpCode -ne "000") {
                            $httpResults += @{Label=$proto.Label; Code=$httpCode; Status="OK"}
                        } else {
                            $httpResults += @{Label=$proto.Label; Code="ERROR"; Status="ERROR"}
                        }
                    } catch {
                        $httpResults += @{Label=$proto.Label; Code="ERROR"; Status="ERROR"}
                    }
                }
                
                $pingHost = $value -replace "^https?://", "" -replace "/.*$", ""
                if ($pingHost) {
                    try {
                        $pingResultRaw = ping -n 2 -w 2000 $pingHost 2>&1
                        $pingOutput = $pingResultRaw | Out-String
                        
                        if ($pingOutput -match [char]0x0421 + [char]0x0440 + [char]0x0435 + [char]0x0434 + [char]0x043D + [char]0x0435 + [char]0x0435 + '\s*=\s*(\d+)\s*' + [char]0x043C + [char]0x0441 + [char]0x0435 + [char]0x043A) {
                            $pingResult = "$($matches[1]) ms"
                        } elseif ($pingOutput -match 'Average\s*=\s*(\d+)ms') {
                            $pingResult = "$($matches[1]) ms"
                        } elseif ($pingOutput -match [char]0x0432 + [char]0x0440 + [char]0x0435 + [char]0x043C + [char]0x044F + '=(\d+)' + [char]0x043C + [char]0x0441) {
                            $pingResult = "$($matches[1]) ms"
                        } elseif ($pingOutput -match 'time[=<](\d+)ms') {
                            $pingResult = "$($matches[1]) ms"
                        } elseif ($pingOutput -match 'Reply from' -or $pingOutput -match [char]0x041E + [char]0x0442 + [char]0x0432 + [char]0x0435 + [char]0x0442 + [char]0x0020 + [char]0x043E + [char]0x0442) {
                            $pingResult = "OK"
                        } else {
                            $pingResult = "Timeout"
                        }
                    } catch {
                        $pingResult = "Timeout"
                    }
                }
            }
            
            return @{
                Name = $name
                PingResult = $pingResult
                HttpResults = $httpResults
                IsPingOnly = $isPingOnly
                MaxNameLen = $maxNameLen
            }
        }
        
        $runspaces = @()
        foreach ($target in $targets) {
            $ps = [powershell]::Create().AddScript($scriptBlock)
            [void]$ps.AddArgument($target)
            [void]$ps.AddArgument($maxNameLen)
            $ps.RunspacePool = $runspacePool
            
            $runspaces += [PSCustomObject]@{
                Powershell = $ps
                Handle = $ps.BeginInvoke()
                Name = $target.Name
            }
        }
        
        $targetResults = @()
        foreach ($rs in $runspaces) {
            try {
                $waitMs = 10000
                $handle = $rs.Handle
                if ($handle -and $handle.AsyncWaitHandle) {
                    $completed = $handle.AsyncWaitHandle.WaitOne($waitMs)
                    if (-not $completed) {
                        try { $rs.Powershell.Stop() } catch {}
                    }
                }
            } catch {}
            
            try {
                $targetResults += $rs.Powershell.EndInvoke($rs.Handle)
            } catch {
                $targetResults += @{
                    Name = $rs.Name
                    PingResult = "Timeout"
                    HttpResults = @()
                    IsPingOnly = $false
                    MaxNameLen = $maxNameLen
                }
            }
            $rs.Powershell.Dispose()
        }
        
        $runspacePool.Close()
        $runspacePool.Dispose()
        
        # Вывод результатов
        $targetLookup = @{}
        foreach ($res in $targetResults) { 
            $targetLookup[$res.Name] = $res 
        }
        
        $results = @()
        foreach ($target in $targets) {
            $res = $targetLookup[$target.Name]
            if (-not $res) { continue }
            
            if ($res.IsPingOnly) {
                $pingColor = if ($res.PingResult -eq "Timeout") { "Red" } else { "Cyan" }
                Write-Host "  $($res.Name.PadRight($maxNameLen))" -NoNewline
                Write-Host " Ping: " -NoNewline -ForegroundColor DarkGray
                Write-Host "$($res.PingResult)" -ForegroundColor $pingColor
            } else {
                Write-Host "  $($res.Name.PadRight($maxNameLen))" -NoNewline
                
                foreach ($http in $res.HttpResults) {
                    $color = if ($http.Status -eq "OK") { "Green" } else { "Red" }
                    Write-Host " $($http.Label):" -NoNewline -ForegroundColor DarkGray
                    Write-Host "$($http.Code)" -NoNewline -ForegroundColor $color
                }
                
                Write-Host " | " -NoNewline -ForegroundColor DarkGray
                Write-Host "Ping: " -NoNewline -ForegroundColor DarkGray
                
                $pingColor = if ($res.PingResult -eq "Timeout") { "Red" } else { "Cyan" }
                Write-Host "$($res.PingResult)" -ForegroundColor $pingColor
            }
            
            $results += @{
                Name = $res.Name
                Http = ($res.HttpResults | ForEach-Object { "$($_.Label):$($_.Code)" }) -join " "
                Ping = $res.PingResult
                IsPingOnly = $res.IsPingOnly
            }
        }
        
        $globalResults += @{
            Config = $file.Name
            Results = $results
        }
        
        Stop-Zapret
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }

    # =============================================
    # АНАЛИТИКА И СОХРАНЕНИЕ
    # =============================================
    
    Write-Host ""
    Write-Host "=== ANALYTICS ===" -ForegroundColor Cyan
    
    $analytics = @{}
    foreach ($res in $globalResults) {
        $config = $res.Config
        $analytics[$config] = @{ OK = 0; ERROR = 0; PING_OK = 0; PING_FAIL = 0 }
        foreach ($target in $res.Results) {
            if ($target.IsPingOnly) {
                if ($target.Ping -ne "Timeout" -and $target.Ping -ne "n/a") {
                    $analytics[$config].PING_OK++
                } else {
                    $analytics[$config].PING_FAIL++
                }
            } else {
                if ($target.Http -notmatch "ERROR") {
                    $analytics[$config].OK++
                } else {
                    $analytics[$config].ERROR++
                }
                if ($target.Ping -ne "Timeout" -and $target.Ping -ne "n/a") {
                    $analytics[$config].PING_OK++
                } else {
                    $analytics[$config].PING_FAIL++
                }
            }
        }
    }
    
    $bestConfig = $null
    $maxScore = -1
    foreach ($config in $analytics.Keys) {
        $a = $analytics[$config]
        $score = $a.OK + $a.PING_OK
        $line = "$config : HTTP OK: $($a.OK), ERR: $($a.ERROR), PING OK: $($a.PING_OK), FAIL: $($a.PING_FAIL)"
        Write-Host $line -ForegroundColor Yellow
        if ($score -gt $maxScore) {
            $maxScore = $score
            $bestConfig = $config
        }
    }
    
    Write-Host ""
    Write-Host "Best strategy: $bestConfig" -ForegroundColor Green
    
    # =============================================
    # СОХРАНЕНИЕ В ФАЙЛ
    # =============================================
    
    $dateStr = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $resultFile = Join-Path $resultsDir "test_results_$dateStr.txt"
    
    "" | Out-File $resultFile -Encoding UTF8
    Add-Content $resultFile "=== ZAPRET TEST RESULTS ==="
    Add-Content $resultFile "Date: $(Get-Date)"
    Add-Content $resultFile "Best config: $bestConfig"
    Add-Content $resultFile ""
    
    foreach ($res in $globalResults) {
        Add-Content $resultFile "Config: $($res.Config)"
        foreach ($target in $res.Results) {
            if ($target.IsPingOnly) {
                Add-Content $resultFile "  $($target.Name.PadRight(30)) PING $($target.Ping)"
            } else {
                Add-Content $resultFile "  $($target.Name.PadRight(30)) $($target.Http) | PING $($target.Ping)"
            }
        }
        Add-Content $resultFile ""
    }
    
    Add-Content $resultFile "=== ANALYTICS ==="
    foreach ($config in $analytics.Keys) {
        $a = $analytics[$config]
        $line = "$config : HTTP OK: $($a.OK), ERR: $($a.ERROR), PING OK: $($a.PING_OK), FAIL: $($a.PING_FAIL)"
        Add-Content $resultFile $line
    }
    Add-Content $resultFile ""
    Add-Content $resultFile "Best strategy: $bestConfig"
    
    Write-Host ""
    Write-Host "Results saved to $resultFile" -ForegroundColor Green
    Write-Host "Best config for future use: $bestConfig" -ForegroundColor Yellow
    
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