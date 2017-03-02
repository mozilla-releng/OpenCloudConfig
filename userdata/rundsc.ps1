function Write-Log {
  param (
    [string] $message,
    [string] $severity = 'INFO',
    [string] $source = 'OpenCloudConfig',
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
function Run-RemoteDesiredStateConfig {
  param (
    [string] $url
  )
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    Stop-DesiredStateConfig
    $config = [IO.Path]::GetFileNameWithoutExtension($url)
    $target = ('{0}\{1}.ps1' -f $env:Temp, $config)
    Remove-Item $target -confirm:$false -force -ErrorAction SilentlyContinue
    (New-Object Net.WebClient).DownloadFile(('{0}?{1}' -f $url, [Guid]::NewGuid()), $target)
    Write-Log -message ('{0} :: downloaded {1}, from {2}.' -f $($MyInvocation.MyCommand.Name), $target, $url) -severity 'DEBUG'
    Unblock-File -Path $target
    . $target
    $mof = ('{0}\{1}' -f $env:Temp, $config)
    Remove-Item $mof -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
    Invoke-Expression "$config -OutputPath $mof"
    Write-Log -message ('{0} :: compiled mof {1}, from {2}.' -f $($MyInvocation.MyCommand.Name), $mof, $config) -severity 'DEBUG'
    Start-DscConfiguration -Path "$mof" -Wait -Verbose -Force
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}
function Stop-DesiredStateConfig {
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    # terminate any running dsc process
    $dscpid = (Get-WmiObject msft_providers | ? {$_.provider -like 'dsccore'} | Select-Object -ExpandProperty HostProcessIdentifier)
    if ($dscpid) {
      Get-Process -Id $dscpid | Stop-Process -f
      Write-Log -message ('{0} :: dsc process with pid {1}, stopped.' -f $($MyInvocation.MyCommand.Name), $dscpid) -severity 'DEBUG'
    }
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}
function Remove-DesiredStateConfigTriggers {
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    try {
      $scheduledTask = 'RunDesiredStateConfigurationAtStartup'
      Start-Process 'schtasks.exe' -ArgumentList @('/Delete', '/tn', $scheduledTask, '/F') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.schtask-{2}-delete.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $scheduledTask) -RedirectStandardError ('{0}\log\{1}.schtask-{2}-delete.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $scheduledTask)
      Write-Log -message 'scheduled task: RunDesiredStateConfigurationAtStartup, deleted.' -severity 'INFO'
    }
    catch {
      Write-Log -message ('failed to delete scheduled task: {0}. {1}' -f $scheduledTask, $_.Exception.Message) -severity 'ERROR'
    }
    foreach ($mof in @('Previous', 'backup', 'Current')) {
      if (Test-Path -Path ('{0}\System32\Configuration\{1}.mof' -f $env:SystemRoot, $mof) -ErrorAction SilentlyContinue) {
        Remove-Item -Path ('{0}\System32\Configuration\{1}.mof' -f $env:SystemRoot, $mof) -confirm:$false -force
        Write-Log -message ('{0}\System32\Configuration\{1}.mof deleted' -f $env:SystemRoot, $mof) -severity 'INFO'
      }
    }
    Remove-Item -Path 'C:\dsc\rundsc.ps1' -confirm:$false -force
    Write-Log -message 'C:\dsc\rundsc.ps1 deleted' -severity 'INFO'
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}
function Remove-LegacyStuff {
  param (
    [string] $logFile,
    [string[]] $users = @(
      'cltbld',
      'GenericWorker'
    ),
    [string[]] $paths = @(
      ('{0}\default_browser' -f $env:SystemDrive),
      ('{0}\etc' -f $env:SystemDrive),
      ('{0}\generic-worker' -f $env:SystemDrive),
      ('{0}\gpo_files' -f $env:SystemDrive),
      ('{0}\installersource' -f $env:SystemDrive),
      ('{0}\installservice.bat' -f $env:SystemDrive),
      ('{0}\log\*.zip' -f $env:SystemDrive),
      ('{0}\mozilla-build-bak' -f $env:SystemDrive),
      ('{0}\mozilla-buildbuildbotve' -f $env:SystemDrive),
      ('{0}\mozilla-buildpython27' -f $env:SystemDrive),
      ('{0}\nxlog\conf\nxlog_*.conf' -f $env:ProgramFiles),
      ('{0}\opt' -f $env:SystemDrive),
      ('{0}\opt.zip' -f $env:SystemDrive),
      ('{0}\Puppet Labs' -f $env:ProgramFiles),
      ('{0}\PuppetLabs' -f $env:ProgramData),
      ('{0}\puppetagain' -f $env:ProgramData),
      ('{0}\quickedit' -f $env:SystemDrive),
      ('{0}\slave' -f $env:SystemDrive),
      ('{0}\sys-scripts' -f $env:SystemDrive),
      ('{0}\System32\Configuration\backup.mof' -f $env:SystemRoot),
      ('{0}\System32\Configuration\Current.mof' -f $env:SystemRoot),
      ('{0}\System32\Configuration\Previous.mof' -f $env:SystemRoot),
      ('{0}\System32\Tasks\runner' -f $env:SystemRoot),
      ('{0}\timeset.bat' -f $env:SystemDrive),
      ('{0}\updateservice' -f $env:SystemDrive),
      ('{0}\Users\Administrator\Desktop\TESTER RUNNER' -f $env:SystemDrive),
      ('{0}\Users\Administrator\Desktop\PyYAML-3.11' -f $env:SystemDrive),
      ('{0}\Users\Administrator\Desktop\PyYAML-3.11.zip' -f $env:SystemDrive),
      ('{0}\Users\Public\Desktop\*.lnk' -f $env:SystemDrive),
      ('{0}\Users\root\Desktop\*.reg' -f $env:SystemDrive)
    ),
    [string[]] $services = @(
      'puppet',
      'uvnc_service'
    ),
    [string[]] $scheduledTasks = @(
      'Disable_maintain',
      'Disable_Notifications',
      '"INSTALL on startup"',
      'rm_reboot_semaphore',
      'RunDesiredStateConfigurationAtStartup',
      '"START RUNNER"',
      'Update_Logon_Count.xml',
      'enabel-userdata-execution',
      '"Make sure userdata runs"',
      '"Run Generic Worker on login"',
      'timesync',
      'runner'
    ),
    [string[]] $registryKeys = @(
      'HKLM:\SOFTWARE\PuppetLabs'
    ),
    [hashtable] $registryEntries = @{
      # g-w won't set autologin password if these keys pre-exist
      # https://github.com/taskcluster/generic-worker/blob/fb74177141c39afaa1daae53b6fb2a01edd8f32d/plat_windows.go#L440
      'DefaultUserName' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';
      'DefaultPassword' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';
      'AutoAdminLogon' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    },
    [hashtable] $ec2ConfigSettings = @{
      'Ec2HandleUserData' = 'Enabled';
      'Ec2InitializeDrives' = 'Enabled';
      'Ec2EventLog' = 'Enabled';
      'Ec2OutputRDPCert' = 'Enabled';
      'Ec2SetDriveLetter' = 'Enabled';
      'Ec2WindowsActivate' = 'Enabled';
      'Ec2SetPassword' = 'Disabled';
      'Ec2SetComputerName' = 'Disabled';
      'Ec2ConfigureRDP' = 'Disabled';
      'Ec2DynamicBootVolumeSize' = 'Disabled';
      'AWS.EC2.Windows.CloudWatch.PlugIn' = 'Disabled'
    }
  )
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    # clear the event log (if it hasn't just been done)
    if (-not (Get-EventLog -logName 'Application' -source 'OpenCloudConfig' -message 'Remove-LegacyStuff :: event log cleared.' -after (Get-Date).AddHours(-1) -newest 1 -ErrorAction SilentlyContinue)) {
      wevtutil el | % { wevtutil cl $_ }
      Write-Log -message ('{0} :: event log cleared.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
    }

    # remove scheduled tasks
    foreach ($scheduledTask in $scheduledTasks) {
      try {
        Start-Process 'schtasks.exe' -ArgumentList @('/Delete', '/tn', $scheduledTask, '/F') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.schtask-{2}-delete.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $scheduledTask) -RedirectStandardError ('{0}\log\{1}.schtask-{2}-delete.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $scheduledTask)
        Write-Log -message ('{0} :: scheduled task: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $scheduledTask) -severity 'INFO'
      }
      catch {
        Write-Log -message ('{0} :: failed to delete scheduled task: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $scheduledTask, $_.Exception.Message) -severity 'ERROR'
      }
    }

    # remove user accounts
    foreach ($user in $users) {
      if (@(Get-WMiObject -class Win32_UserAccount | Where { $_.Name -eq $user }).length -gt 0) {
        Start-Process 'logoff' -ArgumentList @((((quser /server:. | ? { $_ -match $user }) -split ' +')[2]), '/server:.') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.net-user-{2}-logoff.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $user) -RedirectStandardError ('{0}\log\{1}.net-user-{2}-logoff.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $user)
        Start-Process 'net' -ArgumentList @('user', $user, '/DELETE') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.net-user-{2}-delete.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $user) -RedirectStandardError ('{0}\log\{1}.net-user-{2}-delete.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $user)
        Write-Log -message ('{0} :: user: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $user) -severity 'INFO'
      }
      if (Test-Path -Path ('{0}\Users\{1}' -f $env:SystemDrive, $user) -ErrorAction SilentlyContinue) {
        Remove-Item ('{0}\Users\{1}' -f $env:SystemDrive, $user) -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
        Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), ('{0}\Users\{1}' -f $env:SystemDrive, $user)) -severity 'INFO'
      }
      if (Test-Path -Path ('{0}\Users\{1}*' -f $env:SystemDrive, $user) -ErrorAction SilentlyContinue) {
        Remove-Item ('{0}\Users\{1}*' -f $env:SystemDrive, $user) -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
        Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), ('{0}\Users\{1}*' -f $env:SystemDrive, $user)) -severity 'INFO'
      }
    }

    # delete paths
    foreach ($path in $paths) {
      if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
        Remove-Item $path -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
        Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $path) -severity 'INFO'
      }
    }

    # delete old mozilla-build. presence of python27 indicates old mozilla-build
    if (Test-Path -Path ('{0}\mozilla-build\python27' -f $env:SystemDrive) -ErrorAction SilentlyContinue) {
      Remove-Item ('{0}\mozilla-build' -f $env:SystemDrive) -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
      Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), ('{0}\mozilla-build' -f $env:SystemDrive)) -severity 'INFO'
    }

    # delete services
    foreach ($service in $services) {
      if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
        Get-Service -Name $service | Stop-Service -PassThru
        (Get-WmiObject -Class Win32_Service -Filter "Name='$service'").delete()
        Write-Log -message ('{0} :: service: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $service) -severity 'INFO'
      }
    }

    # remove registry keys
    foreach ($registryKey in $registryKeys) {
      if ((Get-Item -Path $registryKey -ErrorAction SilentlyContinue) -ne $null) {
        Remove-Item -Path $registryKey -recurse
        Write-Log -message ('{0} :: registry key: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $registryKey) -severity 'INFO'
      }
    }

    # remove registry entries
    foreach ($name in $registryEntries.Keys) {
      $path = $registryEntries.Item($name)
      $item = (Get-Item -Path $path)
      if (($item -ne $null) -and ($item.GetValue($name) -ne $null)) {
        Remove-ItemProperty -path $path -name $name
        Write-Log -message ('{0} :: registry entry: {1}\{2}, deleted.' -f $($MyInvocation.MyCommand.Name), $path, $name) -severity 'INFO'
      }
    }

    # reset ec2 config settings
    $ec2ConfigSettingsFile = 'C:\Program Files\Amazon\Ec2ConfigService\Settings\Config.xml'
    $ec2ConfigSettingsFileModified = $false;
    [xml]$xml = (Get-Content $ec2ConfigSettingsFile)
    foreach ($plugin in $xml.DocumentElement.Plugins.Plugin) {
      if ($ec2ConfigSettings.ContainsKey($plugin.Name)) {
        if ($plugin.State -ne $ec2ConfigSettings[$plugin.Name]) {
          $plugin.State = $ec2ConfigSettings[$plugin.Name]
          $ec2ConfigSettingsFileModified = $true
          Write-Log -message ('{0} :: Ec2Config {1} set to: {2}, in: {3}' -f $($MyInvocation.MyCommand.Name), $plugin.Name, $plugin.State, $ec2ConfigSettingsFile) -severity 'INFO'
        }
      }
    }
    if ($ec2ConfigSettingsFileModified) {
      & 'icacls' @($ec2ConfigSettingsFile, '/grant', 'Administrators:F') | Out-File -filePath $logFile -append
      & 'icacls' @($ec2ConfigSettingsFile, '/grant', 'System:F') | Out-File -filePath $logFile -append
      $xml.Save($ec2ConfigSettingsFile) | Out-File -filePath $logFile -append
    }
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}
function Map-DriveLetters {
  param (
    [hashtable] $driveLetterMap = @{
      'D:' = 'Y:';
      'E:' = 'Z:'
    }
  )
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    $driveLetterMap.Keys | % {
      $old = $_
      $new = $driveLetterMap.Item($_)
      if (Test-Path -Path ('{0}\' -f $old) -ErrorAction SilentlyContinue) {
        $volume = Get-WmiObject -Class win32_volume -Filter "DriveLetter='$old'"
        if ($null -ne $volume) {
          $volume.DriveLetter = $new
          $volume.Put()
          Write-Log -message ('{0} :: drive {1} assigned new drive letter: {2}.' -f $($MyInvocation.MyCommand.Name), $old, $new) -severity 'INFO'
        }
      }
    }
    if ((Test-Path -Path 'Y:\' -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path 'Z:\' -ErrorAction SilentlyContinue))) {
      $volume = Get-WmiObject -Class win32_volume -Filter "DriveLetter='Y:'"
      if ($null -ne $volume) {
        $volume.DriveLetter = 'Z:'
        $volume.Put()
        Write-Log -message ('{0} :: drive Y: assigned new drive letter: Z:.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
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
    [string] $password,
    [switch] $setautologon
  )
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    try {
      & net @('user', $username, $password)
      Write-Log -message ('{0} :: credentials set for user: {1}.' -f $($MyInvocation.MyCommand.Name), $username) -severity 'INFO'
      if ($setautologon) {
        Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Type 'String' -Name 'DefaultPassword' -Value $password
        Write-Log -message ('{0} :: autologon set for user: {1}.' -f $($MyInvocation.MyCommand.Name), $username) -severity 'INFO'
      }
    }
    catch {
      Write-Log -message ('{0} :: failed to set credentials for user: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $username, $_.Exception.Message) -severity 'ERROR'
    }
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}
function New-LocalCache {
  param (
    [string[]] $paths = @(
      'y:\hg-shared',
      'y:\pip-cache',
      'y:\tooltool-cache'
    )
  )
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
    foreach ($path in $paths) {
      New-Item -Path $path -ItemType directory -force
      & 'icacls.exe' @($path, '/grant', 'Everyone:(OI)(CI)F')
    }
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}

# SourceRepo is in place to toggle between production and testing environments
#$evn:SourceRepo = mozilla-releng
$SourceRepo = "markcor"
Write-host "$SourceRepo"

# The Windows update service needs to be enabled for OCC to process but needs to be disabled during testing. 
$UpdateService = Get-Service -Name wuauserv
if ($UpdateService.Status -ne "Running"){
 Start-Service $UpdateService
 Write-Log -message 'Enabling Windows update service'
} else {
  Write-Log -message 'Windows update service is running'
}

if (Get-Service "Ec2Config" -ErrorAction SilentlyContinue) {
  $LocationType = "AWS"
} else {
  $LocationType = "DataCenter"
}

$lock = 'C:\dsc\in-progress.lock'
if (Test-Path -Path $lock -ErrorAction SilentlyContinue) {
  Write-Log -message 'userdata run aborted. lock file exists.' -severity 'INFO'
  exit
} else {
  $lockDir = [IO.Path]::GetDirectoryName($lock)
  if (-not (Test-Path -Path $lockDir -ErrorAction SilentlyContinue)) {
    New-Item -Path $lockDir -ItemType directory -force
  }
  New-Item $lock -type file -force
}
Write-Log -message 'userdata run starting.' -severity 'INFO'

tzutil /s UTC
Write-Log -message 'system timezone set to UTC.' -severity 'INFO'
W32tm /register
W32tm /resync /force
Write-Log -message 'system clock synchronised.' -severity 'INFO'

# set up a log folder, an execution policy that enables the dsc run and a winrm envelope size large enough for the dynamic dsc.
$logFile = ('{0}\log\{1}.userdata-run.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
New-Item -ItemType Directory -Force -Path ('{0}\log' -f $env:SystemDrive)

If ($LocationType -eq "AWS") {
  try {
    $userdata = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/user-data')
  } catch {
    $userdata = $null
  }
  $publicKeys = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-keys')

  if ($publicKeys.StartsWith('0=aws-provisioner-v1-managed:')) {
    # provisioned worker
    $isWorker = $true
    $workerType = $publicKeys.Split(':')[1]
  } else {
    # ami creation instance
    $isWorker = $false
    $workerType = $publicKeys.Replace('0=mozilla-taskcluster-worker-', '')
  }
  Write-Log -message ('isWorker: {0}.' -f $isWorker) -severity 'INFO'
  $az = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/placement/availability-zone')
  Write-Log -message ('workerType: {0}.' -f $workerType) -severity 'INFO'
  switch -wildcard ($az) {
    'eu-central-1*'{
      $dnsRegion = 'euc1'
    }
    'us-east-1*'{
      $dnsRegion = 'use1'
    }
    'us-west-1*'{
      $dnsRegion = 'usw1'
    }
    'us-west-2*'{
      $dnsRegion = 'usw2'
    }
  }
  Write-Log -message ('availabilityZone: {0}, dnsRegion: {1}.' -f $az, $dnsRegion) -severity 'INFO'

  # if importing releng amis, do a little housekeeping
  switch -wildcard ($workerType) {
    'gecko-t-*' {
      $runDscOnWorker = $false
      $renameInstance = $true
      $setFqdn = $true
      if (-not ($isWorker)) {
        Remove-LegacyStuff -logFile $logFile
        Set-Credentials -username 'root' -password ('{0}' -f [regex]::matches($userdata, '<rootPassword>(.*)<\/rootPassword>')[0].Groups[1].Value)
      }
      Map-DriveLetters
    }
    default {
      $runDscOnWorker = $true
      $renameInstance = $true
      $setFqdn = $true
      if (-not ($isWorker)) {
        Set-Credentials -username 'Administrator' -password ('{0}' -f [regex]::matches($userdata, '<rootPassword>(.*)<\/rootPassword>')[0].Groups[1].Value)
      }
      Map-DriveLetters
    }
  }

  Get-ChildItem -Path $env:SystemRoot\Microsoft.Net -Filter ngen.exe -Recurse | % {
    try {
      & $_.FullName executeQueuedItems
      Write-Log -message ('executed: "{0} executeQueuedItems".' -f $_.FullName) -severity 'INFO'
    }
    catch {
      Write-Log -message ('failed to execute: "{0} executeQueuedItems"' -f $_.FullName) -severity 'ERROR'
    }
  }

  # rename the instance
  $instanceId = ((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/instance-id'))
  $dnsHostname = [System.Net.Dns]::GetHostName()
  if ($renameInstance -and ([bool]($instanceId)) -and (-not ($dnsHostname -ieq $instanceId))) {
    [Environment]::SetEnvironmentVariable("COMPUTERNAME", "$instanceId", "Machine")
    $env:COMPUTERNAME = $instanceId
    (Get-WmiObject Win32_ComputerSystem).Rename($instanceId)
    $rebootReasons += 'host renamed'
    Write-Log -message ('host renamed from: {0} to {1}.' -f $dnsHostname, $instanceId) -severity 'INFO'
  }
  # set fqdn
  if ($setFqdn) {
    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\NV Domain") {
      $currentDomain = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\" -Name "NV Domain")."NV Domain"
    } elseif (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Domain") {
      $currentDomain = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\" -Name "Domain")."Domain"
    } else {
      $currentDomain = $env:USERDOMAIN
    }
    $domain = ('{0}.{1}.mozilla.com' -f $workerType, $dnsRegion)
    if (-not ($currentDomain -ieq $domain)) {
      [Environment]::SetEnvironmentVariable("USERDOMAIN", "$domain", "Machine")
      $env:USERDOMAIN = $domain
      Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\' -Name 'Domain' -Value "$domain"
      Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\' -Name 'NV Domain' -Value "$domain"
      Write-Log -message ('domain set to: {0}' -f $domain) -severity 'INFO'
    }
  }

  $instanceType = ((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/instance-type'))
  Write-Log -message ('instanceType: {0}.' -f $instanceType) -severity 'INFO'
  [Environment]::SetEnvironmentVariable("TASKCLUSTER_INSTANCE_TYPE", "$instanceType", "Machine")
}
if ($rebootReasons.length) {
  Remove-Item -Path $lock -force
  & shutdown @('-r', '-t', '0', '-c', [string]::Join(', ', $rebootReasons), '-f', '-d', 'p:4:1') | Out-File -filePath $logFile -append
} else {
if (Get-Service "Ec2Config" -ErrorAction SilentlyContinue) {
  $LocationType = "AWS"
    # create a scheduled task to run HaltOnIdle continuously
    if (Test-Path -Path 'C:\dsc\HaltOnIdle.ps1' -ErrorAction SilentlyContinue) {
      Remove-Item -Path 'C:\dsc\HaltOnIdle.ps1' -confirm:$false -force
      Write-Log -message 'C:\dsc\HaltOnIdle.ps1 deleted.' -severity 'INFO'
    }
    (New-Object Net.WebClient).DownloadFile(("https://raw.githubusercontent.com/$SourceRepo/OpenCloudConfig/master/userdata/HaltOnIdle.ps1?{0}" -f [Guid]::NewGuid()), 'C:\dsc\HaltOnIdle.ps1')
    Write-Log -message 'C:\dsc\HaltOnIdle.ps1 downloaded.' -severity 'INFO'
    & schtasks @('/create', '/tn', 'HaltOnIdle', '/sc', 'minute', '/mo', '2', '/ru', 'SYSTEM', '/rl', 'HIGHEST', '/tr', 'powershell.exe -File C:\dsc\HaltOnIdle.ps1', '/f')
    Write-Log -message 'scheduled task: HaltOnIdle, created.' -severity 'INFO'
}

  if (($runDscOnWorker) -or (-not ($isWorker))) {

    # pre dsc setup ###############################################################################################################################################
    switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
      'Microsoft Windows 7*' {
        # set network interface to private (reverted after dsc run) http://www.hurryupandwait.io/blog/fixing-winrm-firewall-exception-rule-not-working-when-internet-connection-type-is-set-to-public
        ([Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))).GetNetworkConnections() | % { $_.GetNetwork().SetCategory(1) }
        # this setting persists only for the current session
        Enable-PSRemoting -Force
      }
      'Microsoft Windows 10*' {
        # set network interface to private (reverted after dsc run) http://www.hurryupandwait.io/blog/fixing-winrm-firewall-exception-rule-not-working-when-internet-connection-type-is-set-to-public
        ([Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))).GetNetworkConnections() | % { $_.GetNetwork().SetCategory(1) }
        # this setting persists only for the current session
        Enable-PSRemoting -SkipNetworkProfileCheck -Force
      }
      default {
        # this setting persists only for the current session
        Enable-PSRemoting -SkipNetworkProfileCheck -Force
      }
    }
    Set-ExecutionPolicy RemoteSigned -force | Out-File -filePath $logFile -append
    & cmd @('/c', 'winrm', 'set', 'winrm/config', '@{MaxEnvelopeSizekb="8192"}')
    $transcript = ('{0}\log\{1}.dsc-run.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
    # end pre dsc setup ###########################################################################################################################################

    # run dsc #####################################################################################################################################################
    Start-Transcript -Path $transcript -Append
    Run-RemoteDesiredStateConfig -url "https://raw.githubusercontent.com/$SourceRepo/OpenCloudConfig/master/userdata/DynamicConfig.ps1" -workerType $workerType
    Stop-Transcript
    # end run dsc #################################################################################################################################################
    
    # post dsc teardown ###########################################################################################################################################
    if (((Get-Content $transcript) | % { (($_ -match 'requires a reboot') -or ($_ -match 'reboot is required')) }) -contains $true) {
      Remove-Item -Path $lock -force
      & shutdown @('-r', '-t', '0', '-c', 'a package installed by dsc requested a restart', '-f', '-d', 'p:4:1') | Out-File -filePath $logFile -append
    }
    switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
      'Microsoft Windows 7*' {
        # set network interface to public
        ([Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))).GetNetworkConnections() | % { $_.GetNetwork().SetCategory(0) }
      }
      'Microsoft Windows 10*' {
        # set network interface to public
        ([Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))).GetNetworkConnections() | % { $_.GetNetwork().SetCategory(0) }

        # todo: move MS Edge install to json manifest.
        $gwEdgeFolder = 'C:\Users\GenericWorker\AppData\Local\Packages\Microsoft.MicrosoftEdge_8wekyb3d8bbwe'
        if (Test-Path -Path $gwEdgeFolder -ErrorAction SilentlyContinue) {
          Remove-Item -Path $gwEdgeFolder -recurse -force
          Write-Log -message ('{0} deleted.' -f $gwEdgeFolder) -severity 'INFO'
        }
        Get-AppXPackage -AllUsers -Name 'Microsoft.MicrosoftEdge' | % {
          Add-AppxPackage -DisableDevelopmentMode -Register ('{0}\AppXManifest.xml' -f $($_.InstallLocation)) -Verbose
        }
      }
    }
    # end post dsc teardown #######################################################################################################################################

    # create a scheduled task to run dsc at startup
    if (Test-Path -Path 'C:\dsc\rundsc.ps1' -ErrorAction SilentlyContinue) {
      Remove-Item -Path 'C:\dsc\rundsc.ps1' -confirm:$false -force
      Write-Log -message 'C:\dsc\rundsc.ps1 deleted.' -severity 'INFO'
    }
    (New-Object Net.WebClient).DownloadFile(("https://raw.githubusercontent.com/$SourceRepo/OpenCloudConfig/master/userdata/rundsc.ps1?{0}" -f [Guid]::NewGuid()), 'C:\dsc\rundsc.ps1')
    Write-Log -message 'C:\dsc\rundsc.ps1 downloaded.' -severity 'INFO'
    & schtasks @('/create', '/tn', 'RunDesiredStateConfigurationAtStartup', '/sc', 'onstart', '/ru', 'SYSTEM', '/rl', 'HIGHEST', '/tr', 'powershell.exe -File C:\dsc\rundsc.ps1', '/f')
    Write-Log -message 'scheduled task: RunDesiredStateConfigurationAtStartup, created.' -severity 'INFO'
  }
  if (($isWorker) -and (-not ($runDscOnWorker))) {
    Stop-DesiredStateConfig
    Remove-DesiredStateConfigTriggers
    New-LocalCache
  }

  if (-not ($isWorker)) {
    Set-Credentials -username 'GenericWorker' -password ('{0}' -f [regex]::matches($userdata, '<workerPassword>(.*)<\/workerPassword>')[0].Groups[1].Value) -setautologon
  }

  # archive dsc logs
  Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and $_.Length -eq 0 } | % { Remove-Item -Path $_.FullName -Force }
  New-ZipFile -ZipFilePath $logFile.Replace('.log', '.zip') -Item @(Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and $_.FullName -ne $logFile } | % { $_.FullName })
  Write-Log -message ('log archive {0} created.' -f $logFile.Replace('.log', '.zip')) -severity 'INFO'
  Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and $_.FullName -ne $logFile } | % { Remove-Item -Path $_.FullName -Force }

  if ((-not ($isWorker)) -and (Test-Path -Path 'C:\generic-worker\run-generic-worker.bat' -ErrorAction SilentlyContinue)) {
    Remove-Item -Path $lock -force
    if ($LocationType -eq "AWS") {
      if (@(Get-Process | ? { $_.ProcessName -eq 'rdpclip' }).length -eq 0) {
        & shutdown @('-s', '-t', '0', '-c', 'dsc run complete', '-f', '-d', 'p:4:1') | Out-File -filePath $logFile -append
      }
    }
  } elseif ($isWorker) {
    if ($LocationType -eq "AWS") {
      if (-not (Test-Path -Path 'Z:\' -ErrorAction SilentlyContinue)) { # if the Z: drive isn't mapped, map it.
        Map-DriveLetters
      }
    }
    if (Test-Path -Path 'C:\generic-worker\run-generic-worker.bat' -ErrorAction SilentlyContinue) {
      Write-Log -message 'generic-worker installation detected.' -severity 'INFO'
      New-Item 'C:\dsc\task-claim-state.valid' -type file -force
      # give g-w 2 minutes to fire up, if it doesn't, boot loop.
      $timeout = New-Timespan -Minutes 2
      $timer = [Diagnostics.Stopwatch]::StartNew()
      $waitlogged = $false
      while (($timer.Elapsed -lt $timeout) -and (@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).length -eq 0)) {
        if (!$waitlogged) {
          Write-Log -message 'waiting for generic-worker process to start.' -severity 'INFO'
          $waitlogged = $true
        }
      }
      if ((@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).length -eq 0)) {
        Write-Log -message 'no generic-worker process detected.' -severity 'INFO'
        & format @('Z:', '/fs:ntfs', '/v:""', '/q', '/y')
        Write-Log -message 'Z: drive formatted.' -severity 'INFO'
        #& net @('user', 'GenericWorker', (Get-ItemProperty -path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -name 'DefaultPassword').DefaultPassword)
        Remove-Item -Path $lock -force
        & shutdown @('-r', '-t', '0', '-c', 'reboot to rouse the generic worker', '-f', '-d', 'p:4:1') | Out-File -filePath $logFile -append
      } else {
        $timer.Stop()
        Write-Log -message ('generic-worker running process detected {0} ms after task-claim-state.valid flag set.' -f $timer.ElapsedMilliseconds) -severity 'INFO'
        $gwProcess = (Get-Process | ? { $_.ProcessName -eq 'generic-worker' })
        if (($gwProcess) -and ($gwProcess.PriorityClass) -and ($gwProcess.PriorityClass -ne [Diagnostics.ProcessPriorityClass]::AboveNormal)) {
          $priorityClass = $gwProcess.PriorityClass
          $gwProcess.PriorityClass = [Diagnostics.ProcessPriorityClass]::AboveNormal
          Write-Log -message ('process priority for generic worker altered from {0} to {1}.' -f $priorityClass, $gwProcess.PriorityClass) -severity 'INFO'
          Stop-Service $UpdateService
          Set-Service $UpdateService -StartupType Manual
        }
      }
    }
  }
}
Write-Log -message "Disabling Windows Update service"
Remove-Item -Path $lock -force
Write-Log -message 'userdata run completed' -severity 'INFO'
