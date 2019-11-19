param (
  [string]$gitBranchOrRef = 'master'
)
Invoke-Expression (New-Object Net.WebClient).DownloadString(('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/{0}/userdata/rundsc.ps1?{1}' -f $gitBranchOrRef, [Guid]::NewGuid()))