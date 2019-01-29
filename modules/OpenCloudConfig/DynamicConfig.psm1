<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

function Invoke-DirectoryDelete {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $path,
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
  process {
    try {
      Remove-Item $path -Confirm:$false -force
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: deleted directory {1}.' -f  $($MyInvocation.MyCommand.Name), $path)
    } catch {
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: error deleting directory ({1}). {2}' -f  $($MyInvocation.MyCommand.Name), $path, $_.Exception.Message)
      try {
        Start-Process 'icacls' -ArgumentList @($path, '/grant', ('{0}:(OI)(CI)F' -f $env:Username), '/inheritance:r') -Wait -NoNewWindow -PassThru | Out-Null
        Remove-Item $path -Confirm:$false -force
      } catch {
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: error resetting permissions or deleting directory ({1}). {2}' -f  $($MyInvocation.MyCommand.Name), $path, $_.Exception.Message)
        throw
      }
    }
  }
  end {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
}

function Invoke-CommandRun {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $command,

    [string[]] $arguments,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
  process {
    $redirectStandardOutput = ('{0}\log\{1}-{2}-stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), [IO.Path]::GetFileNameWithoutExtension($command))
    $redirectStandardError = ('{0}\log\{1}-{2}-stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), [IO.Path]::GetFileNameWithoutExtension($command))
    try {
      $process = (Start-Process $command -ArgumentList $arguments -NoNewWindow -RedirectStandardOutput $redirectStandardOutput -RedirectStandardError $redirectStandardError -PassThru)
      Wait-Process -InputObject $process # see: https://stackoverflow.com/a/43728914/68115
      if ($process.ExitCode -and $process.TotalProcessorTime) {
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: command ({1} {2}) exited with code: {3} after a processing time of: {4}.' -f $($MyInvocation.MyCommand.Name), $command, ($arguments -join ' '), $process.ExitCode, $process.TotalProcessorTime)
      } else {
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: command ({1} {2}) executed.' -f $($MyInvocation.MyCommand.Name), $command, ($arguments -join ' '))
      }
    } catch {
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: error executing command ({1} {2}). {3}' -f $($MyInvocation.MyCommand.Name), $command, ($arguments -join ' '), $_.Exception.Message)
      $standardErrorFile = (Get-Item -Path $redirectStandardError -ErrorAction SilentlyContinue)
      if (($standardErrorFile) -and $standardErrorFile.Length) {
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: ({1} {2}). {3}' -f $($MyInvocation.MyCommand.Name), $command, ($arguments -join ' '), (Get-Content -Path $redirectStandardError -Raw))
      }
      throw
    }
    $standardErrorFile = (Get-Item -Path $redirectStandardError -ErrorAction SilentlyContinue)
    if (($standardErrorFile) -and $standardErrorFile.Length) {
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: ({1} {2}). {3}' -f $($MyInvocation.MyCommand.Name), $command, ($arguments -join ' '), (Get-Content -Path $redirectStandardError -Raw))
    }
    $standardOutputFile = (Get-Item -Path $redirectStandardOutput -ErrorAction SilentlyContinue)
    if (($standardOutputFile) -and $standardOutputFile.Length) {
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: ({1} {2}). log: {3}' -f $($MyInvocation.MyCommand.Name), $command, ($arguments -join ' '), $redirectStandardOutput)
    }
  }
  end {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
}

function Invoke-FileDownload {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $localPath,

    [string] $url,

    [string] $sha512,

    [string] $tooltoolHost,

    [string] $tokenPath,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
  process {
    if (($sha512) -and (Test-Path -Path $tokenPath -ErrorAction SilentlyContinue)) {
      if ((Get-TooltoolResource -localPath $localPath -sha512 $sha512 -tokenPath $tokenPath -tooltoolHost $tooltoolHost -eventLogName $eventLogName -eventLogSource $eventLogSource)) {
        Write-Verbose ('downloaded {0} from tooltool' -f $localPath)
      } else {
        Write-Verbose ('failed to download {0} from tooltool' -f $localPath)
        throw ('failed to download {0} from tooltool' -f $localPath)
      }
    } else {
      if ((Get-RemoteResource -localPath $localPath -url $url -eventLogSource $eventLogSource)) {
        Write-Verbose ('downloaded {0} from {1}' -f $localPath, $url)
      } else {
        Write-Verbose ('failed to download {0} from {1}' -f $localPath, $url)
        throw ('failed to download {0} from {1}' -f $localPath, $url)
      }
    }
    Unblock-File -Path $localPath
  }
  end {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
}

function Invoke-SymbolicLink {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $target,

    [Parameter(Mandatory = $true)]
    [string] $link,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
  process {
    try {
      if (Test-Path -Path $target -PathType Container -ErrorAction SilentlyContinue) {
        & 'cmd' @('/c', 'mklink', '/D', $link, $target)
      } elseif (Test-Path -Path $target -PathType Leaf -ErrorAction SilentlyContinue) {
        & 'cmd' @('/c', 'mklink', $link, $target)
      }
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: created symlink {1} to {2}' -f $($MyInvocation.MyCommand.Name), $link, $target)
    } catch {
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: failed to create symlink {1} to {2}. {3}' -f $($MyInvocation.MyCommand.Name), $link, $target, $_.Exception.Message)
      throw
    }
  }
  end {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
}

function Invoke-EnvironmentVariableSet {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $name,

    [Parameter(Mandatory = $true)]
    [string] $value,

    [Parameter(Mandatory = $true)]
    [string] $target,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
  process {
    try {
      [Environment]::SetEnvironmentVariable($name, $value, $target)
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: environment variable: {1} set to: {2} for {3}' -f $($MyInvocation.MyCommand.Name), $name, $value, $target)
    } catch {
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: failed to set environment variable: {1} to: {2} for {3}. {4}' -f $($MyInvocation.MyCommand.Name), $name, $value, $target, $_.Exception.Message)
      throw
    }
  }
  end {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
}

function Invoke-RegistryKeySetOwner {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $key,

    [Parameter(Mandatory = $true)]
    [string] $sid,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
  process {
    try {
      $ntdll = Add-Type -Member '[DllImport("ntdll.dll")] public static extern int RtlAdjustPrivilege(ulong a, bool b, bool c, ref bool d);' -Name NtDll -PassThru
      @{ SeTakeOwnership = 9; SeBackup =  17; SeRestore = 18 }.Values | % { $null = $ntdll::RtlAdjustPrivilege($_, 1, 0, [ref]0) }
      $subkey = ($key).Replace(('{0}\' -f ($key).Split('\')[0]), '')
      switch -regex (($key).Split('\')[0]) {
        'HKCU|HKEY_CURRENT_USER' {
          $hive = 'CurrentUser'
        }
        'HKLM|HKEY_LOCAL_MACHINE' {
          $hive = 'LocalMachine'
        }
        'HKCR|HKEY_CLASSES_ROOT' {
          $hive = 'ClassesRoot'
        }
        'HKCC|HKEY_CURRENT_CONFIG' {
          $hive = 'CurrentConfig'
        }
        'HKU|HKEY_USERS' {
          $hive = 'Users'
        }
      }
      $regKey = [Microsoft.Win32.Registry]::$hive.OpenSubKey($subkey, 'ReadWriteSubTree', 'TakeOwnership')
      $acl = New-Object System.Security.AccessControl.RegistrySecurity
      $acl.SetOwner([System.Security.Principal.SecurityIdentifier]$sid)
      $regKey.SetAccessControl($acl)
      $acl.SetAccessRuleProtection($false, $false)
      $regKey.SetAccessControl($acl)
      $regKey = $regKey.OpenSubKey('', 'ReadWriteSubTree', 'ChangePermissions')
      $acl.ResetAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule([System.Security.Principal.SecurityIdentifier]$sid, 'FullControl', @('ObjectInherit', 'ContainerInherit'), 'None', 'Allow')))
      $regKey.SetAccessControl($acl)
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: registry key owner set to: {1} for {2}' -f $($MyInvocation.MyCommand.Name), $sid, $key)
    } catch {
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: failed to set registry key owner to: {1} for {2}. {3}' -f $($MyInvocation.MyCommand.Name),  $sid, $key, $_.Exception.Message)
      throw
    }
  }
  end {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
}

function Invoke-FirewallRuleSet {
  [CmdletBinding()]
  param (
    [Alias('component')]
    [Parameter(Mandatory = $true)]
    [string] $componentName,

    [Parameter(Mandatory = $true)]
    [string] $action,

    [Parameter(Mandatory = $true)]
    [string] $direction,

    [Parameter(Mandatory = $true)]
    [string] $remoteAddress,

    [string] $program,

    [string] $protocol,

    [string] $localPort,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
  process {
    $dir = $(if ($direction -ieq 'Outbound') { 'out' } else { 'in' })
    if (($protocol) -and ($localPort)) {
      $ruleName = ('{0} ({1} {2} {3}): {4}' -f $componentName, $protocol, $localPort, $direction, $action)
      try {
        if (Get-Command 'New-NetFirewallRule' -errorAction SilentlyContinue) {
          if ($remoteAddress) {
            New-NetFirewallRule -DisplayName $ruleName -Protocol $protocol -LocalPort $localPort -Direction $direction -Action $action -RemoteAddress $remoteAddress
          } else {
            New-NetFirewallRule -DisplayName $ruleName -Protocol $protocol -LocalPort $localPort -Direction $direction -Action $action
          }
        } else {
          if ($remoteAddress) {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $action), ('protocol={0}' -f $protocol), ('localport={0}' -f $localPort), ('remoteip={0}' -f $remoteAddress))
          } else {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $action), ('protocol={0}' -f $protocol), ('localport={0}' -f $localPort))
          }
        }
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: firewall rule: {1} created' -f $($MyInvocation.MyCommand.Name), $ruleName)
      } catch {
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: failed to create firewall rule: {1}. {2}' -f $($MyInvocation.MyCommand.Name),  $ruleName, $_.Exception.Message)
        throw
      }
    } elseif (($protocol -eq 'ICMPv4') -or ($protocol -eq 'ICMPv6')) {
      $ruleName = ('{0} ({1} {2} {3}): {4}' -f $componentName, $protocol, $action)
      try {
        if (Get-Command 'New-NetFirewallRule' -errorAction SilentlyContinue) {
          if ($remoteAddress) {
            New-NetFirewallRule -DisplayName $ruleName -Protocol $protocol -IcmpType 8 -Action $action -RemoteAddress $remoteAddress
          } else {
            New-NetFirewallRule -DisplayName $ruleName -Protocol $protocol -IcmpType 8 -Action $action
          }
        } else {
          if ($remoteAddress) {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $action), ('protocol={0}:8,any' -f $protocol), ('localport={0}' -f $localPort), ('remoteip={0}' -f $remoteAddress))
          } else {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $action), ('protocol={0}:8,any' -f $protocol), ('localport={0}' -f $localPort))
          }
        }
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: firewall rule: {1} created' -f $($MyInvocation.MyCommand.Name), $ruleName)
      } catch {
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: failed to create firewall rule: {1}. {2}' -f $($MyInvocation.MyCommand.Name),  $ruleName, $_.Exception.Message)
        throw
      }
    } elseif ($program) {
      $ruleName = ('{0} ({1} {2}): {3}' -f $componentName, $program, $direction, $action)
      try {
        if (Get-Command 'New-NetFirewallRule' -errorAction SilentlyContinue) {
          if ($remoteAddress) {
            New-NetFirewallRule -DisplayName $ruleName -Program $program -Direction $direction -Action $action -RemoteAddress $remoteAddress
          } else {
            New-NetFirewallRule -DisplayName $ruleName -Program $program -Direction $direction -Action $action
          }
        } else {
          if ($remoteAddress) {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $action), ('program={0}' -f $program), ('remoteip={0}' -f $remoteAddress))
          } else {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $action), ('program={0}' -f $program))
          }
        }
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: firewall rule: {1} created' -f $($MyInvocation.MyCommand.Name), $ruleName)
      } catch {
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: failed to create firewall rule: {1}. {2}' -f $($MyInvocation.MyCommand.Name),  $ruleName, $_.Exception.Message)
        throw
      }
    }
  }
  end {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
}

function Invoke-ReplaceInFile {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $path,

    [Parameter(Mandatory = $true)]
    [string] $matchString,

    [Parameter(Mandatory = $true)]
    [string] $replaceString,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
  process {
    try {
      $content = ((Get-Content -Path $path) | Foreach-Object { $_ -replace $matchString, (Invoke-Expression -Command $replaceString) })
      [System.IO.File]::WriteAllLines($path, $content, (New-Object System.Text.UTF8Encoding $false))
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} :: replaced occurences of: {1} with: {2} in: {3}' -f $($MyInvocation.MyCommand.Name), $matchString, $replaceString, $path)
    } catch {
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} :: failed to replace occurences of: {1} with: {2} in: {3}. {4}' -f $($MyInvocation.MyCommand.Name), $matchString, $replaceString, $path, $_.Exception.Message)
      throw
    }
  }
  end {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
}