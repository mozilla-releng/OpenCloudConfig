<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

function Write-Log {
  param (
    [string] $message,
    [string] $severity = 'INFO',
    [string] $source = 'HaltOnIdle',
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

function Get-Uptime {
  if ($lastBoot = (Get-WmiObject win32_operatingsystem | select @{LABEL='LastBootUpTime';EXPRESSION={$_.ConverttoDateTime($_.lastbootuptime)}}).LastBootUpTime) {
    $uptime = ((Get-Date) - $lastBoot)
    Write-Log -message ('{0} :: last boot: {1}; uptime: {2:c}.' -f $($MyInvocation.MyCommand.Name), $lastBoot, $uptime) -severity 'INFO'
    return $uptime
  } else {
    Write-Log -message ('{0} :: failed to determine last boot.' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
    return $false
  } 
}

function Is-ConditionTrue {
  param (
    [string] $proc,
    [bool] $predicate,
    [string] $activity = 'running',
    [string] $trueSeverity = 'INFO',
    [string] $falseSeverity = 'WARN'
  )
  if ($predicate) {
    Write-Log -message ('{0} :: {1} is {2}.' -f $($MyInvocation.MyCommand.Name), $proc, $activity) -severity $trueSeverity
  } else {
    Write-Log -message ('{0} :: {1} is not {2}.' -f $($MyInvocation.MyCommand.Name), $proc, $activity) -severity $falseSeverity
  }
  return $predicate
}

function Is-Terminating {
  param (
    [string] $locationType
  )
  switch ($locationType) {
    'AWS' {
      try {
        $response = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/spot/termination-time')
        $result = (-not ($response.Contains('(404)')))
      } catch {
        $result = $false
      }
      $isTerminating = (($result) -and ($response))
      break
    }
    default {
      $isTerminating = $false
      break
    }
  }
  Write-Log -message ('{0} :: locationType: {1}, isTerminating: {2}' -f $($MyInvocation.MyCommand.Name), $locationType, $isTerminating) -severity 'DEBUG'
  return $isTerminating
}

function Is-OpenCloudConfigRunning {
  return (Is-ConditionTrue -proc 'OpenCloudConfig' -predicate (Test-Path -Path 'C:\dsc\in-progress.lock' -ErrorAction SilentlyContinue))
}

function Is-GenericWorkerRunning {
  return (Is-ConditionTrue -proc 'generic-worker' -predicate (@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).length -gt 0))
}

function Is-RdpSessionActive {
  return (Is-ConditionTrue -proc 'remote desktop session' -predicate (@(Get-Process | ? { $_.ProcessName -eq 'rdpclip' }).length -gt 0) -activity 'active' -falseSeverity 'DEBUG')
}

function Get-PublicKeys {
  # just a helper function that fails quietly if no public keys are associated with the instance
  process {
    try {
      $publicKeys = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-keys')
    } catch {
      $publicKeys = ''
    }
    return $publicKeys
  }
}

function Is-Worker {
  param (
    [string] $locationType
  )
  switch ($locationType) {
    'AWS' {
      $isWorker = (-not ((Get-PublicKeys).StartsWith('0=mozilla-taskcluster-worker-')))
      break
    }
    'Azure' {
      $isWorker = (((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version={0}' -f '2019-06-04')).Content) | ConvertFrom-Json).compute.resourceGroupName.StartsWith('taskcluster-')
      break
    }
    default {
      $isWorker = $true
      break
    }
  }
  Write-Log -message ('{0} :: locationType: {1}, isWorker: {2}' -f $($MyInvocation.MyCommand.Name), $locationType, $isWorker) -severity 'DEBUG'
  return $isWorker
}

$locationType = $(
  if (Get-Service -Name @('Ec2Config', 'AmazonSSMAgent') -ErrorAction 'SilentlyContinue') {
    'AWS'
  } elseif ((Get-Service -Name 'GCEAgent' -ErrorAction 'SilentlyContinue') -or (Test-Path -Path ('{0}\GooGet\googet.exe' -f $env:ProgramData) -ErrorAction 'SilentlyContinue')) {
    'GCP'
  } elseif (Get-Service -Name @('WindowsAzureGuestAgent', 'WindowsAzureNetAgentSvc') -ErrorAction 'SilentlyContinue') {
    'Azure'
  } else {
    try {
      # on azure we may trigger occ before the agent is installed or we may not have installed the agent (32 bit systems). this is a quick check to verify if that is what's happening here.
      if ((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version={0}' -f '2019-06-04')).Content) {
        'Azure'
      }
    } catch {
      'DataCenter'
    }
  }
)

if ((Is-Terminating -locationType $locationType) -or (-not (Is-Worker -locationType $locationType))) {
  exit
}

foreach ($driveLetter in @('C', 'D', 'E', 'F', 'Y', 'Z')) {
  if (Test-Path -Path ('{0}:\' -f $driveLetter) -ErrorAction SilentlyContinue) {
    $drive = (Get-PSDrive -Name $driveLetter -ErrorAction 'SilentlyContinue')
    $volume = (Get-Volume -DriveLetter $driveLetter -ErrorAction 'SilentlyContinue')
    Write-Log -message ('drive {0}: exists with volume label {1}, {2:N2}gb used and {3:N2}gb free' -f $driveLetter, $volume.FileSystemLabel, ($drive.Used / 1Gb), ($drive.Free / 1Gb)) -severity 'DEBUG'
  } elseif (@('Y', 'Z').Contains($driveLetter)) {
    Write-Log -message ('drive {0}: does not exist' -f $driveLetter) -severity 'DEBUG'
  }
}

# prevent HaltOnIdle running before host rename has occured.
$expectedHostname = $(
  switch ($locationType) {
    'AWS' {
      (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/instance-id')
    }
    'GCP' {
      (New-Object Net.WebClient).DownloadString('http://169.254.169.254/computeMetadata/v1beta1/instance/name')
    }
    'Azure' {
      # todo: revisit this when we see what the worker manager sets instance names to
      (((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version={0}' -f '2019-06-04')).Content) | ConvertFrom-Json).compute.name
    }
    'DataCenter' {
      [System.Net.Dns]::GetHostName()
    }
  }
)
$dnsHostname = ([System.Net.Dns]::GetHostName())
if ($expectedHostname -ne $dnsHostname) {
  Write-Log -message ('productivity checks skipped. expected hostname: {0} does not match actual hostname: {1}.' -f $expectedHostname, $dnsHostname) -severity 'DEBUG'
  exit
}
try {
  $publicKeys = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-keys')
} catch {
  # handle worker manager instances that are created without keys
  $publicKeys = ''
}
if ($publicKeys.StartsWith('0=mozilla-taskcluster-worker-')) {
  Write-Log -message 'productivity checks skipped. ami creation instance detected.' -severity 'DEBUG'
  exit
}

if (-not (Is-GenericWorkerRunning)) {
  if (-not (Is-OpenCloudConfigRunning)) {
    $uptime = (Get-Uptime)
    if (($uptime) -and ($uptime -gt (New-TimeSpan -minutes 8))) {
      if (-not (Is-RdpSessionActive)) {
        switch ($locationType) {
          'AWS' {
            Write-Log -message ('instance failed productivity check and will be halted. uptime: {0}' -f $uptime) -severity 'ERROR'
            & shutdown @('-s', '-t', '0', '-c', 'HaltOnIdle :: instance failed productivity checks', '-f', '-d', 'p:4:1')
          }
          default {
            Write-Log -message ('instance failed productivity check and will be rebooted. uptime: {0}' -f $uptime) -severity 'ERROR'
            & shutdown @('-r', '-t', '0', '-c', 'HaltOnIdle :: instance failed productivity checks', '-f', '-d', 'p:4:1')
          }
        }
      } else {
        Write-Log -message 'instance failed productivity checks and would be halted, but has rdp session in progress.' -severity 'DEBUG'
      }
    } else {
      Write-Log -message 'instance failed productivity checks and will be retested shortly.' -severity 'WARN'
    }
  } else {
    try {
      $lastOccEventLog = (@(Get-EventLog -logName 'Application' -source 'OpenCloudConfig' -newest 1)[0])
      if (($lastOccEventLog.TimeGenerated) -lt ((Get-Date).AddHours(-1))) {
        Write-Log -message ('occ completed over an hour ago at: {0:u}, with message: {1}.' -f $lastOccEventLog.TimeGenerated, $lastOccEventLog.Message) -severity 'WARN'
        $gwLastLogWrite = (Get-Item 'C:\generic-worker\generic-worker.log').LastWriteTime
        if (($gwLastLogWrite) -lt ((Get-Date).AddHours(-1))) {
          switch ($locationType) {
            'AWS' {
              Write-Log -message ('generic worker log was last updated at: {0:u}, with message: {1}. halting...' -f $gwLastLogWrite, (Get-Content 'C:\generic-worker\generic-worker.log' -Tail 1)) -severity 'WARN'
              & shutdown @('-s', '-t', '30', '-c', 'HaltOnIdle :: instance failed to start generic worker', '-d', 'p:4:1')
            }
            default {
              Write-Log -message ('generic worker log was last updated at: {0:u}, with message: {1}. rebooting...' -f $gwLastLogWrite, (Get-Content 'C:\generic-worker\generic-worker.log' -Tail 1)) -severity 'WARN'
              & shutdown @('-r', '-t', '30', '-c', 'HaltOnIdle :: instance failed to start generic worker', '-d', 'p:4:1')
            }
          }
        }
      }
    }
    catch {
      Write-Log -message ('failed to determine occ or gw state: {0}' -f $_.Exception.Message) -severity 'ERROR'
    }
    Write-Log -message 'instance appears to be initialising.' -severity 'INFO'
  }
} else {
  Write-Log -message 'instance appears to be productive.' -severity 'DEBUG'
  $gwProcess = (Get-Process | ? { $_.ProcessName -eq 'generic-worker' })
  if (($gwProcess) -and ($gwProcess.PriorityClass) -and ($gwProcess.PriorityClass -ne [Diagnostics.ProcessPriorityClass]::AboveNormal)) {
    $priorityClass = $gwProcess.PriorityClass
    $gwProcess.PriorityClass = [Diagnostics.ProcessPriorityClass]::AboveNormal
    Write-Log -message ('process priority for generic worker altered from {0} to {1}.' -f $priorityClass, $gwProcess.PriorityClass) -severity 'INFO'
  }
}
if (Test-Path -Path 'y:\' -ErrorAction SilentlyContinue) {
  if (-not (Test-Path -Path 'y:\hg-shared' -ErrorAction SilentlyContinue)) {
    New-Item -Path 'y:\hg-shared' -ItemType directory -force
    Write-Log -message ('{0} :: y:\hg-shared created' -f $($MyInvocation.MyCommand.Name), $path) -severity 'INFO'
  } else {
    Write-Log -message ('{0} :: y:\hg-shared detected' -f $($MyInvocation.MyCommand.Name), $path) -severity 'DEBUG'
  }
  & icacls @('y:\hg-shared', '/grant', 'Everyone:(OI)(CI)F')
}
