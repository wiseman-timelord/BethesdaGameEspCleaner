@echo off
:: Script `.\OblivionEspCleaner.bat`

:: Constants
set "GAME_TITLE=Oblivion"
set "SETTINGS_FILE=oec_settings.psd1"
set "INSTALLER_SCRIPT=oec_installer.ps1"

:: admin check
net session >nul 2>&1 || (
    echo Run as Administrator
    pause & exit /b 1
)

:: cd to script dir
pushd "%~dp0"

:: Create temp folder if it doesn't exist
if not exist ".\temp" mkdir ".\temp"

:MainMenu
cls
goto :Banner
:Bar
echo ===============================================================================
goto :eof

:Banner
call :Bar
echo      %GAME_TITLE% Esp Cleaner
call :Bar
echo.
echo.
echo.
echo.
echo.
echo.
echo.
echo     1. Run %GAME_TITLE% Esp Cleaner
echo.
echo     2. Configure/Install Program
echo.
echo.
echo.
echo.
echo.
echo.
echo.
echo.
call :Bar
set /p "choice=Selection; Menu Options = 1-2, Exit Batch = X: "

:: Process menu choice
if /i "%choice%"=="1" goto :RunCleaner
if /i "%choice%"=="2" goto :Configure
if /i "%choice%"=="x" goto :Exit
if /i "%choice%"=="X" goto :Exit

echo Invalid selection. Please choose 1, 2, or X.
timeout /t 2 >nul
goto :MainMenu

:RunCleaner
cls
call :Bar
echo Starting %GAME_TITLE% Esp Cleaner...
call :Bar
echo.

:: Check if configuration exists
if not exist "%SETTINGS_FILE%" (
    echo [ERROR] Configuration not found!
    echo Please run "Configure/Install Program" first.
    echo.
    pause
    goto :MainMenu
)

:: Load settings and extract thread count
call :LoadSettings
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to read configuration!
    echo Please reconfigure the program.
    echo.
    pause
    goto :MainMenu
)

echo [OK] Configuration loaded ^(%THREAD_COUNT% threads^)
timeout /t 1 >nul

:: Verify PowerShell
call :VerifyPowerShell
if %ERRORLEVEL% neq 0 (
    pause
    goto :MainMenu
)

:: Verify GameDataPath from settings (replaces ..\Data check)
call :CheckGameDataPath
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Game data path not found: %GAME_DATA_PATH%
    echo Please check your %SETTINGS_FILE%.
    pause
    goto :MainMenu
)
echo [OK] Game data folder found
timeout /t 1 >nul

:: Verify thread installations
call :VerifyThreads
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Thread verification failed!
    echo Please reconfigure the program.
    pause
    goto :MainMenu
)

:: Create blacklist if needed (keep in root as it's persistent data)
if not exist "oec_blacklist.txt" type nul >"oec_blacklist.txt"
echo [OK] Blacklist ready
timeout /t 1 >nul

:: Comprehensive cleanup of old files
call :CleanupFiles
echo [OK] Old files cleaned
timeout /t 1 >nul

:: PowerShell banner
echo.
echo Launching PowerShell script ^(%THREAD_COUNT% threads^)...

:: Run script with thread count parameter
"%PSCMD%" -NoP -EP Bypass -File "oec_program.ps1" -ThreadCount %THREAD_COUNT%
set "PS_EXIT_CODE=%ERRORLEVEL%"

:: Post-execution cleanup (in case PowerShell didn't clean up properly)
call :CleanupFiles
echo [OK] Post-execution cleanup done
timeout /t 1 >nul

if %PS_EXIT_CODE% neq 0 (
    echo [ERROR] PowerShell script failed with exit code %PS_EXIT_CODE%
    pause
    goto :MainMenu
)
echo [OK] PowerShell script finished
timeout /t 1 >nul
goto :MainMenu

:Configure
cls
call :Bar
echo Starting Configuration/Installation...
call :Bar
echo.

:: Verify PowerShell
call :VerifyPowerShell
if %ERRORLEVEL% neq 0 (
    pause
    goto :MainMenu
)

:: Run PowerShell installer
echo [INFO] Launching PowerShell installer...
echo.
"%PSCMD%" -NoP -EP Bypass -File ".\oec_installer.ps1"

goto :MainMenu

:Exit
cls
call :Bar
echo    %GAME_TITLE% Esp Cleaner
call :Bar
echo.
echo Exiting Batch in 5 seconds...
timeout /t 5 >nul
popd
exit /b 0

:: Skip Bar Bar
goto :End

:Bar
echo ===============================================================================
goto :eof

:End

:VerifyPowerShell
set "PSCMD="
for /f "delims=" %%G in ('where pwsh.exe 2^>nul') do set "PSCMD=%%G"
if not defined PSCMD (
    for /f "delims=" %%G in ('where powershell.exe 2^>nul') do set "PSCMD=%%G"
)
if not defined PSCMD (
    echo [ERROR] PowerShell not found
    exit /b 1
)
echo [OK] PowerShell located
timeout /t 1 >nul
exit /b 0

:LoadSettings
:: Parse the PowerShell data file to extract ThreadCount
setlocal enabledelayedexpansion
set "THREAD_COUNT="
for /f "usebackq tokens=1,2 delims== " %%A in ("%SETTINGS_FILE%") do (
    if "%%A"=="ThreadCount" (
        set "TEMP_COUNT=%%B"
        set "TEMP_COUNT=!TEMP_COUNT: =!"
        set "TEMP_COUNT=!TEMP_COUNT:'=!"
        set "TEMP_COUNT=!TEMP_COUNT:"=!"
    )
)
endlocal & set "THREAD_COUNT=%TEMP_COUNT%"
if not defined THREAD_COUNT (
    echo [ERROR] Could not read ThreadCount from %SETTINGS_FILE%
    exit /b 1
)
:: Validate thread count is numeric
set /a "TEST_COUNT=%THREAD_COUNT%" 2>nul
if %TEST_COUNT% leq 0 (
    echo [ERROR] Invalid ThreadCount in settings: %THREAD_COUNT%
    exit /b 1
)
exit /b 0

:CheckGameDataPath
:: Read GameDataPath from the settings file
setlocal enabledelayedexpansion
set "GAME_DATA_PATH="
for /f "usebackq tokens=1,2 delims== " %%A in ("%SETTINGS_FILE%") do (
    if "%%A"=="GameDataPath" (
        set "TEMP_PATH=%%B"
        set "TEMP_PATH=!TEMP_PATH: =!"
        set "TEMP_PATH=!TEMP_PATH:'=!"
        set "TEMP_PATH=!TEMP_PATH:"=!"
    )
)
endlocal & set "GAME_DATA_PATH=%TEMP_PATH%"
if not defined GAME_DATA_PATH (
    echo [ERROR] GameDataPath not found in %SETTINGS_FILE%
    exit /b 1
)
:: Check if the folder exists
if not exist "%GAME_DATA_PATH%" (
    exit /b 1
)
exit /b 0

:VerifyThreads
:: Check that all required thread directories exist with executables
set "MISSING_THREADS="
set "AUTOCLEANER_EXE=TES4EditQuickAutoClean.exe"
call :LoadSettings >nul 2>&1 || exit /b 1

for /L %%i in (1,1,%THREAD_COUNT%) do (
    if not exist ".\Thread%%i\%AUTOCLEANER_EXE%" (
        if defined MISSING_THREADS (
            set "MISSING_THREADS=%MISSING_THREADS%, %%i"
        ) else (
            set "MISSING_THREADS=%%i"
        )
    )
)

if defined MISSING_THREADS (
    echo [ERROR] Missing executables in Thread folders: %MISSING_THREADS%
    echo Please run "Configure/Install Program" to fix this issue.
    exit /b 1
)

echo [OK] All %THREAD_COUNT% thread^(s^) verified
timeout /t 1 >nul
exit /b 0

:CleanupFiles
:: Delete entire temp folder contents but preserve the folder
if exist ".\temp" (
    del /q ".\temp\*" 2>nul
)

:: Clean up any thread-specific temp files in Thread directories
for /L %%i in (1,1,16) do (
    if exist ".\Thread%%i\*.tmp" del /q ".\Thread%%i\*.tmp" 2>nul
    if exist ".\Thread%%i\TES4Edit_*.txt" del /q ".\Thread%%i\TES4Edit_*.txt" 2>nul
)

goto :eof