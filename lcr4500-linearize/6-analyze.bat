@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
echo Recorded runs in data\:
dir /b data\*.csv 2>nul
echo.
set /p FILES="CSV file(s) to analyze (e.g. data\before.csv data\after.csv): "
"%PY%" analysis\check_linearity.py %FILES% --plot
echo.
pause
popd
