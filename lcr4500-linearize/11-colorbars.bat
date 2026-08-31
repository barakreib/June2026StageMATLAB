@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
echo Switching the projector to its OWN internal colour bars.
echo This bypasses the PC, the GPU, HDMI and your stimulus software entirely.
echo.
"%PY%" testpattern.py colorbars
echo.
echo   COLOUR bars -^> projector colour path is fine, problem is PC-side
echo   GREY bars   -^> the fault is inside the projector
echo.
echo Press any key to switch back to the HDMI input...
pause >nul
"%PY%" testpattern.py off
echo.
pause
popd
