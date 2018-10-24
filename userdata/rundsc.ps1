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
  if ([Environment]::UserInteractive -and $env:OccConsoleOutput) {
    $fc = @{ 'Information' = 'White'; 'Error' = 'Red'; 'Warning' = 'DarkYellow'; 'SuccessAudit' = 'DarkGray' }[$entryType]
    Write-Host -object $message -ForegroundColor $fc
  }
}
function Run-RemoteDesiredStateConfig {
  param (
    [string] $url
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
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
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Stop-DesiredStateConfig {
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
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
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Remove-DesiredStateConfigTriggers {
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
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
    if (Test-Path -Path 'C:\dsc\rundsc.ps1' -ErrorAction SilentlyContinue) {
      Remove-Item -Path 'C:\dsc\rundsc.ps1' -confirm:$false -force
      Write-Log -message 'C:\dsc\rundsc.ps1 deleted' -severity 'INFO'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Remove-LegacyStuff {
  param (
    [string] $logFile,
    [string[]] $users = @(
      'cltbld',
      'GenericWorker',
      't-w1064-vanilla',
      'inst'
    ),
    [string[]] $paths = @(
      ('{0}\Apache Software Foundation' -f $env:ProgramFiles),
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
      ('{0}\scripts' -f $env:SystemDrive),
      ('{0}\sys-scripts' -f $env:SystemDrive),
      ('{0}\System32\Configuration\backup.mof' -f $env:SystemRoot),
      ('{0}\System32\Configuration\Current.mof' -f $env:SystemRoot),
      ('{0}\System32\Configuration\Previous.mof' -f $env:SystemRoot),
      ('{0}\System32\Tasks\runner' -f $env:SystemRoot),
      ('{0}\TeamViewer' -f ${env:ProgramFiles(x86)}),
      ('{0}\Temp\*.exe' -f $env:SystemRoot),
      ('{0}\Temp\*.msi' -f $env:SystemRoot),
      ('{0}\Temp\*.msu' -f $env:SystemRoot),
      ('{0}\Temp\*.zip' -f $env:SystemRoot),
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
      'Apache2.2',
      'ViscosityService',
      'TeamViewer'
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
      'runner',
      '"OneDrive Standalone Update task v2"'
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
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
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
        try {
          $quserMatch = ((quser /server:. | ? { $_ -match $user }) -split ' +')
        }
        catch {
          $quserMatch = $false
        }
        if ($quserMatch) {
          Start-Process 'logoff' -ArgumentList @(($quserMatch[2]), '/server:.') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.net-user-{2}-logoff.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $user) -RedirectStandardError ('{0}\log\{1}.net-user-{2}-logoff.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $user)
        }
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

    # delete services
    foreach ($service in $services) {
      if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
        Get-Service -Name $service | Stop-Service -PassThru
        (Get-WmiObject -Class Win32_Service -Filter "Name='$service'").delete()
        Write-Log -message ('{0} :: service: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $service) -severity 'INFO'
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
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Mount-DiskOne {
  param (
    [string] $lock = 'C:\dsc\in-progress.lock'
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    if ((Test-Path -Path 'Y:\' -ErrorAction SilentlyContinue) -and (Test-Path -Path 'Z:\' -ErrorAction SilentlyContinue)) {
      Write-Log -message ('{0} :: skipping disk mount (drives y: and z: already exist).' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
    } else {
      $pagefileName = $false
      Get-WmiObject Win32_PagefileSetting | ? { !$_.Name.StartsWith('c:') } | % {
        $pagefileName = $_.Name
        try {
          $_.Delete()
          Write-Log -message ('{0} :: page file: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $pagefileName) -severity 'INFO'
        }
        catch {
          Write-Log -message ('{0} :: failed to delete page file: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $pagefileName, $_.Exception.Message) -severity 'ERROR'
        }
      }
      if ($pagefileName) {
        Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
        & shutdown @('-r', '-t', '0', '-c', ('page file {0} removed' -f $pagefileName), '-f', '-d', 'p:2:4')
      }
      if (Get-Command 'Clear-Disk' -errorAction SilentlyContinue) {
        try {
          Clear-Disk -Number 1 -RemoveData -Confirm:$false
          Write-Log -message ('{0} :: disk 1 partition table cleared.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
        }
        catch {
          Write-Log -message ('{0} :: failed to clear partition table on disk 1. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
        }
      } else {
        Write-Log -message ('{0} :: partition table clearing skipped on unsupported os' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      }
      if (Get-Command 'Initialize-Disk' -errorAction SilentlyContinue) {
        try {
          Initialize-Disk -Number 1 -PartitionStyle MBR
          Write-Log -message ('{0} :: disk 1 initialized.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
        }
        catch {
          Write-Log -message ('{0} :: failed to initialize disk 1. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
        }
      } else {
        Write-Log -message ('{0} :: disk initialisation skipped on unsupported os' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      }
      if (Get-Command 'New-Partition' -errorAction SilentlyContinue) {
        try {
          New-Partition -DiskNumber 1 -Size 20GB -DriveLetter Y
          Format-Volume -FileSystem NTFS -NewFileSystemLabel cache -DriveLetter Y -Confirm:$false
          Write-Log -message ('{0} :: cache drive Y: formatted.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
        }
        catch {
          Write-Log -message ('{0} :: failed to format cache drive Y:. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
        }
        try {
          New-Partition -DiskNumber 1 -UseMaximumSize -DriveLetter Z
          Format-Volume -FileSystem NTFS -NewFileSystemLabel task -DriveLetter Z -Confirm:$false
          Write-Log -message ('{0} :: task drive Z: formatted.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
        }
        catch {
          Write-Log -message ('{0} :: failed to format task drive Z:. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
        }
      } else {
        Write-Log -message ('{0} :: partitioning skipped on unsupported os' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Resize-DiskZero {
  param (
    [char] $drive = 'C'
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    if ((Get-Command 'Resize-Partition' -errorAction SilentlyContinue) -and (Get-Command 'Get-PartitionSupportedSize' -errorAction SilentlyContinue)) {
      $oldSize = (Get-WmiObject Win32_LogicalDisk | ? { $_.DeviceID -eq ('{0}:' -f $drive)}).Size
      $maxSize = (Get-PartitionSupportedSize -DriveLetter $drive).SizeMax
      # if at least 1gb can be gained from a resize, perform a resize
      if ((($maxSize - $oldSize)/1GB) -gt 1GB) {
        try {
          Resize-Partition -DriveLetter $drive -Size $maxSize
          Write-Log -message ('{0} :: system drive {1}: resized from {2} to {3}.' -f $($MyInvocation.MyCommand.Name), $drive, [math]::Round($oldSize/1GB, 2), [math]::Round($maxSize/1GB, 2)) -severity 'INFO'
        }
        catch {
          Write-Log -message ('{0} :: failed to resize partition for system drive {1}:. {2}' -f $($MyInvocation.MyCommand.Name), $drive, $_.Exception.Message) -severity 'ERROR'
        }
      } else {
        Write-Log -message ('{0} :: partition resizing skipped. drive {1}: at maximum size ({2})' -f $($MyInvocation.MyCommand.Name, $drive, [math]::Round($oldSize/1GB, 2))) -severity 'DEBUG'
      }
    } else {
      Write-Log -message ('{0} :: partition resizing skipped on unsupported os' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Resize-DiskOne {
  param (
    [char] $drive = 'Z',
    [UInt64] $newSize = 100GB,
    [char] $newDrive = 'Y'
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    if ((Get-Command 'Resize-Partition' -errorAction SilentlyContinue) -and (Get-Command 'New-Partition' -errorAction SilentlyContinue) -and (Get-Command 'Format-Volume' -errorAction SilentlyContinue)) {
      $oldSize = (Get-WmiObject Win32_LogicalDisk | ? { $_.DeviceID -eq ('{0}:' -f $drive)}).Size
      # if the current partition size is larger than expected
      if ($oldSize -gt ($newSize + 2GB)) {
        try {
          Resize-Partition -DriveLetter $drive -Size $newSize
          Write-Log -message ('{0} :: task drive {1}: resized from {2} to {3}.' -f $($MyInvocation.MyCommand.Name), $drive, [math]::Round($oldSize/1GB, 2), [math]::Round($newSize/1GB, 2)) -severity 'INFO'
          try {
            New-Partition -DiskNumber 1 -DriveLetter $newDrive -UseMaximumSize
            Format-Volume -FileSystem 'NTFS' -DriveLetter $newDrive -NewFileSystemLabel 'cache' -Confirm:$false
            Write-Log -message ('{0} :: cache drive {1}: partition created and formatted.' -f $($MyInvocation.MyCommand.Name), $newDrive) -severity 'INFO'
          }
          catch {
            Write-Log -message ('{0} :: failed to create or format partition for cache drive {1}:. {2}' -f $($MyInvocation.MyCommand.Name), $newDrive, $_.Exception.Message) -severity 'ERROR'
          }
        }
        catch {
          Write-Log -message ('{0} :: failed to resize partition for task drive {1}:. {2}' -f $($MyInvocation.MyCommand.Name), $drive, $_.Exception.Message) -severity 'ERROR'
        }
      } else {
        Write-Log -message ('{0} :: partition resizing skipped. drive {1}: ({2}) within expected size ({3})' -f $($MyInvocation.MyCommand.Name, $drive, [math]::Round($oldSize/1GB, 2), [math]::Round($newSize/1GB, 2))) -severity 'DEBUG'
      }
    } else {
      Write-Log -message ('{0} :: partition resizing skipped on unsupported os' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-Pagefile {
  param (
    [switch] $isWorker = $false,
    [string] $lock = 'c:\dsc\in-progress.lock',
    [string] $name = 'y:\pagefile.sys',
    [int] $initialSize = 8192,
    [int] $maximumSize = 8192,
    [string] $workerType
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    switch -regex ($workerType) {
      '^(relops-image-builder|gecko-t-win7-32([-a-z]*)?)$' {
        if (($isWorker) -and (Test-Path -Path ('{0}:\' -f $name[0]) -ErrorAction SilentlyContinue) -and (@(Get-WmiObject Win32_PagefileSetting | ? { $_.Name -ieq $name }).length -lt 1)) {
          try {
            $computerSystem = (Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges)
            $computerSystem.AutomaticManagedPagefile = $false
            $computerSystem.Put()
            Write-Log -message ('{0} :: automatic managed pagefile disabled.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
          }
          catch {
            Write-Log -message ('{0} :: failed to disable automatic managed pagefile. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
          }
          Get-WmiObject Win32_PagefileSetting | ? { $_.Name.StartsWith('c:') } | % {
            $existingPagefileName = $_.Name
            try {
              $_.Delete()
              Write-Log -message ('{0} :: page file: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $existingPagefileName) -severity 'INFO'
            }
            catch {
              Write-Log -message ('{0} :: failed to delete page file: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $existingPagefileName, $_.Exception.Message) -severity 'ERROR'
            }
          }
          try {
            Set-WmiInstance -class Win32_PageFileSetting -Arguments @{name=$name;InitialSize=$initialSize;MaximumSize=$maximumSize}
            Write-Log -message ('{0} :: page file: {1}, created.' -f $($MyInvocation.MyCommand.Name), $name) -severity 'INFO'
            Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
            & shutdown @('-r', '-t', '0', '-c', ('page file {0} created' -f $name), '-f', '-d', 'p:2:4')
          }
          catch {
            Write-Log -message ('{0} :: failed to create pagefile: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $name, $_.Exception.Message) -severity 'ERROR'
          }
        } else {
          if (-not ($isWorker)) {
            Write-Log -message ('{0} :: skipping pagefile creation (not a worker).' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
          } elseif (-not (Test-Path -Path ('{0}:\' -f $name[0]) -ErrorAction SilentlyContinue)) {
            Write-Log -message ('{0} :: skipping pagefile creation ({1}: drive missing).' -f $($MyInvocation.MyCommand.Name), $name[0]) -severity 'INFO'
          } else {
            Write-Log -message ('{0} :: skipping pagefile creation ({1} exists).' -f $($MyInvocation.MyCommand.Name), $name) -severity 'INFO'
          }
        }
      }
      default {
        Write-Log -message ('{0} :: skipping pagefile creation (not configured for worker type: {1}).' -f $($MyInvocation.MyCommand.Name), $workerType) -severity 'INFO'
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
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
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    $driveLetterMap.Keys | % {
      $old = $_
      $new = $driveLetterMap.Item($_)
      if (Test-Path -Path ('{0}\' -f $old) -ErrorAction SilentlyContinue) {
        $volume = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter='$old'"
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
    $volumes = @(Get-WmiObject -Class Win32_Volume | sort-object { $_.Name })
    Write-Log -message ('{0} :: {1} volumes detected.' -f $($MyInvocation.MyCommand.Name), $volumes.length) -severity 'INFO'
    foreach ($volume in $volumes) {
      Write-Log -message ('{0} :: {1} {2}gb' -f $($MyInvocation.MyCommand.Name), $volume.Name.Trim('\'), [math]::Round($volume.Capacity/1GB,2)) -severity 'DEBUG'
    }
    $partitions = @(Get-WmiObject -Class Win32_DiskPartition | sort-object { $_.Name })
    Write-Log -message ('{0} :: {1} disk partitions detected.' -f $($MyInvocation.MyCommand.Name), $partitions.length) -severity 'INFO'
    foreach ($partition in $partitions) {
      Write-Log -message ('{0} :: {1}: {2}gb' -f $($MyInvocation.MyCommand.Name), $partition.Name, [math]::Round($partition.Size/1GB,2)) -severity 'DEBUG'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-Credentials {
  param (
    [string] $username,
    [string] $password,
    [switch] $setautologon
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    if (($username) -and ($password)) {
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
    } else {
      Write-Log -message ('{0} :: empty username or password.' -f $($MyInvocation.MyCommand.Name)) -severity 'ERROR'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function New-LocalCache {
  param (
    [string] $cacheDrive = $(if (Test-Path -Path 'Y:\' -ErrorAction SilentlyContinue) {'Y:'} else {$env:SystemDrive}),
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
      New-Item -Path $path -ItemType directory -force
      & 'icacls.exe' @($path, '/grant', 'Everyone:(OI)(CI)F')
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Create-ScheduledPowershellTask {
  param (
    [string] $taskName,
    [string] $scriptUrl,
    [string] $scriptPath,
    [string] $sc,
    [string] $mo = $null
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    # delete scheduled task if it pre-exists
    if ([bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
      try {
        Start-Process 'schtasks.exe' -ArgumentList @('/delete', '/tn', $taskName, '/f') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.schtask-{2}-delete.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $taskName) -RedirectStandardError ('{0}\log\{1}.schtask-{2}-delete.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $taskName)
        Write-Log -message ('{0} :: scheduled task: {1} deleted.' -f $($MyInvocation.MyCommand.Name), $taskName) -severity 'INFO'
      }
      catch {
        Write-Log -message ('{0} :: failed to delete scheduled task: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $taskName, $_.Exception.Message) -severity 'ERROR'
      }
    }
    # delete script if it pre-exists
    if (Test-Path -Path $scriptPath -ErrorAction SilentlyContinue) {
      Remove-Item -Path $scriptPath -confirm:$false -force
      Write-Log -message ('{0} :: {1} deleted.' -f $($MyInvocation.MyCommand.Name), $scriptPath) -severity 'INFO'
    }
    # download script
    try {
      (New-Object Net.WebClient).DownloadFile($scriptUrl, $scriptPath)
      Write-Log -message ('{0} :: {1} downloaded from {2}.' -f $($MyInvocation.MyCommand.Name), $scriptPath, $scriptUrl) -severity 'INFO'
    }
    catch {
      Write-Log -message ('{0} :: failed to download scheduled task script {1} from {2}. {3}' -f $($MyInvocation.MyCommand.Name), $scriptPath, $scriptUrl, $_.Exception.Message) -severity 'ERROR'
    }
    if (Test-Path -Path $scriptPath -ErrorAction SilentlyContinue) {
      # create scheduled task
      try {
        if ($mo) {
          Start-Process 'schtasks.exe' -ArgumentList @('/create', '/tn', $taskName, '/sc', $sc, '/mo', $mo, '/ru', 'SYSTEM', '/rl', 'HIGHEST', '/tr', ('"{0}\powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -File \"{1}\" -ExecutionPolicy RemoteSigned -ConsoleOutputFile \"{2}\" "' -f $pshome, $scriptPath, $scriptPath.Replace('.ps1', '-run.log')), '/f') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.schtask-{2}-create.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $taskName) -RedirectStandardError ('{0}\log\{1}.schtask-{2}-create.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $taskName)
        } else {
          Start-Process 'schtasks.exe' -ArgumentList @('/create', '/tn', $taskName, '/sc', $sc, '/ru', 'SYSTEM', '/rl', 'HIGHEST', '/tr', ('"{0}\powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -File \"{1}\" -ExecutionPolicy RemoteSigned -ConsoleOutputFile \"{2}\" "' -f $pshome, $scriptPath, $scriptPath.Replace('.ps1', '-run.log')), '/f') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.schtask-{2}-create.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $taskName) -RedirectStandardError ('{0}\log\{1}.schtask-{2}-create.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $taskName)
        }
        Write-Log -message ('{0} :: scheduled task: {1} created.' -f $($MyInvocation.MyCommand.Name), $taskName) -severity 'INFO'
      }
      catch {
        Write-Log -message ('{0} :: failed to create scheduled task: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $taskName, $_.Exception.Message) -severity 'ERROR'
      }
    } else {
      Write-Log -message ('{0} :: skipped creation of scheduled task: {1}. missing script: {2}' -f $($MyInvocation.MyCommand.Name), $taskName, $scriptPath) -severity 'ERROR'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Wipe-Drive {
  # derived from http://blog.whatsupduck.net/2012/03/powershell-alternative-to-sdelete.html
  param (
    [char] $drive,
    $percentFree = 0.05
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    $filename = "thinsan.tmp"
    $filePath = Join-Path ('{0}:\' -f $drive) $filename
    if (Test-Path $filePath -ErrorAction SilentlyContinue) {
      Remove-Item -Path $filePath -force -ErrorAction SilentlyContinue
    }
    $volume = (gwmi win32_volume -filter ("name='{0}:\\'" -f $drive))
    if ($volume) {
      $arraySize = 64kb
      $fileSize = $volume.FreeSpace - ($volume.Capacity * $percentFree)
      $zeroArray = new-object byte[]($arraySize)
      $stream = [io.File]::OpenWrite($filePath)
      try {
        $curfileSize = 0
        while ($curfileSize -lt $fileSize) {
          $stream.Write($zeroArray, 0, $zeroArray.Length)
          $curfileSize += $zeroArray.Length
        }
      } finally {
        if($stream) {
          $stream.Close()
        }
        if((Test-Path $filePath)) {
          del $filePath
        }
      }
    } else {
      Write-Log -message ('{0} :: unable to locate a volume mounted at {0}:' -f $($MyInvocation.MyCommand.Name), $drive) -severity 'ERROR'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Activate-Windows {
  param (
    [string] $keyManagementServiceMachine = '10.48.69.100',
    [int] $keyManagementServicePort = 1688
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    $productKeyMap = (Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Configuration/product-key-map.json?{0}' -f [Guid]::NewGuid()) -UseBasicParsing | ConvertFrom-Json)
    $osCaption = (Get-WmiObject -class Win32_OperatingSystem).Caption.Trim()
    $productKey = ($productKeyMap | ? {$_.os_caption -eq $osCaption}).product_key
    if (-not ([bool]$productKey)) {
      Write-Log -message ('{0} :: failed to determine product key with os caption: {1}.' -f $($MyInvocation.MyCommand.Name), $osCaption) -severity 'INFO'
      return
    }
    try {
      $sls = (Get-WMIObject SoftwareLicensingService)
      $sls.SetKeyManagementServiceMachine($keyManagementServiceMachine)
      Write-Log -message ('{0} :: SoftwareLicensingService.SetKeyManagementServiceMachine: {1}.' -f $($MyInvocation.MyCommand.Name), $keyManagementServiceMachine) -severity 'DEBUG'
      $sls.SetKeyManagementServicePort($keyManagementServicePort)
      Write-Log -message ('{0} :: SoftwareLicensingService.SetKeyManagementServicePort: {1}.' -f $($MyInvocation.MyCommand.Name), $keyManagementServicePort) -severity 'DEBUG'
      $sls.InstallProductKey($productKey)
      Write-Log -message ('{0} :: SoftwareLicensingService.InstallProductKey: {1}.' -f $($MyInvocation.MyCommand.Name), $productKey) -severity 'DEBUG'
      $sls.RefreshLicenseStatus()
      Write-Log -message ('{0} :: SoftwareLicensingService.RefreshLicenseStatus.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'

      $slp = (Get-WmiObject SoftwareLicensingProduct | ? { (($_.ApplicationId -eq '55c92734-d682-4d71-983e-d6ec3f16059f') -and ($_.PartialProductKey) -and (-not $_.LicenseIsAddon)) })
      $slp.SetKeyManagementServiceMachine($keyManagementServiceMachine)
      Write-Log -message ('{0} :: SoftwareLicensingProduct.SetKeyManagementServiceMachine: {1}.' -f $($MyInvocation.MyCommand.Name), $keyManagementServiceMachine) -severity 'DEBUG'
      $slp.SetKeyManagementServicePort($keyManagementServicePort)
      Write-Log -message ('{0} :: SoftwareLicensingProduct.SetKeyManagementServicePort: {1}.' -f $($MyInvocation.MyCommand.Name), $keyManagementServicePort) -severity 'DEBUG'
      $slp.Activate()
      Write-Log -message ('{0} :: SoftwareLicensingProduct.Activate.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'

      $sls.RefreshLicenseStatus()
      Write-Log -message ('{0} :: SoftwareLicensingService.RefreshLicenseStatus.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      
      Write-Log -message ('{0} :: Windows activated with product key: {1} ({2}) against {3}:{4}.' -f $($MyInvocation.MyCommand.Name), $productKey, $osCaption, $keyManagementServiceMachine, $keyManagementServicePort) -severity 'INFO'
      $licenseStatus = @('Unlicensed', 'Licensed', 'OOB Grace', 'OOT Grace', 'Non-Genuine Grace', 'Notification', 'Extended Grace')
      Write-Log -message ('{0} :: Windows licensing status. Product: {1}, Status: {2}.' -f $($MyInvocation.MyCommand.Name), $slp.Name, $licenseStatus[$slp.LicenseStatus]) -severity 'INFO'
    }
    catch {
      Write-Log -message ('{0} :: failed to activate Windows. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Import-RegistryHive {
  param(
    [string] $file,
    [string] $key,
    [string] $name
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    # check whether the drive name is available
    $testDrive = Get-PSDrive -Name $Name -ErrorAction SilentlyContinue
    if ($testDrive -ne $null) {
      $errorRecord = New-Object Management.Automation.ErrorRecord (
        (New-Object Management.Automation.SessionStateException("A drive with the name '$Name' already exists.")),
        'DriveNameUnavailable', [Management.Automation.ErrorCategory]::ResourceUnavailable, $null
      )
      $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    # load the registry hive from file using reg.exe
    $process = Start-Process -FilePath "$env:WINDIR\system32\reg.exe" -ArgumentList "load $Key $File" -WindowStyle Hidden -PassThru -Wait
    if ($process.ExitCode) {
      $errorRecord = New-Object Management.Automation.ErrorRecord(
        (New-Object Management.Automation.PSInvalidOperationException("The registry hive '$File' failed to load. Verify the source path or target registry key.")),
        'HiveLoadFailure', [Management.Automation.ErrorCategory]::ObjectNotFound, $null
      )
      $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    try {
      # create a global drive using the registry provider, with the root path as the previously loaded registry hive
      New-PSDrive -Name $Name -PSProvider Registry -Root $Key -Scope Global -ErrorAction Stop | Out-Null
    }
    catch {
      # validate patten on $Name in the Params and the drive name check at the start make it very unlikely New-PSDrive will fail
      $errorRecord = New-Object Management.Automation.ErrorRecord(
        (New-Object Management.Automation.PSInvalidOperationException("An unrecoverable error creating drive '$Name' has caused the registy key '$Key' to be left loaded, this must be unloaded manually.")),
        'DriveCreateFailure', [Management.Automation.ErrorCategory]::InvalidOperation, $null
      )
      $PSCmdlet.ThrowTerminatingError($errorRecord);
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Remove-RegistryHive {
  param (
    [string] $name
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    # get the drive that was used to map the registry hive
    $drive = Get-PSDrive -Name $name -ErrorAction SilentlyContinue
    # if $drive is $null the drive name was incorrect
    if ($drive -eq $null) {
      Write-Log -message ('{0} :: failed to load ps drive: "{1}"' -f $($MyInvocation.MyCommand.Name), $name) -severity 'Error'
      $errorRecord = New-Object Management.Automation.ErrorRecord(
        (New-Object Management.Automation.DriveNotFoundException('The drive "{0}" does not exist.' -f $name)),
        'DriveNotFound', [Management.Automation.ErrorCategory]::ResourceUnavailable, $null
      )
      $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    # $drive.Root is the path to the registry key, save this before the drive is removed
    $key = $drive.Root
    try {
      # remove the drive, the only reason this should fail is if the resource is busy
      Remove-PSDrive $name -ErrorAction Stop
    }
    catch {
      Write-Log -message ('{0} :: failed to remove ps drive: "{1}"' -f $($MyInvocation.MyCommand.Name), $name) -severity 'Error'
      $errorRecord = New-Object Management.Automation.ErrorRecord(
        (New-Object Management.Automation.PSInvalidOperationException('The drive "{0}" could not be removed, it may still be in use.' -f $name)),
        'DriveRemoveFailure', [Management.Automation.ErrorCategory]::ResourceBusy, $null)
      $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    $process = Start-Process -FilePath "$env:WINDIR\system32\reg.exe" -ArgumentList @('unload', $key) -WindowStyle Hidden -PassThru -Wait
    if ($process.ExitCode) {
      Write-Log -message ('{0} :: failed to unload registry key: "{1}"' -f $($MyInvocation.MyCommand.Name), $key) -severity 'Error'
      # if "reg unload" fails due to the resource being busy, the drive gets added back to keep the original state
      New-PSDrive -Name $Name -PSProvider Registry -Root $key -Scope Global -ErrorAction Stop | Out-Null
      $errorRecord = New-Object Management.Automation.ErrorRecord(
        (New-Object Management.Automation.PSInvalidOperationException('The registry key "{0}" could not be unloaded, it may still be in use.' -f $key)),
        'HiveUnloadFailure', [Management.Automation.ErrorCategory]::ResourceBusy, $null)
      $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-DefaultProfileProperties {
  param (
    [string] $path = 'C:\Users\Default\NTUSER.DAT',
    [object[]] $entries = @(
      New-Object PSObject -Property @{
        Key = 'Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects';
        ValueName = 'VisualFXSetting';
        ValueType = 'DWord';
        ValueData = 1
      }
    )
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    try {
      Import-RegistryHive -File $path -Key 'HKLM\TEMP_HIVE' -Name TempHive
      foreach ($entry in $entries) {
        if (-not (Test-Path -Path ('TempHive:\{0}' -f $entry.Key) -ErrorAction SilentlyContinue)) {
          New-Item -Path ('TempHive:\{0}' -f $entry.Key) -Force
          Write-Log -message ('{0} :: {1} created' -f $($MyInvocation.MyCommand.Name), $entry.Key) -severity 'DEBUG'
        }
        New-ItemProperty -Path ('TempHive:\{0}' -f $entry.Key) -Name $entry.ValueName -PropertyType $entry.ValueType -Value $entry.ValueData
        Write-Log -message ('{0} :: {1}\{2} set to {3}' -f $($MyInvocation.MyCommand.Name), $entry.Key, $entry.ValueName, $entry.ValueData) -severity 'DEBUG'
      }
      $attempt = 0 # attempt Remove-RegistryHive up to 3 times
      while($attempt -le 3) {
        try {
          $attempt++
          Remove-RegistryHive -Name TempHive
          Write-Log -message ('{0} :: temporary hive unloaded' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
          break
        }
        catch {
          if ($attempt -eq 3) {
            throw
          }
          Write-Log -message ('{0} :: temporary hive unload failed. retrying...' -f $($MyInvocation.MyCommand.Name)) -severity 'ERROR'
          Start-Sleep -Milliseconds 100
          [System.GC]::Collect()
        }
      }
    }
    catch {
      Write-Log -message ('{0} :: failed to set default profile properties. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-DefaultStrongCryptography {
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
    Write-Log -message ('{0} :: CLRVersion: {1}, PSVersion: {2}' -f $($MyInvocation.MyCommand.Name), $PSVersionTable['CLRVersion'], $PSVersionTable['PSVersion']) -severity 'DEBUG'
    Write-Log -message ('{0} :: SecurityProtocol: {1}' -f $($MyInvocation.MyCommand.Name), [Net.ServicePointManager]::SecurityProtocol) -severity 'DEBUG'
  }
  process {
    try {
      if ([Net.ServicePointManager]::SecurityProtocol -ne ([Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12)) {
        [Net.ServicePointManager]::SecurityProtocol = ([Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12)
        Write-Log -message ('{0} :: Added TLS v1.2 to security protocol support list for current powershell session' -f $($MyInvocation.MyCommand.Name))
      } else {
        Write-Log -message ('{0} :: Detected TLS v1.2 in security protocol support list' -f $($MyInvocation.MyCommand.Name))
      }
      if (-not (Get-WmiObject -class Win32_OperatingSystem).Caption.StartsWith('Microsoft Windows 7')) {
        if((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto').SchUseStrongCrypto -ne 1) {
          Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord
          Write-Log -message ('{0} :: Registry updated to use strong cryptography on 64 bit .Net Framework' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
        } else {
          Write-Log -message ('{0} :: Detected registry setting to use strong cryptography on 64 bit .Net Framework' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
        }
      }
      if((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto').SchUseStrongCrypto -ne 1) {
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord
        Write-Log -message ('{0} :: Registry updated to use strong cryptography on 32 bit .Net Framework' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
      } else {
        Write-Log -message ('{0} :: Detected registry setting to use strong cryptography on 32 bit .Net Framework' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      }
    }
    catch {
      Write-Log -message ('{0} :: failed to add strong cryptography (TLS v1.2) support. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
    }
  }
  end {
    Write-Log -message ('{0} :: SecurityProtocol: {1}' -f $($MyInvocation.MyCommand.Name), [Net.ServicePointManager]::SecurityProtocol) -severity 'DEBUG'
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Conserve-DiskSpace {
  param (
    [string[]] $paths = @(
      ('{0}\SoftwareDistribution\Download\*' -f $env:SystemRoot)
    )
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    # delete paths
    foreach ($path in $paths) {
      if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
        Remove-Item $path -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
        Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $path) -severity 'INFO'
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-SystemClock {
  param (
    [string] $locationType,
    [string] $ntpserverlist = $(if ($locationType -eq 'DataCenter') { "infoblox1.private.$MozSpace.mozilla.com" } else { '0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org' })
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    $timeService = Get-Service -Name 'w32time'
    if (($timeService) -and ($timeService.Status -ne 'Stopped')) {
      Write-Log -message ('{0} :: w32time service status: {1}. stopping...' -f $($MyInvocation.MyCommand.Name), $timeService.Status) -severity 'INFO'
      Stop-Service -InputObject $timeService
    }
    if ($timeService) {
      Write-Log -message ('{0} :: w32time service status: {1}' -f $($MyInvocation.MyCommand.Name), (Get-Service -Name 'w32time').Status) -severity 'INFO'
    } else {
      Write-Log -message ('{0} :: w32time service is unregistered' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
    }
    try {
      Start-Process 'tzutil' -ArgumentList @('/s', 'UTC') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.tzutil-utc.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.tzutil-utc.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      Write-Log -message ('{0} :: system timezone set to UTC.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
    }
    catch {
      Write-Log -message ('{0} :: failed to set system timezone to UTC. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
    }
    if ($timeService) {
      try {
        Start-Process 'w32tm' -ArgumentList @('/unregister') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.w32tm-unregister.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.w32tm-unregister.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
        Write-Log -message ('{0} :: time service unregistered.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
      }
      catch {
        Write-Log -message ('{0} :: failed to unregister time service. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
      }
    }
    try {
      Start-Process 'w32tm' -ArgumentList @('/register') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.w32tm-register.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.w32tm-register.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      Write-Log -message ('{0} :: time service registered.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
    }
    catch {
      Write-Log -message ('{0} :: failed to register time service. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
    }
    try {
      Start-Process 'w32tm' -ArgumentList @('/config', '/syncfromflags:manual', '/update', ('/manualpeerlist:"{0}",0x8' -f $ntpserverlist)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.w32tm-config.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.w32tm-config.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      Write-Log -message ('{0} :: time service configured with peerlist: {1}' -f $($MyInvocation.MyCommand.Name), $ntpserverlist) -severity 'INFO'
    }
    catch {
      Write-Log -message ('{0} :: failed to configure time service with peerlist: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $ntpserverlist, $_.Exception.Message) -severity 'ERROR'
    }
    $timeService = Get-Service -Name 'w32time'
    if ($timeService.Status -ne 'Running') {
      Write-Log -message ('{0} :: w32time service status: {1}. starting...' -f $($MyInvocation.MyCommand.Name), $timeService.Status) -severity 'INFO'
      Start-Service -InputObject $timeService
    }
    Write-Log -message ('{0} :: w32time service status: {1}' -f $($MyInvocation.MyCommand.Name), (Get-Service -Name 'w32time').Status) -severity 'INFO'
    try {
      Start-Process 'w32tm' -ArgumentList @('/resync', '/force') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.w32tm-resync.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.w32tm-resync.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      Write-Log -message ('{0} :: time service resynchronised.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
    }
    catch {
      Write-Log -message ('{0} :: failed to resynchronise time service. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-NetworkRoutes {
  param (
    [string[]] $destinationPrefixes = @(
      '169.254.169.254/32',
      '169.254.169.250/32',
      '169.254.169.251/32'
    )
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
      'Microsoft Windows Server 2016*' {
        # handle miscofingured routing for meta/user data (see: https://serverfault.com/questions/844494/aws-instance-not-access-metadata-server-with-ip#comment1172021_844494)
        $defaultNetIPConfig = @(Get-NetIPConfiguration | Sort-Object -Property 'InterfaceIndex')[0]
        foreach ($destinationPrefix in $destinationPrefixes) {
          try {
            foreach ($policyStore in @('ActiveStore', 'PersistentStore')) {
              $netRoute = @(Get-NetRoute -DestinationPrefix $destinationPrefix -PolicyStore $policyStore)
              if (($netRoute.Length) -and ($netRoute[0].NextHop -ne $defaultNetIPConfig.IPv4DefaultGateway.NextHop)) {
                Remove-NetRoute -DestinationPrefix $destinationPrefix -PolicyStore $policyStore -Confirm:$false -ErrorAction SilentlyContinue
                Write-Log -message ('{0} :: network route for prefix: {1} removed from policy store: {2}' -f $($MyInvocation.MyCommand.Name), $destinationPrefix, $policyStore) -severity 'DEBUG'
              }
            }
            if (@(Get-NetRoute -DestinationPrefix $destinationPrefix).Length -lt 1) {
              New-NetRoute -DestinationPrefix $destinationPrefix -InterfaceIndex $defaultNetIPConfig.InterfaceIndex -NextHop $defaultNetIPConfig.IPv4DefaultGateway.NextHop -RouteMetric 1 -ErrorAction Stop
              Write-Log -message ('{0} :: network route for prefix: {1} added.' -f $($MyInvocation.MyCommand.Name), $destinationPrefix) -severity 'INFO'
            }
          }
          catch {
            Write-Log -message ('{0} :: failed to correct network route for prefix: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $destinationPrefix, $_.Exception.Message) -severity 'ERROR'
          }
        }
      }
      default {
        Write-Log -message ('{0} :: skipping network route correction (not configured for OS: {1}).' -f $($MyInvocation.MyCommand.Name), (Get-WmiObject -class Win32_OperatingSystem).Caption) -severity 'INFO'
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function hw-DiskManage {
  param (
    [string[]] $paths = @(
      ('{0}Program Files\rempl\Logs' -f $env:SystemDrive),
      ('{0}\SoftwareDistribution\Download\*' -f $env:SystemRoot),
      ('{0}\ProgramData\Package Cache' -f $env:SystemDrive)
    ),
    [string] $olddscfiles = '{0}\log' -f $env:SystemDrive,
    [string] $oldwindowslog = '{0}\Windows\logs' -f $env:SystemDrive,
    [string] $driveletter = (get-location).Drive.Name,
    [string] $lock = 'c:\dsc\in-progress.lock',
    [string] $WarnPercent = .55,
    [string] $StopPercent = .20
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    foreach ($path in $paths) {
      if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
      Remove-Item $path -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
      Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $path) -severity 'INFO'
      }
    }
    Get-ChildItem $olddscfiles -Recurse | ? {-Not $_.PsIsContainer -And ($_.LastWriteTime -lt (Get-Date).AddDays(-1))} | Remove-Item -force -ErrorAction SilentlyContinue
    Get-ChildItem $oldwindowslog -Recurse | ? {-Not $_.PsIsContainer -And ($_.LastWriteTime -lt (Get-Date).AddDays(-7))} |  Remove-Item -force -ErrorAction SilentlyContinue
    Clear-RecycleBin -force -ErrorAction SilentlyContinue
    $freespace = Get-WmiObject -Class Win32_logicalDisk | ? {$_.DriveType -eq '3'}
    $percentfree = $freespace.FreeSpace / $freespace.Size
    $freeB = $freespace.FreeSpace
    $freeMB =  [math]::Round($freeB / 1000000)
    $perfree = [math]::Round($percentfree,2)*100
    Write-Log -message "Current free space of drive $driveletter $freeMB MB"  -severity 'INFO' 
    Write-Log -message "Current free space percentage of drive $driveletter $perfree%" -severity 'INFO'
    if ($percentfree -lt $WarnPercent) {
      Write-Log -message "Current available disk space WARNING $perfree%" -severity 'WARN'
      Write-Log -message "Attempting to clean and optimize disk" -severity 'WARN'
      Start-Process -Wait Dism.exe /online /Cleanup-Image /StartComponentCleanup
      Start-Process -Wait cleanmgr.exe /autoclean
      optimize-Volume $driveletter
      $freespace = Get-WmiObject -Class Win32_logicalDisk | ? {$_.DriveType -eq '3'}
      $percentfree = $freespace.FreeSpace / $freespace.Size
      $freeMB =  [math]::Round($freeB / 1000000)
      $perfree = [math]::Round($percentfree,2)*100
      Write-Log -message "Current free space of drive post clean and optimize disk $driveletter $freeMB MB"  -severity 'INFO' 
      Write-Log -message "Current free space percentage of drive post clean and optimize disk $driveletter $perfree %" -severity 'INFO'
    }
    if ($percentfree -lt $StopPercent) {
      $TimeStart = Get-Date
      $TimeEnd = $timeStart.addminutes(1)
      do {
        $TimeNow = Get-Date
        Write-Log -message "Current available disk space CRITCAL $perfree% free. Will not start Generic-Worker!" -severity 'Error' 
        Sleep 15
      } until ($TimeNow -ge $TimeEnd)
      Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
      & shutdown @('-s', '-t', '0', '-c', 'Restarting disk space Critical', '-f', '-d', 'p:2:4') | Out-File -filePath $logFile -append
      exit
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}

# Before doing anything else, make sure we are using TLS 1.2
# See https://bugzilla.mozilla.org/show_bug.cgi?id=1443595 for context.
Set-DefaultStrongCryptography
Set-NetworkRoutes

# SourceRepo is in place to toggle between production and testing environments
$SourceRepo = 'mozilla-releng'

# The Windows update service needs to be enabled for OCC to process but needs to be disabled during testing. 
$UpdateService = Get-Service -Name wuauserv
if ($UpdateService.Status -ne 'Running') {
  Start-Service $UpdateService
  Write-Log -message 'Enabling Windows update service'
} else {
  Write-Log -message 'Windows update service is running'
}

if ((Get-Service 'Ec2Config' -ErrorAction SilentlyContinue) -or (Get-Service 'AmazonSSMAgent' -ErrorAction SilentlyContinue)) {
  $locationType = 'AWS'
} else {
  $locationType = 'DataCenter'
  $SearchDomain = (Get-ItemProperty 'HKLM:SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters').'NV Domain'
  $MozSpace =  $SearchDomain -replace ".mozilla.com$"
}
$lock = 'C:\dsc\in-progress.lock'
if (Test-Path -Path $lock -ErrorAction SilentlyContinue) {
  if ((Get-CimInstance Win32_Process -Filter "name = 'powershell.exe'" | ? { $_.CommandLine -eq 'powershell.exe -File C:\dsc\rundsc.ps1' }).Length -gt 1) {
    Write-Log -message 'userdata run aborted. lock file exists and alternate powershell rundsc process detected.' -severity 'INFO'
    exit
  }
  Write-Log -message 'lock file exists but alternate powershell rundsc process not detected.' -severity 'WARN'
} elseif ((@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).length -gt 0)) {
  Write-Log -message 'userdata run aborted. generic-worker is running.' -severity 'INFO'
  exit
} else {
  $lockDir = [IO.Path]::GetDirectoryName($lock)
  if (-not (Test-Path -Path $lockDir -ErrorAction SilentlyContinue)) {
    New-Item -Path $lockDir -ItemType directory -force
  }
  New-Item $lock -type file -force
}
if ($locationType -eq 'DataCenter') {
  hw-DiskManage
}
Write-Log -message 'userdata run starting.' -severity 'INFO'
Set-SystemClock -locationType $locationType

# set up a log folder, an execution policy that enables the dsc run and a winrm envelope size large enough for the dynamic dsc.
$logFile = ('{0}\log\{1}.userdata-run.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
New-Item -ItemType Directory -Force -Path ('{0}\log' -f $env:SystemDrive)

if ($locationType -ne 'DataCenter') {
  try {
    $userdata = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/user-data')
  } catch {
    $userdata = $null
  }
  $publicKeys = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-keys')

  if ($publicKeys.StartsWith('0=mozilla-taskcluster-worker-')) {
    # ami creation instance
    $isWorker = $false
    $workerType = $publicKeys.Replace('0=mozilla-taskcluster-worker-', '')
    Activate-Windows
  } else {
    # provisioned worker
    $isWorker = $true
    $workerType = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/user-data' -UseBasicParsing | ConvertFrom-Json).workerType
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
    'us-east-2*'{
      $dnsRegion = 'use2'
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
  try {
    $rootPassword = [regex]::matches($userdata, '<rootPassword>(.*)<\/rootPassword>')[0].Groups[1].Value
  }
  catch {
    $rootPassword = $null
  }
  switch -wildcard ($workerType) {
    'gecko-t-win7-*' {
      $runDscOnWorker = $true
      $renameInstance = $true
      $setFqdn = $true
      if (-not ($isWorker)) {
        Remove-LegacyStuff -logFile $logFile
        Set-Credentials -username 'root' -password ('{0}' -f $rootPassword)
      }
    }
    'gecko-t-win10-*' {
      $runDscOnWorker = $true
      $renameInstance = $true
      $setFqdn = $true
      if (-not ($isWorker)) {
        Remove-LegacyStuff -logFile $logFile
        Set-Credentials -username 'Administrator' -password ('{0}' -f $rootPassword)
      }
    }
    default {
      $runDscOnWorker = $true
      $renameInstance = $true
      $setFqdn = $true
      if (-not ($isWorker)) {
        Set-Credentials -username 'Administrator' -password ('{0}' -f $rootPassword)
      }
    }
  }
  Write-Log -message ('runDscOnWorker: {0}, renameInstance: {1}, setFqdn: {2}.' -f $runDscOnWorker, $renameInstance, $setFqdn) -severity 'DEBUG'
  $instanceType = ((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/instance-type'))
  Write-Log -message ('instanceType: {0}.' -f $instanceType) -severity 'INFO'
  [Environment]::SetEnvironmentVariable("TASKCLUSTER_INSTANCE_TYPE", "$instanceType", "Machine")

  # workaround for windows update failures on g3 instances
  # https://support.microsoft.com/en-us/help/10164/fix-windows-update-errors
  #if ($instanceType.StartsWith('g3.')) {
  #  try {
  #    & dism.exe @('/Online', '/Cleanup-image', '/Restorehealth') | Out-File -filePath $logFile -append
  #    Write-Log -message 'executed: dism cleanup.' -severity 'DEBUG'
  #  }
  #  catch {
  #    Write-Log -message ('failed to run dism cleanup. {0}' -f $_.Exception.Message) -severity 'ERROR'
  #  }
  #  try {
  #    & sfc @('/scannow') | Out-File -filePath $logFile -append
  #    Write-Log -message 'executed: sfc scan.' -severity 'DEBUG'
  #  }
  #  catch {
  #    Write-Log -message ('failed to run sfc scan. {0}' -f $_.Exception.Message) -severity 'ERROR'
  #  }
  #}

  Mount-DiskOne -lock $lock
  if ($isWorker) {
    Resize-DiskZero
  }
  Set-Pagefile -isWorker:$isWorker -lock $lock -workerType $workerType
  # reattempt drive mapping for up to 10 minutes
  $driveMapTimeout = (Get-Date).AddMinutes(10)
  do {
    if (((Get-WmiObject -class Win32_OperatingSystem).Caption.Contains('Windows 10')) -and (($instanceType.StartsWith('c5.')) -or ($instanceType.StartsWith('g3.'))) -and (Test-Path -Path 'Z:\' -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path 'Y:\' -ErrorAction SilentlyContinue)) -and ((Get-WmiObject Win32_LogicalDisk | ? { $_.DeviceID -eq 'Z:' }).Size -ge 119GB)) {
      Resize-DiskOne
    }
    Map-DriveLetters
    Sleep 60
  } while (((-not (Test-Path -Path 'Z:\' -ErrorAction SilentlyContinue)) -or (-not (Test-Path -Path 'Y:\' -ErrorAction SilentlyContinue))) -and (Get-Date) -lt $driveMapTimeout)
  if ($isWorker) {
    if (($isWorker) -and (-not (Test-Path -Path 'Z:\' -ErrorAction SilentlyContinue))) {
      Write-Log -message 'missing task drive. terminating instance...' -severity 'ERROR'
      & shutdown @('-s', '-t', '0', '-c', 'missing task drive', '-f', '-d', '1:1') | Out-File -filePath $logFile -append
    }
    if (($isWorker) -and (-not (Test-Path -Path 'Y:\' -ErrorAction SilentlyContinue))) {
      Write-Log -message 'missing cache drive. terminating instance...' -severity 'ERROR'
      & shutdown @('-s', '-t', '0', '-c', 'missing cache drive', '-f', '-d', '1:1') | Out-File -filePath $logFile -append
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
  Write-Log -message ('instanceId: {0}, dnsHostname: {1}.' -f $instanceId, $dnsHostname) -severity 'INFO'
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
    # Turn off DNS address registration (EC2 DNS is configured to not allow it)
    foreach($nic in (Get-WmiObject "Win32_NetworkAdapterConfiguration where IPEnabled='TRUE'")) {
      $nic.SetDynamicDNSRegistration($false)
      Write-Log -message ('dynamic dns registration disabled on network interface {0} ({1})' -f $nic.Index, $nic.Description) -severity 'DEBUG'
    }
  }
  Write-Log -message ('instanceId: {0}, dnsHostname: {1}.' -f $instanceId, $dnsHostname) -severity 'INFO'
}
if ($rebootReasons.length) {
  Write-Log -message ('reboot required: {0}' -f [string]::Join(', ', $rebootReasons)) -severity 'DEBUG'
  Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
  & shutdown @('-r', '-t', '0', '-c', [string]::Join(', ', $rebootReasons), '-f', '-d', 'p:4:1') | Out-File -filePath $logFile -append
} else {
  if ($locationType -ne 'DataCenter') {
    # create a scheduled task to run HaltOnIdle every 2 minutes
    Create-ScheduledPowershellTask -taskName 'HaltOnIdle' -scriptUrl ('https://raw.githubusercontent.com/{0}/OpenCloudConfig/master/userdata/HaltOnIdle.ps1?{1}' -f $SourceRepo, [Guid]::NewGuid()) -scriptPath 'C:\dsc\HaltOnIdle.ps1' -sc 'minute' -mo '2'
  }
  # create a scheduled task to run system maintenance on startup
  Create-ScheduledPowershellTask -taskName 'MaintainSystem' -scriptUrl ('https://raw.githubusercontent.com/{0}/OpenCloudConfig/master/userdata/MaintainSystem.ps1?{1}' -f $SourceRepo, [Guid]::NewGuid()) -scriptPath 'C:\dsc\MaintainSystem.ps1' -sc 'onstart'
  if ($locationType -eq 'DataCenter') {
    $isWorker = $true
    $runDscOnWorker = $true
  }
  if (($runDscOnWorker) -or (-not ($isWorker)) -or ("$env:RunDsc" -ne "")) {

    # pre dsc setup ###############################################################################################################################################
    switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
      'Microsoft Windows 7*' {
        # set network interface to private (reverted after dsc run) http://www.hurryupandwait.io/blog/fixing-winrm-firewall-exception-rule-not-working-when-internet-connection-type-is-set-to-public
        ([Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))).GetNetworkConnections() | % { $_.GetNetwork().SetCategory(1) }
        # this setting persists only for the current session
        Enable-PSRemoting -Force
        #if (-not ($isWorker)) {
        #  Set-DefaultProfileProperties
        #}
      }
      'Microsoft Windows 10*' {
        # set network interface to private (reverted after dsc run) http://www.hurryupandwait.io/blog/fixing-winrm-firewall-exception-rule-not-working-when-internet-connection-type-is-set-to-public
        ([Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))).GetNetworkConnections() | % { $_.GetNetwork().SetCategory(1) }
        # this setting persists only for the current session
        Enable-PSRemoting -SkipNetworkProfileCheck -Force
        #if (-not ($isWorker)) {
        #  Set-DefaultProfileProperties
        #}
      }
      default {
        # this setting persists only for the current session
        Enable-PSRemoting -SkipNetworkProfileCheck -Force
      }
    }
    Set-ExecutionPolicy RemoteSigned -force | Out-File -filePath $logFile -append
    & cmd @('/c', 'winrm', 'set', 'winrm/config', '@{MaxEnvelopeSizekb="32696"}')
    & cmd @('/c', 'winrm', 'set', 'winrm/config', '@{MaxTimeoutms="180000"}')
    $transcript = ('{0}\log\{1}.dsc-run.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
    # end pre dsc setup ###########################################################################################################################################

    # run dsc #####################################################################################################################################################
    Start-Transcript -Path $transcript -Append
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force
    if (-not (Get-Module -ListAvailable -Name xPSDesiredStateConfiguration)) {
      Install-Module -Name xPSDesiredStateConfiguration -Force
    }
    if (-not (Get-Module -ListAvailable -Name xWindowsUpdate)) {
      Install-Module -Name xWindowsUpdate -Force
    }
    Run-RemoteDesiredStateConfig -url "https://raw.githubusercontent.com/$SourceRepo/OpenCloudConfig/master/userdata/xDynamicConfig.ps1" -workerType $workerType
    
    Stop-Transcript
    # end run dsc #################################################################################################################################################
    
    # post dsc teardown ###########################################################################################################################################
    if (((Get-Content $transcript) | % { (($_ -match 'requires a reboot') -or ($_ -match 'reboot is required')) }) -contains $true) {
      Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
      & shutdown @('-r', '-t', '0', '-c', 'a package installed by dsc requested a restart', '-f', '-d', 'p:4:2') | Out-File -filePath $logFile -append
    }
    if (($locationType -ne 'DataCenter') -and (((Get-Content $transcript) | % { ($_ -match 'failed to execute Set-TargetResource') }) -contains $true)) {
      Write-Log -message 'dsc run failed.' -severity 'ERROR'
      if (-not ($isWorker)) {
        # if this is the ami creation instance, we don't have a way to communicate with the taskcluster-github job to tell it that the dsc run has failed.
        # the best we can do is sleep until the taskcluster-github job fails, because of a task timeout.
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while ($timer.Elapsed.TotalHours -lt 5) {
          Write-Log -message ('waiting for occ ci task to fail due to timeout. shutdown in {0} minutes.' -f [Math]::Round(((5 * 60) - $timer.Elapsed.TotalMinutes))) -severity 'WARN'
          Start-Sleep -Seconds 600
        }
        & shutdown @('-s', '-t', '0', '-c', 'dsc run failed', '-f', '-d', 'p:2:4') | Out-File -filePath $logFile -append
      }
    }
    switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
      'Microsoft Windows 7*' {
        # set network interface to public
        ([Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))).GetNetworkConnections() | % { $_.GetNetwork().SetCategory(0) }
      }
      'Microsoft Windows 10*' {
        # set network interface to public
        ([Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))).GetNetworkConnections() | % { $_.GetNetwork().SetCategory(0) }
      }
    }
    # end post dsc teardown #######################################################################################################################################

    # create a scheduled task to run dsc at startup
    Create-ScheduledPowershellTask -taskName 'RunDesiredStateConfigurationAtStartup' -scriptUrl ('https://raw.githubusercontent.com/{0}/OpenCloudConfig/master/userdata/rundsc.ps1?{1}' -f $SourceRepo, [Guid]::NewGuid()) -scriptPath 'C:\dsc\rundsc.ps1' -sc 'onstart'
  }
  if (($isWorker) -and (-not ($runDscOnWorker))) {
    Stop-DesiredStateConfig
    Remove-DesiredStateConfigTriggers
    New-LocalCache
  }
  #if ($isWorker) {
    # test disk conservation on beta workers only
    #if ($workerType.EndsWith('-beta') -or $workerType.EndsWith('-gpu-b')) {
    #  Conserve-DiskSpace
    #}
  #}


  # archive dsc logs
  Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and $_.Length -eq 0 } | % { Remove-Item -Path $_.FullName -Force }
  New-ZipFile -ZipFilePath $logFile.Replace('.log', '.zip') -Item @(Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and $_.FullName -ne $logFile } | % { $_.FullName })
  Write-Log -message ('log archive {0} created.' -f $logFile.Replace('.log', '.zip')) -severity 'INFO'
  Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and (-not $_.Name.EndsWith('.dsc-run.log')) -and $_.FullName -ne $logFile } | % { Remove-Item -Path $_.FullName -Force }

  if ((-not ($isWorker)) -and (Test-Path -Path 'C:\generic-worker\run-generic-worker.bat' -ErrorAction SilentlyContinue)) {
    Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
    if ($locationType -ne 'DataCenter') {
      switch -regex ($workerType) {
        # level 3 builder needs key added by user intervention and must already exist in cot repo
        '^gecko-3-b-win2012(-c[45])?$' {
          while ((-not (Test-Path -Path 'C:\generic-worker\cot.key' -ErrorAction SilentlyContinue)) -or (@(Get-Process | ? { $_.ProcessName -eq 'rdpclip' }).length -gt 0)) {
            Write-Log -message 'cot key missing. awaiting user intervention.' -severity 'WARN'
            Sleep 60
          }
          if (Test-Path -Path 'C:\generic-worker\cot.key' -ErrorAction SilentlyContinue) {
            & icacls @('C:\generic-worker\cot.key', '/grant', 'Administrators:(GA)')
            & icacls @('C:\generic-worker\cot.key', '/inheritance:r')
            Write-Log -message 'cot key detected. shutting down.' -severity 'INFO'
            & shutdown @('-s', '-t', '0', '-c', 'dsc run complete', '-f', '-d', 'p:2:4') | Out-File -filePath $logFile -append
          } else {
            Write-Log -message 'cot key intervention failed. awaiting timeout or cancellation.' -severity 'ERROR'
          }
        }
        # all other workers can generate new keys. these don't require trust from cot repo
        default {
          if (-not (Test-Path -Path 'C:\generic-worker\cot.key' -ErrorAction SilentlyContinue)) {
            Write-Log -message 'cot key missing. generating key.' -severity 'WARN'
            & 'C:\generic-worker\generic-worker.exe' @('new-openpgp-keypair', '--file', 'C:\generic-worker\cot.key') | Out-File -filePath $logFile -append
            if (Test-Path -Path 'C:\generic-worker\cot.key' -ErrorAction SilentlyContinue) {
              Write-Log -message 'cot key generated.' -severity 'INFO'
            } else {
              Write-Log -message 'cot key generation failed.' -severity 'ERROR'
            }
          }
          if (Test-Path -Path 'C:\generic-worker\cot.key' -ErrorAction SilentlyContinue) {
            Write-Log -message 'cot key detected. shutting down.' -severity 'INFO'
            & shutdown @('-s', '-t', '0', '-c', 'dsc run complete', '-f', '-d', 'p:2:4') | Out-File -filePath $logFile -append
          } else {
            Write-Log -message 'cot key missing. awaiting timeout or cancellation.' -severity 'INFO'
          }
          if (@(Get-Process | ? { $_.ProcessName -eq 'rdpclip' }).length -eq 0) {
            & shutdown @('-s', '-t', '0', '-c', 'dsc run complete', '-f', '-d', 'p:2:4') | Out-File -filePath $logFile -append
          }
        }
      }
    }
  } elseif ($isWorker) {
    if ($locationType -ne 'DataCenter') {
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
        Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
        if ($locationType -eq 'DataCenter') {
          Remove-Item -Path C:\dsc\task-claim-state.valid -force -ErrorAction SilentlyContinue
        }
        & shutdown @('-r', '-t', '0', '-c', 'reboot to rouse the generic worker', '-f', '-d', '4:5') | Out-File -filePath $logFile -append
      } else {
        $timer.Stop()
        Write-Log -message ('generic-worker running process detected {0} ms after task-claim-state.valid flag set.' -f $timer.ElapsedMilliseconds) -severity 'INFO'
        if (Test-Path -Path $lock -ErrorAction SilentlyContinue) {
          Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
        }
        $gwProcess = (Get-Process | ? { $_.ProcessName -eq 'generic-worker' })
        if (($gwProcess) -and ($gwProcess.PriorityClass) -and ($gwProcess.PriorityClass -ne [Diagnostics.ProcessPriorityClass]::AboveNormal)) {
          $priorityClass = $gwProcess.PriorityClass
          $gwProcess.PriorityClass = [Diagnostics.ProcessPriorityClass]::AboveNormal
          Write-Log -message ('process priority for generic worker altered from {0} to {1}.' -f $priorityClass, $gwProcess.PriorityClass) -severity 'INFO'
          Stop-Service $UpdateService
        }
      }
    }
  }
}
if (Test-Path -Path $lock -ErrorAction SilentlyContinue) {
  Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
}
Write-Log -message 'userdata run completed' -severity 'INFO'
