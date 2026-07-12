@echo off
setlocal EnableExtensions

REM Push the entire repo to the original GitHub remote.
REM Usage:
REM   push.bat
REM   push.bat "your commit message"

cd /d "%~dp0"

set "REMOTE_URL=https://github.com/PPainez/idk.git"
set "BRANCH=main"

where git >nul 2>&1
if errorlevel 1 (
    echo [error] Git is not installed or not on PATH.
    echo Install Git from https://git-scm.com/download/win
    pause
    exit /b 1
)

if not exist ".git" (
    echo [setup] Initializing git repository...
    git init
    if errorlevel 1 goto :fail
    git branch -M "%BRANCH%"
    if errorlevel 1 goto :fail
)

git remote get-url origin >nul 2>&1
if errorlevel 1 (
    echo [setup] Adding remote origin: %REMOTE_URL%
    git remote add origin "%REMOTE_URL%"
    if errorlevel 1 goto :fail
) else (
    echo [setup] Using remote: %REMOTE_URL%
    git remote set-url origin "%REMOTE_URL%"
    if errorlevel 1 goto :fail
)

echo.
echo [stage] Adding all files...
git add -A
if errorlevel 1 goto :fail

echo.
echo [status] Current changes:
git status --short
echo.

set "COMMIT_MSG=%~1"
if "%COMMIT_MSG%"=="" set "COMMIT_MSG=Update xanhub repo"

git diff --cached --quiet
if errorlevel 1 (
    echo [commit] %COMMIT_MSG%
    git commit -m "%COMMIT_MSG%"
    if errorlevel 1 goto :fail
) else (
    echo [commit] No staged changes to commit.
)

echo.
echo [sync] Pulling latest from origin/%BRANCH%...
git pull --rebase origin "%BRANCH%"
if errorlevel 1 (
    echo.
    echo [error] Pull failed. Fix any merge conflicts, then run push.bat again.
    pause
    exit /b 1
)

echo.
echo [push] Pushing to origin/%BRANCH%...
git push -u origin "%BRANCH%"
if errorlevel 1 goto :fail

echo.
echo [done] Repository pushed successfully to %REMOTE_URL%
pause
exit /b 0

:fail
echo.
echo [error] Command failed. See messages above.
pause
exit /b 1
