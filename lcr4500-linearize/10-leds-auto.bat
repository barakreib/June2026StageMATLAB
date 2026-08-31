@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
echo Restoring sequencer (automatic) LED control - the power-on default.
echo This does NOT touch LED drive currents.
echo.
"%PY%" leds.py auto
echo.
pause
popd
