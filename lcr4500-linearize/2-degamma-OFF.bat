@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
echo Disabling the DLPC350 de-gamma table (linear output).
echo This is a volatile register write - it resets on power cycle.
echo.
"%PY%" gamma.py off
echo.
pause
popd
