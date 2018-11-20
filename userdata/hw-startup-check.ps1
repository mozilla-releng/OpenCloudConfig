<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

# This script is called by a schedule task that is implemented during the initial deployment

[string[]] $flags = @(
  ('{0}\\dsc\\in-progress.lock' -f $env:SystemDrive),
  ('{0}\\dsc\\EndOfManifest.semaphore' -f $env:SystemRoot),
  ('{0}\\dsc\\task-claim-state.valid' -f $env:SystemDrive)
)
$rundsc = '{0}\\dsc\\rundsc.ps1'-f $env:SystemDrive

if (!(Test-Path $rundsc ) -Or ((Get-Content $rundsc) -eq $Null) ) {
  (New-Object Net.WebClient).DownloadFile("https://raw.githubusercontent.com/markcor/OpenCloudConfig/master/userdata/rundsc.ps1", "$rundsc")
  while (!(Test-Path $rundsc)){ Start-Sleep 10 }
  foreach ($flag in $flagss) {
    if (Test-Path -Path $flag -ErrorAction SilentlyContinue) {
    Remove-Item $flag -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
    }
  }
  shutdown @('-r', '-t', '0', '-c', 'Rundsc.ps1 did not exists or is empty; Restarting', '-f')
}

Start-Sleep -s 1800
if((Get-Process -Name generic-worker -ErrorAction SilentlyContinue) -eq $null){
  foreach ($flag in $flagss) {
    if (Test-Path -Path $flag -ErrorAction SilentlyContinue) {
    }
  }
    Remove-Item $flag -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
    shutdown @('-r', '-t', '0', '-c', 'Generic-worker.exe has not started within the expected time; Restarting', '-f')
}

exit
