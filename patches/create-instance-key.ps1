if (${env:PROCESSOR_ARCHITEW6432} -eq 'ARM64') {
  if (-not (Test-Path -Path ('{0}\Mozilla\OpenCloudConfig\occ-public.key' -f $env:ProgramData) -ErrorAction SilentlyContinue)) {
    New-Item -Path ('{0}\Mozilla\OpenCloudConfig' -f $env:ProgramData) -ItemType Directory -ErrorAction SilentlyContinue
    $gpgKeyGenConfigPath = ('{0}\Mozilla\OpenCloudConfig\gpg-keygen-config.txt' -f $env:ProgramData)
    [IO.File]::WriteAllLines($gpgKeyGenConfigPath, @(
      'Key-Type: RSA',
      'Key-Length: 4096',
      'Subkey-Type: RSA',
      'Subkey-Length: 4096',
      'Expire-Date: 0',
      ('Name-Real: {0} {1}' -f $env:USERNAME, [System.Net.Dns]::GetHostName()),
      ('Name-Email: {0}@{1}' -f $env:USERNAME, [System.Net.Dns]::GetHostName()),
      '%no-protection',
      '%commit',
      '%echo done'
    ), (New-Object -TypeName 'System.Text.UTF8Encoding' -ArgumentList $false))
    if (Test-Path -Path $gpgKeyGenConfigPath -ErrorAction SilentlyContinue) {
      Write-Log -message ('{0} :: {1} created' -f $($MyInvocation.MyCommand.Name), $gpgKeyGenConfigPath) -severity 'DEBUG'
      Write-Log -message ('{0} :: {1}' -f $($MyInvocation.MyCommand.Name), (Get-Content -Path $gpgKeyGenConfigPath -Raw)) -severity 'DEBUG'
      $gpgBatchGenerateKeyStdOutPath = ('{0}\log\{1}.gpg-batch-generate-key.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      $gpgBatchGenerateKeyStdErrPath = ('{0}\log\{1}.gpg-batch-generate-key.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      Start-Process ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)}) -ArgumentList @('--batch', '--gen-key', ('{0}\Mozilla\OpenCloudConfig\gpg-keygen-config.txt' -f $env:ProgramData)) -Wait -NoNewWindow -PassThru -RedirectStandardOutput $gpgBatchGenerateKeyStdOutPath -RedirectStandardError $gpgBatchGenerateKeyStdErrPath
      if ((Get-Item -Path $gpgBatchGenerateKeyStdErrPath).Length -gt 0kb) {
        Write-Log -message ('{0} :: {1}' -f $($MyInvocation.MyCommand.Name), (Get-Content -Path $gpgBatchGenerateKeyStdErrPath -Raw)) -severity 'ERROR'
      }
      if ((Get-Item -Path $gpgBatchGenerateKeyStdOutPath).Length -gt 0kb) {
        Write-Log -message ('{0} :: {1}' -f $($MyInvocation.MyCommand.Name), (Get-Content -Path $gpgBatchGenerateKeyStdOutPath -Raw)) -severity 'INFO'
      }
    } else {
      Write-Log -message ('{0} :: error: {1} not created' -f $($MyInvocation.MyCommand.Name), $gpgKeyGenConfigPath) -severity 'ERROR'
    }
  }
}