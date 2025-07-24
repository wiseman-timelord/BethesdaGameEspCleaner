@echo off
:: Script `.\OblivionEspCleaner.bat`

:: Constants
set "GAME_TITLE=Oblivion"
set "XEditVariant=TES4Edit"
set "AutoCleanExe=TES4EditQuickAutoClean.exe"
set "XEditUrl=https://www.nexusmods.com/oblivion/mods/11536"

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
echo     %GAME_TITLE% Esp Cleaner
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

:: Check for cleaners in Thread folders
set "THREAD_COUNT=1"
if exist ".\Thread1\%AutoCleanExe%" (
    if exist ".\Thread2\%AutoCleanExe%" (
        set "THREAD_COUNT=2"
        echo [OK] Found, Thread1 and Thread2, using 2 threads
    ) else (
        echo [INFO] Found only Thread1, using 1 thread.
    )
    timeout /t 1 >nul
) else (
    echo ERROR: Missing %AutoCleanExe% in Thread1 folder
    echo Place %AutoCleanExe% in .\Thread1\
    echo Download from: %XEditUrl%
    pause & exit /b 1
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

:: Thread status files - now in temp
if exist ".\temp\oec_status1.txt" del /q ".\temp\oec_status1.txt" 2>nul
if exist ".\temp\oec_status2.txt" del /q ".\temp\oec_status2.txt" 2>nul

:: Thread progress files - now in temp
if exist ".\temp\oec_progress1.txt" del /q ".\temp\oec_progress1.txt" 2>nul
if exist ".\temp\oec_progress2.txt" del /q ".\temp\oec_progress2.txt" 2>nul

:: Any temporary xEdit files that might be left behind in thread folders
if exist ".\Thread1\*.tmp" del /q ".\Thread1\*.tmp" 2>nul
if exist ".\Thread2\*.tmp" del /q ".\Thread2\*.tmp" 2>nul
if exist ".\Thread1\TES4Edit_*.txt" del /q ".\Thread1\TES4Edit_*.txt" 2>nul
if exist ".\Thread2\TES4Edit_*.txt" del /q ".\Thread2\TES4Edit_*.txt" 2>nul

goto :eof