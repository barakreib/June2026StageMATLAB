@echo off
setlocal enabledelayedexpansion
pushd "%~dp0"

echo ============================================================
echo  Downloading TI reference PDFs into docs\
echo ============================================================
echo.

where curl.exe >nul 2>&1
if errorlevel 1 (
    set "FETCH=powershell"
    echo Using PowerShell to download.
) else (
    set "FETCH=curl"
    echo Using curl.exe to download.
)
echo.

call :get dlpu010f.pdf "https://www.ti.com/lit/ug/dlpu010f/dlpu010f.pdf" "DLPC350 Programmers Guide - THE important one"
call :get dlpu011f.pdf "https://www.ti.com/lit/ug/dlpu011f/dlpu011f.pdf" "LightCrafter 4500 EVM Users Guide"
call :get dlp4500.pdf  "https://www.ti.com/lit/ds/symlink/dlp4500.pdf"   "DLP4500 DMD datasheet"
call :get dlpc350.pdf  "https://www.ti.com/lit/ds/symlink/dlpc350.pdf"   "DLPC350 controller datasheet"
call :get dlpu017a.pdf "https://www.ti.com/lit/ug/dlpu017a/dlpu017a.pdf" "Flash Programming Guide - reference only, do not use"

echo.
echo ============================================================
dir /b *.pdf 2>nul
if errorlevel 1 (
    echo  No PDFs downloaded. Check the internet connection or proxy,
    echo  or open the URLs in docs\REFERENCES.md by hand.
) else (
    echo  Done. See REFERENCES.md for what each document covers.
)
echo ============================================================
echo.

set /p OPENGUI="Open the TI tool page to get the official GUI? [y/N] "
if /i "%OPENGUI%"=="y" start "" "https://www.ti.com/tool/DLPLCR4500EVM"

pause
popd
exit /b 0

:get
if exist "%~1" (
    echo [skip] %~1 already present  -  %~3
    exit /b 0
)
echo [get ] %~1  -  %~3
if "%FETCH%"=="curl" (
    curl.exe -sSL --fail -o "%~1" "%~2"
) else (
    powershell -NoProfile -Command "try { Invoke-WebRequest -Uri '%~2' -OutFile '%~1' -UseBasicParsing } catch { exit 1 }"
)
if errorlevel 1 (
    echo        FAILED - fetch by hand: %~2
    if exist "%~1" del "%~1"
) else (
    for %%F in ("%~1") do echo        ok, %%~zF bytes
)
exit /b 0
