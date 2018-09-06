@echo off

copy /y C:\generic-worker\generic-worker.log c:\log\generic-worker%time:~-5%.log 
type NUL > C:\generic-worker\generic-worker.log
ping -n 5 127.0.0.1 1>/nul

:ManifestCheck 
rem https://bugzilla.mozilla.org/show_bug.cgi?id=1442472
ping -n 6 127.0.0.1 1>/nul
echo Checking for manifest completetion >> C:\generic-worker\generic-worker.log
if exist C:\DSC\EndOfManifest.semaphore GoTo key_pair
tasklist /FI "IMAGENAME eq powershell.exe" | findstr "powershell.exe" >nul
if %ERRORLEVEL% == 1 goto loop_reboot
GoTo ManifestCheck

:key_pair
del /Q /F C:\DSC\EndOfManifest.semaphore  >> C:\generic-worker\generic-worker.log
echo Checking for key pair >> C:\generic-worker\generic-worker.log
If exist C:\generic-worker\generic-worker-gpg-signing-key.key echo Key pair present >> C:\generic-worker\generic-worker.log
If not exist C:\generic-worker\generic-worker-gpg-signing-key.key echo Generating key pair >> C:\generic-worker\generic-worker.log
If not exist C:\generic-worker\generic-worker-gpg-signing-key.key C:\generic-worker\generic-worker.exe new-openpgp-keypair --file C:\generic-worker\generic-worker-gpg-signing-key.key"
If exist C:\generic-worker\generic-worker-gpg-signing-key.key echo Key pair created >> C:\generic-worker\generic-worker.log
If not exist C:\generic-worker\generic-worker-gpg-signing-key.key shutdown /r /t 0 /f /c "Rebooting as key generation failed"


echo Running generic-worker startup script (run-generic-worker.bat) ... >> C:\generic-worker\generic-worker.log

echo Disk space stats of C:\ >> C:\generic-worker\generic-worker.log
fsutil volume diskfree c: >> C:\generic-worker\generic-worker.log

If exist C:\generic-worker\gen_worker.config GoTo PreWorker
for /F "tokens=14" %%i in ('"ipconfig | findstr IPv4"') do SET LOCAL_IP=%%i
cat C:\generic-worker\master-generic-worker.json | jq ".  | .workerId=\"%COMPUTERNAME%\"" > C:\generic-worker\gen_worker.json
cat C:\generic-worker\gen_worker.json | jq ".  | .publicIP=\"%LOCAL_IP%\"" > C:\generic-worker\gen_worker.config


:PreWorker
echo Checking config file contents >> C:\generic-worker\generic-worker.log
Type C:\generic-worker\gen_worker.config  >> C:\generic-worker\generic-worker.log
if exist C:\generic-worker\disable-desktop-interrupt.reg reg import C:\generic-worker\disable-desktop-interrupt.reg

:CheckForStateFlag
echo Checking for C:\dsc\task-claim-state.valid file... >> C:\generic-worker\generic-worker.log
if exist C:\dsc\task-claim-state.valid goto RunWorker
tasklist /FI "IMAGENAME eq powershell.exe" | findstr "powershell.exe" >nul
if %ERRORLEVEL% == 1 goto loop_reboot
ping -n 2 127.0.0.1 1>/nul
goto CheckForStateFlag

 
ping -n 2 127.0.0.1 1>/nul
goto CheckForStateFlag

:RunWorker

echo File C:\dsc\task-claim-state.valid found >> C:\generic-worker\generic-worker.log
echo Deleting C:\dsc\task-claim-state.valid file >> C:\generic-worker\generic-worker.log
del /Q /F C:\dsc\task-claim-state.valid >> C:\generic-worker\generic-worker.log 
pushd %~dp0
set errorlevel=
C:\generic-worker\generic-worker.exe run --config C:\generic-worker\gen_worker.config >> C:\generic-worker\generic-worker.log
set GW_EXIT_CODE=%errorlevel%

if %GW_EXIT_CODE% EQU 69 goto ErrorReboot

<nul (set/p z=) >C:\dsc\task-claim-state.valid
echo Generic worker ran successfully (exit code %GW_EXIT_CODE%) rebooting >> C:\generic-worker\generic-worker.log
if exist C:\DSC\EndOfManifest.semaphore del /Q /F C:\DSC\EndOfManifest.semaphore >> C:\generic-worker\generic-worker.log
if exist C:\generic-worker\rebootcount.txt del /Q /F  C:\generic-worker\rebootcount.txt
if exist C:\DSC\in-progress.lock del /Q /F C:\DSC\in-progress.lock
if exist C:\dsc\task-claim-state.valid del /Q /F C:\dsc\task-claim-state.valid
ping -n 10 127.0.0.1 1>/nul
shutdown /r /t 0 /f /c "Rebooting as generic worker ran successfully"  >> C:\generic-worker\generic-worker.log


set /a minutes=0
set /a reboots=1
:WaitingOnReboot 
echo "Generic worker has exited. Waiting on reboot. %minutes% minutes since command." >> C:\generic-worker\generic-worker.log
ping -n 60 127.0.0.1 1>/nul
set /a minutes=%minutes%+1
if %minutes% GTR 10 Goto InfoGather
Goto WaitingOnReboot
exit

:InfoGather 
echo dumping tasklsit to C:\generic-worker\tasklist*.txt >> C:\generic-worker\generic-worker.log
tasklist >> C:\generic-worker\tasklist%time:~-5%.txt
set /a minutes=0
set /a reboots=%reboots%+1
echo "Attempting reboot again. %reboots% attempted."  >> C:\generic-worker\generic-worker.log
shutdown /r /t 0 /f /c "Attemptng additional reboot."  >> C:\generic-worker\generic-worker.log
Goto WaitingOnReboot

:ErrorReboot
if exist C:\DSC\in-progress.lock del /Q /F C:\DSC\in-progress.lock
if exist C:\generic-worker\rebootcount.txt GoTo AdditonalReboots
echo 1 >> C:\generic-worker\rebootcount.txt
echo Generic worker exit with code %GW_EXIT_CODE%; Rebooting to recover  >> C:\generic-worker\generic-worker.log
shutdown /r /t 0 /f /c "Generic worker exit with code %GW_EXIT_CODE%; Attempting reboot to recover"
exit
:AdditonalReboots
ping -n 10 127.0.0.1 1>/nul
for /f "delims=" %%a in ('type "C:\generic-worker\rebootcount" ' ) do set num=%%a
set /a num=num + 1 > C:\generic-worker\rebootcount.txt
if %num% GTR 5 GoTo WaitReboot
echo Generic worker exit with code %GW_EXIT_CODE% more than once; Rebooting to recover  >> C:\generic-worker\generic-worker.log
shutdown /r /t 0 /f /c "Generic worker has not recovered;  Rebooting"
exit
:WaitReboot
echo Generic worker exit with code %GW_EXIT_CODE% %num% times; 1800 second delay and then rebooting  >> C:\generic-worker\generic-worker.log
ping -n 1800 127.0.0.1 1>/nul
shutdown /r /t 0 /f /c "Generic worker has not recovered;  Rebooting"
exit

:loop_reboot 
ping -n 7200 127.0.0.1 1>/nul
if exist C:\DSC\EndOfManifest.semaphore del /Q /F C:\DSC\EndOfManifest.semaphore >> C:\generic-worker\generic-worker.log
if exist C:\generic-worker\rebootcount.txt del /Q /F  C:\generic-worker\rebootcount.txt
if exist C:\DSC\in-progress.lock del /Q /F C:\DSC\in-progress.lock
shutdown /r /t 0 /f /c "OCC did not complete and is not running;  Rebooting"
exit
