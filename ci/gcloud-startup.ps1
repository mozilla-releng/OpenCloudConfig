<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

$gitBranchOrRef = 'gamma'
Invoke-Expression (New-Object Net.WebClient).DownloadString(('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/{0}/userdata/rundsc.ps1?{1}' -f $gitBranchOrRef, [Guid]::NewGuid()))
