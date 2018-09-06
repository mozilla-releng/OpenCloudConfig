if (!(Test-Path C:\dsc\rundsc.ps1)) {
  (New-Object Net.WebClient).DownloadFile(("https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/rundsc.ps1?{0}" -f [Guid]::NewGuid()), 'C:\dsc\rundsc.ps1')
  while (!(Test-Path "C:\dsc\rundsc.ps1")) { Start-Sleep 10 }
  Remove-Item -Path c:\dsc\in-progress.lock -force -ErrorAction SilentlyContinue
  shutdown @('-r', '-t', '0', '-c', 'Rundsc.ps1 did not exists; Restarting', '-f')
}
