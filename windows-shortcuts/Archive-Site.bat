@echo off
REM VibeDeploy Site Archival Tool
REM Interactive script to archive a deployed site
REM
REM SETUP: Copy this file to your Windows Desktop
REM Double-click to archive a site

wsl.exe bash -c "cd ~/Projects/vibe-deploy && ./archive-site.sh"

echo.
echo Press any key to close this window...
pause >nul
