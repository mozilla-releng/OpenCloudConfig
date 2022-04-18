if (${env:PROCESSOR_ARCHITEW6432} -eq 'ARM64') {
  if ((Test-Path -Path ('{0}\gnupg\secring.gpg' -f $env:AppData) -ErrorAction SilentlyContinue) -and ((Get-Item ('{0}\gnupg\secring.gpg' -f $env:AppData)).length -gt 0kb)) {
    Write-Log -message ('{0} :: gpg keyring detected' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
    New-Item -Path 'C:\builds' -ItemType Directory -ErrorAction SilentlyContinue
    New-Item -Path ('{0}\Mozilla\OpenCloudConfig' -f $env:ProgramData) -ItemType Directory -ErrorAction SilentlyContinue
    $ipAddresses = @(Get-NetIPConfiguration | ? { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -ne "Disconnected" } | % { $_.IPv4Address.IPAddress })
    $gwConfig=(Get-Content -Raw -Path 'C:\generic-worker\gw.config' | ConvertFrom-Json)
    if (($gwConfig.requiredDiskSpaceMegabytes) -or (-not ($ipAddresses.Contains($gwConfig.publicIP))) -or ($gwConfig.rootURL -ne 'https://firefox-ci-tc.services.mozilla.com') -or ($gwConfig.clientId -ne 'project/releng/generic-worker/bitbar-gecko-t-win10-aarch64') -or ($gwConfig.wstAudience -ne 'firefoxcitc')) {
      Write-Log -message ('{0} :: invalid config detected. rootURL: {1}, clientId: {2}, publicIP: {3}, wstAudience: {4}' -f $($MyInvocation.MyCommand.Name), $gwConfig.rootURL, $gwConfig.clientId, $gwConfig.publicIP, $gwConfig.wstAudience) -severity 'WARN'
      Remove-Item 'C:\generic-worker\gw.config' -Confirm:$false -force -ErrorAction SilentlyContinue
      Remove-Item 'C:\generic-worker\generic-worker.config' -Confirm:$false -force -ErrorAction SilentlyContinue
      Remove-Item 'C:\generic-worker\master-generic-worker.json' -Confirm:$false -force -ErrorAction SilentlyContinue
    } else {
      Write-Log -message ('{0} :: valid config detected. rootURL: {1}, clientId: {2}, publicIP: {3}' -f $($MyInvocation.MyCommand.Name), $gwConfig.rootURL, $gwConfig.clientId, $gwConfig.publicIP) -severity 'DEBUG'
    }    
    [hashtable] $resources = @{
      'C:\builds\taskcluster-worker-ec2@aws-stackdriver-log-1571127027.json' = 'https://s3.amazonaws.com/windows-opencloudconfig-packages/FirefoxBuildResources/taskcluster-worker-ec2@aws-stackdriver-log-1571127027.json.gpg?raw=true';
      'C:\builds\relengapi.tok' = 'https://s3.amazonaws.com/windows-opencloudconfig-packages/FirefoxBuildResources/relengapi.tok.gpg?raw=true';
      'C:\builds\occ-installers.tok' = 'https://s3.amazonaws.com/windows-opencloudconfig-packages/FirefoxBuildResources/occ-installers.tok.gpg?raw=true';
      ('{0}\Mozilla\OpenCloudConfig\project_releng_generic-worker_bitbar-gecko-t-win10-aarch64.txt' -f $env:ProgramData) = 'https://gist.github.com/grenade/dfbf31ef54bb6a0191fc386240bb71e7/raw/project_releng_generic-worker_bitbar-gecko-t-win10-aarch64.txt.gpg';
      'C:\generic-worker\gw.config' = ('https://github.com/mozilla-releng/OpenCloudConfig/raw/master/cfg/generic-worker/{0}.json.gpg' -f $(if ([System.Net.Dns]::GetHostName().ToLower().StartsWith('yoga-')) { 't-lenovoyogac630-{0}' -f [System.Net.Dns]::GetHostName().Split('-')[1] } else { [System.Net.Dns]::GetHostName().ToLower() }));
      'C:\generic-worker\generic-worker.config' = ('https://github.com/mozilla-releng/OpenCloudConfig/raw/master/cfg/generic-worker/{0}.json.gpg' -f $(if ([System.Net.Dns]::GetHostName().ToLower().StartsWith('yoga-')) { 't-lenovoyogac630-{0}' -f [System.Net.Dns]::GetHostName().Split('-')[1] } else { [System.Net.Dns]::GetHostName().ToLower() }));
      'C:\generic-worker\master-generic-worker.json' = ('https://github.com/mozilla-releng/OpenCloudConfig/raw/master/cfg/generic-worker/{0}.json.gpg' -f $(if ([System.Net.Dns]::GetHostName().ToLower().StartsWith('yoga-')) { 't-lenovoyogac630-{0}' -f [System.Net.Dns]::GetHostName().Split('-')[1] } else { [System.Net.Dns]::GetHostName().ToLower() }));
      ('{0}\Mozilla\OpenCloudConfig\OpenCloudConfig.private.key' -f $env:ProgramData) = 'https://github.com/mozilla-releng/OpenCloudConfig/raw/master/cfg/OpenCloudConfig.private.key.gpg';
      ('{0}\Mozilla\OpenCloudConfig\.bitbar.pw' -f $env:ProgramData) = 'https://github.com/mozilla-releng/OpenCloudConfig/raw/master/cfg/bitbar/.bitbar.pw.gpg';
      ('{0}\Mozilla\OpenCloudConfig\.testdroid.pw' -f $env:ProgramData) = 'https://github.com/mozilla-releng/OpenCloudConfig/raw/master/cfg/bitbar/.testdroid.pw.gpg'
    }
    foreach ($localPath in $resources.Keys) {
      $downloadUrl = $resources.Item($localPath)
      if (-not (Test-Path -Path $localPath -ErrorAction SilentlyContinue)) {
        try {
          (New-Object Net.WebClient).DownloadFile($downloadUrl, ('{0}.gpg' -f $localPath))
        } catch {
          Write-Log -message ('{0} :: error downloading {1} to {2}. {3}' -f $($MyInvocation.MyCommand.Name), $downloadUrl, ('{0}.gpg' -f $localPath), $_.Exception.Message) -severity 'ERROR'
        }
        if (Test-Path -Path ('{0}.gpg' -f $localPath) -ErrorAction SilentlyContinue) {
          Write-Log -message ('{0} :: {1} downloaded from {2}' -f $($MyInvocation.MyCommand.Name), ('{0}.gpg' -f $localPath), $downloadUrl) -severity 'INFO'
          Start-Process ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)}) -ArgumentList @('-d', ('{0}.gpg' -f $localPath)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput $localPath -RedirectStandardError ('{0}\log\{1}.gpg-decrypt-{2}.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), [IO.Path]::GetFileNameWithoutExtension($localPath))
          if (Test-Path -Path $localPath -ErrorAction SilentlyContinue) {
            Write-Log -message ('{0} :: decrypted {1} to {2}' -f $($MyInvocation.MyCommand.Name), ('{0}.gpg' -f $localPath), $localPath) -severity 'INFO'
          }
          Remove-Item -Path ('{0}.gpg' -f $localPath) -Force
          Write-Log -message ('{0} :: deleted "{1}"' -f $($MyInvocation.MyCommand.Name), ('{0}.gpg' -f $localPath))
        }
      } else {
        Write-Log -message ('{0} :: detected {1}. skipping download from {2}' -f $($MyInvocation.MyCommand.Name), $localPath, $downloadUrl) -severity 'DEBUG'
      }
    }
  } else {
    Write-Log -message ('{0} :: gpg keyring not found' -f $($MyInvocation.MyCommand.Name)) -severity 'ERROR'
  }
}