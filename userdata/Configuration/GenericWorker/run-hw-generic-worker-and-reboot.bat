

if exist C:\generic-worker\disable-desktop-interrupt.reg reg import C:\generic-worker\disable-desktop-interrupt.reg

:CheckForStateFlag
if exist C:\dsc\task-claim-state.valid goto RunWorker
timeout /t 1 >nul
goto CheckForStateFlag

:RunWorker
del /Q /F C:\dsc\task-claim-state.valid
pushd %~dp0
rem C:\generic-worker\generic-worker.exe run --config C:\generic-worker\gen_worker.config > C:\generic-worker\generic-worker.log 2>&1
C:\generic-worker\generic-worker.exe run --config C:\generic-worker\gen_worker.config

rem shutdown /r /t 0 /f /c "Rebooting as generic worker ran successfully"
