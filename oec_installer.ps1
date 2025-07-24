#Requires -Version 5.1
<#
.SYNOPSIS
    Oblivion Esp Cleaner configuration installer
.DESCRIPTION
    Detects existing threads, downloads/extracts TES4Edit,
    copies AutoCleaner to thread folders, creates settings
.NOTES
    Run from OblivionEspCleaner.bat folder
#>

param()

$ErrorActionPreference = 'Stop'
$host.UI.RawUI.WindowTitle = 'Oblivion Esp Cleaner – Configuration'

# Constants
$AutoCleanExe  = 'TES4EditQuickAutoClean.exe'
$SettingsFile  = 'oec_settings.psd1'
$MinThreads    = 1
$MaxThreads    = 4
$ScriptDir     = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$TempDir       = Join-Path $ScriptDir 'temp'
$DownloadDir   = Join-Path $TempDir 'downloads'
$SevenZipDir   = Join-Path $TempDir '7za'
$ExtractDir    = Join-Path $TempDir 'TES4Edit'
$SevenZipUrl   = 'https://7-zip.org/a/7za920.zip'
$SevenZipExe   = Join-Path $SevenZipDir '7za.exe'

# Global variables
$Global:CurrentThreadCount = 0
$Global:AutoCleanerPath = $null

# Functions
function Write-Banner {
    Clear-Host
    '=' * 60
    '    Oblivion Esp Cleaner – Configuration / Installation'
    '=' * 60
    ''
}

function Get-CurrentThreadCount {
    $count = 0
    1..$MaxThreads | ForEach-Object {
        $tDir = Join-Path $ScriptDir "Thread$_"
        if (Test-Path $tDir) {
            $autoCleanPath = Join-Path $tDir $AutoCleanExe
            if (Test-Path $autoCleanPath) {
                $count = $_
                if ($_ -eq 1) {
                    $Global:AutoCleanerPath = $autoCleanPath
                }
            }
        }
    }
    $Global:CurrentThreadCount = $count
    return $count
}

function Find-TES4EditArchive {
    $archives = Get-ChildItem -LiteralPath $ScriptDir -File | Where-Object { $_.Name -like 'TES4Edit*.7z' }
    if ($archives.Count -eq 0) {
        return $null
    } elseif ($archives.Count -eq 1) {
        return $archives[0].FullName
    } else {
        Write-Host "Multiple TES4Edit archives found:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $archives.Count; $i++) {
            Write-Host "  $i) $($archives[$i].Name)" -ForegroundColor Yellow
        }
        do {
            $sel = Read-Host "Select archive (0-$(($archives.Count) - 1))"
            $idx = [int]::TryParse($sel, [ref]$null) ? [int]$sel : -1
        } while ($idx -lt 0 -or $idx -ge $archives.Count)
        return $archives[$idx].FullName
    }
}

function Download-FileWithRetry {
    param(
        [string]$Url,
        [string]$OutputPath,
        [int]$MaxRetries = 5
    )
    
    $attempt = 1
    while ($attempt -le $MaxRetries) {
        try {
            Write-Host "[INFO] Download attempt $attempt of $MaxRetries..." -ForegroundColor Cyan
            
            # Ensure directory exists
            $dir = Split-Path $OutputPath -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            
            # Use WebClient for retries
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add('User-Agent', 'OblivionEspCleaner/1.0')
            $webClient.DownloadFile($Url, $OutputPath)
            $webClient.Dispose()
            
            Write-Host "[OK] Download completed successfully" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "[WARNING] Download attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
            if ($attempt -eq $MaxRetries) {
                Write-Host "[ERROR] All download attempts failed" -ForegroundColor Red
                return $false
            }
            Start-Sleep -Seconds (2 * $attempt)  # Progressive delay
            $attempt++
        }
    }
    return $false
}

function Initialize-SevenZip {
    if (Test-Path $SevenZipExe) {
        Write-Host "[INFO] 7za.exe already available" -ForegroundColor Cyan
        return $true
    }
    
    Write-Host "[INFO] Downloading 7-Zip standalone..." -ForegroundColor Cyan
    $zipPath = Join-Path $DownloadDir '7za920.zip'
    
    if (-not (Download-FileWithRetry -Url $SevenZipUrl -OutputPath $zipPath)) {
        return $false
    }
    
    try {
        Write-Host "[INFO] Extracting 7-Zip..." -ForegroundColor Cyan
        if (-not (Test-Path $SevenZipDir)) {
            New-Item -ItemType Directory -Path $SevenZipDir -Force | Out-Null
        }
        
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $SevenZipDir)
        
        if (Test-Path $SevenZipExe) {
            Write-Host "[OK] 7za.exe ready" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[ERROR] 7za.exe not found after extraction" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "[ERROR] Failed to extract 7-Zip: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Extract-TES4EditArchive {
    param([string]$ArchivePath)
    
    if (-not (Initialize-SevenZip)) {
        return $null
    }
    
    try {
        Write-Host "[INFO] Extracting TES4Edit archive..." -ForegroundColor Cyan
        
        if (Test-Path $ExtractDir) {
            Remove-Item -Path $ExtractDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
        
        Write-Host "[INFO] Starting extraction process..." -ForegroundColor Cyan
        Write-Host "[INFO] Archive: $(Split-Path $ArchivePath -Leaf)" -ForegroundColor Gray
        Write-Host "[INFO] Extract to: $ExtractDir" -ForegroundColor Gray
        
        # Format output directory correctly
        $outputArg = "-o$ExtractDir"
        
        Write-Host "[INFO] Command: $SevenZipExe x `"$ArchivePath`" $outputArg -y" -ForegroundColor Gray
        
        # Use correct argument format
        $process = Start-Process -FilePath $SevenZipExe -ArgumentList "x", "`"$ArchivePath`"", $outputArg, "-y" -Wait -PassThru -WindowStyle Hidden
        
        # Check exit code
        if ($process.ExitCode -ne 0) {
            Write-Host "[ERROR] 7za extraction failed (Exit Code: $($process.ExitCode))" -ForegroundColor Red
            
            # Provide specific error info
            switch ($process.ExitCode) {
                1 { Write-Host "[ERROR] Warning (Non fatal error(s))" -ForegroundColor Yellow }
                2 { Write-Host "[ERROR] Fatal error" -ForegroundColor Red }
                7 { Write-Host "[ERROR] Command line error - check file paths and syntax" -ForegroundColor Red }
                8 { Write-Host "[ERROR] Not enough memory for operation" -ForegroundColor Red }
                255 { Write-Host "[ERROR] User stopped the process" -ForegroundColor Red }
                default { Write-Host "[ERROR] Unknown error code: $($process.ExitCode)" -ForegroundColor Red }
            }
            
            # Debug info
            Write-Host "[DEBUG] Archive exists: $(Test-Path $ArchivePath)" -ForegroundColor Gray
            Write-Host "[DEBUG] Archive size: $((Get-Item $ArchivePath).Length) bytes" -ForegroundColor Gray
            Write-Host "[DEBUG] 7za.exe exists: $(Test-Path $SevenZipExe)" -ForegroundColor Gray
            Write-Host "[DEBUG] Extract dir exists: $(Test-Path $ExtractDir)" -ForegroundColor Gray
            Write-Host "[DEBUG] Extract dir writable: $(Test-Path $ExtractDir -PathType Container)" -ForegroundColor Gray
            
            return $null
        }
        
        Write-Host "[OK] Archive extraction completed" -ForegroundColor Green
        
        # Wait for file system sync
        Start-Sleep -Milliseconds 500
        
        # Verify extraction worked
        $extractedItems = Get-ChildItem -Path $ExtractDir -Recurse -ErrorAction SilentlyContinue
        if ($extractedItems.Count -eq 0) {
            Write-Host "[ERROR] No files found after extraction" -ForegroundColor Red
            return $null
        }
        
        Write-Host "[INFO] Extracted $($extractedItems.Count) items" -ForegroundColor Cyan
        Write-Host "[INFO] Searching for $AutoCleanExe..." -ForegroundColor Cyan
        
        # Find AutoCleaner in extracted folder
        $autoCleanFiles = Get-ChildItem -Path $ExtractDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $AutoCleanExe }
        
        if ($autoCleanFiles.Count -eq 0) {
            Write-Host "[ERROR] $AutoCleanExe not found in extracted archive" -ForegroundColor Red
            Write-Host "[INFO] Available .exe files:" -ForegroundColor Yellow
            Get-ChildItem -Path $ExtractDir -Recurse -File -Filter "*.exe" | ForEach-Object {
                Write-Host "  $($_.Name) - $($_.DirectoryName)" -ForegroundColor Gray
            }
            Write-Host "[INFO] All files:" -ForegroundColor Yellow
            Get-ChildItem -Path $ExtractDir -Recurse -File | Select-Object -First 15 | ForEach-Object {
                Write-Host "  $($_.Name)" -ForegroundColor Gray
            }
            return $null
        }
        
        $foundPath = $autoCleanFiles[0].FullName
        Write-Host "[OK] Found $AutoCleanExe" -ForegroundColor Green
        Write-Host "[INFO] Full path: $foundPath" -ForegroundColor Cyan
        return $foundPath
        
    }
    catch {
        Write-Host "[ERROR] Failed to extract archive: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[ERROR] Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        return $null
    }
}

function Setup-AutoCleaner {
    # Check for existing threads
    $currentThreads = Get-CurrentThreadCount
    
    if ($currentThreads -gt 0) {
        Write-Host "[INFO] Existing installation detected ($currentThreads thread(s))" -ForegroundColor Cyan
        Write-Host "[INFO] Using existing AutoCleaner from Thread1" -ForegroundColor Cyan
        return $Global:AutoCleanerPath
    }
    
    # Look for TES4Edit archive
    Write-Host "[INFO] First-time setup - searching for TES4Edit archive..." -ForegroundColor Cyan
    $archivePath = Find-TES4EditArchive
    
    if (-not $archivePath) {
        Write-Host "`n[ERROR] No TES4Edit*.7z file found in script directory" -ForegroundColor Red
        Write-Host "Please download TES4Edit from:" -ForegroundColor Yellow
        Write-Host "https://www.nexusmods.com/oblivion/mods/11536" -ForegroundColor Yellow
        Write-Host "`nSave the TES4Edit*.7z file to: $ScriptDir" -ForegroundColor Yellow
        Write-Host "`nThen re-run this configuration script." -ForegroundColor Yellow
        Write-Host "`nPress Enter to return to main menu..." -ForegroundColor Gray
        $null = Read-Host
        return $null
    }
    
    Write-Host "[OK] Found archive: $(Split-Path $archivePath -Leaf)" -ForegroundColor Green
    
    # Extract and find AutoCleaner
    $extractedPath = Extract-TES4EditArchive -ArchivePath $archivePath
    if (-not $extractedPath) {
        return $null
    }
    
    # Create Thread1 and copy executable
    $thread1Dir = Join-Path $ScriptDir 'Thread1'
    $thread1AutoCleaner = Join-Path $thread1Dir $AutoCleanExe
    
    try {
        if (-not (Test-Path $thread1Dir)) {
            New-Item -ItemType Directory -Path $thread1Dir -Force | Out-Null
        }
        
        Copy-Item -Path $extractedPath -Destination $thread1AutoCleaner -Force
        Write-Host "[OK] Created Thread1 with AutoCleaner" -ForegroundColor Green
        
        $Global:AutoCleanerPath = $thread1AutoCleaner
        $Global:CurrentThreadCount = 1
        return $thread1AutoCleaner
        
    }
    catch {
        Write-Host "[ERROR] Failed to setup Thread1: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-ThreadSelection {
    Write-Host "`nHow many threads to use? (Lower=Stable)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1 = Similar speed to P.A.C.T." -ForegroundColor White
    Write-Host "2 = Whoo that was faster." -ForegroundColor Yellow
    Write-Host "3 = Impressively super fast." -ForegroundColor Yellow
    Write-Host "4 = I cant believe it works." -ForegroundColor Red
    Write-Host "5 = There is no 5, try 4." -ForegroundColor Red
	Write-Host ""
    Write-Host "Warning: do not watch processing phase if you suffer from Epilepsy."
    Write-Host ""
    
    do {
        $selection = Read-Host "Selection; Options 1-4"
        $threads = [int]::TryParse($selection, [ref]$null) ? [int]$selection : 0
    } while ($threads -lt 1 -or $threads -gt 4)
    
    return $threads
}

function Configure-ThreadDirectories {
    param([int]$TargetThreads, [string]$SourceAutoCleanerPath)
    
    if (-not (Test-Path $SourceAutoCleanerPath)) {
        Write-Host "[ERROR] Source AutoCleaner not found: $SourceAutoCleanerPath" -ForegroundColor Red
        return $false
    }
    
    $success = 0
    
    # FIRST: Remove extra thread directories BEFORE creating new ones
    # This prevents the bug where we accidentally remove a thread we just created
    if ($TargetThreads -lt $MaxThreads) {
        ($TargetThreads + 1)..$MaxThreads | ForEach-Object {
            $threadNum = $_
            $threadDir = Join-Path $ScriptDir "Thread$threadNum"
            if (Test-Path $threadDir) {
                try {
                    Remove-Item -Path $threadDir -Recurse -Force
                    Write-Host "  [OK] Removed Thread$threadNum" -ForegroundColor Cyan
                }
                catch {
                    Write-Host "  [WARNING] Failed to remove Thread${threadNum}: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }
    
    # SECOND: Create required thread directories
    1..$TargetThreads | ForEach-Object {
        $threadNum = $_
        $threadDir = Join-Path $ScriptDir "Thread$threadNum"
        $threadAutoClean = Join-Path $threadDir $AutoCleanExe
        
        try {
            if (-not (Test-Path $threadDir)) {
                New-Item -ItemType Directory -Path $threadDir -Force | Out-Null
            }
            
            if ($threadNum -eq 1 -and (Test-Path $threadAutoClean)) {
                # Thread1 already exists
                Write-Host "  [OK] Thread1 (existing)" -ForegroundColor Green
            } else {
                Copy-Item -Path $SourceAutoCleanerPath -Destination $threadAutoClean -Force
                Write-Host "  [OK] Thread$threadNum configured" -ForegroundColor Green
            }
            $success++
        }
        catch {
            Write-Host "  [ERROR] Thread${threadNum}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    return ($success -eq $TargetThreads)
}

function New-SettingsFile {
    param([int]$ThreadCount, [string]$AutoCleanerPath)
    
    $content = @"
# Oblivion Esp Cleaner Settings
# Auto-generated configuration file

@{
    ThreadCount = $ThreadCount
    AutoCleanExe = '$AutoCleanExe'
    AutoCleanerPath = '$AutoCleanerPath'
    GameTitle = 'Oblivion'
    XEditVariant = 'TES4Edit'
    Version = '1.0'
    LastConfigured = '$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))'
    ScriptDirectory = '$ScriptDir'
}
"@
    try {
        $settingsPath = Join-Path $ScriptDir $SettingsFile
        $content | Out-File -FilePath $settingsPath -Encoding utf8
        Write-Host "[OK] Settings file created: $SettingsFile" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[ERROR] Failed to create settings file: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-Installation {
    param([int]$ExpectedThreads)
    
    $ok = $true
    Write-Host "`n" + '=' * 60
    Write-Host "    Installation Report"
    Write-Host '=' * 60

    # Settings file
    $settingsPath = Join-Path $ScriptDir $SettingsFile
    if (Test-Path $settingsPath) {
        Write-Host "[OK] Settings file: $SettingsFile" -ForegroundColor Green
        try {
            $settings = Import-PowerShellDataFile -Path $settingsPath
            Write-Host "[OK] Configured threads: $($settings.ThreadCount)" -ForegroundColor Green
            if ($settings.AutoCleanerPath) {
                Write-Host "[OK] AutoCleaner source: $(Split-Path $settings.AutoCleanerPath -Leaf)" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "[ERROR] Failed to read settings: $($_.Exception.Message)" -ForegroundColor Red
            $ok = $false
        }
    }
    else {
        Write-Host "[ERROR] Settings file missing" -ForegroundColor Red
        $ok = $false
    }

    # Thread directories
    $actual = 0
    1..$MaxThreads | ForEach-Object {
        $threadPath = Join-Path $ScriptDir "Thread$_"
        $autoCleanPath = Join-Path $threadPath $AutoCleanExe
        if (Test-Path $autoCleanPath) {
            Write-Host "[OK] Thread$_ : Ready" -ForegroundColor Green
            $actual = $_
        }
    }
    
    Write-Host "[INFO] Active threads: $actual" -ForegroundColor Cyan

    if ($ok -and $actual -eq $ExpectedThreads) { 
        Write-Host "`n[SUCCESS] Installation completed successfully!" -ForegroundColor Green 
    }
    elseif ($actual -gt 0) {     
        Write-Host "`n[WARNING] Installation completed with $actual of $ExpectedThreads threads" -ForegroundColor Yellow 
    }
    else {
        Write-Host "`n[ERROR] Installation failed" -ForegroundColor Red
    }

    return $ok
}

function Cleanup-TempFiles {
    if (Test-Path $TempDir) {
        try {
            Remove-Item -Path $TempDir -Recurse -Force
            Write-Host "[INFO] Temporary files cleaned up" -ForegroundColor Cyan
        }
        catch {
            Write-Host "[WARNING] Could not clean up temp files: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Main execution
try {
    Write-Banner

    # Setup AutoCleaner from existing or archive
    $autoCleanerPath = Setup-AutoCleaner
    if (-not $autoCleanerPath) {
        return  # Error already displayed
    }

    # Get user thread selection
    $targetThreads = Get-ThreadSelection

    Write-Host "`n[INFO] Configuration Summary:" -ForegroundColor Cyan
    Write-Host "  Source executable: $(Split-Path $autoCleanerPath -Leaf)"
    Write-Host "  Current threads: $Global:CurrentThreadCount"
    Write-Host "  Target threads: $targetThreads"
    Write-Host "  Thread directories: Thread1..Thread$targetThreads"

    $confirm = Read-Host "`nProceed with configuration? (Y/n)"
    if ($confirm -match '^n') { 
        Cleanup-TempFiles
        return 
    }

    # Configure thread directories
    Write-Host "`n[INFO] Configuring thread directories..." -ForegroundColor Cyan
    if (-not (Configure-ThreadDirectories -TargetThreads $targetThreads -SourceAutoCleanerPath $autoCleanerPath)) {
        Write-Host "[ERROR] Failed to configure all thread directories" -ForegroundColor Red
        Read-Host "`nPress Enter to return to main menu"
        return
    }

    # Create settings file
    if (-not (New-SettingsFile -ThreadCount $targetThreads -AutoCleanerPath $autoCleanerPath)) {
        Write-Host "[ERROR] Failed to create settings file" -ForegroundColor Red
        Read-Host "`nPress Enter to return to main menu"
        return
    }

    # Verify installation
    $null = Test-Installation -ExpectedThreads $targetThreads

    # Cleanup temp files
    Cleanup-TempFiles

    Write-Host "`nPress Enter to return to main menu..." -ForegroundColor Gray
    $null = Read-Host
}
catch {
    Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    Cleanup-TempFiles
    Read-Host "`nPress Enter to return to main menu"
}