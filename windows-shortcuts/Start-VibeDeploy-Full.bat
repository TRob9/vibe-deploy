@echo off
REM VibeDeploy Full Startup Script for Windows
REM This launches VibeDeploy AND deploys all sites from deployments/ folder
REM
REM SETUP: Copy this file to your Windows Desktop
REM Double-click to start VibeDeploy with full site deployment

echo Starting VibeDeploy (Full Deployment)...
echo.

REM Launch WSL and run the comprehensive startup script
wsl.exe bash -c "cd ~/Projects/vibe-deploy && ./start-full.sh"

echo.
echo Press any key to close this window...
pause >nul
