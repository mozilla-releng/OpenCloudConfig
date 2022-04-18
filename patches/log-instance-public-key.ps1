if (${env:PROCESSOR_ARCHITEW6432} -eq 'ARM64') {
  if (Test-Path -Path ('{0}\Mozilla\OpenCloudConfig\occ-public.key' -f $env:ProgramData) -ErrorAction SilentlyContinue) {
    Write-Log -message ('{0} :: gpg public key found at: {1}' -f $($MyInvocation.MyCommand.Name), ('{0}\Mozilla\OpenCloudConfig\occ-public.key' -f $env:ProgramData)) -severity 'DEBUG'
    $publicKey = (Get-Content -Path ('{0}\Mozilla\OpenCloudConfig\occ-public.key' -f $env:ProgramData) -Raw)
    Write-Log -message ('{0} :: {1}' -f $($MyInvocation.MyCommand.Name), $publicKey) -severity 'DEBUG'
  } else {
    Write-Log -message ('{0} :: gpg public key not found at: {1}' -f $($MyInvocation.MyCommand.Name), ('{0}\Mozilla\OpenCloudConfig\occ-public.key' -f $env:ProgramData)) -severity 'ERROR'
  }
}