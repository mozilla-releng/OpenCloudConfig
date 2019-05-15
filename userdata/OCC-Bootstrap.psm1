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
  if ((-not ([System.Diagnostics.EventLog]::Exists($logName))) -or (-not ([System.Diagnostics.EventLog]::SourceExists($source)))) {
    try {
      New-EventLog -LogName $logName -Source $source
    } catch {
      Write-Error -Exception $_.Exception -message ('failed to create event log source: {0}/{1}' -f $logName, $source)
    }
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
  try {
    Write-EventLog -LogName $logName -Source $source -EntryType $entryType -Category 0 -EventID $eventId -Message $message
  } catch {
    Write-Error -Exception $_.Exception -message ('failed to write to event log source: {0}/{1}. the log message was: {2}' -f $logName, $source, $message)
  }
  if ([Environment]::UserInteractive -and $env:OccConsoleOutput) {
    $fc = @{ 'Information' = 'White'; 'Error' = 'Red'; 'Warning' = 'DarkYellow'; 'SuccessAudit' = 'DarkGray' }[$entryType]
    Write-Host -object $message -ForegroundColor $fc
  }
}
function Start-LoggedProcess {
  param (
    [string] $filePath,
    [string[]] $argumentList,
    [string] $name = [IO.Path]::GetFileNameWithoutExtension($filePath),
    [string] $redirectStandardOutput = ('{0}\log\{1}.{2}.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $name),
    [string] $redirectStandardError = ('{0}\log\{1}.{2}.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $name)
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    try {
      $process = (Start-Process -FilePath $filePath -ArgumentList $argumentList -NoNewWindow -RedirectStandardOutput $redirectStandardOutput -RedirectStandardError $redirectStandardError -PassThru)
      Wait-Process -InputObject $process # see: https://stackoverflow.com/a/43728914/68115
      if ($process.ExitCode -and $process.TotalProcessorTime) {
        Write-Log -message ('{0} :: {1} - command ({2} {3}) exited with code: {4} after a processing time of: {5}.' -f $($MyInvocation.MyCommand.Name), $name, $filePath, ($argumentList -join ' '), $process.ExitCode, $process.TotalProcessorTime) -severity 'INFO'
      } else {
        Write-Log -message ('{0} :: {1} - command ({2} {3}) executed.' -f $($MyInvocation.MyCommand.Name), $name, $filePath, ($argumentList -join ' ')) -severity 'INFO'
      }
    } catch {
      Write-Log -message ('{0} :: {1} - error executing command ({2} {3}). {4}' -f $($MyInvocation.MyCommand.Name), $name, $filePath, ($argumentList -join ' '), $_.Exception.Message) -severity 'ERROR'
    }
    $standardErrorFile = (Get-Item -Path $redirectStandardError -ErrorAction SilentlyContinue)
    if (($standardErrorFile) -and $standardErrorFile.Length) {
      Write-Log -message ('{0} :: {1} - {2}' -f $($MyInvocation.MyCommand.Name), $name, (Get-Content -Path $redirectStandardError -Raw)) -severity 'ERROR'
    }
    $standardOutputFile = (Get-Item -Path $redirectStandardOutput -ErrorAction SilentlyContinue)
    if (($standardOutputFile) -and $standardOutputFile.Length) {
      Write-Log -message ('{0} :: {1} - log: {2}' -f $($MyInvocation.MyCommand.Name), $name, $redirectStandardOutput) -severity 'INFO'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Install-Dependencies {
  param (
    [hashtable] $packageProviders = @{ 'NuGet' = 2.8.5.208 },
    [hashtable[]] $modules = @(
      @{
        'ModuleName' = 'PowerShellGet';
        'Repository' = 'PSGallery';
        'ModuleVersion' = '2.0.4'
      },
      @{
        'ModuleName' = 'PSDscResources';
        'Repository' = 'PSGallery';
        'ModuleVersion' = '2.9.0.0'
      },
      @{
        'ModuleName' = 'xPSDesiredStateConfiguration';
        'Repository' = 'PSGallery';
        'ModuleVersion' = '8.4.0.0'
      },
      @{
        'ModuleName' = 'xWindowsUpdate';
        'Repository' = 'PSGallery';
        'ModuleVersion' = '2.7.0.0'
      },
      @{
        'ModuleName' = 'OpenCloudConfig';
        'Repository' = 'PSGallery';
        'ModuleVersion' = '0.0.46'
      }
    ),
    # if modules are detected with a version **less than** specified in ModuleVersion below, they will be purged
    [hashtable[]] $purgeModules = @(
      @{
        'ModuleName' = 'OpenCloudConfig';
        'ModuleVersion' = '0.0.46'
      }
    )
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    foreach ($purgeModule in $purgeModules) {
      if ((Get-Module -ListAvailable -Name $purgeModule['ModuleName'] | ? { $_.Version -lt $purgeModule['ModuleVersion'] })) {
        try {
          Remove-Module -Name $purgeModule['ModuleName'] -Force -ErrorAction SilentlyContinue
          Remove-Item -path (Join-Path -Path $env:PSModulePath.Split(';') -ChildPath $purgeModule['ModuleName']) -recurse -force -ErrorAction SilentlyContinue
        } catch {
          Write-Log -message ('{0} :: error removing module: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $purgeModule['ModuleName'], $_.Exception.Message) -severity 'ERROR'
        }
      }
    }
    foreach ($packageProviderName in $packageProviders.Keys) {
      $version = $packageProviders.Item($packageProviderName)
      $packageProvider = (Get-PackageProvider -Name $packageProviderName -ForceBootstrap:$true)
      if ((-not ($packageProvider)) -or ($packageProvider.Version -lt $version)) {
        try {
          Install-PackageProvider -Name $packageProviderName -MinimumVersion $version -Force
          Write-Log -message ('{0} :: powershell package provider: {1}, version: {2}, installed' -f $($MyInvocation.MyCommand.Name), $packageProviderName, $version) -severity 'INFO'
        } catch {
          Write-Log -message ('{0} :: failed to install powershell package provider: {1}, version: {2}. {3}' -f $($MyInvocation.MyCommand.Name), $packageProviderName, $version, $_.Exception.Message) -severity 'ERROR'
        }
      } else {
        Write-Log -message ('{0} :: powershell package provider: {1}, version: {2}, detected' -f $($MyInvocation.MyCommand.Name), $packageProviderName, $packageProvider.Version) -severity 'DEBUG'
      }
    }
    foreach ($module in $modules) {
      if ((Get-Module -ListAvailable -Name $module['ModuleName'] | ? { $_.Version -eq $module['ModuleVersion'] })) {
        Write-Log -message ('{0} :: powershell module: {1}, version: {2}, detected.' -f $($MyInvocation.MyCommand.Name), $module['ModuleName'], $module['ModuleVersion']) -severity 'DEBUG'
      } else {
        Write-Log -message ('{0} :: powershell module: {1}, version: {2}, not detected' -f $($MyInvocation.MyCommand.Name), $module['ModuleName'], $module['ModuleVersion']) -severity 'DEBUG'
        if (@(Get-PSRepository -Name $module['Repository'])[0].InstallationPolicy -ne 'Trusted') {
          Set-PSRepository -Name $module['Repository'] -InstallationPolicy 'Trusted'
          Write-Log -message ('{0} :: installation policy for repository: {1}, set to "Trusted"' -f $($MyInvocation.MyCommand.Name), $module['Repository']) -severity 'INFO'
        }
        try {
          # AllowClobber was introduced in powershell 6
          if (((Get-Command 'Install-Module').ParameterSets | Select-Object -ExpandProperty 'Parameters' | Where-Object { $_.Name -eq 'AllowClobber' })) {
            Install-Module -Name $module['ModuleName'] -RequiredVersion $module['ModuleVersion'] -Repository $module['Repository'] -Force -AllowClobber
          } else {
            Install-Module -Name $module['ModuleName'] -RequiredVersion $module['ModuleVersion'] -Repository $module['Repository'] -Force
          }
          if (-not (Get-Module -ListAvailable -Name $module['ModuleName'] | ? { $_.Version -eq $module['ModuleVersion'] })) {
            # PSDscResources fails to install on windows 7 but is not required on that os, for dsc to function correctly
            Write-Log -message ('{0} :: installation of powershell module: {1}, version: {2}, from repository: {3}, did not succeed' -f $($MyInvocation.MyCommand.Name), $module['ModuleName'], $module['ModuleVersion'], $module['Repository']) -severity 'ERROR'
          } else {
            Write-Log -message ('{0} :: powershell module: {1}, version: {2}, from repository: {3}, installed' -f $($MyInvocation.MyCommand.Name), $module['ModuleName'], $module['ModuleVersion'], $module['Repository']) -severity 'INFO'
          }
        } catch {
          Write-Log -message ('{0} :: failed to install powershell module: {1}, version: {2}, from repository: {3}. {4}' -f $($MyInvocation.MyCommand.Name), $module['ModuleName'], $module['ModuleVersion'], $module['Repository'], $_.Exception.Message) -severity 'ERROR'
        }
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Get-ComponentAppliedState {
  param (
    [object] $component,
    [object[]] $appliedComponents
  )
  return [bool]($appliedComponents | ? { (($_.ComponentType -eq $component.ComponentType) -and ($_.ComponentName -eq $component.ComponentName)) })
}
function Get-AllDependenciesAppliedState {
  param (
    [object[]] $dependencies,
    [object[]] $appliedComponents
  )
  if (-not ($dependencies)) {
    return $true
  }
  return (-not (($dependencies | % { (Get-ComponentAppliedState -component $_ -appliedComponents $appliedComponents) }) -contains $false))
}
function Invoke-CustomDesiredStateProvider {
  param (
    [string] $workerType,
    [string] $sourceOrg = 'mozilla-releng',
    [string] $sourceRepo = 'OpenCloudConfig',
    [string] $sourceRev = 'master'
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    $manifestUri = ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/{3}.json?{4}' -f $sourceOrg, $sourceRepo, $sourceRev, $workerType, [Guid]::NewGuid())
    Write-Log -severity 'debug' -message ('{0} :: manifest uri determined as: {1}' -f $($MyInvocation.MyCommand.Name), $manifestUri)
    $manifest = ((Invoke-WebRequest -Uri $manifestUri -UseBasicParsing).Content.Replace('mozilla-releng/OpenCloudConfig/master', ('{0}/{1}/{2}' -f $sourceOrg, $sourceRepo, $sourceRev)) | ConvertFrom-Json)
    
    $appliedComponents = @()
    # loop through the manifest until all components have been applied
    while ($appliedComponents.Length -lt $manifest.Components.Length) {
      # loop through all components that have not already been applied
      foreach ($component in ($manifest.Components | ? { (-not (Get-ComponentAppliedState -component $_ -appliedComponents $appliedComponents)) })) {
        if (Get-AllDependenciesAppliedState -dependencies $component.DependsOn -appliedComponents $appliedComponents) {
          try {
            switch ($component.ComponentType) {
              'DirectoryCreate' {
                if (-not (Confirm-DirectoryCreate -verbose -component $component)) {
                  Invoke-DirectoryCreate -verbose -component $component
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of DirectoryCreate component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'DirectoryDelete' {
                if (-not (Confirm-DirectoryDelete -verbose -component $component)) {
                  Invoke-DirectoryDelete -verbose -component $component
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of DirectoryDelete component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'DirectoryCopy' {
                if (-not (Confirm-DirectoryCopy -verbose -component $component)) {
                  Invoke-DirectoryCopy -verbose -component $component
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of DirectoryCopy component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'CommandRun' {
                if (-not (Confirm-CommandRun -verbose -component $component)) {
                  Invoke-CommandRun -verbose -component $component
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of CommandRun component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'FileDownload' {
                if (-not (Confirm-FileDownload -verbose -component $component -localPath $component.Target)) {
                  Invoke-FileDownload -verbose -component $component -localPath $component.Target
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of FileDownload component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'ChecksumFileDownload' {
                if (-not (Confirm-FileDownload -verbose -component $component -localPath $component.Target)) {
                  Invoke-FileDownload -verbose -component $component -localPath $component.Target
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of FileDownload component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'SymbolicLink' {
                if (-not (Confirm-SymbolicLink -verbose -component $component)) {
                  Invoke-SymbolicLink -verbose -component $component
                }
                Invoke-SymbolicLink -verbose -component $component
              }
              'ExeInstall' {
                if (-not (Confirm-ExeInstall -verbose -component $component)) {
                  Invoke-ExeInstall -verbose -component $component
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of ExeInstall component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'MsiInstall' {
                if (-not (Confirm-MsiInstall -verbose -component $component)) {
                  Invoke-MsiInstall -verbose -component $component
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of MsiInstall component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'MsuInstall' {
                if (-not (Confirm-MsuInstall -verbose -component $component)) {
                  Invoke-MsuInstall -verbose -component $component
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of MsuInstall component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'WindowsFeatureInstall' {
                # todo: implement WindowsFeatureInstall in the DynamicConfig module
                Write-Log -message ('{0} :: not implemented: WindowsFeatureInstall.' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
              }
              'ZipInstall' {
                $localPath = ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $(if ($component.sha512) { $component.sha512 } else { $component.ComponentName }))
                if (-not (Confirm-FileDownload -verbose -component $component -localPath $localPath)) {
                  Invoke-FileDownload -verbose -component $component -localPath $localPath
                }
                # todo: confirm or refute prior install with comparison of directory and zip contents
                Invoke-ZipInstall -verbose -component $component -path $localPath -overwrite
              }
              'ServiceControl' {
                # todo: implement ServiceControl in the DynamicConfig module
                Set-ServiceState -name $component.Name -state $component.State
                Set-Service -name $component.Name -StartupType $component.StartupType
              }
              'EnvironmentVariableSet' {
                Invoke-EnvironmentVariableSet -verbose -component $component
              }
              'EnvironmentVariableUniqueAppend' {
                Invoke-EnvironmentVariableUniqueAppend -verbose -component $component
              }
              'EnvironmentVariableUniquePrepend' {
                Invoke-EnvironmentVariableUniquePrepend -verbose -component $component
              }
              'RegistryKeySet' {
                Invoke-RegistryKeySet -verbose -component $component
              }
              'RegistryValueSet' {
                if ($component.SetOwner) {
                  Invoke-RegistryKeySetOwner -verbose -component $component
                }
                Invoke-RegistryValueSet -verbose -component $component
              }
              'DisableIndexing' {
                if (-not (Confirm-DisableIndexing -verbose -component $component)) {
                  Invoke-DisableIndexing -verbose -component $component
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of DisableIndexing component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'FirewallRule' {
                if (-not (Confirm-FirewallRuleSet -verbose -component $component)) {
                  Invoke-FirewallRuleSet -verbose -component $component
                } else {
                  Write-Log -verbose -message ('{0} :: skipping invocation of FirewallRule component: {1}. prior application detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName) -severity 'DEBUG'
                }
              }
              'ReplaceInFile' {
                Invoke-ReplaceInFile -verbose -component $component
              }
            }
            if ($component.DependsOn) {
              Write-Log -severity 'debug' -message ('{0} :: component {1}_{2} applied. component has {3} dependencies ({4}) which have already been applied' -f $($MyInvocation.MyCommand.Name), $component.ComponentType, $component.ComponentName, $component.DependsOn.Length, (($component.DependsOn | % { '{0}_{1}' -f $_.ComponentType, $_.ComponentName }) -join ', '))
            } else {
              Write-Log -severity 'debug' -message ('{0} :: component {1}_{2} applied. component has no dependencies' -f $($MyInvocation.MyCommand.Name), $component.ComponentType, $component.ComponentName)
            }
            $appliedComponents += New-Object -TypeName 'PSObject' -Property @{ 'ComponentName' = $component.ComponentName; 'ComponentType' = $component.ComponentType; 'AppliedState' = 'Success' }
          } catch {
            Write-Log -severity 'error' -message ('{0} :: component {1}_{2} apply failure. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentType, $component.ComponentName, $_.Exception.Message)
            $appliedComponents += New-Object -TypeName 'PSObject' -Property @{ 'ComponentName' = $component.ComponentName; 'ComponentType' = $component.ComponentType; 'AppliedState' = 'Failure' }
          }
        }
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Invoke-RemoteDesiredStateConfig {
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
    Write-Log -message ('{0} :: downloaded {1}, from {2}' -f $($MyInvocation.MyCommand.Name), $target, $url) -severity 'DEBUG'
    Unblock-File -Path $target
    . $target
    $mof = ('{0}\{1}' -f $env:Temp, $config)
    Remove-Item $mof -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
    Invoke-Expression "$config -OutputPath $mof"
    Write-Log -message ('{0} :: compiled mof {1}, from {2}.' -f $($MyInvocation.MyCommand.Name), $mof, $config) -severity 'DEBUG'
    try {
      $errorCount = $error.Count;
      Start-DscConfiguration -Path "$mof" -Wait -Verbose -Force
      if ($error.Count -gt $errorCount) {
        $dscErrors = $error[$errorCount..($error.Count - 1)]
        Write-Log -message ('{0} :: {1} errors encountered during dsc run.' -f $($MyInvocation.MyCommand.Name), $dscErrors.Count) -severity 'ERROR'
        foreach ($dscError in $dscErrors) {
          Write-Log -message ('{0} :: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $dscError.FullyQualifiedErrorId, $dscError.Exception.Message) -severity 'ERROR'
        }
      }
    }
    catch {
      Write-Log -message ('{0} :: failed to run all or part of dsc configuration: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $mof, $_.Exception.Message) -severity 'ERROR'
    }
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
      Write-Log -message ('{0} :: failed to delete scheduled task: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $scheduledTask, $_.Exception.Message) -severity 'ERROR'
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
    [string[]] $users = @(
      'cltbld',
      'GenericWorker',
      't-w1064-vanilla',
      'inst'
    ),
    [string[]] $paths = @(
      ('{0}\Apache Software Foundation' -f $env:ProgramFiles),
      ('{0}\Convert-WindowsImageInfo.txt' -f $env:SystemDrive),
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
      ('{0}\unattend.xml' -f $env:SystemDrive),
      ('{0}\updateservice' -f $env:SystemDrive),
      ('{0}\Users\Administrator\Desktop\TESTER RUNNER' -f $env:SystemDrive),
      ('{0}\Users\Administrator\Desktop\PyYAML-3.11' -f $env:SystemDrive),
      ('{0}\Users\Administrator\Desktop\PyYAML-3.11.zip' -f $env:SystemDrive),
      ('{0}\Users\Public\Desktop\*.lnk' -f $env:SystemDrive),
      ('{0}\Users\root\Desktop\*.reg' -f $env:SystemDrive),
      ('{0}\System32\config\systemprofile\AppData\LocalLow\Microsoft\CryptnetUrlCache\Content\*' -f $env:SystemRoot),
      ('{0}\System32\config\systemprofile\AppData\LocalLow\Microsoft\CryptnetUrlCache\MetaData\*' -f $env:SystemRoot)
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
      'HKLM:\SOFTWARE\PuppetLabs',
      'HKLM:\SOFTWARE\Microsoft\SystemCertificates\AuthRoot\Certificates\*'
    ),
    [hashtable] $registryEntries = @{
      # g-w won't set autologin password if these keys pre-exist
      # https://github.com/taskcluster/generic-worker/blob/fb74177141c39afaa1daae53b6fb2a01edd8f32d/plat_windows.go#L440
      'DefaultUserName' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';
      'DefaultPassword' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';
      'AutoAdminLogon' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
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
        Set-ServiceState -name $service -state 'Stopped'
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
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-Ec2ConfigSettings {
  param (
    [string] $ec2ConfigSettingsFile = ('{0}\Amazon\Ec2ConfigService\Settings\Config.xml' -f $env:ProgramFiles),
    [hashtable] $ec2ConfigSettings = @{
      'Ec2HandleUserData' = $(if (Test-ScheduledTaskExists -TaskName 'RunDesiredStateConfigurationAtStartup') { 'Disabled' } else { 'Enabled' });
      'Ec2InitializeDrives' = 'Enabled';
      'Ec2EventLog' = 'Enabled';
      'Ec2OutputRDPCert' = 'Enabled';
      'Ec2SetDriveLetter' = 'Enabled';
      'Ec2WindowsActivate' = 'Disabled';
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
      try {
        Start-LoggedProcess -filePath 'takeown' -ArgumentList @('/a', '/f', ('"{0}"' -f $ec2ConfigSettingsFile)) -name 'takeown-ec2config-settings'
        Start-LoggedProcess -filePath 'icacls' -ArgumentList @(('"{0}"' -f $ec2ConfigSettingsFile), '/grant', 'Administrators:F') -name 'icacls-ec2config-settings-grant-admin'
        Start-LoggedProcess -filePath 'icacls' -ArgumentList @(('"{0}"' -f $ec2ConfigSettingsFile), '/grant', 'System:F') -name 'icacls-ec2config-settings-grant-system'
        $xml.Save($ec2ConfigSettingsFile)
        Write-Log -message ('{0} :: Ec2Config settings file saved at: {1}' -f $($MyInvocation.MyCommand.Name), $ec2ConfigSettingsFile) -severity 'INFO'
      }
      catch {
        Write-Log -message ('{0} :: failed to save Ec2Config settings file: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $ec2ConfigSettingsFile, $_.Exception.Message) -severity 'ERROR'
      }
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
    if ((Test-VolumeExists -DriveLetter 'Y') -and (Test-VolumeExists -DriveLetter 'Z')) {
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
            if (-not ($isWorker)) {
              # ensure that Ec2HandleUserData is enabled before reboot (if the RunDesiredStateConfigurationAtStartup scheduled task doesn't yet exist)
              Set-Ec2ConfigSettings
            }
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
function Set-DriveLetters {
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
      if (Test-VolumeExists -DriveLetter @($old[0])) {
        $volume = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter='$old'"
        if ($null -ne $volume) {
          $volume.DriveLetter = $new
          $volume.Put()
          Write-Log -message ('{0} :: drive {1} assigned new drive letter: {2}.' -f $($MyInvocation.MyCommand.Name), $old, $new) -severity 'INFO'
        }
      }
    }
    if ((Test-VolumeExists -DriveLetter 'Y') -and (-not (Test-VolumeExists -DriveLetter 'Z'))) {
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
      New-Item -Path $path -ItemType directory -force
      & 'icacls.exe' @($path, '/grant', 'Everyone:(OI)(CI)F')
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Test-ScheduledTaskExists {
  param (
    [string] $taskName
  )
  if (Get-Command 'Get-ScheduledTask' -ErrorAction 'SilentlyContinue') {
    return [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction 'SilentlyContinue')
  }
  # sceduled task commandlets are unavailable on windows 7, so we use com to access sceduled tasks here.
  $scheduleService = (New-Object -ComObject Schedule.Service)
  $scheduleService.Connect()
  return (@($scheduleService.GetFolder("\").GetTasks(0) | ? { $_.Name -eq $taskName }).Length -gt 0)
}
function Test-VolumeExists {
  param (
    [char[]] $driveLetter
  )
  if (Get-Command 'Get-Volume' -ErrorAction 'SilentlyContinue') {
    return (@(Get-Volume -DriveLetter $driveLetter -ErrorAction 'SilentlyContinue').Length -eq $driveLetter.Length)
  }
  # volume commandlets are unavailable on windows 7, so we use wmi to access volumes here.
  return (@($driveLetter | % { Get-WmiObject -Class Win32_Volume -Filter ('DriveLetter=''{0}:''' -f $_) -ErrorAction 'SilentlyContinue' }).Length -eq $driveLetter.Length)
}
function New-PowershellScheduledTask {
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
    if ((Test-ScheduledTaskExists -TaskName $taskName)) {
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
function Set-WindowsActivation {
  param (
    [string] $productKeyMapUrl = ('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Configuration/product-key-map.json?{0}' -f [Guid]::NewGuid()),
    [string] $keyManagementServiceMachine = '10.48.69.100',
    [int] $keyManagementServicePort = 1688
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    Write-Log -message ('{0} :: using product key map: {1}.' -f $($MyInvocation.MyCommand.Name), $productKeyMapUrl) -severity 'DEBUG'
    $productKeyMap = (Invoke-WebRequest -Uri $productKeyMapUrl -UseBasicParsing | ConvertFrom-Json)
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
        if((-not (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -ErrorAction SilentlyContinue)) -or ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto').SchUseStrongCrypto -ne 1)) {
          Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord
          Write-Log -message ('{0} :: Registry updated to use strong cryptography on 64 bit .Net Framework' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
        } else {
          Write-Log -message ('{0} :: Detected registry setting to use strong cryptography on 64 bit .Net Framework' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
        }
      }
      if((-not (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -ErrorAction SilentlyContinue)) -or ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto').SchUseStrongCrypto -ne 1)) {
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
function Set-SystemClock {
  param (
    [string] $locationType,
    [string] $ntpserverlist = $(if (($locationType -eq 'DataCenter') -and (${env:PROCESSOR_ARCHITEW6432} -ne 'ARM64')) { "infoblox1.private.$MozSpace.mozilla.com" } else { '0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org' })
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    $timeService = Get-Service -Name 'w32time'
    if (($timeService) -and ($timeService.Status -ne 'Stopped')) {
      Set-ServiceState -name 'w32time' -state 'Stopped'
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
      Set-ServiceState -name 'w32time' -state 'Running'
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
function Set-NetworkCategory {
  param (
    [ValidateSet('public', 'private')]
    [string] $category
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    $categoryMap = @{ 'public' = 0; 'private'  = 1 }
    ([Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))).GetNetworkConnections() | % {
      try {
        $network = $_.GetNetwork()
        $network.SetCategory($categoryMap[$category])
        Write-Log -message ('{0} :: network category to: {1} (IsConnected: {2}, IsConnectedToInternet: {3}).' -f $($MyInvocation.MyCommand.Name), $category, $network.IsConnected, $network.IsConnectedToInternet) -severity 'INFO'
      }
      catch {
        Write-Log -message ('{0} :: failed to set network category to: {1} (IsConnected: {2}, IsConnectedToInternet: {3}). {4}' -f $($MyInvocation.MyCommand.Name), $category, $network.IsConnected, $network.IsConnectedToInternet, $_.Exception.Message) -severity 'ERROR'
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-WinrmConfig {
  param (
    [string] $executionPolicy = 'RemoteSigned',
    [hashtable] $settings = @{'MaxEnvelopeSizeKb'=32696;'MaxTimeoutMs'=180000},
    [string] $osCaption = ((Get-WmiObject -Class 'Win32_OperatingSystem').Caption)
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    try {
      Set-ExecutionPolicy -executionPolicy $executionPolicy -force
      Write-Log -message ('{0} :: execution policy set to: {1}.' -f $($MyInvocation.MyCommand.Name), $executionPolicy) -severity 'INFO'
    }
    catch {
      Write-Log -message ('{0} :: failed to set execution policy to: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $executionPolicy, $_.Exception.Message) -severity 'ERROR'
    }
    Set-ServiceState -name 'winrm' -state 'Running'
    foreach ($key in $settings.Keys) {
      $value = $settings.Item($key)
      switch -wildcard ($osCaption) {
        'Microsoft Windows 7*' {
          Start-LoggedProcess -filePath 'cmd' -ArgumentList @('/c', 'winrm', 'set', 'winrm/config', ('@{{{0}="{1}"}}' -f $key, $value)) -name ('winrm-config-{0}' -f $key.ToLower())
        }
        default {
          try {
            Set-Item -Path ('WSMan:\localhost\{0}' -f $key) -Value $value
            Write-Log -message ('{0} :: WSMan:\localhost\{1} set to {2}.' -f $($MyInvocation.MyCommand.Name), $key, $value) -severity 'INFO'
          } catch {
            Write-Log -message ('{0} :: failed to set WSMan:\localhost\{1} to {2}. {3}' -f $($MyInvocation.MyCommand.Name), $key, $value, $_.Exception.Message) -severity 'ERROR'
          }
        }
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-ServiceState {
  param (
    [string] $name,
    [ValidateSet('Running', 'Stopped')]
    [string] $state
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    $service = (Get-Service -Name $name)
    if ($service) {
      Write-Log -message ('{0} :: {1} service state: {2}.' -f $($MyInvocation.MyCommand.Name), $name, $service.Status) -severity 'DEBUG'
      $attempt = 0
      while (($service.Status -ne $state) -and ($attempt -lt 2)) {
        try {
          switch ($state) {
            'Running' {
              Start-Service -InputObject $service
            }
            'Stopped' {
              Stop-Service -InputObject $service
            }
          }
          $service.WaitForStatus($state, '00:00:10')
        } catch {
          Write-Log -message ('{0} :: attempt {1} failed to set {2} service state to {3}. {4}' -f $($MyInvocation.MyCommand.Name), ($attempt + 1), $name, $state, $_.Exception.Message) -severity 'ERROR'
          Start-LoggedProcess -filePath 'sc' -argumentList @('config', 'w32time', 'type=', 'own') -name 'sc-config-w32time-type-own'
        }
        Write-Log -message ('{0} :: {1} service state: {2}.' -f $($MyInvocation.MyCommand.Name), $name, (Get-Service -Name $name).Status) -severity 'DEBUG'
        $attempt++
      }
    } else {
      Write-Log -message ('{0} :: {1} service not found.' -f $($MyInvocation.MyCommand.Name), $name) -severity 'ERROR'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-ComputerName {
  param (
    [string] $instanceId = ((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/instance-id')),
    [string] $dnsHostname = [System.Net.Dns]::GetHostName(),
    [string[]] $rebootReasons = @()
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    Write-Log -message ('{0} :: instanceId: {1}, dnsHostname: {2}.' -f $($MyInvocation.MyCommand.Name), $instanceId, $dnsHostname) -severity 'INFO'
    if (([bool]($instanceId)) -and (-not ($dnsHostname -ieq $instanceId))) {
      [Environment]::SetEnvironmentVariable("COMPUTERNAME", "$instanceId", "Machine")
      $env:COMPUTERNAME = $instanceId
      (Get-WmiObject Win32_ComputerSystem).Rename($instanceId)
      $rebootReasons += 'host renamed'
      Write-Log -message ('{0} :: host renamed from: {1} to {2}.' -f $($MyInvocation.MyCommand.Name), $dnsHostname, $instanceId) -severity 'INFO'
    } else {
      Write-Log -message ('{0} :: hostname: {1} matches instance id: {2}.' -f $($MyInvocation.MyCommand.Name), $dnsHostname, $instanceId) -severity 'DEBUG'
    }
    return $rebootReasons
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-DomainName {
  param (
    [string] $publicKeys = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-keys'),
    [string] $workerType = $(if ($publicKeys.StartsWith('0=mozilla-taskcluster-worker-')) { $publicKeys.Replace('0=mozilla-taskcluster-worker-', '') } else { (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/user-data' -UseBasicParsing | ConvertFrom-Json).workerType }),
    [string] $az = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/placement/availability-zone')
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
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
    Write-Log -message ('{0} :: availabilityZone: {1}, dnsRegion: {2}.' -f $($MyInvocation.MyCommand.Name), $az, $dnsRegion) -severity 'INFO'
    if (Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\NV Domain') {
      $currentDomain = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'NV Domain').'NV Domain'
    } elseif (Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Domain') {
      $currentDomain = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'Domain').'Domain'
    } else {
      $currentDomain = $env:USERDOMAIN
    }
    $domain = ('{0}.{1}.mozilla.com' -f $workerType, $dnsRegion)
    if (-not ($currentDomain -ieq $domain)) {
      [Environment]::SetEnvironmentVariable('USERDOMAIN', "$domain", 'Machine')
      $env:USERDOMAIN = $domain
      Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'Domain' -Value "$domain"
      Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'NV Domain' -Value "$domain"
      Write-Log -message ('{0} :: domain set to: {1}' -f $($MyInvocation.MyCommand.Name), $domain) -severity 'INFO'
    } else {
      Write-Log -message ('{0} :: current domain: {1} matches expected domain: {2}.' -f $($MyInvocation.MyCommand.Name), $currentDomain, $domain) -severity 'DEBUG'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-DynamicDnsRegistration {
  param (
    [switch] $enabled = $false
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    foreach($nic in (Get-WmiObject "Win32_NetworkAdapterConfiguration where IPEnabled='TRUE'")) {
      $nic.SetDynamicDNSRegistration($enabled)
      Write-Log -message ('{0} :: dynamic dns registration {1} on network interface {2} ({3})' -f $($MyInvocation.MyCommand.Name), $(if ($enabled) {'enabled'} else {'disabled'}), $nic.Index, $nic.Description) -severity 'DEBUG'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Invoke-HardwareDiskCleanup {
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
      #Start-Process -Wait Dism.exe /online /Cleanup-Image /StartComponentCleanup
      #Start-Process -Wait cleanmgr.exe /autoclean
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
      & shutdown @('-s', '-t', '0', '-c', 'Restarting disk space Critical', '-f', '-d', 'p:2:4')
      exit
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-ChainOfTrustKey {
  param (
    [string] $workerType,
    [switch] $shutdown
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    switch -regex ($workerType) {
      # level 3 builder needs key added by user intervention and must already exist in cot repo
      '^gecko-3-b-win2012(-c[45])?$' {
        while ((-not (Test-Path -Path 'C:\generic-worker\ed25519-private.key' -ErrorAction SilentlyContinue)) -or (-not (Test-Path -Path 'C:\generic-worker\openpgp-private.key' -ErrorAction SilentlyContinue))) {
          Write-Log -message ('{0} :: ed25519 and/or openpgp key missing. awaiting user intervention.' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
          Sleep 60
        }
        while ((-not ((Get-Item -Path 'C:\generic-worker\ed25519-private.key').Length -gt 0)) -or (-not ((Get-Item -Path 'C:\generic-worker\openpgp-private.key').Length -gt 0))) {
          Write-Log -message ('{0} :: ed25519 and/or openpgp key empty. awaiting user intervention.' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
          Sleep 60
        }
        while (@(Get-Process | ? { $_.ProcessName -eq 'rdpclip' }).Length -gt 0) {
          Write-Log -message ('{0} :: rdp session detected. awaiting user disconnect.' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
          Sleep 60
        }
        if ((Test-Path -Path 'C:\generic-worker\ed25519-private.key' -ErrorAction SilentlyContinue) -and (Test-Path -Path 'C:\generic-worker\openpgp-private.key' -ErrorAction SilentlyContinue)) {
          foreach ($keyAlgorithm in @('ed25519', 'openpgp')) {
            Start-LoggedProcess -filePath 'icacls' -ArgumentList @(('C:\generic-worker\{0}-private.key' -f $keyAlgorithm), '/grant', 'Administrators:(GA)') -name ('icacls-{0}-grant-admin' -f $keyAlgorithm)
            Start-LoggedProcess -filePath 'icacls' -ArgumentList @(('C:\generic-worker\{0}-private.key' -f $keyAlgorithm), '/inheritance:r') -name ('icacls-{0}-inheritance-remove' -f $keyAlgorithm)
          }
          if ($shutdown) {
            Write-Log -message ('{0} :: ed25519 and openpgp keys detected. shutting down.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
            & shutdown @('-s', '-t', '0', '-c', 'dsc run complete', '-f', '-d', 'p:2:4')
          } else {
            Write-Log -message ('{0} :: ed25519 and openpgp keys detected' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
          }
        } else {
          Write-Log -message ('{0} :: ed25519 and/or openpgp key intervention failed. awaiting timeout or cancellation.' -f $($MyInvocation.MyCommand.Name)) -severity 'ERROR'
        }
      }
      '^gecko-t-win10-(a64-beta|64-(hw|ux)(-b)?)$' {
        $gwConfigPath = 'C:\generic-worker\gen_worker.config'
        $gwExePath = 'C:\generic-worker\generic-worker.exe'
        if (Test-Path -Path $gwConfigPath -ErrorAction SilentlyContinue) {
          $gwConfig = (Get-Content $gwConfigPath -raw | ConvertFrom-Json)
          Write-Log -message ('{0} :: gw config found at {1}' -f $($MyInvocation.MyCommand.Name), $gwConfigPath) -severity 'DEBUG'
          if (Test-Path -Path $gwExePath -ErrorAction SilentlyContinue) {
            if (@(& $gwExePath @('--version') 2>&1) -like 'generic-worker 10.11.2 *') {
              Write-Log -message ('{0} :: gw 10.11.2 exe found at {1}' -f $($MyInvocation.MyCommand.Name), $gwExePath) -severity 'DEBUG'
              if (($gwConfig.signingKeyLocation) -and ($gwConfig.signingKeyLocation.Length)) {
                Write-Log -message ('{0} :: gw signingKeyLocation configured as: {1} in {2}' -f $($MyInvocation.MyCommand.Name), $gwConfig.signingKeyLocation, $gwConfigPath) -severity 'DEBUG'
                if (Test-Path -Path $gwConfig.signingKeyLocation -ErrorAction SilentlyContinue) {
                  $keyFileSize = (Get-Item -Path $gwConfig.signingKeyLocation).Length
                  Write-Log -message ('{0} :: gw signing key file {1} detected with a file size of {2:N2}kb' -f $($MyInvocation.MyCommand.Name), $gwConfig.signingKeyLocation, ($keyFileSize / 1kb)) -severity 'DEBUG'
                } else {
                  Write-Log -message ('{0} :: gw signing key file {1} not detected' -f $($MyInvocation.MyCommand.Name), $gwConfig.signingKeyLocation) -severity 'WARN'
                }
              } else {
                Write-Log -message ('{0} :: gw signingKeyLocation not configured in {1}' -f $($MyInvocation.MyCommand.Name), $gwConfigPath) -severity 'WARN'
              }
            } elseif (@(& $gwExePath @('--version') 2>&1) -like 'generic-worker 13.0.2 *') {
              Write-Log -message ('{0} :: gw 13.0.2 exe found at {1}' -f $($MyInvocation.MyCommand.Name), $gwExePath) -severity 'DEBUG'
              foreach ($keyAlgorithm in @('ed25519', 'openpgp')) {
                $privateKeyPath = ('C:\generic-worker\{0}-private.key' -f $keyAlgorithm)
                $publicKeyPath = ('C:\generic-worker\{0}-public.key' -f $keyAlgorithm)
                if (-not (Test-Path -Path $privateKeyPath -ErrorAction SilentlyContinue)) {
                  Write-Log -message ('{0} :: {1} key missing. generating key' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm) -severity 'WARN'
                  Start-LoggedProcess -filePath 'C:\generic-worker\generic-worker.exe' -ArgumentList @(('new-{0}-keypair' -f $keyAlgorithm), '--file', $privateKeyPath) -redirectStandardOutput $publicKeyPath -name ('generic-worker-new-{0}-keypair' -f $keyAlgorithm)
                  Start-LoggedProcess -filePath 'icacls' -ArgumentList @($privateKeyPath, '/grant', 'Administrators:(GA)') -name ('icacls-{0}-grant-admin' -f $keyAlgorithm)
                  Start-LoggedProcess -filePath 'icacls' -ArgumentList @($privateKeyPath, '/inheritance:r') -name ('icacls-{0}-inheritance-remove' -f $keyAlgorithm)
                  if ((Test-Path -Path $privateKeyPath -ErrorAction SilentlyContinue) -and (Test-Path -Path $publicKeyPath -ErrorAction SilentlyContinue)) {
                    Write-Log -message ('{0} :: {1} keys generated at: {2}, {3}' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm, $privateKeyPath, $publicKeyPath) -severity 'INFO'
                  } else {
                    Write-Log -message ('{0} :: {1} key generation failed' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm) -severity 'ERROR'
                  }
                }
                foreach ($keyPath in @($privateKeyPath, $publicKeyPath)) {
                  if (Test-Path -Path $keyPath -ErrorAction SilentlyContinue) {
                    $keyFileSize = (Get-Item -Path $keyPath).Length
                    Write-Log -message ('{0} :: gw {1} key file {2} detected with a file size of {3:N2}kb' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm, $keyPath, ($keyFileSize / 1kb)) -severity 'DEBUG'
                  } else {
                    Write-Log -message ('{0} :: gw {1} key file {2} not detected' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm, $keyPath) -severity 'WARN'
                  }
                }

                $configSigningKeyLocation = ($gwConfig.PsObject.Properties | ? { $_.Name -eq ('{0}SigningKeyLocation' -f $keyAlgorithm) }).Value
                if (($configSigningKeyLocation) -and ($configSigningKeyLocation.Length)) {
                  if ($configSigningKeyLocation -eq $privateKeyPath) {
                    Write-Log -message ('{0} :: {1}SigningKeyLocation configured correctly as: {2} in {3}' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm, $configSigningKeyLocation, $gwConfigPath) -severity 'DEBUG'
                  } else {
                    Write-Log -message ('{0} :: {1}SigningKeyLocation configured incorrectly as: {2} in {3}' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm, $configSigningKeyLocation, $gwConfigPath) -severity 'ERROR'
                  }
                } else {
                  Write-Log -message ('{0} :: {1}SigningKeyLocation not configured in {2}' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm, $gwConfigPath) -severity 'ERROR'
                }
              }
            }
          } else {
            Write-Log -message ('{0} :: gw exe not found' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
            try {
              Invoke-Expression (New-Object Net.WebClient).DownloadString(('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/OCC-HealthCheck.ps1?{0}' -f [Guid]::NewGuid()))
            } catch {
              Write-Log -message ('{0} :: error executing remote health check script. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
            }
          }
        } else {
          Write-Log -message ('{0} :: gw config not found' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
          try {
            Invoke-Expression (New-Object Net.WebClient).DownloadString(('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/OCC-HealthCheck.ps1?{0}' -f [Guid]::NewGuid()))
          } catch {
            Write-Log -message ('{0} :: error executing remote health check script. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
          }
        }
      }
      default {
        foreach ($keyAlgorithm in @('ed25519', 'openpgp')) {
          if (-not (Test-Path -Path ('C:\generic-worker\{0}-private.key' -f $keyAlgorithm) -ErrorAction SilentlyContinue)) {
            Write-Log -message ('{0} :: {1} key missing. generating key' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm) -severity 'WARN'
            Start-LoggedProcess -filePath 'C:\generic-worker\generic-worker.exe' -ArgumentList @(('new-{0}-keypair' -f $keyAlgorithm), '--file', ('C:\generic-worker\{0}-private.key' -f $keyAlgorithm)) -redirectStandardOutput ('C:\generic-worker\{0}-public.key' -f $keyAlgorithm) -name ('generic-worker-new-{0}-keypair' -f $keyAlgorithm)
            if (Test-Path -Path ('C:\generic-worker\{0}-private.key' -f $keyAlgorithm) -ErrorAction SilentlyContinue) {
              Write-Log -message ('{0} :: {1} key generated' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm) -severity 'INFO'
            } else {
              Write-Log -message ('{0} :: {1} key generation failed' -f $($MyInvocation.MyCommand.Name), $keyAlgorithm) -severity 'ERROR'
            }
          }
        }
        if ((Test-Path -Path 'C:\generic-worker\ed25519-private.key' -ErrorAction SilentlyContinue) -and (Test-Path -Path 'C:\generic-worker\openpgp-private.key' -ErrorAction SilentlyContinue)) {
          if ($shutdown) {
            Write-Log -message ('{0} :: ed25519 and openpgp keys detected. shutting down.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
            & shutdown @('-s', '-t', '0', '-c', 'dsc run complete', '-f', '-d', 'p:2:4')
          } else {
            Write-Log -message ('{0} :: ed25519 and openpgp keys detected' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
          }
        } else {
          Write-Log -message ('{0} :: ed25519 and/or openpgp key missing. awaiting timeout or cancellation.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
        }
        if ($shutdown) {
          if (@(Get-Process | ? { $_.ProcessName -eq 'rdpclip' }).length -eq 0) {
            & shutdown @('-s', '-t', '0', '-c', 'dsc run complete', '-f', '-d', 'p:2:4')
          } else {
            Write-Log -message ('{0} :: rdp session detected. awaiting manual shutdown.' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
          }
        }
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Wait-GenericWorkerStart {
  param (
    [string] $locationType,
    [string] $lock,
    [string] $taskClaimSemaphore = 'C:\dsc\task-claim-state.valid'
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    if (Test-Path -Path 'C:\generic-worker\run-generic-worker.bat' -ErrorAction SilentlyContinue) {
      Write-Log -message ('{0} :: generic-worker installation detected.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
      New-Item -Path $taskClaimSemaphore -type file -force
      Write-Log -message ('{0} :: semaphore {1} created.' -f $($MyInvocation.MyCommand.Name), $taskClaimSemaphore) -severity 'INFO'
      # give g-w 2 minutes to fire up, if it doesn't, boot loop.
      $timeout = New-Timespan -Minutes 2
      $timer = [Diagnostics.Stopwatch]::StartNew()
      $waitlogged = $false
      while (($timer.Elapsed -lt $timeout) -and (@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).length -eq 0)) {
        if (!$waitlogged) {
          Write-Log -message ('{0} :: waiting for generic-worker process to start.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
          $waitlogged = $true
        }
      }
      if ((@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).length -eq 0)) {
        Write-Log -message ('{0} :: no generic-worker process detected.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
        Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
        if ($locationType -eq 'DataCenter') {
          Remove-Item -Path $taskClaimSemaphore -force -ErrorAction SilentlyContinue
          Write-Log -message ('{0} :: semaphore {1} deleted.' -f $($MyInvocation.MyCommand.Name), $taskClaimSemaphore) -severity 'INFO'
        }
        & shutdown @('-r', '-t', '0', '-c', 'reboot to rouse the generic worker', '-f', '-d', '4:5')
      } else {
        $timer.Stop()
        Write-Log -message ('{0} :: generic-worker running process detected {1} ms after task-claim-state.valid flag set.' -f $($MyInvocation.MyCommand.Name), $timer.ElapsedMilliseconds) -severity 'INFO'
        if (Test-Path -Path $lock -ErrorAction SilentlyContinue) {
          Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
        }
        $gwProcess = (Get-Process | ? { $_.ProcessName -eq 'generic-worker' })
        if (($gwProcess) -and ($gwProcess.PriorityClass) -and ($gwProcess.PriorityClass -ne [Diagnostics.ProcessPriorityClass]::AboveNormal)) {
          $priorityClass = $gwProcess.PriorityClass
          $gwProcess.PriorityClass = [Diagnostics.ProcessPriorityClass]::AboveNormal
          Write-Log -message ('{0} :: process priority for generic worker altered from {1} to {2}.' -f $($MyInvocation.MyCommand.Name), $priorityClass, $gwProcess.PriorityClass) -severity 'INFO'
          Set-ServiceState -name 'wuauserv' -state 'Stopped'
          Set-ServiceState -name 'bits' -state 'Stopped'
        }
      }
    } else {
      Write-Log -message ('{0} :: generic worker install not detected (missing C:\generic-worker\run-generic-worker.bat).' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Initialize-NativeImageCache {
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    Get-ChildItem -Path $env:SystemRoot\Microsoft.Net -Filter 'ngen.exe' -Recurse | % {
      # todo: put framework version in name arg
      Start-LoggedProcess -filePath $_.FullName -ArgumentList @('executeQueuedItems') -name 'ngen-executeQueuedItems'
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Set-NxlogConfig {
  param (
    [string] $sourceOrg = 'mozilla-releng',
    [string] $sourceRepo = 'OpenCloudConfig',
    [string] $sourceRev = 'master',
    [string] $osCaption = ((Get-WmiObject -class Win32_OperatingSystem).Caption)
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    switch -wildcard ($osCaption) {
      'Microsoft Windows 7*' {
        $url = ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Configuration/nxlog/win7.conf' -f $sourceOrg, $sourceRepo, $sourceRev)
        $config = ('{0}\nxlog\conf\nxlog.conf' -f $env:ProgramFiles)
      }
      'Microsoft Windows 10*' {
        $url = ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Configuration/nxlog/win10.conf' -f $sourceOrg, $sourceRepo, $sourceRev)
        $config = ('{0}\nxlog\conf\nxlog.conf' -f ${env:ProgramFiles(x86)})
      }
      'Microsoft Windows Server 2012*' {
        $url = ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Configuration/nxlog/win2012.conf' -f $sourceOrg, $sourceRepo, $sourceRev)
        $config = ('{0}\nxlog\conf\nxlog.conf' -f ${env:ProgramFiles(x86)})
      }
      'Microsoft Windows Server 2016*' {
        $url = ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Configuration/nxlog/win2016.conf' -f $sourceOrg, $sourceRepo, $sourceRev)
        $config = ('{0}\nxlog\conf\nxlog.conf' -f ${env:ProgramFiles(x86)})
      }
    }
    if (($url) -and ($config) -and (Test-Path -Path $config -ErrorAction SilentlyContinue)) {
      try {
        $oldConfig = $config.Replace('.conf', ('.{0}.conf' -f [DateTime]::Now.ToString('yyyyMMddHHmmss')))
        Move-item -LiteralPath $config -Destination $oldConfig
        Write-Log -message ('{0} :: renamed {1} to {2}' -f $($MyInvocation.MyCommand.Name), $config, $oldConfig) -severity 'DEBUG'
        (New-Object Net.WebClient).DownloadFile($url, $config)
        Unblock-File -Path $config
        Write-Log -message ('{0} :: downloaded {1} to {2}' -f $($MyInvocation.MyCommand.Name), $url, $config) -severity 'DEBUG'
      } catch {
        Write-Log -message ('{0} :: failed to download {1} to {2}. {3}' -f $($MyInvocation.MyCommand.Name), $url, $config, $_.Exception.Message) -severity 'ERROR'
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Initialize-Instance {
  param (
    [string] $sourceOrg = 'mozilla-releng',
    [string] $sourceRepo = 'OpenCloudConfig',
    [string] $sourceRev = 'master',
    [string] $locationType
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    if ($locationType -eq 'AWS') {
      $rebootReasons = (Set-ComputerName)
      Set-DomainName
      # Turn off DNS address registration (EC2 DNS is configured to not allow it)
      Set-DynamicDnsRegistration -enabled:$false
    }
    if ($rebootReasons.length) {
      # if this is an ami creation instance (not a worker) ...
      if (($locationType -eq 'AWS') -and (((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-keys')).StartsWith('0=mozilla-taskcluster-worker-'))) {
        # ensure that Ec2HandleUserData is enabled before reboot (if the RunDesiredStateConfigurationAtStartup scheduled task doesn't yet exist)
        Set-Ec2ConfigSettings
        # ensure that an up to date nxlog configuration is used as early as possible
        Set-NxlogConfig -sourceOrg $sourceOrg -sourceRepo $sourceRepo -sourceRev $sourceRev
      }
      Write-Log -message ('{0} :: reboot required: {1}' -f $($MyInvocation.MyCommand.Name), [string]::Join(', ', $rebootReasons)) -severity 'DEBUG'
      & shutdown @('-r', '-t', '0', '-c', [string]::Join(', ', $rebootReasons), '-f', '-d', 'p:4:1')
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function Invoke-OpenCloudConfig {
  param (
    [string] $sourceOrg = 'mozilla-releng',
    [string] $sourceRepo = 'OpenCloudConfig',
    [string] $sourceRev = 'master',
    [string] $locationType = $(if ((Get-Service 'Ec2Config' -ErrorAction SilentlyContinue) -or (Get-Service 'AmazonSSMAgent' -ErrorAction SilentlyContinue)) { 'AWS' } else { 'DataCenter' })
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    # Before doing anything else, make sure we are using TLS 1.2
    # See https://bugzilla.mozilla.org/show_bug.cgi?id=1443595 for context.
    Set-DefaultStrongCryptography
    Set-NetworkRoutes
    Initialize-Instance -sourceOrg $sourceOrg -sourceRepo $sourceRepo -sourceRev $sourceRev -locationType $locationType

    # The Windows update service needs to be enabled for OCC to process but needs to be disabled during testing.
    Set-ServiceState -name 'wuauserv' -state 'Running'

    if ($locationType -eq 'DataCenter') {
      Set-Variable -Name 'MozSpace' -Value (((Get-ItemProperty 'HKLM:SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters').'NV Domain') -replace ".mozilla.com$") -Scope global
      [Environment]::SetEnvironmentVariable('MozSpace', "$MozSpace", 'Machine')
    }
    $lock = 'C:\dsc\in-progress.lock'
    if (Test-Path -Path $lock -ErrorAction SilentlyContinue) {
      if ((Get-CimInstance Win32_Process -Filter "name = 'powershell.exe'" | ? { $_.CommandLine -eq 'powershell.exe -File C:\dsc\rundsc.ps1' }).Length -gt 1) {
        Write-Log -message ('{0} :: userdata run aborted. lock file exists and alternate powershell rundsc process detected.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
        exit
      }
      Write-Log -message ('{0} :: lock file exists but alternate powershell rundsc process not detected.' -f $($MyInvocation.MyCommand.Name)) -severity 'WARN'
    } elseif ((@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).Length -gt 0)) {
      while ((@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).Length -gt 0)) {
        Write-Log -message ('{0} :: userdata run paused. generic-worker is running.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
        try {
          Invoke-Expression (New-Object Net.WebClient).DownloadString(('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/OCC-HealthCheck.ps1?{0}' -f [Guid]::NewGuid()))
        } catch {
          Write-Log -message ('{0} :: error executing remote health check script. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
        }
        Start-Sleep -Seconds 30
      }
    } else {
      $lockDir = [IO.Path]::GetDirectoryName($lock)
      if (-not (Test-Path -Path $lockDir -ErrorAction SilentlyContinue)) {
        New-Item -Path $lockDir -ItemType directory -force
      }
      New-Item -Path $lock -type file -force
    }
    if ($locationType -eq 'DataCenter') {
      Invoke-HardwareDiskCleanup
    }
    Write-Log -message ('{0} :: userdata run starting.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
    Set-SystemClock -locationType $locationType

    # set up a log folder, an execution policy that enables the dsc run and a winrm envelope size large enough for the dynamic dsc.
    New-Item -ItemType Directory -Force -Path ('{0}\log' -f $env:SystemDrive)
    if ($locationType -eq 'DataCenter') {
      switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
        'Microsoft Windows 7*' {
          $isWorker = $true
          $runDscOnWorker = $true
          $workerType = 'gecko-t-win7-32-hw'
        }
        'Microsoft Windows 10*' {
          $isWorker = $true
          $runDscOnWorker = $true
          if (${env:PROCESSOR_ARCHITEW6432} -eq 'ARM64') {
            $workerType = 'gecko-t-win10-a64-beta'
            Write-Log -message ('{0} :: arm 64 architecture detected' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
          } else {
            $workerType = $(if (Test-Path -Path 'C:\dsc\GW10UX.semaphore' -ErrorAction SilentlyContinue) { 'gecko-t-win10-64-ux' } else { 'gecko-t-win10-64-hw' })
          }
        }
      }
      Write-Log -message ('{0} :: isWorker: {1}.' -f $($MyInvocation.MyCommand.Name), $isWorker) -severity 'INFO'
      Write-Log -message ('{0} :: workerType: {1}.' -f $($MyInvocation.MyCommand.Name), $workerType) -severity 'INFO'
      Write-Log -message ('{0} :: runDscOnWorker: {1}.' -f $($MyInvocation.MyCommand.Name), $runDscOnWorker) -severity 'DEBUG'
    } else {
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
        Set-WindowsActivation -productKeyMapUrl ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Configuration/product-key-map.json' -f $sourceOrg, $sourceRepo, $sourceRev)
      } else {
        # provisioned worker
        $isWorker = $true
        $workerType = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/user-data' -UseBasicParsing | ConvertFrom-Json).workerType
      }
      Write-Log -message ('{0} :: isWorker: {1}.' -f $($MyInvocation.MyCommand.Name), $isWorker) -severity 'INFO'
      Write-Log -message ('{0} :: workerType: {1}.' -f $($MyInvocation.MyCommand.Name), $workerType) -severity 'INFO'

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
          if (-not ($isWorker)) {
            Remove-LegacyStuff
            Set-Credentials -username 'root' -password ('{0}' -f $rootPassword)
          }
        }
        'gecko-t-win10-*' {
          $runDscOnWorker = $true
          if (-not ($isWorker)) {
            Remove-LegacyStuff
            Set-Credentials -username 'Administrator' -password ('{0}' -f $rootPassword)
          }
        }
        default {
          $runDscOnWorker = $true
          if (-not ($isWorker)) {
            Set-Credentials -username 'Administrator' -password ('{0}' -f $rootPassword)
          }
        }
      }
      Write-Log -message ('{0} :: runDscOnWorker: {1}' -f $($MyInvocation.MyCommand.Name), $runDscOnWorker) -severity 'DEBUG'
      $instanceType = ((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/instance-type'))
      Write-Log -message ('{0} :: instanceType: {1}.' -f $($MyInvocation.MyCommand.Name), $instanceType) -severity 'INFO'
      [Environment]::SetEnvironmentVariable("TASKCLUSTER_INSTANCE_TYPE", "$instanceType", "Machine")

      # workaround for windows update failures on g3 instances
      # https://support.microsoft.com/en-us/help/10164/fix-windows-update-errors
      #if ($instanceType.StartsWith('g3.')) {
      #  try {
      #    & dism.exe @('/Online', '/Cleanup-image', '/Restorehealth')
      #    Write-Log -message ('{0} :: executed: dism cleanup.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      #  }
      #  catch {
      #    Write-Log -message ('{0} :: failed to run dism cleanup. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
      #  }
      #  try {
      #    & sfc @('/scannow')
      #    Write-Log -message ('{0} :: executed: sfc scan.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      #  }
      #  catch {
      #    Write-Log -message ('{0} :: failed to run sfc scan. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
      #  }
      #}

      Mount-DiskOne -lock $lock
      if ($isWorker) {
        Resize-DiskZero
      }
      Set-Pagefile -isWorker:$isWorker -lock $lock -workerType $workerType
      # reattempt drive mapping for up to 10 minutes
      $driveMapTimeout = (Get-Date).AddMinutes(10)
      $driveMapAttempt = 0
      Write-Log -message ('{0} :: drive map timeout set to {1}' -f $($MyInvocation.MyCommand.Name), $driveMapTimeout) -severity 'DEBUG'
      while (((Get-Date) -lt $driveMapTimeout) -and (-not (Test-VolumeExists -DriveLetter @('Z', 'Y')))) {
        if (((Get-WmiObject -class Win32_OperatingSystem).Caption.Contains('Windows 10')) -and (($instanceType.StartsWith('c5.')) -or ($instanceType.StartsWith('g3.'))) -and (Test-VolumeExists -DriveLetter @('Z')) -and (-not (Test-VolumeExists -DriveLetter @('Y'))) -and ((Get-WmiObject Win32_LogicalDisk | ? { $_.DeviceID -ne 'C:' }).Size -ge 119GB)) {
          Resize-DiskOne
        }
        Set-DriveLetters
        $driveMapAttempt ++
        if (Test-VolumeExists -DriveLetter @('Z', 'Y')) {
          Write-Log -message ('{0} :: drive map attempt {1} succeeded' -f $($MyInvocation.MyCommand.Name), $driveMapAttempt) -severity 'INFO'
        } else {
          Write-Log -message ('{0} :: drive map attempt {1} failed' -f $($MyInvocation.MyCommand.Name), $driveMapAttempt) -severity 'WARN'
          Sleep 60
        }
      }
      if ($isWorker) {
        if (-not (Test-VolumeExists -DriveLetter @('Z'))) {
          Write-Log -message ('{0} :: missing task drive. terminating instance...' -f $($MyInvocation.MyCommand.Name)) -severity 'ERROR'
          & shutdown @('-s', '-t', '0', '-c', 'missing task drive', '-f', '-d', '1:1')
        }
        if (-not (Test-VolumeExists -DriveLetter @('Y'))) {
          Write-Log -message ('{0} :: missing cache drive. terminating instance...' -f $($MyInvocation.MyCommand.Name)) -severity 'ERROR'
          & shutdown @('-s', '-t', '0', '-c', 'missing cache drive', '-f', '-d', '1:1')
        }
      }
      Initialize-NativeImageCache
    }
    if ($locationType -ne 'DataCenter') {
      # create a scheduled task to run HaltOnIdle every 2 minutes
      New-PowershellScheduledTask -taskName 'HaltOnIdle' -scriptUrl ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/HaltOnIdle.ps1?{3}' -f $sourceOrg, $sourceRepo, $sourceRev, [Guid]::NewGuid()) -scriptPath 'C:\dsc\HaltOnIdle.ps1' -sc 'minute' -mo '2'
    }
    # create a scheduled task to run system maintenance on startup
    New-PowershellScheduledTask -taskName 'MaintainSystem' -scriptUrl ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/MaintainSystem.ps1?{3}' -f $sourceOrg, $sourceRepo, $sourceRev, [Guid]::NewGuid()) -scriptPath 'C:\dsc\MaintainSystem.ps1' -sc 'onstart'
    if (($runDscOnWorker) -or (-not ($isWorker)) -or ("$env:RunDsc" -ne "")) {

      # pre dsc setup ###############################################################################################################################################
      switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
        'Microsoft Windows 7*' {
          # set network interface to private (reverted after dsc run) http://www.hurryupandwait.io/blog/fixing-winrm-firewall-exception-rule-not-working-when-internet-connection-type-is-set-to-public
          Set-NetworkCategory -category 'private'
          try {
            # this setting persists only for the current session
            Enable-PSRemoting -Force
          } catch {
            Write-Log -message ('{0} :: error enabling powershell remoting. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
          }
          #if (-not ($isWorker)) {
          #  Set-DefaultProfileProperties
          #}
          Set-WinrmConfig -settings @{'MaxEnvelopeSizekb'=8192;'MaxTimeoutms'=60000}
        }
        'Microsoft Windows 10*' {
          # set network interface to private (reverted after dsc run) http://www.hurryupandwait.io/blog/fixing-winrm-firewall-exception-rule-not-working-when-internet-connection-type-is-set-to-public
          Set-NetworkCategory -category 'private'
          try {
            # this setting persists only for the current session
            Enable-PSRemoting -SkipNetworkProfileCheck -Force
          } catch {
            Write-Log -message ('{0} :: error enabling powershell remoting. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
          }
          #if (-not ($isWorker)) {
          #  Set-DefaultProfileProperties
          #}
          Set-WinrmConfig -settings @{'MaxEnvelopeSizekb'=32696;'MaxTimeoutms'=180000}
        }
        default {
          try {
            # this setting persists only for the current session
            Enable-PSRemoting -SkipNetworkProfileCheck -Force
          } catch {
            Write-Log -message ('{0} :: error enabling powershell remoting. {1}' -f $($MyInvocation.MyCommand.Name), $_.Exception.Message) -severity 'ERROR'
          }
          Set-WinrmConfig -settings @{'MaxEnvelopeSizekb'=32696;'MaxTimeoutms'=180000}
        }
      }
      if (Test-Path -Path ('{0}\log\*.dsc-run.log' -f $env:SystemDrive) -ErrorAction SilentlyContinue) {
        try {
          Stop-Transcript
        } catch {}
        Remove-Item -Path ('{0}\log\*.dsc-run.log' -f $env:SystemDrive) -force -ErrorAction SilentlyContinue
      }
      $transcript = ('{0}\log\{1}.dsc-run.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      # end pre dsc setup ###########################################################################################################################################

      # run dsc #####################################################################################################################################################
      # use a code block similar to below for testing rundsc changes on beta
      #if ($workerType.EndsWith('-beta') -or $workerType.EndsWith('-gpu-b')) {
      #  $sourceRev = 'function-refactor'
      #}
      Start-Transcript -Path $transcript -Append

      if (-not ([Diagnostics.EventLog]::SourceExists('occ-dsc'))) {
        New-EventLog -LogName 'Application' -Source 'occ-dsc'
        Write-Log -message ('{0} :: event log source "occ-dsc" created.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
      } else {
        Write-Log -message ('{0} :: event log source "occ-dsc" detected.' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
      }
      Install-Dependencies

      switch -regex ($workerType) {
        # bypass dsc on hardware (gecko-t-win10-a64-beta, gecko-t-win10-64-hw*, gecko-t-win10-64-ux*)
        '^gecko-t-win10-(a64-beta|64-(hw|ux)(-[ab])?)$' {
          Invoke-CustomDesiredStateProvider -sourceOrg $sourceOrg -sourceRepo $sourceRepo -sourceRev $sourceRev -workerType $workerType
        }
        default {
          Invoke-RemoteDesiredStateConfig -url ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/xDynamicConfig.ps1' -f $sourceOrg, $sourceRepo, $sourceRev)
        }
      }
      
      Stop-Transcript
      # end run dsc #################################################################################################################################################
      
      # post dsc teardown ###########################################################################################################################################
      
      if (((Get-Content $transcript) | % {(
          # a package installed by dsc requested a restart
          ($_ -match 'requires a reboot') -or
          ($_ -match 'reboot is required') -or
          # a wsman network outage prevented the dsc run from completing
          ($_ -match 'WSManNetworkFailureDetected') -or
          # a service disable attempt through registry settings failed, because another running service interfered with the registry write
          ($_ -match 'Attempted to perform an unauthorized'))}) -contains $true) {
        if (-not ($isWorker)) {
          # ensure that Ec2HandleUserData is enabled before reboot (if the RunDesiredStateConfigurationAtStartup scheduled task doesn't yet exist)
          Set-Ec2ConfigSettings
        }
        Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
        & shutdown @('-r', '-t', '0', '-c', 'the dsc process did not complete and now requires a restart', '-f', '-d', 'p:4:2')
      }
      if (($locationType -ne 'DataCenter') -and (((Get-Content $transcript) | % { ($_ -match 'failed to execute Set-TargetResource') }) -contains $true)) {
        Write-Log -message ('{0} :: dsc run failed.' -f $($MyInvocation.MyCommand.Name)) -severity 'ERROR'
        if (-not ($isWorker)) {
          # if this is the ami creation instance, we don't have a way to communicate with the taskcluster-github job to tell it that the dsc run has failed.
          # the best we can do is sleep until the taskcluster-github job fails, because of a task timeout.
          $timer = [Diagnostics.Stopwatch]::StartNew()
          while ($timer.Elapsed.TotalHours -lt 5) {
            Write-Log -message ('{0} :: waiting for occ ci task to fail due to timeout. shutdown in {1} minutes.' -f $($MyInvocation.MyCommand.Name), [Math]::Round(((5 * 60) - $timer.Elapsed.TotalMinutes))) -severity 'WARN'
            Start-Sleep -Seconds 600
          }
          & shutdown @('-s', '-t', '0', '-c', 'dsc run failed', '-f', '-d', 'p:2:4')
        }
      }
      switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
        'Microsoft Windows 7*' {
          Set-NetworkCategory -category 'public'
        }
        'Microsoft Windows 10*' {
          Set-NetworkCategory -category 'public'
        }
      }
      # end post dsc teardown #######################################################################################################################################

      # create a scheduled task to run dsc at startup
      New-PowershellScheduledTask -taskName 'RunDesiredStateConfigurationAtStartup' -scriptUrl ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/rundsc.ps1?{3}' -f $sourceOrg, $sourceRepo, $sourceRev, [Guid]::NewGuid()) -scriptPath 'C:\dsc\rundsc.ps1' -sc 'onstart'
      if (-not ($isWorker)) {
        # ensure that Ec2HandleUserData is disabled after the RunDesiredStateConfigurationAtStartup scheduled task has been created
        Set-Ec2ConfigSettings
      }
    }
    if (($isWorker) -and (-not ($runDscOnWorker))) {
      Stop-DesiredStateConfig
      Remove-DesiredStateConfigTriggers
      New-LocalCache
    }

    # archive dsc logs
    Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and $_.Length -eq 0 } | % { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue }
    $zipFilePath = ('{0}\log\{1}.userdata-run.zip' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
    New-ZipFile -ZipFilePath $zipFilePath -Item @(Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') } | % { $_.FullName })
    Write-Log -message ('{0} :: log archive {1} created.' -f $($MyInvocation.MyCommand.Name), $zipFilePath) -severity 'INFO'
    Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and (-not $_.Name.EndsWith('.dsc-run.log')) } | % { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue }

    if ((-not ($isWorker)) -and (Test-Path -Path 'C:\generic-worker\run-generic-worker.bat' -ErrorAction SilentlyContinue)) {
      Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
      if ($locationType -ne 'DataCenter') {
        Set-ChainOfTrustKey -workerType $workerType -shutdown:$true
      }
    } elseif ($isWorker) {
      if ($locationType -ne 'DataCenter') {
        if (-not (Test-VolumeExists -DriveLetter 'Z')) { # if the Z: drive isn't mapped, map it.
          Set-DriveLetters
        }
      } else {
        # todo: generate config file if it does not exist or is invalid (eg: created for an older version of gw)
        Set-ChainOfTrustKey -workerType $workerType -shutdown:$false
      }
      Wait-GenericWorkerStart -locationType $locationType -lock $lock
    }
    if (Test-Path -Path $lock -ErrorAction SilentlyContinue) {
      Remove-Item -Path $lock -force -ErrorAction SilentlyContinue
    }
    Write-Log -message ('{0} :: userdata run completed' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'

  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}