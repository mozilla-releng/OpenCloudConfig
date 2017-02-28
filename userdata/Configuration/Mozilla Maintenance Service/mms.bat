"C:\DSC\maintenanceservice_installer.exe"

certutil.exe -addstore Root C:\DSC\MozFakeCA.cer
certutil.exe -addstore Root C:\DSC\MozRoot.cer

reg.exe import c:\DSC\mms.reg