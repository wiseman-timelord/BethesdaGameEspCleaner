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

:: exe exists
if not exist "%AutoCleanExe%" (
    echo Missing: %AutoCleanExe%
    echo Place %AutoCleanExe% in script Dir.
    echo Download from: %XEditUrl%
    pause & exit /b 1
)
echo [OK] %AutoCleanExe%   & timeout /t 1 >nul

:: data folder
if not exist "..\Data" (
    echo Install to %GAME_TITLE%Folder\SomeFolder
    pause & exit /b 1
)
echo [OK] Data folder                  & timeout /t 1 >nul

:: blacklist
if not exist "oec_blacklist.txt" type nul >"oec_blacklist.txt"
echo [OK] Blacklist ready              & timeout /t 1 >nul

:: powershell banner
echo.
echo Launching PowerShell script...

:: run script
"%PSCMD%" -NoP -EP Bypass -File "oec_powershell.ps1"
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