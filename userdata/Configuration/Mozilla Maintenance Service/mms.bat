Rem Refrence https://support.mozilla.org/t5/Install-and-Update/What-is-the-Mozilla-Maintenance-Service/ta-p/11800
Rem Refrence https://bugzilla.mozilla.org/show_bug.cgi?id=1241225

Set workingdir="C:\DSC\MozillaMaintenance"

"%workingdir%\maintenanceservice_installer.exe"

certutil.exe -addstore Root %workingdir%\MozFakeCA.cer
certutil.exe -addstore Root %workingdir%\MozRoot.cer

reg.exe import %workingdir%\mms.reg
