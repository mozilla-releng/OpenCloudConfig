<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

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
function Install-SupportingModules {
  param (
    [string] $sourceOrg,
    [string] $sourceRepo,
    [string] $sourceRev,
    [string] $modulesPath = ('{0}\Modules' -f $pshome),
    [string[]] $moduleUrls = @(
      ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/OCC-Bootstrap.psm1' -f $sourceOrg, $sourceRepo, $sourceRev)
    )
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    foreach ($url in $moduleUrls) {
      $filename = [IO.Path]::GetFileName($url)
      $moduleName = [IO.Path]::GetFileNameWithoutExtension($filename)
      $modulePath = ('{0}\{1}' -f $modulesPath, $moduleName)
      if (Test-Path -Path $modulePath -ErrorAction SilentlyContinue) {
        try {
          Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
          Remove-Item -path $modulePath -recurse -force
          if (Test-Path -Path $modulePath -ErrorAction SilentlyContinue) {
            Write-Log -message ('{0} :: failed to remove module: {1}.' -f $($MyInvocation.MyCommand.Name), $moduleName) -severity 'ERROR'
          } else {
            Write-Log -message ('{0} :: removed module: {1}.' -f $($MyInvocation.MyCommand.Name), $moduleName) -severity 'DEBUG'
          }
        } catch {
          Write-Log -message ('{0} :: error removing module: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $moduleName, $_.Exception.Message) -severity 'ERROR'
        }
      }
      try {
        New-Item -ItemType Directory -Force -Path $modulePath
        (New-Object Net.WebClient).DownloadFile(('{0}?{1}' -f $url, [Guid]::NewGuid()), ('{0}\{1}' -f $modulePath, $filename))
        Unblock-File -Path ('{0}\{1}' -f $modulePath, $filename)
        if (Test-Path -Path $modulePath -ErrorAction SilentlyContinue) {
          Write-Log -message ('{0} :: installed module: {1}.' -f $($MyInvocation.MyCommand.Name), $moduleName) -severity 'DEBUG'
        } else {
          Write-Log -message ('{0} :: failed to install module: {1}.' -f $($MyInvocation.MyCommand.Name), $moduleName) -severity 'ERROR'
        }
      } catch {
        Write-Log -message ('{0} :: error installing module: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $moduleName, $_.Exception.Message) -severity 'ERROR'
      }
      try {
        Import-Module -Name $moduleName
        Write-Log -message ('{0} :: imported module: {1}.' -f $($MyInvocation.MyCommand.Name), $moduleName) -severity 'DEBUG'
      } catch {
        Write-Log -message ('{0} :: error importing module: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $moduleName, $_.Exception.Message) -severity 'ERROR'
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}

# modify sourceOrg and/or sourceRepo to toggle between testing environments
# todo: determine sourceOrg, sourceRepo, sourceRev from userdata and store in registry (bug 1406354)
$sourceOrg = $(if (Test-Path -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source\Organisation' -ErrorAction SilentlyContinue) { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Organisation').'Organisation' } else { 'mozilla-releng' })
$sourceRepo = $(if (Test-Path -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source\Repository' -ErrorAction SilentlyContinue) { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Repository').'Repository' } else { 'OpenCloudConfig' })
$sourceRev = $(if (Test-Path -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source\Revision' -ErrorAction SilentlyContinue) { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Revision').'Revision' } else { 'master' })

Install-SupportingModules -sourceOrg $sourceOrg -sourceRepo $sourceRepo -sourceRev $sourceRev
Run-OpenCloudConfig -sourceOrg $sourceOrg -sourceRepo $sourceRepo -sourceRev $sourceRev