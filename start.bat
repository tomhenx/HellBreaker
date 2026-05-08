@echo off
title HellBreaker — Dev Server

:: Try python, then py launcher (Windows Store Python fallback)
where python >nul 2>&1
if %errorlevel% == 0 (
    python "%~dp0server.py"
    goto end
)

where py >nul 2>&1
if %errorlevel% == 0 (
    py "%~dp0server.py"
    goto end
)

echo.
echo  [ERROR] Python not found. Install Python 3 from https://python.org
echo.

:end
pause
