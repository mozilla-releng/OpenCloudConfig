<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

function Write-Log {
  param (
    [string] $message,
    [string] $severity = 'INFO',
    [string] $source = 'MaintainSystem',
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
  if ([Environment]::UserInteractive) {
    $fc = @{ 'Information' = 'White'; 'Error' = 'Red'; 'Warning' = 'DarkYellow'; 'SuccessAudit' = 'DarkGray' }[$entryType]
    Write-Host -object $message -ForegroundColor $fc
  }
}
function Run-MaintainSystem {
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    Remove-OldTaskDirectories
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Remove-OldTaskDirectories {
  param (
    [string[]] $targets = @('Z:\task_*', 'C:\Users\task_*')
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    foreach ($target in ($targets | ? { (Test-Path -Path ('{0}:\' -f $_[0]) -ErrorAction SilentlyContinue) })) {
      $all_task_paths = @(Get-ChildItem -Path $target | Sort-Object -Property { $_.LastWriteTime })
      if ($all_task_paths.length -gt 1) {
        Write-Log -message ('{0} task directories detected matching pattern: {1}' -f $all_task_paths.length, $target) -severity 'INFO'
        $old_task_paths = $all_task_paths[0..($all_task_paths.Length-2)]
        foreach ($old_task_path in $old_task_paths) {
          try {
            & takeown.exe @('/a', '/f', $old_task_path, '/r', '/d', 'Y')
            & icacls.exe @($old_task_path, '/grant', 'Administrators:F', '/t')
            Remove-Item -Path $old_task_path -Force -Recurse
            Write-Log -message ('removed task directory: {0}, with last write time: {1}' -f $old_task_path.FullName, $old_task_path.LastWriteTime) -severity 'INFO'
          } catch {
            Write-Log -message ('failed to remove task directory: {0}, with last write time: {1}. {2}' -f $old_task_path.FullName, $old_task_path.LastWriteTime, $_.Exception.Message) -severity 'ERROR'
          }
        }
      } elseif ($all_task_paths.length -eq 1) {
        Write-Log -message ('a single task directory was detected at: {0}, with last write time: {1}' -f $all_task_paths[0].FullName, $all_task_paths[0].LastWriteTime) -severity 'DEBUG'
      } else {
        Write-Log -message ('no task directories detected matching pattern: {0}' -f $target) -severity 'DEBUG'
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
Run-MaintainSystem
