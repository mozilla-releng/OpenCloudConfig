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
  if ((Get-Command 'New-EventLog' -ErrorAction 'SilentlyContinue') -and (!([Diagnostics.EventLog]::Exists($logName)) -or !([Diagnostics.EventLog]::SourceExists($source)))) {
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
  if (Get-Command 'Write-EventLog' -ErrorAction 'SilentlyContinue') {
    Write-EventLog -LogName $logName -Source $source -EntryType $entryType -Category 0 -EventID $eventId -Message $message
  } else {
    Write-Verbose -Message $message
  }
}

function Get-Uptime {
  if ((Get-Command 'Get-WmiObject' -ErrorAction 'SilentlyContinue') -and ($lastBoot = (Get-WmiObject win32_operatingsystem | select @{LABEL='LastBootUpTime';EXPRESSION={$_.ConverttoDateTime($_.lastbootuptime)}}).LastBootUpTime)) {
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
    [string] $locationType = $(if ((Get-Command 'Get-Service' -ErrorAction 'SilentlyContinue') -and ((Get-Service 'Ec2Config' -ErrorAction SilentlyContinue) -or (Get-Service 'AmazonSSMAgent' -ErrorAction SilentlyContinue))) { 'AWS' } elseif (((Get-Command 'Get-Service' -ErrorAction 'SilentlyContinue') -and (Get-Service 'GCEAgent' -ErrorAction SilentlyContinue)) -or (Test-Path -Path ('{0}\GooGet\googet.exe' -f $env:ProgramData) -ErrorAction 'SilentlyContinue')) { 'GCP' } else { 'DataCenter' })
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    switch ($locationType) {
      'EC2'{
        try {
          $response = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/spot/termination-time')
          $result = (-not ($response.Contains('(404)')))
        }
        catch {
          $result = $false
        }
        if (($result) -and ($response)) {
          Write-Log -message ('{0} :: spot termination notice received: {1}.' -f $($MyInvocation.MyCommand.Name), $response) -severity 'WARN'
        } else {
          #Write-Log -message ('{0} :: spot termination notice not detected.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
        }
        return [bool](($result) -and ($response))
      }
      'GCP'{
        try {
          $webClient = (New-Object -TypeName 'System.Net.WebClient')
          $webClient.Headers.Add('Metadata-Flavor', 'Google')
          $preempted = ($webClient.DownloadString('http://metadata.google.internal/computeMetadata/v1/instance/preempted', $localPath) -eq 'TRUE')
        } catch {
          $preempted = $false
        }
        if ($preempted) {
          Write-Log -message ('{0} :: gcp preemption notice received: {1}.' -f $($MyInvocation.MyCommand.Name), $response) -severity 'WARN'
        } else {
          #Write-Log -message ('{0} :: gcp preemption notice not detected.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
        }
        return $preempted
      }
      default {
        return $false
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}

function Is-OpenCloudConfigRunning {
  #return ((Is-ConditionTrue -proc 'OpenCloudConfig semaphore' -activity 'present' -predicate (Test-Path -Path 'C:\dsc\in-progress.lock' -ErrorAction SilentlyContinue)) -and (Is-ConditionTrue -proc 'OpenCloudConfig' -predicate ((Get-CimInstance Win32_Process -Filter "name = 'powershell.exe'" | ? { $_.CommandLine -eq 'powershell.exe -File C:\dsc\rundsc.ps1' }).Length -gt 0)))
  return (Is-ConditionTrue -proc 'OpenCloudConfig' -predicate (Test-Path -Path 'C:\dsc\in-progress.lock' -ErrorAction SilentlyContinue))
}

function Is-GenericWorkerRunning {
  return (Is-ConditionTrue -proc 'generic-worker' -predicate (@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).length -gt 0))
}

function Is-RdpSessionActive {
  return (Is-ConditionTrue -proc 'remote desktop session' -predicate (@(Get-Process | ? { $_.ProcessName -eq 'rdpclip' }).length -gt 0) -activity 'active' -falseSeverity 'DEBUG')
}

function Test-InstanceProductivity {
  param (
    [string] $locationType = $(if ((Get-Command 'Get-Service' -ErrorAction 'SilentlyContinue') -and ((Get-Service 'Ec2Config' -ErrorAction SilentlyContinue) -or (Get-Service 'AmazonSSMAgent' -ErrorAction SilentlyContinue))) { 'AWS' } elseif (((Get-Command 'Get-Service' -ErrorAction 'SilentlyContinue') -and (Get-Service 'GCEAgent' -ErrorAction SilentlyContinue)) -or (Test-Path -Path ('{0}\GooGet\googet.exe' -f $env:ProgramData) -ErrorAction 'SilentlyContinue')) { 'GCP' } else { 'DataCenter' })
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    if (Is-Terminating -locationType $locationType) {
      exit
    }
    # log the presence or absence of the Z: & Y: drives
    foreach ($drive in @('Y', 'Z')) {
      Is-ConditionTrue -proc ('drive {0}:' -f $drive) -activity 'detected' -predicate (Test-Path -Path ('{0}:\' -f $drive) -ErrorAction SilentlyContinue)
    }
    switch ($locationType) {
      'EC2'{
        # prevent productivity checks running before host rename has occured.
        $instanceId = ((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/instance-id'))
        $dnsHostname = ([System.Net.Dns]::GetHostName())
        if ($instanceId -ne $dnsHostname) {
          Write-Log -message ('{0} :: productivity checks skipped. instance id: {1} does not match hostname: {2}.' -f $($MyInvocation.MyCommand.Name), $instanceId, $dnsHostname) -severity 'DEBUG'
          exit
        }
        $publicKeys = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-keys')
        if ($publicKeys.StartsWith('0=mozilla-taskcluster-worker-')) {
          Write-Log -message ('{0} :: productivity checks skipped. ami creation instance detected.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
          exit
        }
      }
    }
    if (-not (Is-GenericWorkerRunning)) {
      if (-not (Is-OpenCloudConfigRunning)) {
        $uptime = (Get-Uptime)
        if (($uptime) -and ($uptime -gt (New-TimeSpan -minutes 8))) {
          if (-not (Is-RdpSessionActive)) {
            Write-Log -message ('{0} :: instance failed productivity check and will be halted. uptime: {1}' -f $($MyInvocation.MyCommand.Name), $uptime) -severity 'ERROR'
            & shutdown @('-s', '-t', '0', '-c', 'HaltOnIdle :: instance failed productivity checks', '-f', '-d', 'p:4:1')
          } else {
            Write-Log -message ('{0} :: instance failed productivity checks and would be halted, but has rdp session in progress.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
          }
        } else {
          Write-Log -message ('{0} :: instance failed productivity checks and will be retested shortly.' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
        }
      } else {
        try {
          $lastOccEventLog = (@(Get-EventLog -logName 'Application' -source 'OpenCloudConfig' -newest 1)[0])
          if (($lastOccEventLog.TimeGenerated) -lt ((Get-Date).AddHours(-1))) {
            Write-Log -message ('{0} :: occ completed over an hour ago at: {1:u}, with message: {2}.' -f $($MyInvocation.MyCommand.Name), $lastOccEventLog.TimeGenerated, $lastOccEventLog.Message) -severity 'WARN'
            $gwLastLogWrite = (Get-Item 'C:\generic-worker\generic-worker.log').LastWriteTime
            if (($gwLastLogWrite) -lt ((Get-Date).AddHours(-1))) {
              Write-Log -message ('{0} :: generic worker log was last updated at: {1:u}, with message: {2}.' -f $($MyInvocation.MyCommand.Name), $gwLastLogWrite, (Get-Content 'C:\generic-worker\generic-worker.log' -Tail 1)) -severity 'WARN'
              & shutdown @('-s', '-t', '30', '-c', 'HaltOnIdle :: instance failed to start generic worker', '-d', 'p:4:1')
            }
          }
        }
        catch {
          Write-Log -message ('{0} :: failed to determine occ or gw state: {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
        }
        Write-Log -message ('{0} :: instance appears to be initialising.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
      }
    } else {
      Write-Log -message ('{0} :: instance appears to be productive.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      $gwProcess = (Get-Process | ? { $_.ProcessName -eq 'generic-worker' })
      if (($gwProcess) -and ($gwProcess.PriorityClass) -and ($gwProcess.PriorityClass -ne [Diagnostics.ProcessPriorityClass]::AboveNormal)) {
        $priorityClass = $gwProcess.PriorityClass
        $gwProcess.PriorityClass = [Diagnostics.ProcessPriorityClass]::AboveNormal
        Write-Log -message ('{0} :: process priority for generic worker altered from {1} to {2}.' -f $($MyInvocation.MyCommand.Name), $priorityClass, $gwProcess.PriorityClass) -severity 'INFO'
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}

Test-InstanceProductivity