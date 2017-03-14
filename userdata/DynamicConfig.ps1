<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

Configuration DynamicConfig {
  Import-DscResource -ModuleName PSDesiredStateConfiguration
  # SourceRepo is in place to toggle between production and testing environments
    $SourceRepo = "mozilla-releng"
	
  if (Get-Service "Ec2Config" -ErrorAction SilentlyContinue) {
    $LocationType = "AWS"
  } else {
    $LocationType = "DataCenter"
  }
	
  If ($LocationType -eq "AWS") { 
    Script GpgKeyImport {
      DependsOn = @('[Script]InstallSupportingModules', '[Script]ExeInstall_GpgForWin')
      GetScript = { @{ Result = (((Test-Path -Path ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction SilentlyContinue) -and ((Get-Item ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb)) -or ((Test-Path -Path ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction SilentlyContinue) -and ((Get-Item ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb))) } }
      SetScript = {
        if ("${env:ProgramFiles(x86)}") {
          $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
        } else{
          $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f $env:ProgramFiles)
        }
        # todo: pipe key to gpg import, avoiding disk write
        Start-Process ('{0}\System32\diskperf.exe' -f $env:SystemRoot) -ArgumentList '-y' -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.diskperf.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.diskperf.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
        [IO.File]::WriteAllLines(('{0}\Temp\private.key' -f $env:SystemRoot), [regex]::matches((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/user-data'), '(?s)-----BEGIN PGP PRIVATE KEY BLOCK-----.*-----END PGP PRIVATE KEY BLOCK-----').Value)
        Start-Process $gpg -ArgumentList @('--allow-secret-key-import', '--import', ('{0}\Temp\private.key' -f $env:SystemRoot)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.gpg-import-key.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.gpg-import-key.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
        Remove-Item -Path ('{0}\Temp\private.key' -f $env:SystemRoot) -Force
      }
      TestScript = { if (((Test-Path -Path ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction SilentlyContinue) -and ((Get-Item ('{0}\SysWOW64\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb)) -or ((Test-Path -Path ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot) -ErrorAction SilentlyContinue) -and ((Get-Item ('{0}\System32\config\systemprofile\AppData\Roaming\gnupg\secring.gpg' -f $env:SystemRoot)).length -gt 0kb)))  { $true } else { $false } }
    }
  }
  File BuildsFolder {
    Type = 'Directory'
    DestinationPath = ('{0}\builds' -f $env:SystemDrive)
    Ensure = 'Present'
  }
  If ($LocationType -eq "AWS") { 
    Script FirefoxBuildSecrets {
      DependsOn = @('[Script]GpgKeyImport', '[File]BuildsFolder')
      GetScript = "@{ Script = FirefoxBuildSecrets }"
      SetScript = {
        if ("${env:ProgramFiles(x86)}") {
          $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
        } else{
          $gpg = ('{0}\GNU\GnuPG\pub\gpg.exe' -f $env:ProgramFiles)
        }
        $files = Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Manifest/releng-secrets.json' -UseBasicParsing | ConvertFrom-Json
        foreach ($file in $files) {
          (New-Object Net.WebClient).DownloadFile(('https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Configuration/FirefoxBuildResources/{0}.gpg?raw=true' -f $file), ('{0}\builds\{1}.gpg' -f $env:SystemDrive, $file))
          Start-Process $gpg -ArgumentList @('-d', ('{0}\builds\{1}.gpg' -f $env:SystemDrive, $file)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\builds\{1}' -f $env:SystemDrive, $file) -RedirectStandardError ('{0}\log\{1}.gpg-decrypt-{2}.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $file)
          Remove-Item -Path ('{0}\builds\{1}.gpg' -f $env:SystemDrive, $file) -Force
        }
      }
      TestScript = { if ((Test-Path -Path ('{0}\builds\*.tok' -f $env:SystemDrive) -ErrorAction SilentlyContinue) -and (-not (Compare-Object -ReferenceObject (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Manifest/releng-secrets.json' -UseBasicParsing | ConvertFrom-Json) -DifferenceObject (Get-ChildItem -Path ('{0}\builds' -f $env:SystemDrive) | Where-Object { !$_.PSIsContainer } | % { $_.Name })))) { $true } else { $false } }
    }
  }

  $supportingModules = @(
    'https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/OCC-User.psm1',
    'https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/OCC-Validate.psm1',
    'https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/OCC-Archive.psm1'
  )
  Script InstallSupportingModules {
    GetScript = "@{ Script = InstallSupportingModules }"
    SetScript = {
      $modulesPath = ('{0}\Modules' -f $pshome)
      foreach ($url in $using:supportingModules) {
        $filename = [IO.Path]::GetFileName($url)
        $moduleName = [IO.Path]::GetFileNameWithoutExtension($filename)
        $modulePath = ('{0}\{1}' -f $modulesPath, $moduleName)
        if (Test-Path -Path $modulePath -ErrorAction SilentlyContinue) {
          Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
          Remove-Item -path $modulePath -recurse -force
        }
        New-Item -ItemType Directory -Force -Path $modulePath
        (New-Object Net.WebClient).DownloadFile(('{0}?{1}' -f $url, [Guid]::NewGuid()), ('{0}\{1}' -f $modulePath, $filename))
        Unblock-File -Path ('{0}\{1}' -f $modulePath, $filename)
        Import-Module -Name $moduleName
      }
    }
    TestScript = { return $false }
  }

  If ($LocationType -eq "AWS") { 
    $instancekey = (Invoke-WebRequest -Uri 'http://169.254.169.254/latest/meta-data/public-keys' -UseBasicParsing).Content
    if ($instancekey.StartsWith('0=aws-provisioner-v1-managed:')) {
      # provisioned worker
      $workerType = $instancekey.Split(':')[1]
    } else {
      # ami creation instance
      $workerType = $instancekey.Replace('0=mozilla-taskcluster-worker-', '')
    }
    if ($workerType) {
      if ($workerType.StartsWith('loan-')) {		
	      # loan workers share a manifest with gecko parent worker type.		
	      $manifest = (Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Manifest/{0}.json?{1}' -f ($workerType.Replace('loan-', 'gecko-') -replace ".{3}$"), [Guid]::NewGuid()) -UseBasicParsing | ConvertFrom-Json)		
	    } else {
      $manifest = (Invoke-WebRequest -Uri ("https://raw.githubusercontent.com/$SourceRepo/OpenCloudConfig/master/userdata/Manifest/{0}.json?{1}" -f $workerType, [Guid]::NewGuid()) -UseBasicParsing | ConvertFrom-Json)
    }
	}
  } else {
    switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
      'Microsoft Windows 7*' {
        $manifest = (Invoke-WebRequest -Uri ("https://raw.githubusercontent.com/$SourceRepo/OpenCloudConfig/master/userdata/Manifest/gecko-t-win7-32-hw.json?{0}" -f [Guid]::NewGuid()) -UseBasicParsing | ConvertFrom-Json)
      }
      'Microsoft Windows 10*' {
        $manifest = (Invoke-WebRequest -Uri ("https://raw.githubusercontent.com/$SourceRepo/OpenCloudConfig/master/userdata/Manifest/gecko-t-win10-64-hw.json?{0}" -f [Guid]::NewGuid()) -UseBasicParsing | ConvertFrom-Json)
      }
      'Microsoft Windows Server 2012*' {
        $manifest = (Invoke-WebRequest -Uri ("https://raw.githubusercontent.com/$SourceRepo/OpenCloudConfig/master/userdata/Manifest/gecko-1-b-win2012.json?{0}" -f [Guid]::NewGuid()) -UseBasicParsing | ConvertFrom-Json)
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
    'WindowsFeatureInstall' = 'WindowsFeature';
    'ZipInstall' = 'Archive';
    'ServiceControl' = 'Service';
    'EnvironmentVariableSet' = 'Script';
    'EnvironmentVariableUniqueAppend' = 'Script';
    'EnvironmentVariableUniquePrepend' = 'Script';
    'RegistryKeySet' = 'Registry';
    'RegistryValueSet' = 'Registry';
    'FirewallRule' = 'Script'
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
            try {
              Remove-Item $($using:item.Path) -Confirm:$false -force
            } catch {
              Start-Process 'icacls' -ArgumentList @($($using:item.Path), '/grant', ('{0}:(OI)(CI)F' -f $env:Username), '/inheritance:r') -Wait -NoNewWindow -PassThru | Out-Null
              Remove-Item $($using:item.Path) -Confirm:$false -force
              # todo: another try catch block with move to recycle bin, empty recycle bin
            }
          }
          TestScript = {
            return Log-Validation (Validate-PathsNotExistOrNotRequested -items @($using:item.Path) -verbose) -verbose
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
            Start-Process $($using:item.Command) -ArgumentList @($using:item.Arguments | % { $($_) }) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}-{2}-stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $using:item.ComponentName) -RedirectStandardError ('{0}\log\{1}-{2}-stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $using:item.ComponentName)
          }
          TestScript = {
            return Log-Validation (Validate-All -validations $using:item.Validate -verbose) -verbose
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
            try {
              (New-Object Net.WebClient).DownloadFile($using:item.Source, $using:item.Target)
              Write-Verbose ('Downloaded {0} to {1} on first attempt' -f $using:item.Source, $using:item.Target)
            } catch {
              # handle redirects (eg: sourceforge)
              Invoke-WebRequest -Uri $using:item.Source -OutFile $using:item.Target -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
              Write-Verbose ('Downloaded {0} to {1} on second attempt' -f $using:item.Source, $using:item.Target)
            }
            Unblock-File -Path $using:item.Target
          }
          TestScript = {
            return Log-Validation (Validate-PathsExistOrNotRequested -items @($using:item.Target) -verbose) -verbose
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
            $tempTarget = ('{0}\Temp\{1}' -f $env:SystemRoot, [IO.Path]::GetFileName($using:item.Target))
            if (Test-Path -Path $tempTarget -ErrorAction SilentlyContinue) {
              Remove-Item -Path $tempTarget -Force
              Write-Verbose ('Deleted {0}' -f $tempTarget)
            }
            try {
              (New-Object Net.WebClient).DownloadFile($using:item.Source, $tempTarget)
              Write-Verbose ('Downloaded {0} to {1} on first attempt' -f $using:item.Source, $tempTarget)
            } catch {
              # handle redirects (eg: sourceforge)
              Invoke-WebRequest -Uri $using:item.Source -OutFile $tempTarget -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
              Write-Verbose ('Downloaded {0} to {1} on second attempt' -f $using:item.Source, $tempTarget)
            }
            Unblock-File -Path $tempTarget
          }
          TestScript = { return $false }
        }
        #Script ('ChecksumFileKillProcesses_{0}' -f $item.ComponentName) {
        #  DependsOn = ('[Script]ChecksumFileDownload_{0}' -f $item.ComponentName)
        #  GetScript = "@{ ChecksumFileKillProcesses = $item.ComponentName }"
        #  SetScript = {
        #    $processName = [IO.Path]::GetFileNameWithoutExtension($using:item.Target)
        #    try {
        #      Stop-Process -name $processName -Force
        #      Write-Verbose ('Process: {0} stopped' -f $processName)
        #    } catch {
        #      Write-Verbose ('Failed to stop process: {0}' -f $processName)
        #    }
        #  }
        #  TestScript = {
        #    $tempTarget = ('{0}\Temp\{1}' -f $env:SystemRoot, [IO.Path]::GetFileName($using:item.Target))
        #    $processName = [IO.Path]::GetFileNameWithoutExtension($using:item.Target)
        #    if (([IO.Path]::GetExtension($using:item.Target) -ieq '.exe') -and (
        #      (Test-Path -Path $using:item.Target -ErrorAction SilentlyContinue)) -and (
        #      (Get-FileHash -Path $tempTarget -Algorithm 'SHA1') -ne (Get-FileHash -Path $using:item.Target -Algorithm 'SHA1')) -and (
        #      (@(Get-Process | ? { $_.ProcessName -eq $processName }).length -gt 0))) {
        #      return $false
        #    } else {
        #      return $true
        #    }
        #  }
        #}
        File ('ChecksumFileCopy_{0}' -f $item.ComponentName) {
          #DependsOn = @(('[Script]ChecksumFileDownload_{0}' -f $item.ComponentName), ('[Script]ChecksumFileKillProcesses_{0}' -f $item.ComponentName))
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
            if (Test-Path -Path $using:item.Target -PathType Container -ErrorAction SilentlyContinue) {
              & 'cmd' @('/c', 'mklink', '/D', $using:item.Link, $using:item.Target)
            } elseif (Test-Path -Path $using:item.Target -PathType Leaf -ErrorAction SilentlyContinue) {
              & 'cmd' @('/c', 'mklink', $using:item.Link, $using:item.Target)
            }
          }
          TestScript = {
            return Log-Validation ((Test-Path -Path $using:item.Link -ErrorAction SilentlyContinue) -and ((Get-Item $using:item.Link).Attributes.ToString() -match "ReparsePoint")) -verbose
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
            if (($using:item.sha512) -and (Test-Path -Path ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -ErrorAction SilentlyContinue)) {
              $webClient = New-Object System.Net.WebClient
              $webClient.Headers.Add('Authorization', ('Bearer {0}' -f (Get-Content ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -Raw)))
              $webClient.DownloadFile(('https://api.pub.build.mozilla.org/tooltool/sha512/{0}' -f $using:item.sha512), ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $using:item.ComponentName))
            } else {
              # todo: handle non-http fetches
              try {
                (New-Object Net.WebClient).DownloadFile($using:item.Url, ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $using:item.ComponentName))
              } catch {
                # handle redirects (eg: sourceforge)
                Invoke-WebRequest -Uri $using:item.Url -OutFile ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $using:item.ComponentName) -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
              }
            }
            Unblock-File -Path ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $using:item.ComponentName)
          }
          TestScript = { return (Test-Path -Path ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $using:item.ComponentName) -ErrorAction SilentlyContinue) }
        }
        Log ('Log_ExeDownload_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]ExeDownload_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, download completed' -f $item.ComponentType, $item.ComponentName)
        }
        Script ('ExeInstall_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]ExeDownload_{0}' -f $item.ComponentName)
          GetScript = "@{ ExeInstall = $item.ComponentName }"
          SetScript = {
            $exe = ('{0}\Temp\{1}' -f $env:SystemRoot, $using:item.ComponentName)
            $process = Start-Process $exe -ArgumentList $using:item.Arguments -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}-{2}-stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), [IO.Path]::GetFileNameWithoutExtension($exe)) -RedirectStandardError ('{0}\log\{1}-{2}-stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), [IO.Path]::GetFileNameWithoutExtension($exe))
            if (-not (($process.ExitCode -eq 0) -or ($using:item.AllowedExitCodes -contains $process.ExitCode))) {
              throw
            }
          }
          TestScript = {
            return Log-Validation (Validate-All -validations $using:item.Validate -verbose) -verbose
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
            if (($using:item.sha512) -and (Test-Path -Path ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -ErrorAction SilentlyContinue)) {
              $webClient = New-Object System.Net.WebClient
              $webClient.Headers.Add('Authorization', ('Bearer {0}' -f (Get-Content ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -Raw)))
              $webClient.DownloadFile(('https://api.pub.build.mozilla.org/tooltool/sha512/{0}' -f $using:item.sha512), ('{0}\Temp\{1}.msi' -f $env:SystemRoot, $using:item.ComponentName))
            } else {
              # todo: handle non-http fetches
              try {
                (New-Object Net.WebClient).DownloadFile($using:item.Url, ('{0}\Temp\{1}.msi' -f $env:SystemRoot, $using:item.ComponentName))
              } catch {
                # handle redirects (eg: sourceforge)
                Invoke-WebRequest -Uri $using:item.Url -OutFile ('{0}\Temp\{1}.msi' -f $env:SystemRoot, $using:item.ComponentName) -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
              }
            }
            Unblock-File -Path ('{0}\Temp\{1}.msi' -f $env:SystemRoot, $using:item.ComponentName)
          }
          TestScript = { return (Test-Path -Path ('{0}\Temp\{1}.msi' -f $env:SystemRoot, $using:item.ComponentName) -ErrorAction SilentlyContinue) }
        }
        Log ('Log_MsiDownload_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]MsiDownload_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, download completed' -f $item.ComponentType, $item.ComponentName)
        }
        Package ('MsiInstall_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Name = $item.Name
          Path = ('{0}\Temp\{1}.msi' -f $env:SystemRoot, $item.ComponentName)
          ProductId = $item.ProductId
          Ensure = 'Present'
          LogPath = ('{0}\log\{1}-{2}.msi.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $item.ComponentName)
        }
        Log ('Log_MsiInstall_{0}' -f $item.ComponentName) {
          DependsOn = ('[Package]MsiInstall_{0}' -f $item.ComponentName)
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
            if (($using:item.sha512) -and (Test-Path -Path ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -ErrorAction SilentlyContinue)) {
              $webClient = New-Object System.Net.WebClient
              $webClient.Headers.Add('Authorization', ('Bearer {0}' -f (Get-Content ('{0}\builds\occ-installers.tok' -f $env:SystemDrive) -Raw)))
              $webClient.DownloadFile(('https://api.pub.build.mozilla.org/tooltool/sha512/{0}' -f $using:item.sha512), ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $using:item.ComponentName))
            } else {
            # todo: handle non-http fetches
              try {
                (New-Object Net.WebClient).DownloadFile($using:item.Url, ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $using:item.ComponentName))
              } catch {
                # handle redirects (eg: sourceforge)
                Invoke-WebRequest -Uri $using:item.Url -OutFile ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $using:item.ComponentName) -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
              }
            }
            Unblock-File -Path ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $using:item.ComponentName)
          }
          TestScript = { return (Test-Path -Path ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $using:item.ComponentName) -ErrorAction SilentlyContinue) }
        }
        Log ('Log_ZipDownload_{0}' -f $item.ComponentName) {
          DependsOn = ('[Script]ZipDownload_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, download completed' -f $item.ComponentType, $item.ComponentName)
        }
        Archive ('ZipInstall_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Path = ('{0}\Temp\{1}.zip' -f $env:SystemRoot, $item.ComponentName)
          Destination = $item.Destination
          Ensure = 'Present'
        }
        Log ('Log_ZipInstall_{0}' -f $item.ComponentName) {
          DependsOn = ('[Archive]ZipInstall_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'ServiceControl' {
        Service ('ServiceControl_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          Name = $item.Name
          State = $item.State
          StartupType = $item.StartupType
        }
        Log ('Log_ServiceControl_{0}' -f $item.ComponentName) {
          DependsOn = ('[Service]ServiceControl_{0}' -f $item.ComponentName)
          Message = ('{0}: {1}, completed' -f $item.ComponentType, $item.ComponentName)
        }
      }
      'EnvironmentVariableSet' {
        Script ('EnvironmentVariableSet_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ EnvironmentVariableSet = $item.ComponentName }"
          SetScript = {
            [Environment]::SetEnvironmentVariable($using:item.Name, $using:item.Value, $using:item.Target)
          }
          TestScript = {
            return Log-Validation ((Get-ChildItem env: | ? { $_.Name -ieq $using:item.Name } | Select-Object -first 1).Value -eq $using:item.Value) -verbose
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
            $value = (@((@(((Get-ChildItem env: | ? { $_.Name -ieq $using:item.Name } | Select-Object -first 1).Value) -split ';') + $using:item.Values) | select -Unique) -join ';')
            [Environment]::SetEnvironmentVariable($using:item.Name, $value, $using:item.Target)
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
            $value = (@(($using:item.Values + @(((Get-ChildItem env: | ? { $_.Name -ieq $using:item.Name } | Select-Object -first 1).Value) -split ';')) | select -Unique) -join ';')
            [Environment]::SetEnvironmentVariable($using:item.Name, $value, $using:item.Target)
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
      'FirewallRule' {
        Script ('FirewallRule_{0}' -f $item.ComponentName) {
          DependsOn = @( @($item.DependsOn) | ? { (($_) -and ($_.ComponentType)) } | % { ('[{0}]{1}_{2}' -f $componentMap.Item($_.ComponentType), $_.ComponentType, $_.ComponentName) } )
          GetScript = "@{ FirewallRule = $item.ComponentName }"
          SetScript = {
            if ($using:item.Direction -ieq 'Outbound') {
              $dir = 'out'
            } else {
              $dir = 'in'
            }
            if (($using:item.Protocol) -and ($using:item.LocalPort)) {
              $ruleName = ('{0} ({1} {2} {3}): {4}' -f $using:item.ComponentName, $using:item.Protocol, $using:item.LocalPort, $using:item.Direction, $using:item.Action)
              if (Get-Command 'New-NetFirewallRule' -errorAction SilentlyContinue) {
                New-NetFirewallRule -DisplayName $ruleName -Protocol $using:item.Protocol -LocalPort $using:item.LocalPort -Direction $using:item.Direction -Action $using:item.Action
              } else {
                & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $using:item.Action), ('protocol={0}' -f $using:item.Protocol), ('localport={0}' -f $using:item.LocalPort))
              }
            } elseif ($using:item.Program) {
              $ruleName = ('{0} ({1} {2}): {3}' -f $using:item.ComponentName, $using:item.Program, $using:item.Direction, $using:item.Action)
              if (Get-Command 'New-NetFirewallRule' -errorAction SilentlyContinue) {
                New-NetFirewallRule -DisplayName $ruleName -Program $using:item.Program -Direction $using:item.Direction -Action $using:item.Action
              } else {
                & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $using:item.Action), ('program={0}' -f $using:item.Program))
              }
            }
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
              return Log-Validation ([bool](Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) -verbose
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
    }
  }
}
