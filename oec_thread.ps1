# Script: oec_thread.ps1 - Multi-Thread Version with PSD1 Support
param(
    [int]$ThreadNumber = 1,
    [string]$AutoCleanExe = 'TES4EditQuickAutoClean.exe'
)

Write-Host "[THREAD$ThreadNumber] *** thread started ***"

$ScriptDir   = $PSScriptRoot
$TempDir     = "$ScriptDir\temp"
$SettingsFile= "$ScriptDir\oec_settings.psd1"

# ------------------------------------------------------------------
# Helper: read GameDataPath from settings
function Load-ThreadSettings {
    if (Test-Path $SettingsFile) {
        try {
            $settings = Import-PowerShellDataFile $SettingsFile
            if ($settings.ContainsKey('GameDataPath')) {
                return $settings.GameDataPath
            }
        } catch {
            Write-Host "[THREAD$ThreadNumber] Warning: Could not load settings file" -ForegroundColor Yellow
        }
    }
    return "$ScriptDir\..\Data"
}

$GameDataPath = Load-ThreadSettings
$CleanerExe   = "$ScriptDir\Thread$ThreadNumber\$AutoCleanExe"
$BlackFile    = "$ScriptDir\oec_blacklist.txt"
$ErrorFile    = "$ScriptDir\oec_errorlist.txt"

# Task-queue / status files
$TaskQueueFile = "$TempDir\oec_taskqueue.txt"
$StatusFile    = "$TempDir\oec_status$ThreadNumber.txt"
$ProgressFile  = "$TempDir\oec_progress$ThreadNumber.txt"

# Ensure temp folder exists
if (-not (Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }

# Track processed tasks to prevent duplicates
$ProcessedTasks = @{}
$completed = 0
$successful = 0
$failed = 0

# ------------------------------------------------------------------
# Helper: write status
function Update-Status($status) {
    $status | Out-File $StatusFile -Encoding utf8
}

# Helper: write progress
function Update-Progress($completed) {
    "COMPLETED:$completed" | Add-Content $ProgressFile -Encoding utf8
}

# Helper: get next task
function Get-NextTask {
    $mutexName = "Global\OECTaskQueueMutex"
    $mutex = $null
    try {
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        if ($mutex.WaitOne(10000)) {
            if (Test-Path $TaskQueueFile) {
                $tasks = @(Get-Content $TaskQueueFile -Encoding utf8 | Where-Object { $_.Trim() -ne "" })
                if ($tasks.Count -gt 0) {
                    $nextTask = $tasks[0]
                    if ($tasks.Count -gt 1) {
                        $tasks[1..($tasks.Count-1)] | Out-File $TaskQueueFile -Encoding utf8
                    } else {
                        Remove-Item $TaskQueueFile -ErrorAction SilentlyContinue
                    }
                    return $nextTask
                } else {
                    Remove-Item $TaskQueueFile -ErrorAction SilentlyContinue
                }
            }
            return $null
        } else {
            Write-Host "[THREAD$ThreadNumber] WARN: mutex timeout" -ForegroundColor Yellow
            return $null
        }
    } finally {
        if ($mutex) { try { $mutex.ReleaseMutex() } catch {} ; $mutex.Dispose() }
    }
}

# Helper: add to blacklist / error list
function AddLog($file, $ok) {
    $mutexName = "Global\OECBlacklistMutex"
    $mutex = $null
    try {
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        if ($mutex.WaitOne(10000)) {
            "$(Get-Date -f 'yyyy-MM-dd')`t$file`t$ok" | Add-Content $BlackFile -Encoding utf8
        }
    } finally {
        if ($mutex) { try { $mutex.ReleaseMutex() } catch {} ; $mutex.Dispose() }
    }
}

function AddError($file) {
    $mutexName = "Global\OECErrorMutex"
    $mutex = $null
    try {
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        if ($mutex.WaitOne(5000)) {
            "$(Get-Date -f 'yyyy-MM-dd')`t$file" | Add-Content $ErrorFile -Encoding utf8
        }
    } finally {
        if ($mutex) { try { $mutex.ReleaseMutex() } catch {} ; $mutex.Dispose() }
    }
}

# ------------------------------------------------------------------
# Helper: run xEdit
function Clean($esp) {
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName               = $CleanerExe
        $psi.Arguments              = "-iknowwhatimdoing -quickautoclean -autoexit -autoload `"$esp`""
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow         = $true
        $psi.WorkingDirectory       = Split-Path $CleanerExe

        Write-Host "[THREAD$ThreadNumber] Starting xEdit for $(Split-Path $esp -Leaf)" -ForegroundColor Gray
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit(300000)   # 5 min timeout
        if (!$p.HasExited) {
            $p.Kill()
            Write-Host "[THREAD$ThreadNumber] TIMEOUT on $(Split-Path $esp -Leaf)" -ForegroundColor Yellow
            AddError (Split-Path $esp -Leaf)
            return $false
        }
        $exitCode = $p.ExitCode
        if ($exitCode -eq 0) {
            return $true
        } else {
            Write-Host "[THREAD$ThreadNumber] FAILED $(Split-Path $esp -Leaf) (exit $exitCode)" -ForegroundColor Red
            AddError (Split-Path $esp -Leaf)
            return $false
        }
    } catch {
        Write-Host "[THREAD$ThreadNumber] ERROR processing $(Split-Path $esp -Leaf): $_" -ForegroundColor Red
        AddError (Split-Path $esp -Leaf)
        return $false
    }
}

# ------------------------------------------------------------------
# MAIN LOOP
Write-Host "[THREAD$ThreadNumber] Beginning task processing..." -ForegroundColor Cyan
Update-Status "WORKING"

while ($true) {
    $task = Get-NextTask
    if ($null -eq $task) { break }

    if ($task -match "^TASK:(\d+):(.+)$") {
        $taskIndex = $matches[1]
        $esp       = $matches[2]

        if ($ProcessedTasks.ContainsKey($taskIndex)) { continue }
        $ProcessedTasks[$taskIndex] = $true

        if (!(Test-Path $esp)) {
            Write-Host "[THREAD$ThreadNumber] MISSING: $esp" -ForegroundColor Yellow
            $failed++
            continue
        }

        $name = Split-Path $esp -Leaf
        Write-Host "[THREAD$ThreadNumber] Processing $name" -ForegroundColor White

        $ok = Clean $esp
        if ($ok) {
            $successful++
        } else {
            $failed++
            Write-Host "[THREAD$ThreadNumber] FAILED: $name" -ForegroundColor Red
        }

        AddLog $name $ok
        $completed++
        Update-Progress $completed
        Start-Sleep -Milliseconds 250
    }
}

Update-Status "FINISHED"
Write-Host "[THREAD$ThreadNumber] FINISHED: $successful ok, $failed failed (total $completed)" -ForegroundColor Green

# quick temp cleanup
Remove-Item "$ScriptDir\Thread$ThreadNumber\*.tmp" -Force -EA SilentlyContinue

exit 0