# Script: oec_thread2.ps1 - Task Queue Version
param(
    [string]$AutoCleanExe = 'TES4EditQuickAutoClean.exe'
)

$ThreadNumber = 2
$ScriptDir = $PSScriptRoot
$CleanerExe = "$ScriptDir\Thread$ThreadNumber\$AutoCleanExe"
$BlackFile = "$ScriptDir\oec_blacklist.txt"
$ErrorFile = "$ScriptDir\oec_errorlist.txt"

# Task Queue Files
$TaskQueueFile = "$ScriptDir\oec_taskqueue.txt"
$StatusFile = "$ScriptDir\Thread$ThreadNumber\oec_status$ThreadNumber.txt"
$ProgressFile = "$ScriptDir\Thread$ThreadNumber\oec_progress$ThreadNumber.txt"

function Update-Status($status) {
    $status | Out-File $StatusFile -Encoding UTF8
}

function Update-Progress($completed) {
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
                    $remainingTasks = $tasks[1..($tasks.Count-1)]
                    
                    if ($remainingTasks.Count -gt 0) {
                        $remainingTasks | Out-File $TaskQueueFile -Encoding UTF8
                    } else {
                        # No more tasks, remove the file
                        Remove-Item $TaskQueueFile -ErrorAction SilentlyContinue
                    }
                    
                    return $nextTask
                }
            }
            return $null
        } else {
            Write-Host "[THREAD2] WARNING: Failed to acquire task queue mutex" -ForegroundColor Yellow
            return $null
        }
    } catch {
        Write-Host "[THREAD2] Task queue mutex error: $_" -ForegroundColor Red
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
            Write-Host "[THREAD2] WARNING: Failed to acquire blacklist mutex" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[THREAD2] Blacklist mutex error: $_" -ForegroundColor Red
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
            Write-Host "[THREAD2] Process timeout for $esp" -ForegroundColor Yellow
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
                Write-Host "[THREAD2] Error mutex failed: $_" -ForegroundColor Yellow
            } finally {
                if ($mutex) {
                    try { $mutex.ReleaseMutex() } catch {}
                    $mutex.Dispose()
                }
            }
        }
        return $p.ExitCode -eq 0
    } catch {
        Write-Host "[THREAD2] Failed to process $esp`: $_" -ForegroundColor Red
        return $false
    }
}

# Main execution starts here
Write-Host "[THREAD2] Thread 2 starting task queue processing..." -ForegroundColor Magenta

# Validate cleaner executable
if (!(Test-Path $CleanerExe)) {
    Write-Host "[THREAD2] ERROR: Cleaner executable not found: $CleanerExe" -ForegroundColor Red
    Update-Status "ERROR"
    exit 1
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
        
        if (!(Test-Path $esp)) {
            Write-Host "[THREAD2] File not found: $esp" -ForegroundColor Yellow
            $failed++
        } else {
            $name = Split-Path $esp -Leaf
            Write-Host "[THREAD2] Processing task $taskIndex`: $name" -ForegroundColor Gray
            
            $ok = Clean $esp
            if ($ok) { 
                $successful++ 
                Write-Host "[THREAD2] Success: $name" -ForegroundColor Green
            } else { 
                $failed++
                Write-Host "[THREAD2] Failed: $name" -ForegroundColor Red
            }
            
            AddLog $name $ok
        }
        
        $completed++
        Update-Progress $completed
        
        # Brief pause to prevent system overload
        Start-Sleep -Milliseconds 100
    } else {
        Write-Host "[THREAD2] Invalid task format: $task" -ForegroundColor Yellow
    }
}

Update-Status "FINISHED"
Write-Host "[THREAD2] Thread 2 completed: $successful successful, $failed failed (total: $completed)" -ForegroundColor Magenta
exit 0