@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
echo Opening the patch generator on the projector display.
echo If it lands on the wrong monitor, edit the --geometry value below
echo (WIDTHxHEIGHT+XOFFSET+YOFFSET) to match your desktop layout.
echo.
"%PY%" tools\ramp.py --geometry 1280x800+1920+0
popd
