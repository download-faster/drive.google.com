@echo off
title Install Traffmonetizer

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_windows.ps1 | iex"
exit
