@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
set /p NAME="Name for this run (e.g. before_degamma_off): "
if "%NAME%"=="" set "NAME=run"
"%PY%" analysis\log_measurements.py "data\%NAME%.csv"
echo.
pause
popd
