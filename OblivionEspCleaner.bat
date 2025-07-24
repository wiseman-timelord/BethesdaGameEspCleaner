@echo off
:: Script `.\OblivionEspCleaner.bat`

:: Constants
set "GAME_TITLE=Oblivion"
set "XEditVariant=TES4Edit"
set "AutoCleanExe=TES4EditQuickAutoClean.exe"
set "XEditUrl=https://www.nexusmods.com/oblivion/mods/11536"
set "DEFAULT_THREADS=2"

:: admin check
net session >nul 2>&1 || (
    echo Run as Administrator
    pause & exit /b 1
)

:: cd to script dir
pushd "%~dp0"

:: Create temp folder if it doesn't exist
if not exist ".\temp" mkdir ".\temp"

:: Skip Bar Bar
goto :Banner
:Bar
echo ===============================================================================
goto :eof

:Banner
call :Bar
echo     %GAME_TITLE% Esp Cleaner (Multi-Thread)
call :Bar
echo.

:: find ps
set "PSCMD="
for /f "delims=" %%G in ('where pwsh.exe 2^>nul') do set "PSCMD=%%G"
if not defined PSCMD (
    for /f "delims=" %%G in ('where powershell.exe 2^>nul') do set "PSCMD=%%G"
)
if not defined PSCMD (
    echo PowerShell missing
    pause & exit /b 1
)
echo [OK] PowerShell located            & timeout /t 1 >nul

:: Auto-detect available threads by checking for executables
set "THREAD_COUNT=0"
for /L %%i in (1,1,16) do (
    if exist ".\Thread%%i\%AutoCleanExe%" (
        set /a "THREAD_COUNT=%%i"
    )
)

if %THREAD_COUNT% equ 0 (
    echo ERROR: No %AutoCleanExe% found in any Thread folders
    echo Create directories Thread1, Thread2, etc. and place %AutoCleanExe% in each
    echo Download from: %XEditUrl%
    pause & exit /b 1
) else (
    echo [OK] Found %THREAD_COUNT% thread^(s^) installed
    timeout /t 1 >nul
)

:: data folder
if not exist "..\Data" (
    echo Install to %GAME_TITLE%Folder\SomeFolder
    pause & exit /b 1
)
echo [OK] Data folder                  & timeout /t 1 >nul

:: blacklist (keep in root as it's persistent data)
if not exist "oec_blacklist.txt" type nul >"oec_blacklist.txt"
echo [OK] Blacklist ready              & timeout /t 1 >nul

:: Comprehensive cleanup of old files
call :CleanupFiles
echo [OK] Old files cleaned            & timeout /t 1 >nul

:: powershell banner
echo.
echo Launching PowerShell script (%THREAD_COUNT% threads)...

:: run script with thread count parameter
"%PSCMD%" -NoP -EP Bypass -File "oec_powershell.ps1" -ThreadCount %THREAD_COUNT%
set "PS_EXIT_CODE=%ERRORLEVEL%"

:: Post-execution cleanup (in case PowerShell didn't clean up properly)
call :CleanupFiles
echo [OK] Post-execution cleanup done  & timeout /t 1 >nul

if %PS_EXIT_CODE% neq 0 (
    echo PowerShell script failed with exit code %PS_EXIT_CODE%
    pause & exit /b %PS_EXIT_CODE%
)
echo [OK] PowerShell script finished   & timeout /t 1 >nul

:: credits
echo.
echo Thank you for using %GAME_TITLE% Esp Cleaner by Wiseman-Timelord
echo.
echo Also Credit to xEdit team for making the backend tool.
timeout /t 5 >nul
popd
exit /b 0

:: Cleanup function
:CleanupFiles
:: Delete entire temp folder contents but preserve the folder
if exist ".\temp" (
    del /q ".\temp\*" 2>nul
)

:: Old batch files (legacy) - now in temp
if exist ".\temp\oec_batch1.txt" del /q ".\temp\oec_batch1.txt" 2>nul
if exist ".\temp\oec_batch2.txt" del /q ".\temp\oec_batch2.txt" 2>nul

:: Task queue system files - now in temp
if exist ".\temp\oec_taskqueue.txt" del /q ".\temp\oec_taskqueue.txt" 2>nul

:: Thread status and progress files for all possible threads - now in temp
for /L %%i in (1,1,16) do (
    if exist ".\temp\oec_status%%i.txt" del /q ".\temp\oec_status%%i.txt" 2>nul
    if exist ".\temp\oec_progress%%i.txt" del /q ".\temp\oec_progress%%i.txt" 2>nul
)

:: Clean up any thread-specific temp files in Thread directories
for /L %%i in (1,1,16) do (
    if exist ".\Thread%%i\*.tmp" del /q ".\Thread%%i\*.tmp" 2>nul
    if exist ".\Thread%%i\TES4Edit_*.txt" del /q ".\Thread%%i\TES4Edit_*.txt" 2>nul
)

goto :eof