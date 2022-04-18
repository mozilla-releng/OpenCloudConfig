if (${env:PROCESSOR_ARCHITEW6432} -eq 'ARM64') {
  if (Test-Path -Path ('{0}\Mozilla\OpenCloudConfig\OpenCloudConfig.private.key' -f $env:ProgramData) -ErrorAction SilentlyContinue) {
    Start-Process 'diskperf.exe' -ArgumentList '-y' -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.diskperf.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.diskperf.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
    Start-Process ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)}) -ArgumentList @('--allow-secret-key-import', '--import', ('{0}\Mozilla\OpenCloudConfig\OpenCloudConfig.private.key' -f $env:ProgramData)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.gpg-import-key.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss")) -RedirectStandardError ('{0}\log\{1}.gpg-import-key.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
    Start-Process 'icacls' -ArgumentList @(('{0}\Mozilla\OpenCloudConfig\OpenCloudConfig.private.key' -f $env:ProgramData), '/grant', 'Administrators:(GA)') -Wait -NoNewWindow -PassThru
    Start-Process 'icacls' -ArgumentList @(('{0}\Mozilla\OpenCloudConfig\OpenCloudConfig.private.key' -f $env:ProgramData), '/inheritance:r') -Wait -NoNewWindow -PassThru
  }
}