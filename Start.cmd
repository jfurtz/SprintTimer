@echo off
title Sprint Time Tracker
where node >nul 2>&1
if %errorlevel%==0 (
  node "%~dp0server.js"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
)
