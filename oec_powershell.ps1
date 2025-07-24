# Script: .\oec_powershell.ps1 - Task Queue Version
# PARAMETERS
param(
    [int]$ThreadCount = 1  # Default to 1 thread if not specified
)

# CONSTANTS
$DaysSkip = 7
$GameTitle = 'Oblivion'
$XEditVariant = 'TES4Edit'
$AutoCleanExe = 'TES4EditQuickAutoClean.exe'
$ScriptDir = $PSScriptRoot
$TempDir = "$ScriptDir\temp"
$BlackFile = "$ScriptDir\oec_blacklist.txt"  # Persistent file stays in root
$ErrorFile = "$ScriptDir\oec_errorlist.txt"  # Persistent file stays in root
$DataPath = "$ScriptDir\..\Data"

# Task Queue Files (now in temp folder)
$TaskQueueFile = "$TempDir\oec_taskqueue.txt"
$StatusFile1 = "$TempDir\oec_status1.txt"
$StatusFile2 = "$TempDir\oec_status2.txt"
$ProgressFile1 = "$TempDir\oec_progress1.txt"
$ProgressFile2 = "$TempDir\oec_progress2.txt"

# Thread scripts
$Thread1Script = "$ScriptDir\oec_thread1.ps1"
$Thread2Script = "$ScriptDir\oec_thread2.ps1"

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
    
    # Initialize status files
    "READY" | Out-File $StatusFile1 -Encoding UTF8
    if ($ThreadCount -eq 2) {
        "READY" | Out-File $StatusFile2 -Encoding UTF8
    }
    
    # Clear progress files
    if (Test-Path $ProgressFile1) { Remove-Item $ProgressFile1 }
    if (Test-Path $ProgressFile2) { Remove-Item $ProgressFile2 }
}

function Get-ThreadStatus($threadNum) {
    $statusFile = if ($threadNum -eq 1) { $StatusFile1 } else { $StatusFile2 }
    if (Test-Path $statusFile) {
        return (Get-Content $statusFile -Raw).Trim()
    }
    return "UNKNOWN"
}

function Wait-ForThreadsToComplete($totalTasks) {
    $completed = 0
    $lastProgress1 = 0
    $lastProgress2 = 0
    $startTime = Get-Date
    $timeoutMinutes = 60  # Timeout after 60 minutes
    
    Write-Host "Monitoring thread progress..." -ForegroundColor Yellow
    
    do {
        Start-Sleep -Seconds 2
        
        # Check for timeout
        $elapsedMinutes = ((Get-Date) - $startTime).TotalMinutes
        if ($elapsedMinutes -gt $timeoutMinutes) {
            Write-Host "Processing timeout reached ($timeoutMinutes minutes). Stopping..." -ForegroundColor Red
            break
        }
        
        # Check thread statuses
        $status1 = Get-ThreadStatus 1
        $status2 = if ($ThreadCount -eq 2) { Get-ThreadStatus 2 } else { "N/A" }
        
        # Read progress files with bounds checking
        $progress1 = 0
        $progress2 = 0
        
        if (Test-Path $ProgressFile1) {
            $prog1Content = Get-Content $ProgressFile1 -ErrorAction SilentlyContinue
            if ($prog1Content -and $prog1Content[-1] -match "COMPLETED:(\d+)") {
                $progress1 = [Math]::Min([int]$matches[1], $totalTasks)  # Cap at total tasks
            }
        }
        
        if ($ThreadCount -eq 2 -and (Test-Path $ProgressFile2)) {
            $prog2Content = Get-Content $ProgressFile2 -ErrorAction SilentlyContinue
            if ($prog2Content -and $prog2Content[-1] -match "COMPLETED:(\d+)") {
                $progress2 = [Math]::Min([int]$matches[1], $totalTasks)  # Cap at total tasks
            }
        }
        
        $totalCompleted = [Math]::Min($progress1 + $progress2, $totalTasks)  # Ensure we don't exceed total
        
        # Display progress if changed
        if ($progress1 -ne $lastProgress1 -or $progress2 -ne $lastProgress2) {
            if ($ThreadCount -eq 2) {
                Write-Host "Thread1 = $progress1, Thread2 = $progress2, Completed/Total = $totalCompleted/$totalTasks" -ForegroundColor Gray
            } else {
                Write-Host "Thread1 = $progress1, Complete/Total = $totalCompleted/$totalTasks" -ForegroundColor Gray
            }
            $lastProgress1 = $progress1
            $lastProgress2 = $progress2
        }
        
        # Check if both threads are done OR if we've completed all tasks
        $thread1Done = ($status1 -eq "FINISHED")
        $thread2Done = ($ThreadCount -eq 1) -or ($status2 -eq "FINISHED")
        $allTasksCompleted = ($totalCompleted -ge $totalTasks)
        
        # Add safety check for hung threads
        if ($allTasksCompleted -and -not ($thread1Done -and $thread2Done)) {
            Write-Host "All tasks completed but threads still running. Waiting for cleanup..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5  # Give threads time to finish cleanup
            # Re-check status after wait
            $status1 = Get-ThreadStatus 1
            $status2 = if ($ThreadCount -eq 2) { Get-ThreadStatus 2 } else { "N/A" }
            $thread1Done = ($status1 -eq "FINISHED")
            $thread2Done = ($ThreadCount -eq 1) -or ($status2 -eq "FINISHED")
        }
        
    } while (-not (($thread1Done -and $thread2Done) -or $allTasksCompleted))
    
    Write-Host "All threads completed!" -ForegroundColor Green
    return $totalCompleted
}

# MAIN
Clear-Host
Write-Separator
Write-Host "    $GameTitle Esp Cleaner" -ForegroundColor Cyan
Write-Separator
Write-Host ""

# Ensure temp directory exists
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
}

# Clean up old files
$filesToClean = @($TaskQueueFile, $StatusFile1, $StatusFile2, $ProgressFile1, $ProgressFile2)
foreach ($file in $filesToClean) {
    if (Test-Path $file) { Remove-Item $file -ErrorAction SilentlyContinue }
}

# Ensure thread directories exist (for executables)
if (-not (Test-Path "$ScriptDir\Thread1")) { New-Item -ItemType Directory -Path "$ScriptDir\Thread1" | Out-Null }
if ($ThreadCount -eq 2 -and -not (Test-Path "$ScriptDir\Thread2")) {
    New-Item -ItemType Directory -Path "$ScriptDir\Thread2" | Out-Null
}

# Verify executables exist
if (-not (Test-Path "$ScriptDir\Thread1\$AutoCleanExe")) {
    Write-Host "ERROR: Thread1 executable not found!" -ForegroundColor Red
    Write-Host "Place '$AutoCleanExe' in: $ScriptDir\Thread1\" -ForegroundColor Yellow
    exit 1
}

if ($ThreadCount -eq 2 -and -not (Test-Path "$ScriptDir\Thread2\$AutoCleanExe")) {
    Write-Host "WARNING: Thread2 executable not found! Falling back to single thread" -ForegroundColor Yellow
    $ThreadCount = 1
}

# Verify thread scripts exist
if (-not (Test-Path $Thread1Script)) {
    Write-Host "ERROR: Thread1 script not found: $Thread1Script" -ForegroundColor Red
    exit 1
}

if ($ThreadCount -eq 2 -and -not (Test-Path $Thread2Script)) {
    Write-Host "ERROR: Thread2 script not found: $Thread2Script" -ForegroundColor Red
    exit 1
}

Write-Host "Using $ThreadCount thread(s) for processing" -ForegroundColor Gray

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
$cut  = (Get-Date).AddDays(-$DaysSkip)
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
    # Start thread jobs
    $job1 = Start-Job -ScriptBlock {
        param($scriptPath, $exe)
        & $scriptPath -AutoCleanExe $exe
    } -ArgumentList $Thread1Script, $AutoCleanExe

    $job2 = $null
    if ($ThreadCount -eq 2) {
        $job2 = Start-Job -ScriptBlock {
            param($scriptPath, $exe)
            & $scriptPath -AutoCleanExe $exe
        } -ArgumentList $Thread2Script, $AutoCleanExe
    }

    # Monitor threads and wait for completion
    $completedTasks = Wait-ForThreadsToComplete $todo.Count

    Write-Host "`nFinal Results:" -ForegroundColor Green
    Write-Host "Tasks completed: $completedTasks/$($todo.Count)" -ForegroundColor Green

    # Display any job output
    $output1 = Receive-Job $job1 -ErrorAction SilentlyContinue
    if ($output1) {
        Write-Host "`nThread 1 Messages:" -ForegroundColor Cyan
        $output1 | ForEach-Object { Write-Host "  $_" }
    }

    if ($job2) {
        $output2 = Receive-Job $job2 -ErrorAction SilentlyContinue
        if ($output2) {
            Write-Host "`nThread 2 Messages:" -ForegroundColor Magenta
            $output2 | ForEach-Object { Write-Host "  $_" }
        }
    }

    # Clean up jobs
    Remove-Job $job1 -Force -ErrorAction SilentlyContinue
    if ($job2) { Remove-Job $job2 -Force -ErrorAction SilentlyContinue }

    Write-Host "`nTask queue processing completed!" -ForegroundColor Green
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