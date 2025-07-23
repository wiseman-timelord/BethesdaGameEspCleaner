# Script: `.\oec_powershell.ps1`
param()  # stub

# CONSTANTS
$GameTitle = 'Oblivion'  
$DaysSkip   = 7
$ScriptDir  = $PSScriptRoot
$BlackFile  = "$ScriptDir\oec_blacklist.txt"
$ErrorFile  = "$ScriptDir\oec_errorlist.txt"
$DataPath   = "$ScriptDir\..\Data"
$CleanerExe = "$ScriptDir\TES4EditQuickAutoClean.exe"

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

function AddLog($file,$ok) {
    "$(Get-Date -f yyyy-MM-dd)`t$file`t$ok" | Add-Content $BlackFile
}

function RunClean($esp) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName  = $CleanerExe
    # Updated arguments for full automation
    $psi.Arguments = "-iknowwhatimdoing -quickautoclean -autoexit -autoload `"$esp`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    
    # Optional: capture output for debugging
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    
    # Log any errors for debugging
    if ($stderr -and $stderr.Trim()) {
        "$(Get-Date -f yyyy-MM-dd HH:mm:ss)`t$esp`tSTDERR: $stderr" | Add-Content $ErrorFile
    }
    
    return $p.ExitCode -eq 0
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

# MAIN
Clear-Host
Write-Separator
Write-Host "    $GameTitle Esp Cleaner" -ForegroundColor Cyan
Write-Separator
Write-Host ''
CleanOld

$esps = Get-ChildItem "$DataPath\*.esp"
if (!$esps) { Write-Host 'No esps found'; Read-Host; exit }

$black = @{}
if (Test-Path $BlackFile) {
    Get-Content $BlackFile | ForEach-Object {
        if ($_ -match '^(\d{4}-\d{2}-\d{2})\t(.+)\t') {
            $black[$matches[2]] = [DateTime]::ParseExact($matches[1],'yyyy-MM-dd',$null)
        }
    }
}

$cut = (Get-Date).AddDays(-$DaysSkip)
$todo = $esps | Where-Object { !$black.ContainsKey($_.Name) -or $black[$_.Name] -lt $cut }

if (!$todo) { Write-Host 'All skipped by blacklist'; Read-Host; exit }

PreventSleep($true)
try {
    $ok = @(); $bad = @()
    foreach ($e in $todo) {
        Write-Host "Cleaning $($e.Name)..." -NoNewline
        if (RunClean $e.FullName) {
            Write-Host " SUCCESS" -ForegroundColor Green
            $ok += $e.Name
            AddLog $e.Name $true
        } else {
            Write-Host " FAILED" -ForegroundColor Red
            $bad += $e.Name
            AddLog $e.Name $false
            "$(Get-Date -f yyyy-MM-dd HH:mm:ss)`t$($e.Name)" | Add-Content $ErrorFile
        }
		Start-Sleep -Seconds 1
    }

    Write-Host "`nResults:" -ForegroundColor Cyan
    Write-Host "Success: $($ok.Count)  Fail: $($bad.Count)" -ForegroundColor Green
    if ($ok) { 
        Write-Host "Successfully cleaned:" -ForegroundColor Green
        $ok | ForEach-Object { Write-Host "  $_" -ForegroundColor Green } 
    }
    if ($bad) { 
        Write-Host "Failed to clean:" -ForegroundColor Red
        $bad | ForEach-Object { Write-Host "  $_" -ForegroundColor Red } 
    }
}
finally {
    PreventSleep($false)
}

Read-Host 'Done'