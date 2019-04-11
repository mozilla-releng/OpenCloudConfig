<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>


function Write-Log {
  <#
  .SYNOPSIS
    Write a log message to the windows event log and powershell verbose stream

  .DESCRIPTION
    This function takes a log message and writes it to the windows event log as well as the powershell verbose stream.
    If the specified logName or source are missing from the windows event log, they are created.

  .PARAMETER  message
    The message parameter is the log message to be recorded to the event log

  .PARAMETER  severity
    The logging severity is the severity rating for the message being recorded.
    There are four ratings:
    - debug: verbose messages about state observations for debugging purposes
    - info: normal messages about state changes
    - warn: messages about unexpected occurences or observations that are not fatal to the running of the application
    - error: messages about failure of a critical logic path in the application

  .PARAMETER  source
    The optional source parameter maps directly to the required event log source.
    This should be set to the name of the application being logged.

  .PARAMETER  logName
    The optional logName parameter maps directly to the required event log logName.
    Most logs should go to the 'Application' pool

  .EXAMPLE
    These examples show how to call the Write-Log function with named parameters.
    PS C:\> Write-Log -message 'the sun is shining, the weather is sweet.' -severity 'debug' -source 'AmazingDaysApp'
    PS C:\> Write-Log -message 'it has started to rain. an umbrella has been provided.' -severity 'info' -source 'AmazingDaysApp'
    PS C:\> Write-Log -message 'thunder and lightning, very, very frightening.' -severity 'warn' -source 'AmazingDaysApp'
    PS C:\> Write-Log -message 'you are snowed in. the door is jammed shut.' -severity 'error' -source 'AmazingDaysApp'

  .NOTES

  #>
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $message,

    [ValidateSet('debug', 'error', 'info', 'warn')]
    [string] $severity = 'info',

    [string] $source = 'OpenCloudConfig',
    [string] $logName = 'Application'
  )
  if ((-not ([System.Diagnostics.EventLog]::Exists($logName))) -or (-not ([System.Diagnostics.EventLog]::SourceExists($source)))) {
    try {
      New-EventLog -LogName $logName -Source $source
    } catch {
      Write-Error -Exception $_.Exception -message ('failed to create event log source: {0}/{1}' -f $logName, $source)
    }
  }
  switch ($severity[0].ToString().ToLower()) {
    # debug
    'd' {
      $entryType = 'SuccessAudit'
      $eventId = 2
      break
    }
    # warn
    'w' {
      $entryType = 'Warning'
      $eventId = 3
      break
    }
    # error
    'e' {
      $entryType = 'Error'
      $eventId = 4
      break
    }
    # info
    default {
      $entryType = 'Information'
      $eventId = 1
      break
    }
  }
  try {
    Write-EventLog -LogName $logName -Source $source -EntryType $entryType -EventId $eventId -Message $message
  } catch {
    Write-Error -Exception $_.Exception -message ('failed to write to event log source: {0}/{1}. the log message was: {2}' -f $logName, $source, $message)
    Write-Verbose -Message ('failed to write to event log source: {0}/{1}. the log message was: {2}' -f $logName, $source, $message)
  }
  Write-Verbose -Message $message
}

function Get-TooltoolResource {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $localPath,

    [Parameter(Mandatory = $true)]
    [string] $sha512,

    [Parameter(Mandatory = $true)]
    [string] $tokenPath,

    [Parameter(Mandatory = $true)]
    [string] $tooltoolHost,

    [string] $eventLogName = 'Application',

    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
  process {
    # read and validate tooltool bearer token from $tokenPath
    try {
      if (-not (Test-Path -Path $tokenPath -ErrorAction SilentlyContinue)) {
        throw [System.IO.FileNotFoundException] ('token file not found at {0}' -f $tokenPath)
      }
      $bearerToken = (Get-Content -Path $tokenPath -Raw)
      # todo: validate token with a regex
      if ($bearerToken) {
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: tooltool bearer token obtained at {1}' -f $($MyInvocation.MyCommand.Name), $tokenPath)
      } else {
        Write-Log -logName $eventLogName -source $eventLogSource -Severity 'error' -message ('{0} :: invalid or null token found at {1}' -f $($MyInvocation.MyCommand.Name), $tokenPath)
      }
    } catch {
      Write-Log -logName $eventLogName -source $eventLogSource -Severity 'error' -message ('{0} :: failed to read valid tooltool bearer token at {1}. {2}' -f $($MyInvocation.MyCommand.Name), $tokenPath, $_.Exception.Message)
    }
    if ($bearerToken) {
      # download remote resource
      $url = ('https://{0}/sha512/{1}' -f $tooltoolHost, $sha512)
      $headers = @{
        'Authorization' = ('Bearer {0}' -f $bearerToken)
      }
      return (Get-RemoteResource -url $url -headers $headers -localPath $localPath -eventLogName $eventLogName -eventLogSource $eventLogSource)
    } else {
      return $false
    }
  }
  end {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
}

function Get-RemoteResource {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string] $localPath,
    [Parameter(Mandatory = $true)]
    [string] $url,
    [hashtable] $headers,
    [string] $eventLogName = 'Application',
    [string] $eventLogSource = 'OpenCloudConfig'
  )
  begin {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
  process {
    try {
      if (Test-Path -Path $localPath -ErrorAction SilentlyContinue) {
        try {
          Remove-Item $localPath -force
          Write-Log -logName $eventLogName -source $eventLogSource -severity 'warn' -message ('{0} :: deleted {1} before download from {2}' -f $($MyInvocation.MyCommand.Name), $localPath, $url)
        } catch {
          Write-Log -logName $eventLogName -source $eventLogSource -Severity 'error' -message ('{0} :: failed to delete {1} before download from {2}. {3}' -f $($MyInvocation.MyCommand.Name), $localPath, $url, $_.Exception.Message)
        }
      }
      $webClient = New-Object -TypeName 'System.Net.WebClient'
      if (($headers) -and ($headers.ContainsKey('Authorization')) -and ($headers['Authorization'])) {
        $webClient.Headers.Add('Authorization', $headers['Authorization'])
      }
      # todo: handle non-auth headers
      $webClient.DownloadFile($url, $localPath)
      Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: remote resource downloaded from {1} to {2} on first attempt' -f $($MyInvocation.MyCommand.Name), $url, $localPath)
    } catch {
      Write-Log -logName $eventLogName -source $eventLogSource -Severity 'error' -message ('{0} :: failed to download remote resource from {1} to {2} on first attempt. {3}' -f $($MyInvocation.MyCommand.Name), $url, $localPath, $_.Exception.Message)
      try {
        # handle redirects (eg: sourceforge)
        if ($headers) {
          Invoke-WebRequest -Uri $url -OutFile $localPath -headers $headers -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
        } else {
          Invoke-WebRequest -Uri $url -OutFile $localPath -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
        }
        Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: remote resource downloaded from {1} to {2} on second attempt' -f $($MyInvocation.MyCommand.Name), $url, $localPath)
      } catch {
        Write-Log -logName $eventLogName -source $eventLogSource -Severity 'error' -message ('{0} :: failed to download remote resource from {1} to {2} on second attempt. {3}' -f $($MyInvocation.MyCommand.Name), $url, $localPath, $_.Exception.Message)
        return $false
      }
    }
    return (Test-Path -Path $localPath -ErrorAction SilentlyContinue)
  }
  end {
    Write-Log -logName $eventLogName -source $eventLogSource -severity 'debug' -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime())
  }
}