<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

Configuration xDynamicConfig {
  Import-DscResource -ModuleName PSDesiredStateConfiguration
  Import-DscResource -ModuleName xPSDesiredStateConfiguration
  Import-DscResource -ModuleName xWindowsUpdate
  Import-DscResource -ModuleName OpenCloudConfig

  LocalConfigurationManager {
    ConfigurationMode = 'ApplyOnly'
  }

  $sourceOrg = $(if ((Test-Path -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -ErrorAction 'SilentlyContinue') -and (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Organisation' -ErrorAction 'SilentlyContinue')) { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Organisation').Organisation } else { 'mozilla-releng' })
  $sourceRepo = $(if ((Test-Path -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -ErrorAction 'SilentlyContinue') -and (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Repository' -ErrorAction 'SilentlyContinue')) { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Repository').Repository } else { 'OpenCloudConfig' })
  $sourceRev = $(if ((Test-Path -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -ErrorAction 'SilentlyContinue') -and (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Revision' -ErrorAction 'SilentlyContinue')) { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Revision').Revision } else { 'master' })

  if (Get-Service @('Ec2Config', 'AmazonSSMAgent', 'AWSLiteAgent') -ErrorAction SilentlyContinue) {
    $locationType = 'AWS'
  } elseif ((Get-Service -Name 'GCEAgent' -ErrorAction 'SilentlyContinue') -or (Test-Path -Path ('{0}\GooGet\googet.exe' -f $env:ProgramData) -ErrorAction 'SilentlyContinue')) {
    $locationType = 'GCP'
  } elseif (Get-Service -Name @('WindowsAzureGuestAgent', 'WindowsAzureNetAgentSvc') -ErrorAction 'SilentlyContinue') {
    $locationType = 'Azure'
  } else {
    try {
      # on azure we may trigger occ before the agent is installed or we may not have installed the agent (32 bit systems). this is a quick check to verify if that is what's happening here.
      if ((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version={0}' -f '2019-06-04')).Content) {
        $locationType = 'Azure'
      }
    } catch {
      $locationType = 'DataCenter'
    }
  }

  if ($locationType -eq 'AWS') {
    Script GpgKeyImport {
      DependsOn = @('[Script]ExeInstall_GpgForWin')
      GetScript = { @{ Result = (((Test-Path -Path ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction 'SilentlyContinue') -and ((Get-Item ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb)) -or ((Test-Path -Path ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction 'SilentlyContinue') -and ((Get-Item ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb))) } }
      SetScript = {
        if ("${env:ProgramFiles(x86)}") {
          $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
        } else{
          $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f $env:ProgramFiles)
        }
        try {
          $gpgPrivateKey = [regex]::matches((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/user-data'), '(?s)-----BEGIN PGP PRIVATE KEY BLOCK-----.*-----END PGP PRIVATE KEY BLOCK-----').Value
        }
        catch {
          $gpgPrivateKey = $false
        }
        if ($gpgPrivateKey) {
          Start-Process ('{0}\System32\diskperf.exe' -f $env:SystemRoot) -ArgumentList '-y' -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.diskperf.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.diskperf.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
          [IO.File]::WriteAllLines(('{0}\Temp\private.key' -f $env:SystemRoot), $gpgPrivateKey)
          Start-Process $gpg -ArgumentList @('--allow-secret-key-import', '--import', ('{0}\Temp\private.key' -f $env:SystemRoot)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.gpg-import-key.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.gpg-import-key.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
          Remove-Item -Path ('{0}\Temp\private.key' -f $env:SystemRoot) -Force
        }
      }
      TestScript = { if (((Test-Path -Path ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction 'SilentlyContinue') -and ((Get-Item ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb)) -or ((Test-Path -Path ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction 'SilentlyContinue') -and ((Get-Item ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb)))  { $true } else { $false } }
    }
  } elseif ((Test-Path -Path ('{0}\Mozilla\OpenCloudConfig\OpenCloudConfig.private.key' -f $env:ProgramData) -ErrorAction 'SilentlyContinue') -and (Test-Path -Path ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)}) -ErrorAction 'SilentlyContinue') -and (-not ((Test-Path -Path ('{0}\gnupg\secring.gpg' -f $env:AppData) -ErrorAction 'SilentlyContinue') -and ((Get-Item ('{0}\gnupg\secring.gpg' -f $env:AppData)).length -gt 0kb)))) {
    Script GpgKeyImport {
      DependsOn = @('[Script]ExeInstall_GpgForWin')
      GetScript = { @{ Result = ((Test-Path -Path ('{0}\gnupg\secring.gpg' -f $env:AppData) -ErrorAction 'SilentlyContinue') -and ((Get-Item ('{0}\gnupg\secring.gpg' -f $env:AppData)).length -gt 0kb)) } }
      SetScript = {
        $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
        if ((Test-Path -Path ('{0}\Mozilla\OpenCloudConfig\OpenCloudConfig.private.key' -f $env:ProgramData) -ErrorAction 'SilentlyContinue') -and (-not ((Test-Path -Path ('{0}\gnupg\secring.gpg' -f $env:AppData) -ErrorAction 'SilentlyContinue') -and ((Get-Item ('{0}\gnupg\secring.gpg' -f $env:AppData)).length -gt 0kb)))) {
          Start-Process ('{0}\System32\diskperf.exe' -f $env:SystemRoot) -ArgumentList '-y' -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.diskperf.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.diskperf.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
          Start-Process $gpg -ArgumentList @('--allow-secret-key-import', '--import', ('{0}\Mozilla\OpenCloudConfig\OpenCloudConfig.private.key' -f $env:ProgramData)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.gpg-import-key.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.gpg-import-key.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
        }
      }
      TestScript = { if ((Test-Path -Path ('{0}\gnupg\secring.gpg' -f $env:AppData) -ErrorAction 'SilentlyContinue') -and ((Get-Item ('{0}\gnupg\secring.gpg' -f $env:AppData)).length -gt 0kb))  { $true } else { $false } }
    }
  }
  File BuildsFolder {
    Type = 'Directory'
    DestinationPath = ('{0}\builds' -f $env:SystemDrive)
    Ensure = 'Present'
  }
  if ($locationType -eq 'AWS') {
    Script FirefoxBuildSecrets {
      DependsOn = @('[Script]GpgKeyImport', '[File]BuildsFolder')
      GetScript = "@{ Script = FirefoxBuildSecrets }"
      SetScript = {
        if ("${env:ProgramFiles(x86)}") {
          $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
        } else{
          $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f $env:ProgramFiles)
        }
        $files = Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/releng-secrets.json' -f $using:sourceOrg, $using:sourceRepo, $using:sourceRev) -UseBasicParsing | ConvertFrom-Json
        foreach ($file in $files) {
          (New-Object Net.WebClient).DownloadFile(('https://s3.amazonaws.com/windows-opencloudconfig-packages/FirefoxBuildResources/{0}.gpg?raw=true' -f $file), ('{0}\builds\{1}.gpg' -f $env:SystemDrive, $file))
          Start-Process $gpg -ArgumentList @('-d', ('{0}\builds\{1}.gpg' -f $env:SystemDrive, $file)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\builds\{1}' -f $env:SystemDrive, $file) -RedirectStandardError ('{0}\log\{1}.gpg-decrypt-{2}.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $file)
          Remove-Item -Path ('{0}\builds\{1}.gpg' -f $env:SystemDrive, $file) -Force
        }
      }
      TestScript = { if ((Test-Path -Path ('{0}\builds\*.tok' -f $env:SystemDrive) -ErrorAction 'SilentlyContinue') -and (-not (Compare-Object -ReferenceObject (Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/releng-secrets.json' -f $using:sourceOrg, $using:sourceRepo, $using:sourceRev) -UseBasicParsing | ConvertFrom-Json) -DifferenceObject (Get-ChildItem -Path ('{0}\builds' -f $env:SystemDrive) | Where-Object { !$_.PSIsContainer } | % { $_.Name })))) { $true } else { $false } }
    }
  }

  if ($locationType -eq 'AWS') {
    try {
      $instancekey = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/meta-data/public-keys' -UseBasicParsing).Content
    } catch {
      # handle worker manager instances that are created without keys
      $instancekey = ''
    }
    if ($instancekey.StartsWith('0=mozilla-taskcluster-worker-')) {
      # ami creation instance
      $workerType = $instancekey.Replace('0=mozilla-taskcluster-worker-', '')
    } else {
      # provisioned worker
      $workerType = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/user-data' -UseBasicParsing | ConvertFrom-Json).workerType
    }
    if ($workerType) {
      $manifest = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/{3}.json?{4}' -f $sourceOrg, $sourceRepo, $sourceRev, $workerType, [Guid]::NewGuid()) -UseBasicParsing).Content.Replace('mozilla-releng/OpenCloudConfig/master', ('{0}/{1}/{2}' -f $sourceOrg, $sourceRepo, $sourceRev)) | ConvertFrom-Json)
    }
  } elseif ($locationType -eq 'GCP') {
    $workerType = (Invoke-WebRequest -Uri 'http://169.254.169.254/computeMetadata/v1beta1/instance/attributes/taskcluster' -UseBasicParsing | ConvertFrom-Json).workerConfig.openCloudConfig.workerType
    if ($workerType) {
      $manifest = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/{3}.json?{4}' -f $sourceOrg, $sourceRepo, $sourceRev, $workerType, [Guid]::NewGuid()) -UseBasicParsing).Content.Replace('mozilla-releng/OpenCloudConfig/master', ('{0}/{1}/{2}' -f $sourceOrg, $sourceRepo, $sourceRev)) | ConvertFrom-Json)
    }
  } elseif ($locationType -eq 'Azure') {
    try {
      $workerType = (@(((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version={0}' -f '2019-06-04')).Content) | ConvertFrom-Json).compute.tagsList | ? { $_.name -eq 'workerType' })[0].value
    } catch {
      $workerType = $false
    }
    if ($workerType) {
      $manifest = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/{3}.json?{4}' -f $sourceOrg, $sourceRepo, $sourceRev, $workerType, [Guid]::NewGuid()) -UseBasicParsing).Content.Replace('mozilla-releng/OpenCloudConfig/master', ('{0}/{1}/{2}' -f $sourceOrg, $sourceRepo, $sourceRev)) | ConvertFrom-Json)
    }
  } else {
    switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
      'Microsoft Windows 7*' {
        $workerType = 'gecko-t-win7-32-hw'
      }
      'Microsoft Windows 10*' {
        if (${env:PROCESSOR_ARCHITEW6432} -eq 'ARM64') {
          $workerType = 'gecko-t-win10-a64-beta'
        } elseif (Test-Path -Path 'C:\dsc\GW10UX.semaphore' -ErrorAction 'SilentlyContinue') {
          $workerType = 'gecko-t-win10-64-ux'
        } else {
          $workerType = 'gecko-t-win10-64-hw'
        }
      } 
      'Microsoft Windows Server 2012*' {
        $workerType = 'gecko-1-b-win2012'
      }
      'Microsoft Windows Server 2016*' {
        $workerType = 'gecko-1-b-win2016'
      }
      default {
        $workerType = $false
      }
    }
    if ($workerType) {
      $manifestUri = ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/{3}.json?{4}' -f $sourceOrg, $sourceRepo, $sourceRev, $workerType, [Guid]::NewGuid())
      $manifest = ((Invoke-WebRequest -Uri $manifestUri -UseBasicParsing).Content.Replace('mozilla-releng/OpenCloudConfig/master', ('{0}/{1}/{2}' -f $sourceOrg, $sourceRepo, $sourceRev)) | ConvertFrom-Json)
      Write-Log -severity 'debug' -message ('xDynamicConfig :: manifest uri determined as: {0}' -f $manifestUri)
    } else {
      $manifest = ('{"Items":[{"ComponentType":"DirectoryCreate","Path":"$env:SystemDrive\\log"}]}' | ConvertFrom-Json)
      Write-Log -severity 'warn' -message 'xDynamicConfig :: failed to find a suitable manifest'
    }
  }

  # this hashtable maps json manifest component types to DSC component types for dependency mapping
  $componentMap = @{
    'DirectoryCreate' = 'File';
    'DirectoryDelete' = 'Script';
    'DirectoryCopy' = 'File';
    'CommandRun' = 'Script';
    'FileDownload' = 'Script';
    'ChecksumFileDownload' = 'Script';
    'SymbolicLink' = 'Script';
    'ExeInstall' = 'Script';
    'MsiInstall' = 'Package';
    'MsuInstall' = 'xHotfix';
    'WindowsFeatureInstall' = 'WindowsFeature';
    'ZipInstall' = 'xArchive';
    'ServiceControl' = 'xService';
    'EnvironmentVariableSet' = 'Script';
    'EnvironmentVariableUniqueAppend' = 'Script';
    'EnvironmentVariableUniquePrepend' = 'Script';
    'RegistryKeySet' = 'Registry';
    'RegistryValueSet' = 'Registry';
    'DisableIndexing' = 'Script';
    'FirewallRule' = 'Script';
    'ReplaceInFile' = 'Script'
  }
  Log Manifest {
    Message = ('Manifest: {0}' -f $manifest)
  }
  foreach ($item in $manifest.Components) {
    switch ($item.ComponentType) {
      'DirectoryCreate' {
        File ('DirectoryCreate_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Ensure = 'Present'
          Type = 'Directory'
          DestinationPath = $($item.Path)
        }
        Log ('Log_DirectoryCreate_{0}' -f $item.ComponentName) {
          DependsOn = ('[File]DirectoryCreate_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'DirectoryDelete' {
        Script ('DirectoryDelete_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ DirectoryDelete = $($item.Path) }"
          SetScript = {
            Invoke-DirectoryDelete -verbose -component $using:item -eventLogSource 'occ-dsc'
          }
          TestScript = {
            return Confirm-LogValidation -source 'occ-dsc' -satisfied (Confirm-PathsNotExistOrNotRequested -items @($using:item.Path) -verbose) -verbose
          }
        }
        Log ('Log_DirectoryDelete_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]DirectoryDelete_{0}' -f $($item.Path).Replace(':', '').Replace('\', '_'))
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'DirectoryCopy' {
        File ('DirectoryCopy_{0}' -f $item.ComponentName) {
          Ensure = 'Present'
          Type = 'Directory'
          Recurse = $true
          SourcePath = $item.Source
          DestinationPath = $item.Target
        }
        Log ('Log_DirectoryCopy_{0}' -f $item.ComponentName) {
          DependsOn = ('[File]DirectoryCopy_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'CommandRun' {
        Script ('CommandRun_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ CommandRun = $item.ComponentName }"
          SetScript = {
            Invoke-CommandRun -verbose -component $using:item -eventLogSource 'occ-dsc'
          }
          TestScript = {
            return Confirm-LogValidation -source 'occ-dsc' -satisfied (Confirm-All -verbose -source 'occ-dsc' -componentName $using:item.ComponentName -validations $using:item.Validate) -verbose
          }
        }
        Log ('Log_CommandRun_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]CommandRun_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'FileDownload' {
        Script ('FileDownload_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ FileDownload = $item.ComponentName }"
          SetScript = {
            Invoke-FileDownload -verbose -component $using:item -localPath $using:item.Target -eventLogSource 'occ-dsc'
          }
          TestScript = {
            return ((Confirm-LogValidation -source 'occ-dsc' -satisfied (Confirm-PathsExistOrNotRequested -items @($using:item.Target) -verbose) -verbose) -and ((-not ($using:item.sha512)) -or ((Get-FileHash -Path $using:item.Target -Algorithm 'SHA512').Hash -eq $using:item.sha512)))
          }
        }
        Log ('Log_FileDownload_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]FileDownload_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'ChecksumFileDownload' {
        Script ('ChecksumFileDownload_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ ChecksumFileDownload = $item.ComponentName }"
          SetScript = {
            Invoke-FileDownload -verbose -component $using:item -localPath ('{0}\Temp\{1}' -f $env:SystemRoot, [IO.Path]::GetFileName($using:item.Target)) -eventLogSource 'occ-dsc'
          }
          TestScript = { return $false }
        }
        File ('ChecksumFileCopy_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]ChecksumFileDownload_{0}' -f $item.ComponentName)
          Type = 'File'
          Checksum = 'SHA-1'
          SourcePath = ('{0}\Temp\{1}' -f $env:SystemRoot, [IO.Path]::GetFileName($item.Target))
          DestinationPath = $item.Target
          Ensure = 'Present'
          Force = $true
        }
        Log ('Log_ChecksumFileDownload_{0}' -f $item.ComponentName) {
          DependsOn = ('[File]ChecksumFileCopy_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'SymbolicLink' {
        Script ('SymbolicLink_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ SymbolicLink = $item.ComponentName }"
          SetScript = {
            Invoke-SymbolicLink -verbose -component $using:item -eventLogSource 'occ-dsc'
          }
          TestScript = {
            return Confirm-LogValidation -source 'occ-dsc' -satisfied ((Test-Path -Path $using:item.Link -ErrorAction 'SilentlyContinue') -and ((Get-Item $using:item.Link).Attributes.ToString() -match "ReparsePoint")) -verbose
          }
        }
        Log ('Log_SymbolicLink_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]SymbolicLink_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'ExeInstall' {
        Script ('ExeDownload_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ ExeDownload = $item.ComponentName }"
          SetScript = {
            Invoke-FileDownload -verbose -component $using:item -localPath ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName })) -eventLogSource 'occ-dsc'
          }
          TestScript = {
            $tempFile = ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName }))
            return (Test-Path -Path $tempFile -ErrorAction 'SilentlyContinue')
          }
        }
        Log ('Log_ExeDownload_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]ExeDownload_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, download completed' -f $item.ComponentType, $item.ComponentName)
        }
        Script ('ExeInstall_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]ExeDownload_{0}' -f $item.ComponentName)
          GetScript = "@{ ExeInstall = $item.ComponentName }"
          SetScript = {
            Invoke-LoggedCommandRun -verbose -componentName $using:item.ComponentName -command ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName })) -arguments @($using:item.Arguments | % { $($_) }) -timeoutInSeconds $(if ($using:item.Timeout) { [int]$using:item.Timeout } else { 600 }) -waitInSeconds $(if ($using:item.Wait) { [int]$using:item.Wait } else { 0 }) -eventLogSource 'occ-dsc'
          }
          TestScript = {
            return Confirm-LogValidation -source 'occ-dsc' -satisfied (Confirm-All -verbose -source 'occ-dsc' -componentName $using:item.ComponentName -validations $using:item.Validate) -verbose
          }
        }
        Log ('Log_ExeInstall_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]ExeInstall_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'MsiInstall' {
        Script ('MsiDownload_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ MsiDownload = $item.ComponentName }"
          SetScript = {
            Invoke-FileDownload -verbose -component $using:item -localPath ('{0}\Temp\{1}_{2}.msi' -f $env:SystemRoot, $using:item.ComponentName, $using:item.ProductId) -eventLogSource 'occ-dsc'
          }
          TestScript = { return (Test-Path -Path ('{0}\Temp\{1}_{2}.msi' -f $env:SystemRoot, $using:item.ComponentName, $using:item.ProductId) -ErrorAction 'SilentlyContinue') }
        }
        Log ('Log_MsiDownload_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]MsiDownload_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, download completed' -f $item.ComponentType, $item.ComponentName)
        }
        Package ('MsiInstall_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Name = $item.Name
          Path = ('{0}\Temp\{1}_{2}.msi' -f $env:SystemRoot, $item.ComponentName, $item.ProductId)
          ProductId = $item.ProductId
          Ensure = 'Present'
          Arguments = $item.Arguments
          LogPath = ('{0}\log\{1}-{2}.msi-install.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $item.ComponentName)
        }
        Log ('Log_MsiInstall_{0}' -f $item.ComponentName) {
          DependsOn = ('[Package]MsiInstall_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'MsuInstall' {
        Script ('MsuDownload_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ MsuDownload = $item.ComponentName }"
          SetScript = {
            Invoke-FileDownload -verbose -component $using:item -localPath ('{0}\Temp\{1}.msu' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName })) -eventLogSource 'occ-dsc'
          }
          TestScript = { return (Test-Path -Path ('{0}\Temp\{1}.msu' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName })) -ErrorAction 'SilentlyContinue') }
        }
        Log ('Log_MsuDownload_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]MsuDownload_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, download completed' -f $item.ComponentType, $item.ComponentName)
        }
        xHotfix ('MsuInstall_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Id = $item.Id
          Path = ('{0}\Temp\{1}.msu' -f $env:SystemRoot, $(if ($item.sha512) { $item.sha512 } else { $item.ComponentName }))
          Ensure = 'Present'
        }
        Log ('Log_MsuInstall_{0}' -f $item.ComponentName) {
          DependsOn = ('[xHotfix]MsuInstall_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'WindowsFeatureInstall' {
        WindowsFeature ('WindowsFeatureInstall_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Name = $item.Name
          Ensure = 'Present'
        }
        Log ('Log_WindowsFeatureInstall_{0}' -f $item.ComponentName) {
          DependsOn = ('[WindowsFeature]WindowsFeatureInstall_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'ZipInstall' {
        Script ('ZipDownload_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ ZipDownload = $item.ComponentName }"
          SetScript = {
            Invoke-FileDownload -verbose -component $using:item -localPath ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName })) -eventLogSource 'occ-dsc'
          }
          TestScript = {
            $tempFile = ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName }))
            return (Test-Path -Path $tempFile -ErrorAction 'SilentlyContinue')
          }
        }
        Log ('Log_ZipDownload_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]ZipDownload_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, download completed' -f $item.ComponentType, $item.ComponentName)
        }
        xArchive ('ZipInstall_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Path = ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $(if ($item.sha512) { $item.sha512 } else { $item.ComponentName }))
          Destination = $item.Destination
          Ensure = 'Present'
        }
        Log ('Log_ZipInstall_{0}' -f $item.ComponentName) {
          DependsOn = ('[xArchive]ZipInstall_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'ServiceControl' {
        xService ('ServiceControl_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Name = $item.Name
          State = $item.State
          StartupType = $item.StartupType
        }
        Log ('Log_ServiceControl_{0}' -f $item.ComponentName) {
          DependsOn = ('[xService]ServiceControl_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'EnvironmentVariableSet' {
        Script ('EnvironmentVariableSet_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ EnvironmentVariableSet = $item.ComponentName }"
          SetScript = {
            Invoke-EnvironmentVariableSet -verbose -component $using:item -eventLogSource 'occ-dsc'
          }
          TestScript = {
            return Confirm-LogValidation -source 'occ-dsc' -satisfied ((Get-ChildItem env: | ? { $_.Name -ieq $using:item.Name } | Select-Object -first 1).Value -eq $using:item.Value) -verbose
          }
        }
        Log ('Log_EnvironmentVariableSet_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]EnvironmentVariableSet_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'EnvironmentVariableUniqueAppend' {
        Script ('EnvironmentVariableUniqueAppend_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ EnvironmentVariableUniqueAppend = $item.ComponentName }"
          SetScript = {
            Invoke-EnvironmentVariableUniqueAppend -verbose -component $using:item -eventLogSource 'occ-dsc'
          }
          TestScript = { return $false }
        }
        Log ('Log_EnvironmentVariableUniqueAppend_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]EnvironmentVariableUniqueAppend_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'EnvironmentVariableUniquePrepend' {
        Script ('EnvironmentVariableUniquePrepend_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ EnvironmentVariableUniquePrepend = $item.ComponentName }"
          SetScript = {
            Invoke-EnvironmentVariableUniquePrepend -verbose -component $using:item -eventLogSource 'occ-dsc'
          }
          TestScript = { return $false }
        }
        Log ('Log_EnvironmentVariableUniquePrepend_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]EnvironmentVariableUniquePrepend_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'RegistryKeySet' {
        Registry ('RegistryKeySet_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Ensure = 'Present'
          Force = $true
          Key = $item.Key
          ValueName = $item.ValueName
        }
        Log ('Log_RegistryKeySet_{0}' -f $item.ComponentName) {
          DependsOn = ('[Registry]RegistryKeySet_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'RegistryValueSet' {
        if ($item.SetOwner) {
          Script ('RegistryTakeOwnership_{0}' -f $item.ComponentName) {
            DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
            GetScript = "@{ RegistryTakeOwnership = $item.ComponentName }"
            SetScript = {
              Invoke-RegistryKeySetOwner -verbose -component $using:item -eventLogSource 'occ-dsc'
            }
            TestScript = { return $false }
          }
        }
        Registry ('RegistryValueSet_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Ensure = 'Present'
          Force = $true
          Key = $item.Key
          ValueName = $item.ValueName
          ValueType = $item.ValueType
          Hex = $item.Hex
          ValueData = $item.ValueData
        }
        Log ('Log_RegistryValueSet_{0}' -f $item.ComponentName) {
          DependsOn = ('[Registry]RegistryValueSet_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'DisableIndexing' {
        Script ( 'DisableIndexing_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ DisableIndexing = $item.ComponentName }"
          SetScript = {
            Invoke-DisableIndexing -verbose -component $using:item -eventLogSource 'occ-dsc'
          }
          TestScript = { return (Confirm-DisableIndexing -verbose -component $using:item -eventLogSource 'occ-dsc') }
        }
        Log ('Log_DisableIndexing_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]DisableIndexing_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'FirewallRule' {
        Script ('FirewallRule_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ FirewallRule = $item.ComponentName }"
          SetScript = {
            Invoke-FirewallRuleSet -verbose -component $using:item -eventLogSource 'occ-dsc'
          }
          TestScript = { return (Confirm-FirewallRuleSet -verbose -component $using:item -eventLogSource 'occ-dsc') }
        }
        Log ('Log_FirewallRule_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]FirewallRule_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'ReplaceInFile' {
        Script ('ReplaceInFile_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ ReplaceInFile = $item.ComponentName }"
          SetScript = {
            Invoke-ReplaceInFile -verbose -component $using:item -eventLogSource 'occ-dsc'
          }
          TestScript = { return $false }
        }
        Log ('Log_ReplaceInFile_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]ReplaceInFile_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
    }
  }
}
