@echo off
title RestartWLAN
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RestartWLAN.ps1" %*
exit /b %errorlevel%
