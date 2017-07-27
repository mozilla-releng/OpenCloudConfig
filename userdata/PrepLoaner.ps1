function Write-Log {
  param (
    [string] $message,
    [string] $severity = 'INFO',
    [string] $source = 'PrepLoaner',
    [string] $logName = 'Application'
  )
  if (!([Diagnostics.EventLog]::Exists($logName)) -or !([Diagnostics.EventLog]::SourceExists($source))) {
    New-EventLog -LogName $logName -Source $source
  }
  switch ($severity) {
    'DEBUG' {
      $entryType = 'SuccessAudit'
      $eventId = 2
      break
    }
    'WARN' {
      $entryType = 'Warning'
      $eventId = 3
      break
    }
    'ERROR' {
      $entryType = 'Error'
      $eventId = 4
      break
    }
    default {
      $entryType = 'Information'
      $eventId = 1
      break
    }
  }
  Write-EventLog -LogName $logName -Source $source -EntryType $entryType -Category 0 -EventID $eventId -Message $message
}

function Remove-InstanceConfig {
  param (
    [string[]] $paths = @(
      ('{0}\Users\inst' -f $env:SystemDrive),
      ('{0}\Users\t-w1064-vanilla' -f $env:SystemDrive),
      ('{0}\log\*.log' -f $env:SystemDrive),
      ('{0}\log\*.zip' -f $env:SystemDrive),
      ('{0}\dsc\MozillaMaintenance' -f $env:SystemDrive)
    )
  )
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    foreach ($path in $paths) {
      if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
        Remove-Item $path -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
        if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
          Write-Log -message ('{0} :: failed to delete path: {1}.' -f $($MyInvocation.MyCommand.Name), $path) -severity 'Error'
        } else {
          Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $path) -severity 'INFO'
        }
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}

function Remove-Secrets {
  param (
    [string[]] $paths = @(
      ('{0}\builds\crash-stats-api.token' -f $env:SystemDrive),
      ('{0}\builds\gapi.data' -f $env:SystemDrive),
      ('{0}\builds\google-oauth-api.key' -f $env:SystemDrive),
      ('{0}\builds\mozilla-api.key' -f $env:SystemDrive),
      ('{0}\builds\mozilla-desktop-geoloc-api.key' -f $env:SystemDrive),
      ('{0}\builds\mozilla-fennec-geoloc-api.key' -f $env:SystemDrive),
      ('{0}\builds\oauth' -f $env:SystemDrive),
      ('{0}\builds\oauth.txt' -f $env:SystemDrive),
      ('{0}\builds\occ-installers.tok' -f $env:SystemDrive),
      # intentionally commented (required for building firefox)
      #('{0}\builds\relengapi.tok' -f $env:SystemDrive),
      ('{0}\builds\tc-sccache.boto' -f $env:SystemDrive),
      ('{0}\Users\Administrator\.ovpn' -f $env:SystemDrive),
      ('{0}\Users\Administrator\AppData\Roaming\Viscosity' -f $env:SystemDrive),
      ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg' -f $env:AppData),
      ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg' -f $env:SystemRoot),
      ('{0}\gnupg' -f $env:AppData)
    )
  )
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    foreach ($path in $paths) {
      if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
        Remove-Item $path -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
        if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
          Write-Log -message ('{0} :: failed to delete path: {1}.' -f $($MyInvocation.MyCommand.Name), $path) -severity 'Error'
        } else {
          Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $path) -severity 'INFO'
        }
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}

function Remove-UserAppData {
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    Get-ChildItem ('{0}\Users' -f $env:SystemDrive) | ? { $_.PSIsContainer -and -not @('Default', 'Public', 'Administrator').Contains($_.Name) } | Select-Object FullName | % {
      $appData = ('{0}\AppData' -f $_.FullName)
      foreach ($appdataProfile in @('Local', 'Roaming')) {
        Get-ChildItem ('{0}\{1}' -f $appData, $appdataProfile) | Select-Object FullName | % {
          Remove-Item $_.FullName -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
          if (Test-Path -Path $_.FullName -ErrorAction SilentlyContinue) {
            Write-Log -message ('{0} :: failed to delete path: {1}.' -f $($MyInvocation.MyCommand.Name), $_.FullName) -severity 'Error'
          } else {
            Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $_.FullName) -severity 'INFO'
          }
        }
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}

function Remove-GenericWorker {
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    $gwService = (Get-Service -Name 'Generic Worker' -ErrorAction SilentlyContinue)
    if (($gwService) -and ($gwService.Status -eq 'Running')) {
      Write-Log -message ('{0} :: attempting to stop running generic-worker service.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      $gwService | Stop-Service -PassThru | Set-Service -StartupType disabled
      $gwService = (Get-Service -Name 'Generic Worker' -ErrorAction SilentlyContinue)
      if (($gwService) -and ($gwService.Status -eq 'Running')) {
        Write-Log -message ('{0} :: failed to stop running generic-worker service.' -f $($MyInvocation.MyCommand.Name)) -severity 'ERROR'
      } else {
        Write-Log -message ('{0} :: generic-worker service stop initiated. current state: {1}.' -f $($MyInvocation.MyCommand.Name), $gwService.Status) -severity 'INFO'
      }
    }
    $gwProcess = (Get-Process | ? { $_.ProcessName -eq 'generic-worker' })
    if ($gwProcess) {
      Write-Log -message ('{0} :: attempting to stop running generic-worker process.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      $gwProcess | Stop-Process -Force -ErrorAction SilentlyContinue
      $gwProcess = (Get-Process | ? { $_.ProcessName -eq 'generic-worker' })
      if ($gwProcess) {
        Write-Log -message ('{0} :: failed to stop running generic-worker process.' -f $($MyInvocation.MyCommand.Name)) -severity 'ERROR'
      } else {
        Write-Log -message ('{0} :: generic-worker process stopped successfully.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
      }
    }
    $paths = @(
      ('{0}\generic-worker\disable-desktop-interrupt.reg' -f $env:SystemDrive),
      ('{0}\generic-worker\generic-worker.log' -f $env:SystemDrive),
      ('{0}\generic-worker\generic-worker.config' -f $env:SystemDrive),
      ('{0}\generic-worker\generic-worker-test-creds.cmd' -f $env:SystemDrive),
      ('{0}\generic-worker\livelog.crt' -f $env:SystemDrive),
      ('{0}\generic-worker\livelog.key' -f $env:SystemDrive),
      ('{0}\generic-worker\cot.key' -f $env:SystemDrive),
      ('{0}\generic-worker\*.xml' -f $env:SystemDrive)
    )
    foreach ($path in $paths) {
      if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
        Remove-Item $path -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
        if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
          Write-Log -message ('{0} :: failed to delete path: {1}.' -f $($MyInvocation.MyCommand.Name), $path) -severity 'Error'
        } else {
          Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $path) -severity 'INFO'
        }
      }
    }
    $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $autologonRegistryEntries = @{
      'DefaultUserName' = $winlogonPath;
      'DefaultDomainName' = $winlogonPath;
      'DefaultPassword' = $winlogonPath;
      'AutoAdminLogon' = $winlogonPath
    }
    foreach ($name in $autologonRegistryEntries.Keys) {
      $path = $autologonRegistryEntries.Item($name)
      $item = (Get-Item -Path $path)
      if (($item -ne $null) -and ($item.GetValue($name) -ne $null)) {
        Remove-ItemProperty -path $path -name $name
        Write-Log -message ('{0} :: registry entry: {1}\{2}, deleted.' -f $($MyInvocation.MyCommand.Name), $path, $name) -severity 'INFO'
      }
    }
    $taskUsers = @(Get-WMiObject -class Win32_UserAccount | Where { (($_.Name -eq 'GenericWorker') -or ($_.Name.StartsWith('task_'))) })
    foreach ($taskUser in $taskUsers) {
      Start-Process 'logoff' -ArgumentList @((((quser /server:. | ? { $_ -match $taskUser.Name}) -split ' +')[2]), '/server:.') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.net-user-{2}-logoff.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $taskUser) -RedirectStandardError ('{0}\log\{1}.net-user-{2}-logoff.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $taskUser)
      Start-Process 'net' -ArgumentList @('user', $taskUser.Name, '/DELETE') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.net-user-{2}-delete.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $taskUser) -RedirectStandardError ('{0}\log\{1}.net-user-{2}-delete.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $taskUser)
      Write-Log -message ('{0} :: user: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $taskUser.Name) -severity 'INFO'
      if (Test-Path -Path ('{0}\Users\{1}' -f $env:SystemDrive, $taskUser.Name) -ErrorAction SilentlyContinue) {
        Remove-Item ('{0}\Users\{1}' -f $env:SystemDrive, $taskUser.Name) -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
        Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), ('{0}\Users\{1}' -f $env:SystemDrive, $taskUser.Name)) -severity 'INFO'
      }
      if (Test-Path -Path ('{0}\Users\{1}*' -f $env:SystemDrive, $taskUser.Name) -ErrorAction SilentlyContinue) {
        Remove-Item ('{0}\Users\{1}*' -f $env:SystemDrive, $taskUser.Name) -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
        Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), ('{0}\Users\{1}*' -f $env:SystemDrive, $taskUser.Name)) -severity 'INFO'
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}

function Set-Credentials {
  param (
    [string] $username,
    [string] $password
  )
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    try {
      & net @('user', $username, $password)
      Write-Log -message ('{0} :: credentials set for user: {1}.' -f $($MyInvocation.MyCommand.Name), $username) -severity 'INFO'
    }
    catch {
      Write-Log -message ('{0} :: failed to set credentials for user: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $username, $_.Exception.Message) -severity 'ERROR'
    }
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}

function Get-GeneratedPassword {
  param (
    [int] $length = 16
  )
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    $chars=$null;
    for ($char = 48; $char -le 122; $char ++) {
      $chars += ,[char][byte]$char
    }
    $rootPassword = ''
    for ($i=1; $i -le $length; $i++) {
      $rootPassword += ($chars | Get-Random)
    }
    return $rootPassword
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}

function Test-RegistryValue {
  param (
    [string] $path,
    [string] $value
  )
  try {
    Get-ItemProperty -Path $Path | Select-Object -ExpandProperty $Value -ErrorAction Stop | Out-Null
    return $true
  } catch {
    return $false
  }
}

$loanReqPath = 'Z:\loan-request.json'
$loanRegPath = 'HKLM:\SOFTWARE\OpenCloudConfig\Loan'

# exit if no loan request
if (-not (Test-Path -Path $loanReqPath -ErrorAction SilentlyContinue)) {
  Write-Log -message 'loaner semaphore not detected' -severity 'DEBUG'
  exit
}
# if reg keys exist, log activity and exit since an earlier run will have performed loan prep
if (Test-Path -Path $loanRegPath -ErrorAction SilentlyContinue) {
  if (@(& qwinsta | ? { $_ -match 'rdp-tcp.*Active' }).length -gt 0) {
    # todo: record the ip address where the rdp session originates
    Write-Log -message 'rdp session detected on active loaner' -severity 'DEBUG'
  } else {
    Write-Log -message 'rdp session not detected on active loaner' -severity 'DEBUG'
  }
  if (Test-RegistryValue -path $loanRegPath -value 'Fulfilled') {
    # rerun this part of cleanup to purge files that may have been locked or in use on previous runs
    Remove-InstanceConfig
    Remove-GenericWorker
  }
  exit
}

# create registry entries if file exists but reg entries don't
if ((Test-Path -Path $loanReqPath -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path $loanRegPath -ErrorAction SilentlyContinue))) {
  New-Item -Path $loanRegPath -Force | Out-Null
  New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'Detected' -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:sszzz')) -Force | Out-Null
  New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'Requested' -Value ((Get-Item -Path $loanReqPath).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:sszzz')) -Force | Out-Null
  $loanRequest = (Get-Content -Raw -Path $loanReqPath | ConvertFrom-Json)
  New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'Email' -Value $loanRequest.requester.email -Force | Out-Null
  New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'PublicKeyUrl' -Value $loanRequest.requester.publickeyurl -Force | Out-Null
  New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'TaskFolder' -Value $loanRequest.requester.taskFolder -Force | Out-Null
  New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'TaskId' -Value $loanRequest.requester.taskid -Force | Out-Null
}

if (-not (Test-Path -Path $loanRegPath -ErrorAction SilentlyContinue)) {
  exit
}

$loanRequestTime = (Get-Date -Date (Get-ItemProperty -Path $loanRegPath -Name 'Requested').Requested)
$loanRequestDetectedTime = (Get-Date -Date (Get-ItemProperty -Path $loanRegPath -Name 'Detected').Detected)
$loanRequestEmail = (Get-ItemProperty -Path $loanRegPath -Name 'Email').Email
$loanRequestPublicKeyUrl = (Get-ItemProperty -Path $loanRegPath -Name 'PublicKeyUrl').PublicKeyUrl
$loanRequestTaskFolder = (Get-ItemProperty -Path $loanRegPath -Name 'TaskFolder').TaskFolder
$loanRequestTaskId = (Get-ItemProperty -Path $loanRegPath -Name 'TaskId').TaskId
Write-Log -message ('loan request from {0}/{1} ({2}) at {3} detected at {4}' -f $loanRequestEmail, $loanRequestPublicKeyUrl, $loanRequestTaskFolder, $loanRequestTime, $loanRequestDetectedTime) -severity 'INFO'
Remove-Secrets
Remove-UserAppData
Remove-InstanceConfig
switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
  'Microsoft Windows 7*' {
    $rootUsername = 'root'
  }
  default {
    $rootUsername = 'Administrator'
  }
}
$rootPassword = (Get-GeneratedPassword)
Set-Credentials -username $rootUsername -password $rootPassword
$workerUsername = 'GenericWorker'
$workerPassword = (Get-GeneratedPassword)
Set-Credentials -username $workerUsername -password $workerPassword

if ("${env:ProgramFiles(x86)}") {
  $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
} else {
  $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f $env:ProgramFiles)
}

$artifactsPath = 'z:\loan'
if (-not (Test-Path $artifactsPath -ErrorAction SilentlyContinue)) {
  New-Item -Path $artifactsPath -ItemType directory -force
}
$token = [Guid]::NewGuid()
$publicIP = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-ipv4')
"host: $publicIP`n" | Out-File -filePath ('{0}\{1}.txt' -f $env:Temp, $token) -Encoding 'UTF8'
"root username: $rootUsername`nroot password: $rootPassword`n" | Out-File -filePath ('{0}\{1}.txt' -f $env:Temp, $token) -Encoding 'UTF8' -append
$bashArgs = '/kbd:${XFR_K:-409} /w:${XFR_W:-1600} /h:${XFR_H:-1200}'
"`nremote desktop from Linux:`nxfreerdp /u:$rootUsername /p:'$rootPassword' $bashArgs +clipboard /v:$publicIP" | Out-File -filePath ('{0}\{1}.txt' -f $env:Temp, $token) -Encoding 'UTF8' -append
"`nremote desktop from Windows:`nmstsc /w:1600 /h:1200 /v:$publicIP" | Out-File -filePath ('{0}\{1}.txt' -f $env:Temp, $token) -Encoding 'UTF8' -append
(New-Object Net.WebClient).DownloadFile($loanRequestPublicKeyUrl, ('{0}\{1}.asc' -f $artifactsPath, $token))
$tempKeyring = ('{0}.gpg' -f $token)
Start-Process $gpg -ArgumentList @('--no-default-keyring', '--keyring', $tempKeyring, '--fingerprint') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\gpg-create-keyring.stdout.log' -f $artifactsPath) -RedirectStandardError ('{0}\gpg-create-keyring.stderr.log' -f $artifactsPath)
Start-Process $gpg -ArgumentList @('--no-default-keyring', '--keyring', $tempKeyring, '--import', ('{0}\{1}.asc' -f $artifactsPath, $token)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\gpg-import-key.stdout.log' -f $artifactsPath) -RedirectStandardError ('{0}\gpg-import-key.stderr.log' -f $artifactsPath)
Start-Process $gpg -ArgumentList @('--no-default-keyring', '--keyring', $tempKeyring, '--trust-model', 'always', '-e', '-u', 'releng-puppet-mail@mozilla.com', '-r', $loanRequestEmail, ('{0}\{1}.txt' -f $env:Temp, $token)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\gpg-encrypt.stdout.log' -f $artifactsPath) -RedirectStandardError ('{0}\gpg-encrypt.stderr.log' -f $artifactsPath)
Get-ChildItem -Path $artifactsPath | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and $_.Length -eq 0 } | % { Remove-Item -Path $_.FullName -Force }
Remove-Item -Path ('{0}\{1}.txt' -f $env:Temp, $token) -force
Move-Item -Path ('{0}\{1}.txt.gpg' -f $env:Temp, $token) -Destination ('{0}\credentials.txt.gpg' -f $artifactsPath)
& 'icacls' @($artifactsPath, '/grant', 'Everyone:(OI)(CI)F')
Write-Log -message 'credentials encrypted in task artefacts' -severity 'DEBUG'
Write-Log -message 'waiting for loan request task to complete' -severity 'DEBUG'
while (-not ((Invoke-WebRequest -Uri ('https://queue.taskcluster.net/v1/task/{0}/status' -f $loanRequestTaskId) -UseBasicParsing | ConvertFrom-Json).status.state -eq 'completed')) {
  Start-Sleep 1
}
New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'Fulfilled' -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:sszzz')) -Force | Out-Null
Write-Log -message 'loan request task completion detected' -severity 'DEBUG'
Remove-GenericWorker
switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
  'Microsoft Windows 10*' {
    Write-Log -message 'rebooting prepped loaner' -severity 'DEBUG'
    & shutdown @('-r', '-t', '0', '-c', 'loaner reboot', '-f', '-d', 'p:4:1')
  }
  default {
    Write-Log -message 'skipping reboot of prepped loaner' -severity 'DEBUG'
  }
}