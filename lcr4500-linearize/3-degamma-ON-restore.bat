@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
echo Restoring the factory TI video de-gamma table.
echo.
"%PY%" gamma.py on
echo.
pause
popd
