function Set-GenericWorkerConfigValue {
  param(
    [string] $key,
    [string] $value,
    [string] $template = 'C:\generic-worker\generic-worker-template.config',
    [string] $path = 'C:\generic-worker\generic-worker.config'
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    if ((Test-Path -Path $template -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path $path -ErrorAction SilentlyContinue))) {
      Copy-Item -Path $template -Destination $path
      Write-Log -message ('{0} :: copied: {1} to: {2}' -f $($MyInvocation.MyCommand.Name), $template, $path) -severity 'INFO'
    }
    $gwConfig=(Get-Content -Raw -Path $path | ConvertFrom-Json)
    if ($gwConfig.PSObject.Properties.Name -contains $key) {
      if ($gwConfig."$key" -eq $value) {
        Write-Log -message ('{0} :: required value: {1} detected in: {2} property of: {3}' -f $($MyInvocation.MyCommand.Name), $(if ($key -eq 'accessToken') { '*****' } else { $value }), $key, $path) -severity 'DEBUG'
      } else {
        [System.IO.File]::WriteAllLines($path, (& jq @('--arg', 'v', ('"{0}"' -f $value), ('. | .{0} = $v' -f $key), $path)), (New-Object -TypeName 'System.Text.UTF8Encoding' -ArgumentList $false))
        Write-Log -message ('{0} :: value of: {1} changed from: {2} to: {3} in: {4}' -f $($MyInvocation.MyCommand.Name), $key, $(if ($key -eq 'accessToken') { '*****' } else { $gwConfig."$key" }), $(if ($key -eq 'accessToken') { '*****' } else { $value }), $path) -severity 'INFO'
      }
    } else {
      [System.IO.File]::WriteAllLines($path, (& jq @('--arg', 'v', ('"{0}"' -f $value), ('. | .{0} = $v' -f $key), $path)), (New-Object -TypeName 'System.Text.UTF8Encoding' -ArgumentList $false))
      Write-Log -message ('{0} :: value of: {1} set to: {2} in: {3}' -f $($MyInvocation.MyCommand.Name), $key, $(if ($key -eq 'accessToken') { '*****' } else { $value }), $path) -severity 'INFO'
    }
  }
  end {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function New-LocalCache {
  param (
    [string] $cacheDrive = $(if (Test-VolumeExists -DriveLetter 'Y') {'Y:'} else {$env:SystemDrive}),
    [string[]] $paths = @(
      ('{0}\hg-shared' -f $cacheDrive),
      ('{0}\pip-cache' -f $cacheDrive),
      ('{0}\tooltool-cache' -f $cacheDrive)
    )
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    foreach ($path in $paths) {
      if (-not (Test-Path -Path $path -ErrorAction SilentlyContinue)) {
        New-Item -Path $path -ItemType directory -force
        Write-Log -message ('{0} :: {1} created' -f $($MyInvocation.MyCommand.Name), $path) -severity 'INFO'
      } else {
        Write-Log -message ('{0} :: {1} detected' -f $($MyInvocation.MyCommand.Name), $path) -severity 'DEBUG'
      }
      & 'icacls.exe' @($path, '/grant', 'Everyone:(OI)(CI)F')
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
try {
  if (Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\NV Domain') {
    $currentDomain = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'NV Domain').'NV Domain'
  } elseif (Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Domain') {
    $currentDomain = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'Domain').'Domain'
  } else {
    $currentDomain = $env:USERDOMAIN
  }
} catch {
  $currentDomain = $env:USERDOMAIN
}
if ($currentDomain -match 'azure') {
  Write-Log -message ('{0} :: domain: {1}' -f 'debug.ps1', $currentDomain) -source 'MaintainSystem' -severity 'DEBUG'
}
if (Get-Service -Name @('WindowsAzureGuestAgent', 'WindowsAzureNetAgentSvc') -ErrorAction 'SilentlyContinue') {
  $azureDataPath = ('{0}\AzureData' -f $env:SystemDrive)
  if (Test-Path -Path $azureDataPath -ErrorAction 'SilentlyContinue') {
    Write-Log -message ('{0} :: {1} exists. listing contents:' -f $($MyInvocation.MyCommand.Name), $azureDataPath) -severity 'DEBUG'
    Get-ChildItem -Path $azureDataPath -Recurse | % {
      Write-Log -message ('{0} :: {1}' -f $($MyInvocation.MyCommand.Name), $_) -severity 'DEBUG'
    }
  } else {
    Write-Log -message ('{0} :: {1} does not exist' -f $($MyInvocation.MyCommand.Name), $azureDataPath) -severity 'WARN'
  }
  $instanceMetadata = ((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version={0}' -f '2019-06-04')).Content)
  Write-Log -message ('instance metadata :: {0}' -f $instanceMetadata) -severity 'DEBUG'
}
if ($false) {
  $privateKeyPath = 'C:\generic-worker\ed25519-private.key'
  if (-not (Test-Path -Path $privateKeyPath -ErrorAction SilentlyContinue)) {
    & 'C:\generic-worker\generic-worker.exe' @('new-ed25519-keypair', '--file', $privateKeyPath)
    if (Test-Path -Path $privateKeyPath -ErrorAction SilentlyContinue) {
      Write-Log -message ('{0} :: created: {1}' -f $($MyInvocation.MyCommand.Name), $privateKeyPath) -severity 'INFO'
    }
  }
  Remove-Item 'C:\generic-worker\run-generic-worker.bat' -Confirm:$false -Force -ErrorAction SilentlyContinue
  Remove-Item 'C:\generic-worker\gw.config' -Confirm:$false -Force -ErrorAction SilentlyContinue
  (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/azure/userdata/Configuration/GenericWorker/run-az-generic-worker-and-reboot.bat', 'C:\generic-worker\run-generic-worker.bat')
  $clientId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\GenericWorker' -Name 'clientId' -ErrorAction SilentlyContinue).clientId
  if (-not $clientId.EndsWith('-azure')) {
    $clientId = ('{0}-azure' -f $clientId)
  }
  $workerPool = $clientId.Replace('azure/', '')
  Set-GenericWorkerConfigValue -key 'provisionerId' -value $workerPool.Split('/')[0]
  Set-GenericWorkerConfigValue -key 'workerType' -value $workerPool.Split('/')[1]
  Set-GenericWorkerConfigValue -key 'clientId' -value $clientId
  Set-GenericWorkerConfigValue -key 'accessToken' -value (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\GenericWorker' -Name 'accessToken' -ErrorAction SilentlyContinue).accessToken
  Set-GenericWorkerConfigValue -key 'publicIP' -value ((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version={0}&format=text' -f '2019-06-04')).Content)
  Set-GenericWorkerConfigValue -key 'workerId' -value (((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version={0}' -f '2019-06-04')).Content) | ConvertFrom-Json).compute.name
  Set-GenericWorkerConfigValue -key 'rootURL' -value 'https://firefox-ci-tc.services.mozilla.com'
  Set-GenericWorkerConfigValue -key 'ed25519SigningKeyLocation' -value 'C:\generic-worker\ed25519-private.key'
  Set-GenericWorkerConfigValue -key 'tasksDir' -value 'Z:\\'
  Set-GenericWorkerConfigValue -key 'cachesDir' -value 'Y:\caches'
  Set-GenericWorkerConfigValue -key 'cachesDir' -value 'Y:\downloads'
  Set-GenericWorkerConfigValue -key 'wstAudience' -value 'firefoxcitc'
  Set-GenericWorkerConfigValue -key 'wstServerURL' -value 'https://firefoxci-websocktunnel.services.mozilla.com'
  Set-GenericWorkerConfigValue -key 'workerLocation' -value ('{0}' -f $env:TASKCLUSTER_WORKER_LOCATION)
  Set-GenericWorkerConfigValue -key 'runAfterUserCreation' -value 'C:\generic-worker\task-user-init.cmd'
  Set-GenericWorkerConfigValue -key 'taskclusterProxyExecutable' -value 'C:\generic-worker\taskcluster-proxy.exe'
  Set-GenericWorkerConfigValue -key 'sentryProject' -value 'generic-worker'
  Set-GenericWorkerConfigValue -key 'workerGroup' -value 'azure'
  #Set-GenericWorkerConfigValue -key 'availabilityZone' -value ''
  #Set-GenericWorkerConfigValue -key 'region' -value ''
  #Set-GenericWorkerConfigValue -key 'deploymentId' -value (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Revision' -ErrorAction SilentlyContinue).Revision
  New-LocalCache
}
if (${env:PROCESSOR_ARCHITEW6432} -eq 'ARM64') {
  $userProfiles = @(Get-ChildItem -path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\ProfileList' | ? { $_.Name -match 'S-1-5-21-'})
  Write-Log -message ('{0} :: {1} UserProfiles detected' -f $($MyInvocation.MyCommand.Name), $userProfiles.Length) -severity 'DEBUG'
  foreach ($userProfile in $userProfiles) {
    $sid = [System.Io.Path]::GetFileName($userProfile)
    try {
      $user = (New-Object System.Security.Principal.SecurityIdentifier ($sid)).Translate([System.Security.Principal.NTAccount]).Value
      Write-Log -message ('{0} :: UserProfile: {1} - {2}' -f $($MyInvocation.MyCommand.Name), $user, $sid) -severity 'DEBUG'
    } catch {
      # the translate call in the try block above will fail if the user profile sid does not map to a user account.
      # if that is the case, we remove the sid from the registry profile list, in order to prevent the registry consuming too much disk space
      # for all the task user profiles created and deleted by the generic worker.
      $userProfile | Remove-Item -Force -Confirm:$false
      Write-Log -message ('{0} :: UserProfile sid: {1} failed to map to a user account and was removed' -f $($MyInvocation.MyCommand.Name), $sid) -severity 'DEBUG'
    }
  }
  $occKey=(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig' -Name 'LastBitbarCredentialReset' -ErrorAction SilentlyContinue)
  foreach ($username in @('bitbar', 'testdroid')) {
    $userSessions = @(Get-CimInstance Win32_LoggedOnUser | ? { $_.Antecedent.Name -eq $username })
    if ($userSessions.Length -gt 0) {
      Write-Log -message ('{0} :: BitbarLocalAccount: {1} {2} session(s) detected' -f $($MyInvocation.MyCommand.Name), $userSessions.Length, $username) -severity 'WARN'
    }
    if ((Test-Path -Path ('{0}\Mozilla\OpenCloudConfig\.{1}.pw' -f $env:ProgramData, $username) -ErrorAction SilentlyContinue) -and ((-not ($occKey.LastBitbarCredentialReset)) -or ([DateTime]::Parse($occKey.LastBitbarCredentialReset) -lt [DateTime]::UtcNow.AddDays(-1)))) {
      #[System.Reflection.Assembly]::LoadWithPartialName("System.Web")
      #$password = $([System.Web.Security.Membership]::GeneratePassword(16,8))
      $password = (Get-Content -Path ('{0}\Mozilla\OpenCloudConfig\.{1}.pw' -f $env:ProgramData, $username))
      try {
        & net @('user', $username, $password)
        Write-Log -message ('{0} :: BitbarLocalAccount: credentials changed for user: {1}.' -f $($MyInvocation.MyCommand.Name), $username) -severity 'INFO'
        $passwordChanged = $true
      }
      catch {
        Write-Log -message ('{0} :: BitbarLocalAccount: failed to set credentials for user: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $username, $_.Exception.Message) -severity 'ERROR'
        $passwordChanged = $false
      }
      try {
        & net @('user', $username, '/active:yes')
        Write-Log -message ('{0} :: BitbarLocalAccount: account enabled for user: {1}.' -f $($MyInvocation.MyCommand.Name), $username) -severity 'INFO'
        $accountEnabled = $true
      }
      catch {
        Write-Log -message ('{0} :: BitbarLocalAccount: failed to enabled account for user: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $username, $_.Exception.Message) -severity 'ERROR'
        $accountEnabled = $false
      }
      if ($passwordChanged -and $accountEnabled) {
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig' -Name 'LastBitbarCredentialReset' -Type 'String' -Value ([DateTime]::UtcNow.ToString('u'))
        Write-Log -message ('{0} :: BitbarLocalAccount: bitbar credential reset complete' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
      } else {
        Write-Log -message ('{0} :: BitbarLocalAccount: bitbar credential reset failed' -f $($MyInvocation.MyCommand.Name)) -severity 'ERROR'
      }
    } elseif ($occKey.LastBitbarCredentialReset) {
      Write-Log -message ('{0} :: BitbarLocalAccount: detected recent bitbar credential reset at: {1}' -f $($MyInvocation.MyCommand.Name), $occKey.LastBitbarCredentialReset) -severity 'DEBUG'
    }
  }
  $userWinLogon=(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultUserName
  $userGwCurrent=(Get-Content -Raw -Path 'C:\generic-worker\current-task-user.json' | ConvertFrom-Json).name
  $userGwNext=(Get-Content -Raw -Path 'C:\generic-worker\next-task-user.json' | ConvertFrom-Json).name
  Write-Log -message ('{0} :: GenericWorkerObserve: Winlogon\DefaultUserName: {1}, gw\current: {2}, gw\next: {3}' -f $($MyInvocation.MyCommand.Name), $userWinLogon, $userGwCurrent, $userGwNext) -severity 'DEBUG'
  $gwLastExitCode=(Get-Content -Raw -Path 'C:\generic-worker\last-exit-code.json' | ConvertFrom-Json).exitCode
  $gwLastExitUsername=(Get-Content -Raw -Path 'C:\generic-worker\last-exit-code.json' | ConvertFrom-Json).username
  Write-Log -message ('{0} :: GenericWorkerObserve: last exit-code: {1}, username: {2}' -f $($MyInvocation.MyCommand.Name), $gwLastExitCode, $gwLastExitUsername) -severity 'DEBUG'
  $occKey=(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig' -Name 'LastGenericWorkerReset' -ErrorAction SilentlyContinue)
  if (($gwLastExitCode -eq 69) -or (-not ($occKey.LastGenericWorkerReset)) -or ([DateTime]::Parse($occKey.LastGenericWorkerReset) -lt [DateTime]::UtcNow.AddHours(-24))) {
    if ($gwLastExitCode -eq 69) {
      Write-Log -message ('{0} :: GenericWorkerReset: detected generic worker panic on last run' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
    }
    if ($occKey.LastGenericWorkerReset) {
      Write-Log -message ('{0} :: GenericWorkerReset: detected {1} generic worker reset at: {2}' -f $($MyInvocation.MyCommand.Name), $(if ($gwLastExitCode -eq 69) { 'last' } else { 'outdated' }), $occKey.LastGenericWorkerReset) -severity 'DEBUG'
    }
    $resetPaths = @(
      'C:\generic-worker\current-task-user.json',
      'C:\generic-worker\next-task-user.json',
      'C:\generic-worker\tasks-resolved-count.txt',
      'C:\generic-worker\directory-caches.json',
      'C:\generic-worker\file-caches.json'
    )
    foreach ($resetPath in $resetPaths) {
      if (Test-Path -Path $resetPath -ErrorAction SilentlyContinue) {
        Remove-Item $resetPath -Confirm:$false -Force -ErrorAction SilentlyContinue
        Write-Log -message ('{0} :: GenericWorkerReset: deleted {1}' -f $($MyInvocation.MyCommand.Name), $resetPath) -severity 'INFO'
      }
    }
    $resetRegistryValues = @(
      'AutoAdminLogon',
      'DefaultDomainName',
      'DefaultUserName',
      'DefaultPassword'
    )
    foreach ($resetRegistryValue in $resetRegistryValues) {
      Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name $resetRegistryValue -Force -ErrorAction SilentlyContinue
      Write-Log -message ('{0} :: GenericWorkerReset: deleted HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\{1}' -f $($MyInvocation.MyCommand.Name), $resetRegistryValue) -severity 'INFO'
    }
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig' -Name 'LastGenericWorkerReset' -Type 'String' -Value ([DateTime]::UtcNow.ToString('u'))
    Write-Log -message ('{0} :: GenericWorkerReset: generic worker reset complete' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
  } else {
    Write-Log -message ('{0} :: GenericWorkerObserve: detected recent generic worker reset at: {1}' -f $($MyInvocation.MyCommand.Name), $occKey.LastGenericWorkerReset) -severity 'DEBUG'
  }
}