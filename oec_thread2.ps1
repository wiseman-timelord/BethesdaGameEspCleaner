# Script: oec_thread2.ps1 - Task Queue Version
param(
    [string]$AutoCleanExe = 'TES4EditQuickAutoClean.exe'
)

$ThreadNumber = 2
$ScriptDir = $PSScriptRoot
$TempDir = "$ScriptDir\temp"
$CleanerExe = "$ScriptDir\Thread$ThreadNumber\$AutoCleanExe"
$BlackFile = "$ScriptDir\oec_blacklist.txt"  # Persistent file stays in root
$ErrorFile = "$ScriptDir\oec_errorlist.txt"  # Persistent file stays in root

# Task Queue Files (now in temp folder)
$TaskQueueFile = "$TempDir\oec_taskqueue.txt"
$StatusFile = "$TempDir\oec_status$ThreadNumber.txt"
$ProgressFile = "$TempDir\oec_progress$ThreadNumber.txt"

# Track processed tasks to prevent duplicates
$ProcessedTasks = @{}

function Update-Status($status) {
    # Ensure temp directory exists
    if (-not (Test-Path $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir | Out-Null
    }
    $status | Out-File $StatusFile -Encoding UTF8
}

function Update-Progress($completed) {
    # Ensure temp directory exists
    if (-not (Test-Path $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir | Out-Null
    }
    "COMPLETED:$completed" | Add-Content $ProgressFile -Encoding UTF8
}

function Get-NextTask() {
    $mutexName = "Global\OECTaskQueueMutex"
    $mutex = $null
    try {
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        if ($mutex.WaitOne(10000)) {
            if (Test-Path $TaskQueueFile) {
                $tasks = @(Get-Content $TaskQueueFile -Encoding UTF8 | Where-Object { $_.Trim() -ne "" })
                if ($tasks.Count -gt 0) {
                    $nextTask = $tasks[0]
                    
                    # Fix: Handle remaining tasks properly
                    if ($tasks.Count -gt 1) {
                        $remainingTasks = $tasks[1..($tasks.Count-1)]
                        $remainingTasks | Out-File $TaskQueueFile -Encoding UTF8
                    } else {
                        # No more tasks, remove the file
                        Remove-Item $TaskQueueFile -ErrorAction SilentlyContinue
                    }
                    
                    return $nextTask
                } else {
                    # Empty file, remove it
                    Remove-Item $TaskQueueFile -ErrorAction SilentlyContinue
                    return $null
                }
            }
            return $null
        } else {
            Write-Host "[THREAD$ThreadNumber] WARNING: Failed to acquire task queue mutex" -ForegroundColor Yellow
            return $null
        }
    } catch {
        Write-Host "[THREAD$ThreadNumber] Task queue mutex error: $_" -ForegroundColor Red
        return $null
    } finally {
        if ($mutex) {
            try { $mutex.ReleaseMutex() } catch {}
            $mutex.Dispose()
        }
    }
}

function AddLog($file, $ok) {
    $mutexName = "Global\OECBlacklistMutex"
    $mutex = $null
    try {
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        if ($mutex.WaitOne(10000)) {
            "$(Get-Date -f 'yyyy-MM-dd')`t$file`t$ok" | Add-Content $BlackFile -Encoding UTF8
        } else {
            Write-Host "[THREAD$ThreadNumber] WARNING: Failed to acquire blacklist mutex" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[THREAD$ThreadNumber] Blacklist mutex error: $_" -ForegroundColor Red
    } finally {
        if ($mutex) {
            try { $mutex.ReleaseMutex() } catch {}
            $mutex.Dispose()
        }
    }
}

function Clean($esp) {
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $CleanerExe
        $psi.Arguments = "-iknowwhatimdoing -quickautoclean -autoexit -autoload `"$esp`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = Split-Path $CleanerExe

        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit(300000)  # 5 minute timeout

        if (!$p.HasExited) {
            $p.Kill()
            Write-Host "[THREAD$ThreadNumber] Process timeout for $esp" -ForegroundColor Yellow
            return $false
        }

        $errorOutput = $p.StandardError.ReadToEnd().Trim()
        if ($errorOutput) {
            $mutexName = "Global\OECErrorMutex"
            $mutex = $null
            try {
                $mutex = [System.Threading.Mutex]::new($false, $mutexName)
                if ($mutex.WaitOne(5000)) {
                    "$(Get-Date -f 'yyyy-MM-dd')`t$(Split-Path $esp -Leaf)" | Add-Content $ErrorFile -Encoding UTF8
                }
            } catch {
                Write-Host "[THREAD$ThreadNumber] Error mutex failed: $_" -ForegroundColor Yellow
            } finally {
                if ($mutex) {
                    try { $mutex.ReleaseMutex() } catch {}
                    $mutex.Dispose()
                }
            }
        }
        return $p.ExitCode -eq 0
    } catch {
        Write-Host "[THREAD$ThreadNumber] Failed to process $esp`: $_" -ForegroundColor Red
        return $false
    }
}

# Main execution starts here
Write-Host "[THREAD$ThreadNumber] Thread $ThreadNumber starting task queue processing..." -ForegroundColor Magenta
Write-Host "[THREAD$ThreadNumber] Script Dir: $ScriptDir" -ForegroundColor Gray
Write-Host "[THREAD$ThreadNumber] Cleaner Exe: $CleanerExe" -ForegroundColor Gray
Write-Host "[THREAD$ThreadNumber] Task Queue File: $TaskQueueFile" -ForegroundColor Gray

# Validate cleaner executable
if (!(Test-Path $CleanerExe)) {
    Write-Host "[THREAD$ThreadNumber] ERROR: Cleaner executable not found: $CleanerExe" -ForegroundColor Red
    Update-Status "ERROR"
    exit 1
}

# Ensure temp directory exists
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
}

Update-Status "WORKING"
$completed = 0
$successful = 0
$failed = 0

# Process tasks from the queue
while ($true) {
    $task = Get-NextTask
    if ($task -eq $null) {
        # No more tasks available
        break
    }
    
    # Parse task: "TASK:index:filepath"
    if ($task -match "^TASK:(\d+):(.+)$") {
        $taskIndex = $matches[1]
        $esp = $matches[2]
        
        # Check if we've already processed this task (duplicate protection)
        if ($ProcessedTasks.ContainsKey($taskIndex)) {
            Write-Host "[THREAD$ThreadNumber] Skipping duplicate task $taskIndex" -ForegroundColor Yellow
            continue
        }
        $ProcessedTasks[$taskIndex] = $true
        
        if (!(Test-Path $esp)) {
            Write-Host "[THREAD$ThreadNumber] File not found: $esp" -ForegroundColor Yellow
            $failed++
        } else {
            $name = Split-Path $esp -Leaf
            Write-Host "[THREAD$ThreadNumber] Processing task $taskIndex`: $name" -ForegroundColor Gray
            
            $ok = Clean $esp
            if ($ok) { 
                $successful++ 
                Write-Host "[THREAD$ThreadNumber] Success: $name" -ForegroundColor Green
            } else { 
                $failed++
                Write-Host "[THREAD$ThreadNumber] Failed: $name" -ForegroundColor Red
            }
            
            AddLog $name $ok
        }
        
        $completed++
        Update-Progress $completed
        
        # Brief pause to prevent system overload
        Start-Sleep -Milliseconds 100
    } else {
        Write-Host "[THREAD$ThreadNumber] Invalid task format: $task" -ForegroundColor Yellow
    }
}

Update-Status "FINISHED"
Write-Host "[THREAD$ThreadNumber] Thread $ThreadNumber completed: $successful successful, $failed failed (total: $completed)" -ForegroundColor Magenta
exit 0