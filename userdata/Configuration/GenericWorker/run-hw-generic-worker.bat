

if exist C:\generic-worker\disable-desktop-interrupt.reg reg import C:\generic-worker\disable-desktop-interrupt.reg

:CheckForStateFlag
if exist C:\dsc\task-claim-state.valid goto RunWorker
timeout /t 1 >nul
goto CheckForStateFlag

:RunWorker
del /Q /F C:\dsc\task-claim-state.valid
pushd %~dp0
C:\generic-worker\generic-worker.exe run run --config C:\generic-worker\work.config
