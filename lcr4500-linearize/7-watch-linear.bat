@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
echo Watching the gamma register. Re-applies the bypass if it ever reverts.
echo Leave this window open for the whole measurement session. Ctrl-C to stop.
echo.
"%PY%" watch_linear.py --interval 10 --log data\watch_log.txt
popd
