@echo off
setlocal EnableExtensions

REM Push the entire repo to GitHub (PPainez/idk).
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
    git remote add origin "%REMOTE_URL%"
    if errorlevel 1 goto :fail
    git fetch origin
    if errorlevel 1 goto :fail
    git checkout -B "%BRANCH%" "origin/%BRANCH%" 2>nul
)

git remote get-url origin >nul 2>&1
if errorlevel 1 (
    echo [setup] Adding remote origin: %REMOTE_URL%
    git remote add origin "%REMOTE_URL%"
    if errorlevel 1 goto :fail
) else (
    git remote set-url origin "%REMOTE_URL%"
)

REM Clean up any stuck rebase from a previous failed run
if exist ".git\rebase-merge" (
    echo [fix] Aborting stuck rebase from previous run...
    git rebase --abort >nul 2>&1
)

echo.
echo [fetch] Getting latest from GitHub...
git fetch origin
if errorlevel 1 goto :fail

echo.
echo [build] Updating build manifest...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update-build.ps1"
if errorlevel 1 goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\verify-build.ps1"
if errorlevel 1 goto :fail

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
echo [sync] Rebasing onto origin/%BRANCH%...
git rebase "origin/%BRANCH%"
if errorlevel 1 (
    echo.
    echo [fix] Rebase failed. Resetting onto remote and keeping your files...
    git rebase --abort >nul 2>&1
    git reset --soft "origin/%BRANCH%"
    if errorlevel 1 goto :fail
    git diff --cached --quiet
    if errorlevel 1 (
        echo [commit] %COMMIT_MSG%
        git commit -m "%COMMIT_MSG%"
        if errorlevel 1 goto :fail
    )
)

echo.
echo [push] Pushing to origin/%BRANCH%...
git push -u origin "%BRANCH%"
if errorlevel 1 goto :fail

echo.
echo [done] Pushed successfully to %REMOTE_URL%
pause
exit /b 0

:fail
echo.
echo [error] Command failed. See messages above.
pause
exit /b 1
