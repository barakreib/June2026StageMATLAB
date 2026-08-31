@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
"%PY%" diagnose.py
echo.
pause
popd
