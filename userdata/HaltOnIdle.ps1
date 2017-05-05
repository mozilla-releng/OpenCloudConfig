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
  try {
    $response = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/spot/termination-time')
  }
  catch {
    $response = $_.Exception.Message
  }
  if (-not ($response.Contains('(404)'))) {
    Write-Log -message ('{0} :: spot termination notice received: {1}.' -f $($MyInvocation.MyCommand.Name), $response) -severity 'WARN'
    return $true
  } else {
    Write-Log -message ('{0} :: spot termination notice not detected.' -f $($MyInvocation.MyCommand.Name), $proc) -severity 'DEBUG'
    return $false
  }
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

function Is-DriveFormatInProgress {
  return (Is-ConditionTrue -proc 'drive format' -predicate (@(Get-Process | ? { $_.ProcessName -eq 'format.com' }).length -gt 0) -activity 'in progress' -falseSeverity 'DEBUG')
}

function Is-Loaner {
  return ((Test-Path -Path 'Z:\loan-request.json' -ErrorAction SilentlyContinue) -or (Test-Path -Path 'HKLM:\SOFTWARE\OpenCloudConfig\Loan' -ErrorAction SilentlyContinue))
}

if (Is-Terminating) {
  exit
}
if (Test-Path -Path 'Z:\' -ErrorAction SilentlyContinue) {
  Write-Log -message 'drive z: exists' -severity 'DEBUG'
} else {
  Write-Log -message 'drive z: does not exist' -severity 'DEBUG'
}
if (-not (Is-Loaner)) {
  if (-not (Is-GenericWorkerRunning)) {
    if (-not (Is-OpenCloudConfigRunning)) {
      $uptime = (Get-Uptime)
      if (($uptime) -and ($uptime -gt (New-TimeSpan -minutes 5))) {
        if ((-not (Is-RdpSessionActive)) -and (-not (Is-DriveFormatInProgress))) {
          Write-Log -message 'instance failed validity check and will be halted.' -severity 'ERROR'
          & shutdown @('-s', '-t', '0', '-c', 'HaltOnIdle :: instance failed validity checks', '-f', '-d', 'p:4:1')
        } else {
          Write-Log -message 'instance failed validity check and would be halted, but has rdp session in progress or is formatting a drive.' -severity 'DEBUG'
        }
      } else {
        Write-Log -message 'instance failed some validity checks and will be retested shortly.' -severity 'WARN'
      }
    } else {
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
  if ([IO.Directory]::GetFiles('C:\log', '*.zip').Count -gt 10) {
    Write-Log -message 'instance appears to be boot-looping and will be halted.' -severity 'ERROR'
    & shutdown @('-s', '-t', '0', '-c', 'HaltOnIdle :: boot-loop detected', '-f', '-d', 'p:4:1')
  }

  if (Test-Path -Path 'y:\' -ErrorAction SilentlyContinue) {
    if (-not (Test-Path -Path 'y:\hg-shared' -ErrorAction SilentlyContinue)) {
      New-Item -Path 'y:\hg-shared' -ItemType directory -force
    }
    & icacls @('y:\hg-shared', '/grant', 'Everyone:(OI)(CI)F')
  }
} else {
  Write-Log -message 'instance is a loaner.' -severity 'INFO'
  # todo: terminate abandoned or unused loaners
}