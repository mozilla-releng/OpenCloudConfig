<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

Configuration xDynamicConfig {
  Import-DscResource -ModuleName PSDesiredStateConfiguration,xPSDesiredStateConfiguration,xWindowsUpdate,OpenCloudConfig

  $sourceOrg = $(if ((Test-Path -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -ErrorAction SilentlyContinue) -and (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Organisation' -ErrorAction SilentlyContinue)) { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Organisation').Organisation } else { 'mozilla-releng' })
  $sourceRepo = $(if ((Test-Path -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -ErrorAction SilentlyContinue) -and (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Repository' -ErrorAction SilentlyContinue)) { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Repository').Repository } else { 'OpenCloudConfig' })
  $sourceRev = $(if ((Test-Path -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -ErrorAction SilentlyContinue) -and (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Revision' -ErrorAction SilentlyContinue)) { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Name 'Revision').Revision } else { 'master' })

  if ((Get-Service 'Ec2Config' -ErrorAction SilentlyContinue) -or (Get-Service 'AmazonSSMAgent' -ErrorAction SilentlyContinue)) {
    $locationType = 'AWS'
  } else {
    $locationType = 'DataCenter'
  }

  if ($locationType -eq 'AWS') {
    Script GpgKeyImport {
      DependsOn = @('[Script]ExeInstall_GpgForWin')
      GetScript = { @{ Result = (((Test-Path -Path ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction SilentlyContinue) -and ((Get-Item ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb)) -or ((Test-Path -Path ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction SilentlyContinue) -and ((Get-Item ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb))) } }
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
          # todo: pipe key to gpg import, avoiding disk write
          Start-Process ('{0}\System32\diskperf.exe' -f $env:SystemRoot) -ArgumentList '-y' -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.diskperf.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.diskperf.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
          [IO.File]::WriteAllLines(('{0}\Temp\private.key' -f $env:SystemRoot), $gpgPrivateKey)
          Start-Process $gpg -ArgumentList @('--allow-secret-key-import', '--import', ('{0}\Temp\private.key' -f $env:SystemRoot)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.gpg-import-key.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.gpg-import-key.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
          Remove-Item -Path ('{0}\Temp\private.key' -f $env:SystemRoot) -Force
        }
      }
      TestScript = { if (((Test-Path -Path ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction SilentlyContinue) -and ((Get-Item ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb)) -or ((Test-Path -Path ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction SilentlyContinue) -and ((Get-Item ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb)))  { $true } else { $false } }
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
      TestScript = { if ((Test-Path -Path ('{0}\builds\*.tok' -f $env:SystemDrive) -ErrorAction SilentlyContinue) -and (-not (Compare-Object -ReferenceObject (Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/releng-secrets.json' -f $using:sourceOrg, $using:sourceRepo, $using:sourceRev) -UseBasicParsing | ConvertFrom-Json) -DifferenceObject (Get-ChildItem -Path ('{0}\builds' -f $env:SystemDrive) | Where-Object { !$_.PSIsContainer } | % { $_.Name })))) { $true } else { $false } }
    }
  }

  if ($locationType -eq 'AWS') {
    $instancekey = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/meta-data/public-keys' -UseBasicParsing).Content
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
  } else {
    switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
      'Microsoft Windows 7*' {
        $manifest = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/gecko-t-win7-32-hw.json?{3}' -f $sourceOrg, $sourceRepo, $sourceRev, [Guid]::NewGuid()) -UseBasicParsing).Content.Replace('mozilla-releng/OpenCloudConfig/master', ('{0}/{1}/{2}' -f $sourceOrg, $sourceRepo, $sourceRev)) | ConvertFrom-Json)
      }
      'Microsoft Windows 10*' {
        if (Test-Path -Path 'C:\dsc\GW10UX.semaphore' -ErrorAction SilentlyContinue) {
          $manifest = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/gecko-t-win10-64-ux.json?{3}' -f $sourceOrg, $sourceRepo, $sourceRev, [Guid]::NewGuid()) -UseBasicParsing).Content.Replace('mozilla-releng/OpenCloudConfig/master', ('{0}/{1}/{2}' -f $sourceOrg, $sourceRepo, $sourceRev)) | ConvertFrom-Json)
        } else {
          $manifest = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/gecko-t-win10-64-hw.json?{3}' -f $sourceOrg, $sourceRepo, $sourceRev, [Guid]::NewGuid()) -UseBasicParsing).Content.Replace('mozilla-releng/OpenCloudConfig/master', ('{0}/{1}/{2}' -f $sourceOrg, $sourceRepo, $sourceRev)) | ConvertFrom-Json)
        }
      } 
      'Microsoft Windows Server 2012*' {
        $manifest = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/gecko-1-b-win2012.json?{3}' -f $sourceOrg, $sourceRepo, $sourceRev, [Guid]::NewGuid()) -UseBasicParsing).Content.Replace('mozilla-releng/OpenCloudConfig/master', ('{0}/{1}/{2}' -f $sourceOrg, $sourceRepo, $sourceRev)) | ConvertFrom-Json)
      }
      'Microsoft Windows Server 2016*' {
        $manifest = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/userdata/Manifest/gecko-1-b-win2016.json?{3}' -f $sourceOrg, $sourceRepo, $sourceRev, [Guid]::NewGuid()) -UseBasicParsing).Content.Replace('mozilla-releng/OpenCloudConfig/master', ('{0}/{1}/{2}' -f $sourceOrg, $sourceRepo, $sourceRev)) | ConvertFrom-Json)
      }
      default {
        $manifest = ('{"Items":[{"ComponentType":"DirectoryCreate","Path":"$env:SystemDrive\\log"}]}' | ConvertFrom-Json)
      }
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
            Invoke-DirectoryDelete -path $($using:item.Path) -eventLogSource 'occ-dsc'
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
            Invoke-CommandRun -command $($using:item.Command) -arguments @($using:item.Arguments | % { $($_) }) -eventLogSource 'occ-dsc'
          }
          TestScript = {
            return Confirm-LogValidation -source 'occ-dsc' -satisfied (Confirm-All -validations $using:item.Validate -verbose) -verbose
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
            Invoke-FileDownload -localPath $using:item.Target -sha512 $($using:item.sha512) -tooltoolHost 'tooltool.mozilla-releng.net' -tokenPath ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -url $using:item.Source -eventLogSource 'occ-dsc'
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
            Invoke-FileDownload -localPath ('{0}\Temp\{1}' -f $env:SystemRoot, [IO.Path]::GetFileName($using:item.Target)) -sha512 $($using:item.sha512) -tooltoolHost 'tooltool.mozilla-releng.net' -tokenPath ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -url $using:item.Source -eventLogSource 'occ-dsc'
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
            Invoke-SymbolicLink -target $using:item.Target -link $using:item.Link -eventLogSource 'occ-dsc'
          }
          TestScript = {
            return Confirm-LogValidation -source 'occ-dsc' -satisfied ((Test-Path -Path $using:item.Link -ErrorAction SilentlyContinue) -and ((Get-Item $using:item.Link).Attributes.ToString() -match "ReparsePoint")) -verbose
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
            Invoke-FileDownload -localPath ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName })) -sha512 $($using:item.sha512) -tooltoolHost 'tooltool.mozilla-releng.net' -tokenPath ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -url $using:item.Url -eventLogSource 'occ-dsc'
          }
          TestScript = {
            if ($using:item.sha512) {
              $tempFile = ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $using:item.sha512)
            } else {
              $tempFile = ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $using:item.ComponentName)
            }
            return (Test-Path -Path $tempFile -ErrorAction SilentlyContinue)
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
            Invoke-CommandRun -command ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName })) -arguments @($using:item.Arguments | % { $($_) }) -eventLogSource 'occ-dsc'
          }
          TestScript = {
            return Confirm-LogValidation -source 'occ-dsc' -satisfied (Confirm-All -validations $using:item.Validate -verbose) -verbose
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
            Invoke-FileDownload -localPath ('{0}\Temp\{1}_{2}.msi' -f $env:SystemRoot, $using:item.ComponentName, $using:item.ProductId) -sha512 $($using:item.sha512) -tooltoolHost 'tooltool.mozilla-releng.net' -tokenPath ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -url $using:item.Url -eventLogSource 'occ-dsc'
          }
          TestScript = { return (Test-Path -Path ('{0}\Temp\{1}_{2}.msi' -f $env:SystemRoot, $using:item.ComponentName, $using:item.ProductId) -ErrorAction SilentlyContinue) }
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
          LogPath = ('{0}\log\{1}-{2}.msi.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $item.ComponentName)
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
            Invoke-FileDownload -localPath ('{0}\Temp\{1}.msu' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName })) -sha512 $($using:item.sha512) -tooltoolHost 'tooltool.mozilla-releng.net' -tokenPath ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -url $using:item.Url -eventLogSource 'occ-dsc'
          }
          TestScript = { return (Test-Path -Path ('{0}\Temp\{1}.msu' -f $env:SystemRoot, $using:item.ComponentName) -ErrorAction SilentlyContinue) }
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
            Invoke-FileDownload -localPath ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $(if ($using:item.sha512) { $using:item.sha512 } else { $using:item.ComponentName })) -sha512 $($using:item.sha512) -tooltoolHost 'tooltool.mozilla-releng.net' -tokenPath ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -url $using:item.Url -eventLogSource 'occ-dsc'
          }
          TestScript = {
            if ($using:item.sha512) {
              $tempFile = ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $using:item.sha512)
            } else {
              $tempFile = ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $using:item.ComponentName)
            }
            return (Test-Path -Path $tempFile -ErrorAction SilentlyContinue)
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
            Invoke-EnvironmentVariableSet -name $using:item.Name -value $using:item.Value -target $using:item.Target -eventLogSource 'occ-dsc'
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
            Invoke-EnvironmentVariableSet -name $using:item.Name -value (@((@(((Get-ChildItem env: | ? { $_.Name -ieq $using:item.Name } | Select-Object -first 1).Value) -split ';') + $using:item.Values) | select -Unique) -join ';') $using:item.Target -eventLogSource 'occ-dsc'
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
            Invoke-EnvironmentVariableSet -name $using:item.Name -value (@(($using:item.Values + @(((Get-ChildItem env: | ? { $_.Name -ieq $using:item.Name } | Select-Object -first 1).Value) -split ';')) | select -Unique) -join ';') -target $using:item.Target -eventLogSource 'occ-dsc'
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
              Invoke-RegistryKeySetOwner -key $using:item.Key -sid $using:item.SetOwner -eventLogSource 'occ-dsc'
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
            # Disable indexing on all disk volumes.
            Get-WmiObject Win32_Volume -Filter "IndexingEnabled=$true" | Set-WmiInstance -Arguments @{IndexingEnabled=$false}
          }
          TestScript = { return $false }
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
            Invoke-FirewallRuleSet -component $using:item.ComponentName -action $using:item.Action -direction $using:item.Direction -remoteAddress $using:item.RemoteAddress -program $using:item.Program -protocol $using:item.Protocol -localPort $using:item.LocalPort -eventLogSource 'occ-dsc'
          }
          TestScript = {
            if ($using:item.LocalPort) {
              $ruleName = ('{0} ({1} {2} {3}): {4}' -f $using:item.ComponentName, $using:item.Protocol, $using:item.LocalPort, $using:item.Direction, $using:item.Action)
            } elseif ($using:item.Program) {
              $ruleName = ('{0} ({1} {2}): {3}' -f $using:item.ComponentName, $using:item.Program, $using:item.Direction, $using:item.Action)
            } else {
              return $false
            }
            if (Get-Command 'Get-NetFirewallRule' -errorAction SilentlyContinue) {
              return Confirm-LogValidation -source 'occ-dsc' -satisfied ([bool](Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) -verbose
            } else {
              return ((& 'netsh.exe' @('advfirewall', 'firewall', 'show', 'rule', $ruleName)) -notcontains 'No rules match the specified criteria.')
            }
          }
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
            Invoke-ReplaceInFile -path $using:item.Path -matchString $using:item.Match -replaceString $using:item.Replace -eventLogSource 'occ-dsc'
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
  if (($locationType -eq 'AWS') -and ($workerType)) {
    Script CotGpgKeyImport {
      DependsOn = @('[Script]ExeInstall_GpgForWin', '[File]DirectoryCreate_GenericWorkerDirectory')
      GetScript = "@{ Script = CotGpgKeyImport }"
      SetScript = {
        if ("${env:ProgramFiles(x86)}") {
          $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
        } else {
          $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f $env:ProgramFiles)
        }
        try {
          $userdata = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/user-data')
          $cotKey = [regex]::matches($userdata, '<cotGpgKey>((.|\n)*)<\/cotGpgKey>')[0].Groups[1].Value.Trim()
          if ((-not ($cotKey.Contains('-----BEGIN PGP PRIVATE KEY BLOCK-----'))) -or (-not ($cotKey.Contains('-----END PGP PRIVATE KEY BLOCK-----')))) {
            $cotKey = $false
          }
        } catch {
          $cotKey = $false
        }
        if ($cotKey) {
          [IO.File]::WriteAllLines(('{0}\generic-worker\cot.key' -f $env:SystemDrive), $cotKey)
        }
      }
      TestScript = { if ((Test-Path -Path ('{0}\generic-worker\cot.key' -f $env:SystemDrive) -ErrorAction SilentlyContinue))  { $true } else { $false } }
    }
  }
}
