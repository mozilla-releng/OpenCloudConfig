function Write-Log {
  param (
    [string] $message,
    [string] $severity = 'INFO',
    [string] $source = 'HaltOnIdle',
    [string] $logName = 'PrepLoaner'
  )
  if (!([Diagnostics.EventLog]::Exists($logName)) -or !([Diagnostics.EventLog]::SourceExists($source))) {
    New-EventLog -LogName $logName -Source $source
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
  Write-EventLog -LogName $logName -Source $source -EntryType $entryType -Category 0 -EventID $eventId -Message $message
}

function Clean-Instance {
  $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  $autologonRegistryEntries = @{
    'DefaultUserName' = $winlogonPath;
    'DefaultPassword' = $winlogonPath;
    'AutoAdminLogon' = $winlogonPath
  }
  foreach ($name in $autologonRegistryEntries.Keys) {
    $path = $registryEntries.Item($name)
    $item = (Get-Item -Path $path)
    if (($item -ne $null) -and ($item.GetValue($name) -ne $null)) {
      Remove-ItemProperty -path $path -name $name
      Write-Log -message ('{0} :: registry entry: {1}\{2}, deleted.' -f $($MyInvocation.MyCommand.Name), $path, $name) -severity 'INFO'
    }
  }
  $gwuser = 'GenericWorker'
  if (@(Get-WMiObject -class Win32_UserAccount | Where { $_.Name -eq $gwuser }).length -gt 0) {
    Start-Process 'logoff' -ArgumentList @((((quser /server:. | ? { $_ -match $gwuser }) -split ' +')[2]), '/server:.') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.net-user-{2}-logoff.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $gwuser) -RedirectStandardError ('{0}\log\{1}.net-user-{2}-logoff.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $gwuser)
    Start-Process 'net' -ArgumentList @('user', $gwuser, '/DELETE') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.net-user-{2}-delete.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $gwuser) -RedirectStandardError ('{0}\log\{1}.net-user-{2}-delete.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $gwuser)
    Write-Log -message ('{0} :: user: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $gwuser) -severity 'INFO'
  }
  if (Test-Path -Path ('{0}\Users\{1}' -f $env:SystemDrive, $gwuser) -ErrorAction SilentlyContinue) {
    Remove-Item ('{0}\Users\{1}' -f $env:SystemDrive, $gwuser) -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
    Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), ('{0}\Users\{1}' -f $env:SystemDrive, $gwuser)) -severity 'INFO'
  }
  if (Test-Path -Path ('{0}\Users\{1}*' -f $env:SystemDrive, $gwuser) -ErrorAction SilentlyContinue) {
    Remove-Item ('{0}\Users\{1}*' -f $env:SystemDrive, $gwuser) -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
    Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), ('{0}\Users\{1}*' -f $env:SystemDrive, $gwuser)) -severity 'INFO'
  }
}

function Set-Credentials {
  param (
    [string] $username,
    [string] $password,
    [switch] $setautologon
  )
  begin {
    Write-Log -message ('{0} :: begin' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
  process {
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
  }
  end {
    Write-Log -message ('{0} :: end' -f $($MyInvocation.MyCommand.Name)) -severity 'DEBUG'
  }
}

function Get-GeneratedPassword {
  param (
    [int] $length = 16
  )
  $chars=$null;
  for ($char = 48; $char –le 122; $char ++) {
    $chars += ,[char][byte]$char
  }
  $password = ''
  for ($i=1; $i –le $length; $i++) {
    $password += ($sourcedata | Get-Random)
  }
  return $password
}

$loanReqPath = 'Z:\loan-request.json'
$loanRegPath = 'HKLM:\SOFTWARE\OpenCloudConfig\Loan'

# exit if no loan request
if (-not (Test-Path -Path $loanReqPath -ErrorAction SilentlyContinue)) {
  exit
}
# if reg keys exist, log activity and exit since an earlier run will have performed loan prep
if (Test-Path -Path $loanRegPath -ErrorAction SilentlyContinue) {
  if (@(Get-Process | ? { $_.ProcessName -eq 'rdpclip' }).length -gt 0) {
    # todo: record the ip address where the rdp session originates
    Write-Log -message 'rdp session detected on active loaner' -severity 'DEBUG'
  } else {
    Write-Log -message 'rdp session not detected on active loaner' -severity 'DEBUG'
  }
  exit
}

# create registry entries if file exists but reg entries don't
if ((Test-Path -Path $loanReqPath -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path $loanRegPath -ErrorAction SilentlyContinue))) {
  New-Item -Path $loanRegPath -Force | Out-Null
  New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'Detected' -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:sszzz')) -Force | Out-Null
  New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'Requested' -Value ((Get-Item -Path 'Z:\loan-requested.json').LastWriteTime) -Force | Out-Null
  $loanRequest = (Get-Content -Raw -Path $loanReqPath | ConvertFrom-Json)
  New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'Email' -Value $loanRequest.requester.email -Force | Out-Null
  New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'PublicKeyUrl' -Value $loanRequest.requester.publickeyurl -Force | Out-Null
}

if (-not (Test-Path -Path $loanRegPath -ErrorAction SilentlyContinue)) {
  exit
}

$loanRequestTime = (Get-Date -Date (Get-ItemProperty -Path $loanRegPath -Name 'Requested').Requested)
$loanRequestDetectedTime = (Get-Date -Date (Get-ItemProperty -Path $loanRegPath -Name 'Detected').Detected)
$loanRequestEmail = (Get-Date -Date (Get-ItemProperty -Path $loanRegPath -Name 'Email').Email)
$loanRequestPublicKeyUrl = (Get-Date -Date (Get-ItemProperty -Path $loanRegPath -Name 'PublicKeyUrl').PublicKeyUrl)
Write-Log -message ('loan request from {0} ({1}) at {2} detected at {3}' -f $loanRequestEmail, $loanRequestPublicKeyUrl, $loanRequestTime, $loanRequestDetectedTime) -severity 'INFO'

Clean-Instance
New-ItemProperty -Path $loanRegPath -PropertyType String -Name 'Cleaned' -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:sszzz')) -Force | Out-Null

$password = (Get-GeneratedPassword)
switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
  'Microsoft Windows 7*' {
    Set-Credentials -username 'root' -password $password
  }
  default {
    Set-Credentials -username 'Administrator' -password $password
  }
}
Send-MailMessage -From 'noreply@mozilla.com' -To $loanRequestEmail -cc 'grenade@mozilla.com' -Subject 'Your TaskCluster Windows instance is ready' -Body 'The attached file contains credentials for accessing your Windows instance.' -Attachments 'credentials.gpg' -SmtpServer 'smtp.fabrikam.com'
