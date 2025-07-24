# Updated oec_powershell.ps1 - Multi-Thread Task Queue Version
param(
    [int]$ThreadCount = 2  # Default to 2 threads, can be overridden
)

# CONSTANTS
$DaysSkip = 7
$GameTitle = 'Oblivion'
$XEditVariant = 'TES4Edit'
$AutoCleanExe = 'TES4EditQuickAutoClean.exe'
$ScriptDir = $PSScriptRoot
$TempDir = "$ScriptDir\temp"
$BlackFile = "$ScriptDir\oec_blacklist.txt"
$ErrorFile = "$ScriptDir\oec_errorlist.txt"
$DataPath = "$ScriptDir\..\Data"

# Task Queue Files (now in temp folder)
$TaskQueueFile = "$TempDir\oec_taskqueue.txt"
$ThreadScript = "$ScriptDir\oec_thread.ps1"  # Single thread script

# FUNCTIONS
function Write-Separator {
    Write-Host ('=' * 79)
}

function CleanOld {
    if (!(Test-Path $BlackFile)) { return }
    $cut = (Get-Date).AddDays(-$DaysSkip).ToString('yyyy-MM-dd')
    (Get-Content $BlackFile) |
        Where-Object { $_ -match '^(\d{4}-\d{2}-\d{2})' -and $matches[1] -ge $cut } |
        Set-Content $BlackFile
}

function PreventSleep($on) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Pwr {
    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    public static extern void SetThreadExecutionState(uint esFlags);
    public const uint ES_CONTINUOUS = 0x80000000;
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
    public const uint ES_AWAYMODE_REQUIRED = 0x00000040;
    public static void StayAwake(bool on) {
        if (on)
            SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
        else
            SetThreadExecutionState(ES_CONTINUOUS);
    }
}
"@
    [Pwr]::StayAwake($on)
}

function Initialize-TaskQueue($espList) {
    # Ensure temp directory exists
    if (-not (Test-Path $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir | Out-Null
    }

    # Create task queue with all ESPs
    $taskQueue = @()
    for ($i = 0; $i -lt $espList.Count; $i++) {
        $taskQueue += "TASK:${i}:$($espList[$i])"
    }
    $taskQueue | Out-File $TaskQueueFile -Encoding UTF8
    
    # Clear any existing status/progress files for all possible threads (cleanup)
    for ($i = 1; $i -le 16; $i++) {  # Clean up to 16 possible thread files
        $statusFile = "$TempDir\oec_status$i.txt"
        $progressFile = "$TempDir\oec_progress$i.txt"
        if (Test-Path $statusFile) { Remove-Item $statusFile }
        if (Test-Path $progressFile) { Remove-Item $progressFile }
    }
}

function Get-ThreadStatus($threadNum) {
    $statusFile = "$TempDir\oec_status$threadNum.txt"
    if (Test-Path $statusFile) {
        return (Get-Content $statusFile -Raw).Trim()
    }
    return "UNKNOWN"
}

function Get-ThreadProgress($threadNum) {
    $progressFile = "$TempDir\oec_progress$threadNum.txt"
    if (Test-Path $progressFile) {
        $content = Get-Content $progressFile -ErrorAction SilentlyContinue
        if ($content -and $content[-1] -match "COMPLETED:(\d+)") {
            return [int]$matches[1]
        }
    }
    return 0
}

function Wait-ForThreadsToComplete($totalTasks) {
    $lastProgressArray = @(0) * ($ThreadCount + 1)  # Index 0 unused, 1-N for threads
    $startTime = Get-Date
    $timeoutMinutes = 60
    
    Write-Host "Monitoring $ThreadCount thread(s) progress..." -ForegroundColor Yellow
    
    do {
        Start-Sleep -Seconds 2
        
        # Check for timeout
        $elapsedMinutes = ((Get-Date) - $startTime).TotalMinutes
        if ($elapsedMinutes -gt $timeoutMinutes) {
            Write-Host "Processing timeout reached ($timeoutMinutes minutes). Stopping..." -ForegroundColor Red
            break
        }
        
        # Check all thread statuses and progress
        $allFinished = $true
        $totalCompleted = 0
        $progressChanged = $false
        
        for ($i = 1; $i -le $ThreadCount; $i++) {
            $status = Get-ThreadStatus $i
            $progress = Get-ThreadProgress $i
            
            # Cap progress at total tasks
            $progress = [Math]::Min($progress, $totalTasks)
            $totalCompleted += $progress
            
            if ($progress -ne $lastProgressArray[$i]) {
                $progressChanged = $true
                $lastProgressArray[$i] = $progress
            }
            
            if ($status -ne "FINISHED") {
                $allFinished = $false
            }
        }
        
        # Cap total completed
        $totalCompleted = [Math]::Min($totalCompleted, $totalTasks)
        
        # Display progress if changed
        if ($progressChanged) {
            $progressDisplay = @()
            for ($i = 1; $i -le $ThreadCount; $i++) {
                $progressDisplay += "T$i=$($lastProgressArray[$i])"
            }
            $progressStr = $progressDisplay -join ", "
            Write-Host "$progressStr, Total=$totalCompleted/$totalTasks" -ForegroundColor Gray
        }
        
        # Check completion conditions
        $allTasksCompleted = ($totalCompleted -ge $totalTasks)
        
        if ($allTasksCompleted -and -not $allFinished) {
            Write-Host "All tasks completed but threads still running. Waiting for cleanup..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            # Re-check statuses
            $allFinished = $true
            for ($i = 1; $i -le $ThreadCount; $i++) {
                if ((Get-ThreadStatus $i) -ne "FINISHED") {
                    $allFinished = $false
                    break
                }
            }
        }
        
    } while (-not ($allFinished -or $allTasksCompleted))
    
    Write-Host "All threads completed!" -ForegroundColor Green
    return $totalCompleted
}

function Validate-ThreadSetup {
    $missingThreads = @()
    $validThreads = 0
    
    for ($i = 1; $i -le $ThreadCount; $i++) {
        $threadDir = "$ScriptDir\Thread$i"
        $threadExe = "$threadDir\$AutoCleanExe"
        
        if (-not (Test-Path $threadDir)) {
            try {
                New-Item -ItemType Directory -Path $threadDir | Out-Null
                Write-Host "[INFO] Created Thread$i directory" -ForegroundColor Cyan
            } catch {
                Write-Host "[ERROR] Failed to create Thread$i directory" -ForegroundColor Red
                $missingThreads += $i
                continue
            }
        }
        
        if (-not (Test-Path $threadExe)) {
            $missingThreads += $i
        } else {
            $validThreads++
        }
    }
    
    if ($missingThreads.Count -gt 0) {
        Write-Host "[WARNING] Missing executables in Thread folders: $($missingThreads -join ', ')" -ForegroundColor Yellow
        Write-Host "[INFO] Place '$AutoCleanExe' in the following directories:" -ForegroundColor Yellow
        foreach ($thread in $missingThreads) {
            Write-Host "  $ScriptDir\Thread$thread\" -ForegroundColor Yellow
        }
        
        if ($validThreads -eq 0) {
            Write-Host "[ERROR] No valid thread executables found!" -ForegroundColor Red
            return $false
        } else {
            Write-Host "[INFO] Continuing with $validThreads available thread(s)" -ForegroundColor Cyan
            # Adjust thread count to available threads
            $script:ThreadCount = $validThreads
            return $true
        }
    }
    
    Write-Host "[OK] All $ThreadCount thread directories validated" -ForegroundColor Green
    return $true
}

# MAIN
Clear-Host
Write-Separator
Write-Host "    $GameTitle Esp Cleaner (Multi-Thread)" -ForegroundColor Cyan
Write-Separator
Write-Host ""

# Validate thread count
if ($ThreadCount -lt 1) {
    Write-Host "[ERROR] Thread count must be at least 1" -ForegroundColor Red
    exit 1
}

if ($ThreadCount -gt 16) {
    Write-Host "[WARNING] Thread count limited to 16 maximum" -ForegroundColor Yellow
    $ThreadCount = 16
}

Write-Host "[INFO] Configured for $ThreadCount thread(s)" -ForegroundColor Cyan

# Ensure temp directory exists
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
}

# Clean up old task queue files
$filesToClean = @($TaskQueueFile)
for ($i = 1; $i -le 16; $i++) {
    $filesToClean += "$TempDir\oec_status$i.txt"
    $filesToClean += "$TempDir\oec_progress$i.txt"
}

foreach ($file in $filesToClean) {
    if (Test-Path $file) { Remove-Item $file -ErrorAction SilentlyContinue }
}

# Validate thread setup
if (-not (Validate-ThreadSetup)) {
    exit 1
}

# Verify thread script exists
if (-not (Test-Path $ThreadScript)) {
    Write-Host "[ERROR] Thread script not found: $ThreadScript" -ForegroundColor Red
    exit 1
}

# Clean old blacklist entries
CleanOld
Write-Host "[OK] Blacklist maintenance complete" -ForegroundColor Green

# Scan for ESPs
$esps = Get-ChildItem "$DataPath\*.esp"
if (!$esps) {
    Write-Host '[ERROR] No ESPs found in Data folder' -ForegroundColor Red
    exit 0
}
Write-Host "[OK] Found $($esps.Count) ESP files" -ForegroundColor Green

# Load blacklist
$black = @{}
if (Test-Path $BlackFile) {
    Get-Content $BlackFile | ForEach-Object {
        if ($_ -match '^(\d{4}-\d{2}-\d{2})\t(.+)\t') {
            $black[$matches[2]] = [DateTime]::ParseExact($matches[1], 'yyyy-MM-dd', $null)
        }
    }
    Write-Host "[OK] Loaded $($black.Count) blacklist entries" -ForegroundColor Green
} else {
    Write-Host "[OK] No existing blacklist found" -ForegroundColor Green
}

# Filter ESPs to process
$cut = (Get-Date).AddDays(-$DaysSkip)
$todo = $esps | Where-Object { !$black.ContainsKey($_.Name) -or $black[$_.Name] -lt $cut }

if (!$todo) {
    Write-Host '[INFO] All ESPs skipped by blacklist' -ForegroundColor Cyan
    exit 0
}

$skipped = $esps.Count - $todo.Count
Write-Host "[OK] Processing $($todo.Count) ESPs (skipped $skipped)" -ForegroundColor Green

# Initialize task queue system
Initialize-TaskQueue $todo.FullName
Write-Host "[OK] Task queue initialized with $($todo.Count) tasks" -ForegroundColor Green

Write-Host ""
Write-Host "Starting task queue processing with $ThreadCount thread(s)..." -ForegroundColor Yellow

PreventSleep($true)
try {
    # Start all thread jobs
    $jobs = @()
    for ($i = 1; $i -le $ThreadCount; $i++) {
        $job = Start-Job -ScriptBlock {
            param($scriptPath, $threadNum, $autoCleanExe)
            & $scriptPath -ThreadNumber $threadNum -AutoCleanExe $autoCleanExe
        } -ArgumentList $ThreadScript, $i, $AutoCleanExe
        
        $jobs += @{
            Job = $job
            ThreadNumber = $i
        }
        
        Write-Host "[INFO] Started Thread $i (Job ID: $($job.Id))" -ForegroundColor Gray
    }

    # Monitor threads and wait for completion
    $completedTasks = Wait-ForThreadsToComplete $todo.Count

    Write-Host "`nFinal Results:" -ForegroundColor Green
    Write-Host "Tasks completed: $completedTasks/$($todo.Count)" -ForegroundColor Green

    # Display job outputs
    foreach ($jobInfo in $jobs) {
        $output = Receive-Job $jobInfo.Job -ErrorAction SilentlyContinue
        if ($output) {
            Write-Host "`nThread $($jobInfo.ThreadNumber) Messages:" -ForegroundColor Cyan
            $output | ForEach-Object { Write-Host "  $_" }
        }
    }

    # Clean up jobs
    foreach ($jobInfo in $jobs) {
        Remove-Job $jobInfo.Job -Force -ErrorAction SilentlyContinue
    }

    Write-Host "`nMulti-thread task queue processing completed!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Processing failed: $_" -ForegroundColor Red
    exit 1
} finally {
    PreventSleep($false)
    
    # Clean up task queue files
    $filesToClean | ForEach-Object {
        if (Test-Path $_) { Remove-Item $_ -ErrorAction SilentlyContinue }
    }
}

exit 0