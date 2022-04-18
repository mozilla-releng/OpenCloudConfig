if (${env:PROCESSOR_ARCHITEW6432} -eq 'ARM64') {
  if (-not (Test-Path -Path ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)}) -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path -Path 'C:\Windows\Temp\gpg4win-2.3.0.exe' -ErrorAction SilentlyContinue)) {
      (New-Object Net.WebClient).DownloadFile('https://files.gpg4win.org/gpg4win-2.3.0.exe', 'C:\Windows\Temp\gpg4win-2.3.0.exe')
    }
    & 'C:\Windows\Temp\gpg4win-2.3.0.exe' @('/S')
    Start-Sleep -Seconds 60
  }
  $commands = @(
    @{
      'executable' = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
      'arguments' = @('--version')
    },
    @{
      'executable' = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
      'arguments' = @('--list-keys', 'releng-puppet-mail@mozilla.com')
    },
    @{
      'executable' = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
      'arguments' = @('--list-keys', ('{0}@{1}' -f $env:USERNAME, [System.Net.Dns]::GetHostName()))
    }
  )
  $fingerprints = @(($(&('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)}) @('--fingerprint', ('{0}@{1}' -f $env:USERNAME, [System.Net.Dns]::GetHostName()))) | ? { $_.Contains('Key fingerprint') }) | % { $_.Split('=')[1].Replace(' ', '')  })
  if (($fingerprints.Length -eq 1) -and (Test-Path -Path ('{0}\Mozilla\OpenCloudConfig\occ-public.key' -f $env:ProgramData) -ErrorAction SilentlyContinue)) {
    Write-Log -message ('{0} :: instance gpg key fingerprint: {1}' -f $($MyInvocation.MyCommand.Name), $fingerprints[0]) -severity 'INFO'
  } elseif (($fingerprints.Length -eq 1) -and (-not (Test-Path -Path ('{0}\Mozilla\OpenCloudConfig\occ-public.key' -f $env:ProgramData) -ErrorAction SilentlyContinue))) {
    Write-Log -message ('{0} :: instance gpg key fingerprint: {1}' -f $($MyInvocation.MyCommand.Name), $fingerprints[0]) -severity 'INFO'
    $commands += @{
      'executable' = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
      'arguments' = @('--batch', '--export', '--output', ('{0}\Mozilla\OpenCloudConfig\occ-public.key' -f $env:ProgramData), '--armor', $fingerprints[0])
    }
  } else {
    Write-Log -message ('{0} :: {1} keys queued for deletion' -f $($MyInvocation.MyCommand.Name), $fingerprints.Length) -severity 'DEBUG'
    foreach ($fingerprint in $fingerprints) {
      $commands += @{
        'executable' = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
        'arguments' = @('--batch', '--delete-secret-key', $fingerprint)
      }
      $commands += @{
        'executable' = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
        'arguments' = @('--batch', '--delete-key', $fingerprint)
      }
    }
    $commands += @{
      'executable' = ('{0}\GNU\GnuPG\pub\gpg.exe' -f ${env:ProgramFiles(x86)})
      'arguments' = @('--list-keys')
    }
  }
  foreach ($command in $commands) {
    try {
      $commandStdOutPath = ('{0}\log\{1}-arbitrary-command-stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      $commandStdErrPath = ('{0}\log\{1}-arbitrary-command-stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      Start-Process $command['executable'] -ArgumentList $command['arguments'] -Wait -NoNewWindow -PassThru -RedirectStandardOutput $commandStdOutPath -RedirectStandardError $commandStdErrPath
      if ((Get-Item -Path $commandStdErrPath).Length -gt 0kb) {
        Write-Log -message ('{0} :: {1} {2} ({3}): {4}' -f $($MyInvocation.MyCommand.Name), $command['executable'], [string]::Join(' ', $command['arguments']), [IO.Path]::GetFileNameWithoutExtension($commandStdErrPath), (Get-Content -Path $commandStdErrPath -Raw)) -severity 'ERROR'
      }
      if ((Get-Item -Path $commandStdOutPath).Length -gt 0kb) {
        Write-Log -message ('{0} :: {1} {2} ({3}): {4}' -f $($MyInvocation.MyCommand.Name), $command['executable'], [string]::Join(' ', $command['arguments']), [IO.Path]::GetFileNameWithoutExtension($commandStdOutPath), (Get-Content -Path $commandStdOutPath -Raw)) -severity 'DEBUG'
      }
      if (((Get-Item -Path $commandStdErrPath).Length -eq 0) -and ((Get-Item -Path $commandStdOutPath).Length -eq 0)) {
        Write-Log -message ('{0} :: no output from command: "{1} {2}"' -f $($MyInvocation.MyCommand.Name), $command['executable'], [string]::Join(' ', $command['arguments'])) -severity 'WARN'
      }
    } catch {
      Write-Log -message ('{0} :: error executing command: {1} {2}. {3}' -f $($MyInvocation.MyCommand.Name), $command['executable'], [string]::Join(' ', $command['arguments']), $_.Exception.Message) -severity 'ERROR'
      Write-Log -message ('{0} :: {1} not found' -f $($MyInvocation.MyCommand.Name), $command['executable']) -severity 'DEBUG'
    }
  }
  $env:PATH=('{0};{1}' -f $env:PATH, ('{0}\GNU\GnuPG\pub' -f ${env:ProgramFiles(x86)}))
  $(echo trust; echo 5; echo y; echo quit) | gpg --command-fd 0 --edit-key releng-puppet-mail@mozilla.com
}