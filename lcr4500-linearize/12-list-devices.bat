@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
"%PY%" ensure_linear.py --list
echo.
echo Unplug/replug one unit and run this again to see which path is which.
echo Pin each unit in rig_config.json lc_projectors by a path substring,
echo and LABEL the USB ports -- the path follows the port, not the unit.
echo.
pause
popd
