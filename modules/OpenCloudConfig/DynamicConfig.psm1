<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

function Invoke-DirectoryCreate {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      New-Item -Path $component.Path -ItemType 'directory' -force
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: created directory {2}.' -f  $($MyInvocation.MyCommand.Name), $component.ComponentName, $omponent.Path)
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: error creating directory {2}. {3}' -f  $($MyInvocation.MyCommand.Name), $component.ComponentName, $omponent.Path, $_.Exception.Message)
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-DirectoryCreate {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      $result = (Test-Path -Path $component.Path -PathType 'Container' -ErrorAction 'SilentlyContinue')
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: directory {2} existence {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Path, $(if ($result) { 'confirmed' } else { 'refuted' }))
    } catch {
      $result = $false
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to confirm or refute directory {2} existence. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Path, $_.Exception.Message)
    }
    return $result
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-DirectoryDelete {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      Remove-Item $component.Path -Confirm:$false -recurse -force
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: deleted directory {2}.' -f  $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Path)
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'warn' -message ('{0} ({1}) :: error deleting directory {2}. {3}' -f  $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Path, $_.Exception.Message)
      try {
        Start-Process 'icacls' -ArgumentList @($component.Path, '/grant', ('{0}:(OI)(CI)F' -f $env:Username), '/inheritance:r') -Wait -NoNewWindow -PassThru | Out-Null
        Remove-Item $component.Path -Confirm:$false -recurse -force
      } catch {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: error resetting permissions or deleting directory ({2}). {3}' -f  $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Path, $_.Exception.Message)
      }
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-DirectoryDelete {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      $result = (-not (Test-Path -Path $component.Path -PathType 'Container' -ErrorAction 'SilentlyContinue'))
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: directory {2} absence {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Path, $(if ($result) { 'confirmed' } else { 'refuted' }))
    } catch {
      $result = $false
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to confirm or refute directory {2} absence. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Path, $_.Exception.Message)
    }
    return $result
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-DirectoryCopy {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      Copy-Item -Path $component.Source -Destination $component.Target -Container
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: copied directory {2} to {3}.' -f  $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Source, $component.Target)
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: error copying directory {2} to {3}. {4}' -f  $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Source, $component.Target, $_.Exception.Message)
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-DirectoryCopy {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      # todo: compare folder contents
      $result = (Test-Path -Path $component.Target -PathType 'Container' -ErrorAction 'SilentlyContinue')
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: directory {2} existence {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Target, $(if ($result) { 'confirmed' } else { 'refuted' }))
    } catch {
      $result = $false
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to confirm or refute directory {2} existence. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Target, $_.Exception.Message)
    }
    return $result
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-LoggedCommandRun {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $componentName,

    [Parameter(Mandatory = $true)]
    [string] $command,

    [string[]] $arguments,

    [int] $timeoutInSeconds = 600,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $componentName, (Get-Date).ToUniversalTime())
  }
  process {
    $redirectStandardOutput = ('{0}\log\{1}-{2}-stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), [IO.Path]::GetFileNameWithoutExtension($command))
    $redirectStandardError = ('{0}\log\{1}-{2}-stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), [IO.Path]::GetFileNameWithoutExtension($command))
    try {
      $process = (Start-Process $command -ArgumentList $arguments -NoNewWindow -RedirectStandardOutput $redirectStandardOutput -RedirectStandardError $redirectStandardError -PassThru)
      $timeoutError = $null
      Wait-Process -Timeout $timeoutInSeconds -InputObject $process -ErrorAction 'SilentlyContinue' -ErrorVariable timeoutError # see: https://stackoverflow.com/a/43728914/68115
      if ($timeoutError) {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'warn' -message ('{0} ({1}) :: command ({2} {3}) execution timed out with error: {4} after {5} seconds.' -f $($MyInvocation.MyCommand.Name), $componentName, $command, ($arguments -join ' '), $timeoutError, $timeoutInSeconds)
      } elseif ($process.ExitCode -and $process.TotalProcessorTime) {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: command ({2} {3}) exited with code: {4} after a processing time of: {5}.' -f $($MyInvocation.MyCommand.Name), $componentName, $command, ($arguments -join ' '), $process.ExitCode, $process.TotalProcessorTime)
      } else {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: command ({2} {3}) executed.' -f $($MyInvocation.MyCommand.Name), $componentName, $command, ($arguments -join ' '))
      }
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: error executing command ({2} {3}). {4}' -f $($MyInvocation.MyCommand.Name), $componentName, $command, ($arguments -join ' '), $_.Exception.Message)
      $standardErrorFile = (Get-Item -Path $redirectStandardError -ErrorAction 'SilentlyContinue')
      if (($standardErrorFile) -and $standardErrorFile.Length) {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: ({2} {3}). {4}' -f $($MyInvocation.MyCommand.Name), $componentName, $command, ($arguments -join ' '), (Get-Content -Path $redirectStandardError -Raw))
      }
    }
    $standardErrorFile = (Get-Item -Path $redirectStandardError -ErrorAction 'SilentlyContinue')
    if (($standardErrorFile) -and $standardErrorFile.Length) {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: ({2} {3}). {4}' -f $($MyInvocation.MyCommand.Name), $componentName, $command, ($arguments -join ' '), (Get-Content -Path $redirectStandardError -Raw))
    }
    $standardOutputFile = (Get-Item -Path $redirectStandardOutput -ErrorAction 'SilentlyContinue')
    if (($standardOutputFile) -and $standardOutputFile.Length) {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: ({2} {3}). log: {4}' -f $($MyInvocation.MyCommand.Name), $componentName, $command, ($arguments -join ' '), $redirectStandardOutput)
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $componentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-CommandRun {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    Invoke-LoggedCommandRun -componentName $component.ComponentName -command $component.Command -arguments $component.Arguments
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-CommandRun {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      $result = (Confirm-All -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -componentName $component.ComponentName -validations $component.Validate)
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: {2} validations {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $(if (($component.Validate) -and $component.Validate.Length) { $component.Validate.Length } else { 0 }), $(if ($result) { 'confirmed' } else { 'refuted' }))
    } catch {
      $result = $false
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to confirm or refute {2} validations. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $(if (($component.Validate) -and $component.Validate.Length) { $component.Validate.Length } else { 0 }), $_.Exception.Message)
    }
    return $result
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-FileDownload {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [Parameter(Mandatory = $true)]
    [string] $localPath,

    [string] $tooltoolHost = 'tooltool.mozilla-releng.net',
    [string] $tokenPath = ('{0}\builds\occ-installers.tok' -f $env:SystemDrive),
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    if (($component.sha512) -and (Test-Path -Path $tokenPath -ErrorAction 'SilentlyContinue')) {
      if ((Get-TooltoolResource -localPath $localPath -sha512 $component.sha512 -tokenPath $tokenPath -tooltoolHost $tooltoolHost -eventLogName $eventLogName -eventLogSource $eventLogSource)) {
        Write-Verbose ('downloaded {0} from tooltool' -f $localPath)
      } else {
        Write-Verbose ('failed to download {0} from tooltool' -f $localPath)
        $url = $(if ($component.Url) { $component.Url } else { $component.Source })
        if ((Get-RemoteResource -localPath $localPath -url $url -eventLogSource $eventLogSource)) {
          Write-Verbose ('downloaded {0} from {1}' -f $localPath, $url)
        } else {
          Write-Verbose ('failed to download {0} from {1}' -f $localPath, $url)
        }
      }
    } else {
      $url = $(if ($component.Url) { $component.Url } else { $component.Source })
      if ((Get-RemoteResource -localPath $localPath -url $url -eventLogSource $eventLogSource)) {
        Write-Verbose ('downloaded {0} from {1}' -f $localPath, $url)
      } else {
        Write-Verbose ('failed to download {0} from {1}' -f $localPath, $url)
      }
    }
    Unblock-File -Path $localPath
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-FileDownload {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [Parameter(Mandatory = $true)]
    [string] $localPath,

    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      if (Test-Path -Path $localPath -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: downloaded file exists at {2}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $localPath)
        if ([bool]($component.sha512)) {
          Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: expected sha512 hash supplied {2}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.sha512)
          $actualSha512Hash = (Get-FileHash -Path $localPath -Algorithm 'SHA512').Hash
          if ($actualSha512Hash -eq $component.sha512) {
            Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: expected sha512 hash {2} matches actual sha512 hash {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.sha512, $actualSha512Hash)
            $result = $true
          } else {
            Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'warn' -message ('{0} ({1}) :: expected sha512 hash {2} does not match actual sha512 hash {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.sha512, $actualSha512Hash)
            $result = $false
          }
        } else {
          Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: expected sha512 hash not supplied' -f $($MyInvocation.MyCommand.Name), $component.ComponentName)
          $result = $true
        }
      } else {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: downloaded file does not exist at {2}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $localPath)
        $result = $false
      }      
    } catch {
      $result = $false
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to confirm or refute download {2} existence. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $localPath, $_.Exception.Message)
    }
    return $result
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-SymbolicLink {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      if (Test-Path -Path $component.Target -PathType Container -ErrorAction 'SilentlyContinue') {
        & 'cmd' @('/c', 'mklink', '/D', $component.Link, $component.Target)
      } elseif (Test-Path -Path $component.Target -PathType Leaf -ErrorAction 'SilentlyContinue') {
        & 'cmd' @('/c', 'mklink', $component.Link, $component.Target)
      }
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: created symlink {2} to {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Link, $component.Target)
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to create symlink {2} to {3}. {4}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Link, $component.Target, $_.Exception.Message)
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-SymbolicLink {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      # todo: check that link points to target (https://stackoverflow.com/a/16926224/68115)
      $result = ((Test-Path -Path $component.Link -ErrorAction 'SilentlyContinue') -and ((Get-Item -Path $component.Link).Attributes.ToString() -match 'ReparsePoint'))
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: symlink {2} existence {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Link, $(if ($result) { 'confirmed' } else { 'refuted' }))
    } catch {
      $result = $false
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to confirm or refute symlink {2} existence. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Link, $component.Target, $_.Exception.Message)
    }
    return $result
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Set-EnvironmentVariable {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $componentName,

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
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $componentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      [Environment]::SetEnvironmentVariable($name, $value, $target)
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: environment variable: {2} set to: {3} for {4}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $name, $value, $target)
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to set environment variable: {2} to: {3} for {4}. {5}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $name, $value, $target, $_.Exception.Message)
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $componentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-EnvironmentVariableSet {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    Set-EnvironmentVariable -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -componentName $component.ComponentName -name $component.Name -value $component.Value -target $component.Target
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-EnvironmentVariableUniqueAppend {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    Set-EnvironmentVariable -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -componentName $component.ComponentName -name $component.Name -value (@((@((((Get-ChildItem env: | ? { $_.Name -ieq $component.Name } | Select-Object -first 1).Value) -split ';') | ? { $component.Values -notcontains $_ }) + $component.Values) | Select-Object -Unique) -join ';') -target $component.Target
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-EnvironmentVariableUniquePrepend {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    Set-EnvironmentVariable -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -componentName $component.ComponentName -name $component.Name -value (@(($component.Values + @((((Get-ChildItem env: | ? { $_.Name -ieq $component.Name } | Select-Object -first 1).Value) -split ';') | ? { $component.Values -notcontains $_ })) | Select-Object -Unique) -join ';') -target $component.Target
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-RegistryKeySetOwner {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      $ntdll = Add-Type -Member '[DllImport("ntdll.dll")] public static extern int RtlAdjustPrivilege(ulong a, bool b, bool c, ref bool d);' -Name NtDll -PassThru
      @{ SeTakeOwnership = 9; SeBackup =  17; SeRestore = 18 }.Values | % { $null = $ntdll::RtlAdjustPrivilege($_, 1, 0, [ref]0) }
      $subkey = ($component.Key).Replace(('{0}\' -f ($component.Key).Split('\')[0]), '')
      switch -regex (($component.Key).Split('\')[0]) {
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
      $acl.SetOwner([System.Security.Principal.SecurityIdentifier]$component.SetOwner)
      $regKey.SetAccessControl($acl)
      $acl.SetAccessRuleProtection($false, $false)
      $regKey.SetAccessControl($acl)
      $regKey = $regKey.OpenSubKey('', 'ReadWriteSubTree', 'ChangePermissions')
      $acl.ResetAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule([System.Security.Principal.SecurityIdentifier]$component.SetOwner, 'FullControl', @('ObjectInherit', 'ContainerInherit'), 'None', 'Allow')))
      $regKey.SetAccessControl($acl)
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: registry key owner set to: {2} for {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.SetOwner, $component.Key)
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to set registry key owner to: {2} for {3}. {4}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName,  $component.SetOwner, $component.Key, $_.Exception.Message)
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-RegistryKeySet {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      New-Item -Path $component.Key -Name $component.ValueName -Force
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: registry key {2} created at {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.ValueName, $component.Key)
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to create registry key {2} at {3}. {4}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.ValueName, $component.Key, $_.Exception.Message)
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-RegistryValueSet {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    switch -regex (($component.Key).Split('\')[0]) {
      'HKEY_CURRENT_USER|HKCU' {
        $path = $component.Key.Replace('HKEY_CURRENT_USER\', 'HKCU:\').Replace('HKCU\', 'HKCU:\')
      }
      'HKEY_LOCAL_MACHINE|HKLM' {
        $path = $component.Key.Replace('HKEY_LOCAL_MACHINE\', 'HKLM:\').Replace('HKLM\', 'HKLM:\')
      }
      'HKEY_CLASSES_ROOT|HKCR' {
        $path = $component.Key.Replace('HKEY_CLASSES_ROOT\', 'HKCR:\').Replace('HKCR\', 'HKCR:\')
      }
      'HKEY_CURRENT_CONFIG|HKCC' {
        $path = $component.Key.Replace('HKEY_CURRENT_CONFIG\', 'HKCC:\').Replace('HKCC\', 'HKCC:\')
      }
      'HKEY_USERS|HKU' {
        $path = $component.Key.Replace('HKEY_USERS\', 'HKU:\').Replace('HKU\', 'HKU:\')
      }
      default {
        $path = $component.Key
      }
    }
    if (-not (Get-Item -Path $path -ErrorAction 'SilentlyContinue')) {
      try {
        New-Item -Path $path -Force
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: registry path: {2} created' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $path)
      } catch {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to create registry path {2}. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $path, $_.Exception.Message)
      }
    } else {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: registry path: {2} detected' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $path)
    }
    if (Get-ItemProperty -Path $path -Name $component.ValueName -ErrorAction 'SilentlyContinue') {
      try {
        trap [System.UnauthorizedAccessException] {
          Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to update registry value to: [{2}]{3}{4} for key {5} at path {6}. {7}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.ValueType, $component.ValueData, $(if ($component.Hex) { '(hex)' } else { '' }), $component.ValueName, $path, $_)
        }
        Set-ItemProperty -Path $path -Name $component.ValueName -Value $component.ValueData -Force
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: registry value updated with value: [{2}]{3}{4} for key {5} at path {6}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.ValueType, $component.ValueData, $(if ($component.Hex) { '(hex)' } else { '' }), $component.ValueName, $path)
      } catch {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to update registry value to: [{2}]{3}{4} for key {5} at path {6}. {7}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.ValueType, $component.ValueData, $(if ($component.Hex) { '(hex)' } else { '' }), $component.ValueName, $path, $_.Exception.Message)
      }
    } else {
      try {
        New-ItemProperty -Path $path -Name $component.ValueName -PropertyType $component.ValueType -Value $component.ValueData -Force
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: registry value created with value: [{2}]{3}{4} for key {5} at path {6}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.ValueType, $component.ValueData, $(if ($component.Hex) { '(hex)' } else { '' }), $component.ValueName, $path)
      } catch {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to create registry value to: [{2}]{3}{4} for key {5} at path {6}. {7}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.ValueType, $component.ValueData, $(if ($component.Hex) { '(hex)' } else { '' }), $component.ValueName, $path, $_.Exception.Message)
      }
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-DisableIndexing {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      # Disable indexing on all disk volumes.
      Get-WmiObject Win32_Volume -Filter "IndexingEnabled=$true" | Set-WmiInstance -Arguments @{IndexingEnabled=$false}
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: indexing disabled' -f $($MyInvocation.MyCommand.Name), $component.ComponentName)
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed disable indexing. {2}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $_.Exception.Message)
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-DisableIndexing {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      $volumesWithIndexingEnabled = (Get-WmiObject Win32_Volume -Filter "IndexingEnabled=$true" -ErrorAction 'SilentlyContinue')
      $result = (-not ($volumesWithIndexingEnabled))
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: indexing disabled {2}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $(if ($result) { 'confirmed' } else { 'refuted' }))
    } catch {
      $result = $false
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to confirm or refute indexing disabled. {2}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $_.Exception.Message)
    }
    return $result
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-FirewallRuleSet {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    $dir = $(if ($component.Direction -ieq 'Outbound') { 'out' } else { 'in' })
    if (($component.Protocol) -and ($component.LocalPort)) {
      $ruleName = ('{0} ({1} {2} {3}): {4}' -f $component.ComponentName, $component.Protocol, $component.LocalPort, $component.Direction, $component.Action)
      try {
        if (Get-Command 'New-NetFirewallRule' -ErrorAction 'SilentlyContinue') {
          if ($component.RemoteAddress) {
            New-NetFirewallRule -DisplayName $ruleName -Protocol $component.Protocol -LocalPort $component.LocalPort -Direction $component.Direction -Action $component.Action -RemoteAddress $component.RemoteAddress
          } else {
            New-NetFirewallRule -DisplayName $ruleName -Protocol $component.Protocol -LocalPort $component.LocalPort -Direction $component.Direction -Action $component.Action
          }
        } else {
          if ($component.RemoteAddress) {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $component.Action), ('protocol={0}' -f $component.Protocol), ('localport={0}' -f $component.LocalPort), ('remoteip={0}' -f $component.RemoteAddress))
          } else {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $component.Action), ('protocol={0}' -f $component.Protocol), ('localport={0}' -f $component.LocalPort))
          }
        }
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: firewall rule: {2} created' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $ruleName)
      } catch {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to create firewall rule: {2}. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName,  $ruleName, $_.Exception.Message)
      }
    } elseif (($component.Protocol -eq 'ICMPv4') -or ($component.Protocol -eq 'ICMPv6')) {
      $ruleName = ('{0} ({1} {2} {3}): {4}' -f $component.ComponentName, $component.Protocol, $component.Action)
      try {
        if (Get-Command 'New-NetFirewallRule' -ErrorAction 'SilentlyContinue') {
          if ($component.RemoteAddress) {
            New-NetFirewallRule -DisplayName $ruleName -Protocol $component.Protocol -IcmpType 8 -Action $component.Action -RemoteAddress $component.RemoteAddress
          } else {
            New-NetFirewallRule -DisplayName $ruleName -Protocol $component.Protocol -IcmpType 8 -Action $component.Action
          }
        } else {
          if ($component.RemoteAddress) {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $component.Action), ('protocol={0}:8,any' -f $component.Protocol), ('localport={0}' -f $component.LocalPort), ('remoteip={0}' -f $component.RemoteAddress))
          } else {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $component.Action), ('protocol={0}:8,any' -f $component.Protocol), ('localport={0}' -f $component.LocalPort))
          }
        }
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: firewall rule: {2} created' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $ruleName)
      } catch {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to create firewall rule: {2}. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName,  $ruleName, $_.Exception.Message)
      }
    } elseif ($component.Program) {
      $ruleName = ('{0} ({1} {2}): {3}' -f $component.ComponentName, $component.Program, $component.Direction, $component.Action)
      try {
        if (Get-Command 'New-NetFirewallRule' -ErrorAction 'SilentlyContinue') {
          if ($component.RemoteAddress) {
            New-NetFirewallRule -DisplayName $ruleName -Program $component.Program -Direction $component.Direction -Action $component.Action -RemoteAddress $component.RemoteAddress
          } else {
            New-NetFirewallRule -DisplayName $ruleName -Program $component.Program -Direction $component.Direction -Action $component.Action
          }
        } else {
          if ($component.RemoteAddress) {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $component.Action), ('program={0}' -f $component.Program), ('remoteip={0}' -f $component.RemoteAddress))
          } else {
            & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', ('name="{0}"' -f $ruleName), ('dir={0}' -f $dir), ('action={0}' -f $component.Action), ('program={0}' -f $component.Program))
          }
        }
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: firewall rule: {2} created' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $ruleName)
      } catch {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to create firewall rule: {2}. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName,  $ruleName, $_.Exception.Message)
      }
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-FirewallRuleSet {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      if (($component.Protocol) -and ($component.LocalPort)) {
        $ruleName = ('{0} ({1} {2} {3}): {4}' -f $component.ComponentName, $component.Protocol, $component.LocalPort, $component.Direction, $component.Action)
      } elseif (($component.Protocol -eq 'ICMPv4') -or ($component.Protocol -eq 'ICMPv6')) {
        $ruleName = ('{0} ({1} {2} {3}): {4}' -f $component.ComponentName, $component.Protocol, $component.Action)
      } elseif ($component.Program) {
        $ruleName = ('{0} ({1} {2}): {3}' -f $component.ComponentName, $component.Program, $component.Direction, $component.Action)
      } else {
        $result = $false
      }
      if (Get-Command 'Get-NetFirewallRule' -ErrorAction 'SilentlyContinue') {
        $result = (Confirm-LogValidation -source 'occ-dsc' -satisfied ([bool](Get-NetFirewallRule -DisplayName $ruleName -ErrorAction 'SilentlyContinue')) -verbose)
      } else {
        $result = ((& 'netsh.exe' @('advfirewall', 'firewall', 'show', 'rule', $ruleName)) -notcontains 'No rules match the specified criteria.')
      }
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: firewall rule: {2} existence {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $ruleName, $(if ($result) { 'confirmed' } else { 'refuted' }))
    } catch {
      $result = $false
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to confirm or refute existence of firewall rule {2}. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $ruleName, $_.Exception.Message)
    }
    return $result
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-ReplaceInFile {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      $content = ((Get-Content -Path $component.Path) | Foreach-Object { $_ -replace $component.Match, (Invoke-Expression -Command $component.Replace) })
      [System.IO.File]::WriteAllLines($component.Path, $content, (New-Object -TypeName 'System.Text.UTF8Encoding' -ArgumentList $false))
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: replaced occurences of: {2} with: {3} in: {4}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Match, $component.Replace, $component.Path)
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to replace occurences of: {2} with: {3} in: {4}. {5}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Match, $component.Replace, $component.Path, $_.Exception.Message)
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
function Invoke-ZipInstall {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [Parameter(Mandatory = $true)]
    [string] $path,

    [switch] $overwrite = $false,
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    if ($overwrite -and (Test-Path -Path $component.Destination -ErrorAction 'SilentlyContinue')) {
      try {
        Remove-Item $component.Destination -Confirm:$false -recurse -force
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: deleted directory {2}.' -f  $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Destination)
      } catch {
        Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'warn' -message ('{0} ({1}) :: error deleting directory {2}. {3}' -f  $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Destination, $_.Exception.Message)
        try {
          Start-Process 'icacls' -ArgumentList @($component.Destination, '/grant', ('{0}:(OI)(CI)F' -f $env:Username), '/inheritance:r') -Wait -NoNewWindow -PassThru | Out-Null
          Remove-Item $component.Destination -Confirm:$false -recurse -force
        } catch {
          Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: error resetting permissions or deleting directory ({2}). {3}' -f  $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Destination, $_.Exception.Message)
        }
      }
    }
    try {
      [System.IO.Compression.ZipFile]::ExtractToDirectory($path, $component.Destination)
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: zip: {2} extracted to: {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $path, $component.Destination)
    } catch {
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to extract zip: {2} to: {3}. {4}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $path, $component.Destination, $_.Exception.Message)
    }
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-DownloadInstall {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [Parameter(Mandatory = $true)]
    [ValidateSet('exe', 'msi', 'msu')]
    [string] $format,

    [string] $localPath = $(if ($format -eq 'msi') { ('{0}\Temp\{1}_{2}.msi' -f $env:SystemRoot, $component.ComponentName, $component.ProductId) } else { ('{0}\Temp\{1}.{2}' -f $env:SystemRoot, $(if ($component.sha512) { $component.sha512 } else { $component.ComponentName }), $format) }),

    [string] $tooltoolHost = 'tooltool.mozilla-releng.net',
    [string] $tokenPath = ('{0}\builds\occ-installers.tok' -f $env:SystemDrive),
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    switch ($format) {
      'exe' {
        $command = $localPath
        $arguments = @($component.Arguments | % { $($_) })
      }
      'msi' {
        $command = ('{0}\system32\msiexec.exe' -f $env:WinDir)
        $arguments = @('/i', $localPath, '/log', ('{0}\log\{1}-{2}.msi.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $component.ComponentName), '/quiet', '/norestart') + @($component.Arguments | % { $($_) })
      }
      'msu' {
        $command = ('{0}\system32\wusa.exe' -f $env:WinDir)
        $arguments = @($localPath, '/quiet', '/norestart')
      }
    }
    Invoke-FileDownload -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -component $component -localPath $localPath -tooltoolHost $tooltoolHost -tokenPath $tokenPath
    Invoke-LoggedCommandRun -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -componentName $component.ComponentName -command $command -arguments $arguments -timeoutInSeconds $(if ($component.Timeout) { [int]$component.Timeout } else { 600 })
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-DownloadInstall {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $localPath = $(if ($format -eq 'msi') { ('{0}\Temp\{1}_{2}.msi' -f $env:SystemRoot, $component.ComponentName, $component.ProductId) } else { ('{0}\Temp\{1}.{2}' -f $env:SystemRoot, $(if ($component.sha512) { $component.sha512 } else { $component.ComponentName }), $format) }),

    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    return ((Confirm-FileDownload -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -component $component -localPath $localPath) -and (Confirm-CommandRun -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -component $component))
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-ExeInstall {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $localPath = ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $(if ($component.sha512) { $component.sha512 } else { $component.ComponentName })),
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    Invoke-DownloadInstall -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -component $component -localPath $localPath -format 'exe'
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-ExeInstall {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $localPath = ('{0}\Temp\{1}.exe' -f $env:SystemRoot, $(if ($component.sha512) { $component.sha512 } else { $component.ComponentName })),
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    return (Confirm-DownloadInstall -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -component $component -localPath $localPath)
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-MsiInstall {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $localPath = ('{0}\Temp\{1}_{2}.msi' -f $env:SystemRoot, $component.ComponentName, $component.ProductId),
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    Invoke-DownloadInstall -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -component $component -localPath $localPath -format 'msi'
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-MsiInstall {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $localPath = ('{0}\Temp\{1}_{2}.msi' -f $env:SystemRoot, $component.ComponentName, $component.ProductId),
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      $result = [bool](Get-WmiObject -Class 'Win32_Product' -Filter ('Name="{0}" AND IdentifyingNumber="{{{1}}}"' -f $component.Name, $component.ProductId) -ErrorAction 'SilentlyContinue')
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: msi: {2} with product id: {3} existence {4}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Name, $component.ProductId, $(if ($result) { 'confirmed' } else { 'refuted' }))
    } catch {
      $result = $false
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to confirm or refute existence of msi {2} with product id: {3}. {4}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Name, $component.ProductId, $_.Exception.Message)
    }
    return $result
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Invoke-MsuInstall {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $localPath = ('{0}\Temp\{1}.msu' -f $env:SystemRoot, $(if ($component.sha512) { $component.sha512 } else { $component.ComponentName })),
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    Invoke-DownloadInstall -verbose:$verbose -eventLogName $eventLogName -eventLogSource $eventLogSource -component $component -localPath $localPath -format 'msu'
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}

function Confirm-MsuInstall {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [object] $component,

    [string] $localPath = ('{0}\Temp\{1}.msu' -f $env:SystemRoot, $(if ($component.sha512) { $component.sha512 } else { $component.ComponentName })),
    
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: begin - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
  process {
    try {
      $result = [bool](Get-WmiObject -Class 'Win32_QuickFixEngineering' -Filter ('HotFixId="{0}"' -f $component.Id) -ErrorAction 'SilentlyContinue')
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'info' -message ('{0} ({1}) :: msu with hot fix id: {2} existence {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Id, $(if ($result) { 'confirmed' } else { 'refuted' }))
    } catch {
      $result = $false
      Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'error' -message ('{0} ({1}) :: failed to confirm or refute existence of msu with hot fix id: {2}. {3}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, $component.Id, $_.Exception.Message)
    }
    return $result
  }
  end {
    Write-Log -verbose:$verbose -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} ({1}) :: end - {2:o}' -f $($MyInvocation.MyCommand.Name), $component.ComponentName, (Get-Date).ToUniversalTime())
  }
}