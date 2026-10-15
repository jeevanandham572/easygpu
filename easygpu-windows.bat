@echo off
setlocal EnableExtensions DisableDelayedExpansion
title EasyGPU - Windows Launcher
REM EasyGPU's Windows SSH launcher. Requires Windows OpenSSH Client.
REM Edit these defaults or enter new values when prompted.
set "GPU_HOST=relay.gridshare.in"
set "GPU_PORT=30001"
set "GPU_USER=root"
set "REPO_URL=https://github.com/jeevanandham572/easygpu.git"

where ssh.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: Windows OpenSSH Client is not installed.
  echo Install it in Windows Settings ^> Optional features.
  pause
  exit /b 1
)

echo.
echo ================================================================
echo                 EasyGPU Windows Launcher
echo ================================================================
echo Default host: %GPU_HOST%   SSH port: %GPU_PORT%
echo.
set /p "ANSWER=GPU hostname or IP [Enter for default]: "
if not "%ANSWER%"=="" set "GPU_HOST=%ANSWER%"
set "ANSWER="
set /p "ANSWER=SSH port [Enter for default]: "
if not "%ANSWER%"=="" set "GPU_PORT=%ANSWER%"
set "ANSWER="
set /p "ANSWER=SSH username [Enter for default]: "
if not "%ANSWER%"=="" set "GPU_USER=%ANSWER%"
set "ANSWER="
echo.
echo [1] Install or repair EasyGPU remotely (first use)
echo [2] Start services + open Open WebUI (normal use)
echo [3] Open secure SSH tunnel only
echo [4] Show remote service status
echo [5] Show where to find API credentials (on remote server)
echo [Q] Quit
echo.
choice /c 12345Q /n /m "Choose an option: "
if errorlevel 6 exit /b 0
if errorlevel 5 goto key
if errorlevel 4 goto status
if errorlevel 3 goto tunnel
if errorlevel 2 goto startservices
if errorlevel 1 goto install

:install
echo.
echo Connecting to %GPU_HOST% to clone/update and install EasyGPU.
echo You might be asked for your SSH password and GitHub credentials.
ssh -tt -p "%GPU_PORT%" "%GPU_USER%@%GPU_HOST%" "if test -d ~/easygpu/.git; then cd ~/easygpu && git pull --ff-only; else git clone https://github.com/jeevanandham572/easygpu.git ~/easygpu && cd ~/easygpu; fi && bash install.sh --native"
if errorlevel 1 goto failure
echo.
echo Installer finished. Launching the tunnel...
goto tunnel

:startservices
echo.
echo Starting native services on the GPU rental...
ssh -tt -p "%GPU_PORT%" "%GPU_USER%@%GPU_HOST%" "cd ~/easygpu && bash scripts/native.sh start"
if errorlevel 1 goto failure
goto tunnel

:status
ssh -tt -p "%GPU_PORT%" "%GPU_USER%@%GPU_HOST%" "cd ~/easygpu && bash scripts/native.sh status && echo --- && curl -sS -o /dev/null -w 'WebUI HTTP: %%{http_code}\n' http://127.0.0.1:8080/ && curl -sS -o /dev/null -w 'API HTTP: %%{http_code}\n' http://127.0.0.1:4000/v1/models"
goto done

:key
echo API secrets are stored in ~/easygpu/.env on the remote server.
echo Do not send them to others or embed a master key in client apps.
ssh -tt -p "%GPU_PORT%" "%GPU_USER%@%GPU_HOST%" "cd ~/easygpu && ls -l .env && echo 'Use: grep ^LITELLM_MASTER_KEY= .env'"
goto done

:tunnel
echo.
echo Opening SSH tunnel in a NEW terminal window.
echo That window MUST remain open for API and WebUI access.
echo Password may be requested again.
echo.
start "EasyGPU SSH Tunnel" cmd /k ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:4000:127.0.0.1:4000 -L 127.0.0.1:8080:127.0.0.1:8080 -p "%GPU_PORT%" "%GPU_USER%@%GPU_HOST%"
echo.
echo Tunnel window opening. Enter the SSH password there.
echo Wait for the tunnel to authenticate before using these links.
echo WebUI:    http://127.0.0.1:8080
echo API:      http://127.0.0.1:4000/v1
echo.
echo Important: the tunnel does not put ports on the public internet.
echo To open WebUI now, press any key after tunnel login completes.
pause >nul
start "" "http://127.0.0.1:8080"
goto done

:failure
echo.
echo ERROR: Remote command failed. Copy the error text above.
echo If Docker is unavailable, this launcher uses native mode.
goto done

:done
echo.
pause
exit /b 0
