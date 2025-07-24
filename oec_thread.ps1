# Script: oec_thread.ps1 - Unified Multi-Thread Version
param(
    [int]$ThreadNumber = 1,
    [string]$AutoCleanExe = 'TES4EditQuickAutoClean.exe'
)

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
                    
                    # Handle remaining tasks properly
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

function AddError($file) {
    $mutexName = "Global\OECErrorMutex"
    $mutex = $null
    try {
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        if ($mutex.WaitOne(5000)) {
            "$(Get-Date -f 'yyyy-MM-dd')`t$file" | Add-Content $ErrorFile -Encoding UTF8
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

        Write-Host "[THREAD$ThreadNumber] Starting xEdit process for $(Split-Path $esp -Leaf)" -ForegroundColor Gray

        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit(300000)  # 5 minute timeout

        if (!$p.HasExited) {
            $p.Kill()
            Write-Host "[THREAD$ThreadNumber] Process timeout for $(Split-Path $esp -Leaf)" -ForegroundColor Yellow
            AddError (Split-Path $esp -Leaf)
            return $false
        }

        $exitCode = $p.ExitCode
        $errorOutput = $p.StandardError.ReadToEnd().Trim()
        
        if ($errorOutput) {
            Write-Host "[THREAD$ThreadNumber] xEdit errors for $(Split-Path $esp -Leaf): $errorOutput" -ForegroundColor Yellow
            AddError (Split-Path $esp -Leaf)
        }

        if ($exitCode -eq 0) {
            Write-Host "[THREAD$ThreadNumber] xEdit completed successfully for $(Split-Path $esp -Leaf)" -ForegroundColor Green
        } else {
            Write-Host "[THREAD$ThreadNumber] xEdit failed with exit code $exitCode for $(Split-Path $esp -Leaf)" -ForegroundColor Red
            AddError (Split-Path $esp -Leaf)
        }

        return $exitCode -eq 0
    } catch {
        Write-Host "[THREAD$ThreadNumber] Failed to process $(Split-Path $esp -Leaf): $_" -ForegroundColor Red
        AddError (Split-Path $esp -Leaf)
        return $false
    }
}

# MAIN EXECUTION
Write-Host "[THREAD$ThreadNumber] Thread $ThreadNumber starting task queue processing..." -ForegroundColor Cyan

# Validate parameters
if ($ThreadNumber -lt 1) {
    Write-Host "[THREAD$ThreadNumber] ERROR: Invalid thread number: $ThreadNumber" -ForegroundColor Red
    exit 1
}

# Validate cleaner executable
if (!(Test-Path $CleanerExe)) {
    Write-Host "[THREAD$ThreadNumber] ERROR: Cleaner executable not found: $CleanerExe" -ForegroundColor Red
    Update-Status "ERROR"
    exit 1
}

Write-Host "[THREAD$ThreadNumber] Using executable: $CleanerExe" -ForegroundColor Gray

# Ensure temp directory exists
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
}

# Initialize status
Update-Status "WORKING"
$completed = 0
$successful = 0
$failed = 0

Write-Host "[THREAD$ThreadNumber] Beginning task processing..." -ForegroundColor Cyan

# Process tasks from the queue
while ($true) {
    $task = Get-NextTask
    if ($task -eq $null) {
        # No more tasks available
        Write-Host "[THREAD$ThreadNumber] No more tasks in queue" -ForegroundColor Gray
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
            Write-Host "[THREAD$ThreadNumber] Processing task $taskIndex`: $name" -ForegroundColor White
            
            $ok = Clean $esp
            if ($ok) { 
                $successful++ 
                Write-Host "[THREAD$ThreadNumber] SUCCESS: $name" -ForegroundColor Green
            } else { 
                $failed++
                Write-Host "[THREAD$ThreadNumber] FAILED: $name" -ForegroundColor Red
            }
            
            AddLog $name $ok
        }
        
        $completed++
        Update-Progress $completed
        
        # Brief pause to prevent system overload and allow other threads to work
        Start-Sleep -Milliseconds 250
    } else {
        Write-Host "[THREAD$ThreadNumber] Invalid task format: $task" -ForegroundColor Yellow
    }
}

Update-Status "FINISHED"
Write-Host "[THREAD$ThreadNumber] Thread $ThreadNumber completed: $successful successful, $failed failed (total: $completed)" -ForegroundColor Green

# Final cleanup for this thread
if (Test-Path "$ScriptDir\Thread$ThreadNumber\*.tmp") {
    Remove-Item "$ScriptDir\Thread$ThreadNumber\*.tmp" -Force -ErrorAction SilentlyContinue
}

exit 0