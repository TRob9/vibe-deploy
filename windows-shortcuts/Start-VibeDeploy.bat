@echo off
REM VibeDeploy Startup Script for Windows
REM This launches the VibeDeploy system in WSL
REM
REM SETUP: Copy this file to your Windows Desktop
REM Double-click to start VibeDeploy

echo Starting VibeDeploy...
echo.

REM Launch WSL and run the startup script
wsl.exe bash -c "cd ~/Projects/vibe-deploy && ./start.sh"

echo.
echo Press any key to close this window...
pause >nul
