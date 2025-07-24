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
        echo [OK] Found both Thread1 and Thread2 cleaners - Using 2 threads
    ) else (
        echo [INFO] Found only Thread1 cleaner - Using 1 thread
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

:: blacklist
if not exist "oec_blacklist.txt" type nul >"oec_blacklist.txt"
echo [OK] Blacklist ready              & timeout /t 1 >nul

:: clean old batch files
if exist ".\Thread1\oec_batch1.txt" del /q ".\Thread1\oec_batch1.txt"
if exist ".\Thread2\oec_batch2.txt" del /q ".\Thread2\oec_batch2.txt"
echo [OK] Old batch files cleaned      & timeout /t 1 >nul

:: powershell banner
echo.
echo Launching PowerShell script with %THREAD_COUNT% thread(s)...

:: run script with thread count parameter
"%PSCMD%" -NoP -EP Bypass -File "oec_powershell.ps1" -ThreadCount %THREAD_COUNT%
if errorlevel 1 (
    echo PowerShell script failed
    pause & exit /b 1
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