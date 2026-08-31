@echo off
setlocal
pushd "%~dp0"
set "PY=%~dp0.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=py"
echo Starting the LightCrafter gamma agent on port 5676 (Ctrl-C to stop).
echo Remote machines (the MATLAB client) reach the projector on THIS box
echo through it. Allow inbound TCP 5676 in Windows Firewall once.
"%PY%" lcr_agent.py
popd
