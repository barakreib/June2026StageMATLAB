@echo off
setlocal
pushd "%~dp0"

echo ============================================================
echo  LightCrafter 4500 linearization toolkit - setup
echo ============================================================
echo.

py --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python was not found on the PATH.
    echo Install Python 3.9+ from python.org, tick "Add python.exe to PATH".
    echo.
    pause
    popd
    exit /b 1
)

echo Python found:
py --version
echo.

echo Creating virtual environment in .venv ...
py -m venv .venv
if errorlevel 1 (
    echo ERROR: could not create the virtual environment.
    pause
    popd
    exit /b 1
)

echo.
echo Installing packages ...
".venv\Scripts\python.exe" -m pip install --upgrade pip --quiet
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 (
    echo.
    echo ERROR: pip install failed. Check the internet connection or proxy.
    pause
    popd
    exit /b 1
)

echo.
echo ============================================================
echo  Setup complete. Next: run  1-check-connection.bat
echo ============================================================
pause
popd
