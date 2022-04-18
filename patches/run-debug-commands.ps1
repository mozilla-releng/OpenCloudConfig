if (${env:PROCESSOR_ARCHITEW6432} -eq 'ARM64') {
  $commands = @(
    @{
      'executable' = 'ver'
    },
    @{
      'executable' = 'wmic'
      'arguments' = @('qfe', 'list')
    },
    @{
      'executable' = 'systeminfo'
    }
  )
  $occKey=(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig' -Name 'LastRegsvr32Reset' -ErrorAction SilentlyContinue)
  if ((-not ($occKey.LastRegsvr32Reset)) -or ([DateTime]::Parse($occKey.LastRegsvr32Reset) -lt [DateTime]::UtcNow.AddDays(-1))) {
    foreach ($dll in @(Get-ChildItem -Path ('{0}\System32\*.dll' -f $env:SystemRoot))) {
      $commands += @{
        'executable' = 'regsvr32'
        'arguments' = @('/s', $dll.FullName)
      }
    }
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig' -Name 'LastRegsvr32Reset' -Type 'String' -Value ([DateTime]::UtcNow.ToString('u'))
    Write-Log -message ('{0} :: Regsvr32Reset: regsvr32 reset complete' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
  } else {
    Write-Log -message ('{0} :: Regsvr32Reset: detected recent regsvr32 reset at: {1}' -f $($MyInvocation.MyCommand.Name), $occKey.LastRegsvr32Reset) -severity 'DEBUG'
  }
  foreach ($command in $commands) {
    try {
      $commandStdOutPath = ('{0}\log\{1}-arbitrary-command-stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      $commandStdErrPath = ('{0}\log\{1}-arbitrary-command-stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
      if ($command.ContainsKey('arguments')) {
        Start-Process $command['executable'] -ArgumentList $command['arguments'] -Wait -NoNewWindow -PassThru -RedirectStandardOutput $commandStdOutPath -RedirectStandardError $commandStdErrPath
      } else {
        Start-Process $command['executable'] -Wait -NoNewWindow -PassThru -RedirectStandardOutput $commandStdOutPath -RedirectStandardError $commandStdErrPath
      }
      if ((Get-Item -Path $commandStdErrPath).Length -gt 0kb) {
        $lineNumber = 0
        foreach ($lineContent in (Get-Content -Path $commandStdErrPath)) {
          Write-Log -message ('{0} :: DebugCommand - {1} {2} ({3}) line {4}: {5}' -f $($MyInvocation.MyCommand.Name), $command['executable'], $(if ($command.ContainsKey('arguments')) { [string]::Join(' ', $command['arguments']) } else {}), [IO.Path]::GetFileNameWithoutExtension($commandStdErrPath), $lineNumber++, $lineContent) -severity 'ERROR'
        }
      }
      if ((Get-Item -Path $commandStdOutPath).Length -gt 0kb) {
        $lineNumber = 0
        foreach ($lineContent in (Get-Content -Path $commandStdOutPath)) {
          Write-Log -message ('{0} :: DebugCommand - {1} {2} ({3}) line {4}: {5}' -f $($MyInvocation.MyCommand.Name), $command['executable'], $(if ($command.ContainsKey('arguments')) { [string]::Join(' ', $command['arguments']) } else {}), [IO.Path]::GetFileNameWithoutExtension($commandStdOutPath), $lineNumber++, $lineContent) -severity 'DEBUG'
        }
      }
      if (((Get-Item -Path $commandStdErrPath).Length -eq 0) -and ((Get-Item -Path $commandStdOutPath).Length -eq 0)) {
        Write-Log -message ('{0} :: DebugCommand - {1} {2} (no output)' -f $($MyInvocation.MyCommand.Name), $command['executable'], $(if ($command.ContainsKey('arguments')) { [string]::Join(' ', $command['arguments']) } else {})) -severity 'WARN'
      }
    } catch {
      Write-Log -message ('{0} :: DebugCommand - {1} {2} (exception). {3}' -f $($MyInvocation.MyCommand.Name), $command['executable'], $(if ($command.ContainsKey('arguments')) { [string]::Join(' ', $command['arguments']) } else {}), $_.Exception.Message) -severity 'ERROR'
      Write-Log -message ('{0} :: {1} not found' -f $($MyInvocation.MyCommand.Name), $command['executable']) -severity 'DEBUG'
    }
  }
}