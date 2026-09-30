@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\article-editor\publish-site.ps1"
if errorlevel 1 pause
