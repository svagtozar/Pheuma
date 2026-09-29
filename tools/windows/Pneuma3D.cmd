@echo off
rem Pneuma3D: check for an update on GitHub, then start the game.
cd /d "%~dp0"
title Pneuma3D
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1"
start "" "%~dp0Pneuma3D.exe" %*
