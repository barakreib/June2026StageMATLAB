@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
echo Verifying the projector is linear (applies the bypass if needed)...
echo.
"%PY%" ensure_linear.py
echo.
if errorlevel 1 (
  echo *** NOT VERIFIED - do not trust measurements taken now. ***
) else (
  echo Verified.
)
pause
popd
