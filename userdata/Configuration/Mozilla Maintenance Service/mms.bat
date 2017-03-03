Rem Refrence https://support.mozilla.org/t5/Install-and-Update/What-is-the-Mozilla-Maintenance-Service/ta-p/11800
Rem Refrence https://bugzilla.mozilla.org/show_bug.cgi?id=1241225

"C:\DSC\maintenanceservice_installer.exe"

certutil.exe -addstore Root C:\DSC\MozFakeCA.cer
certutil.exe -addstore Root C:\DSC\MozRoot.cer

reg.exe import c:\DSC\mms.reg
