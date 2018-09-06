<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

function Validate-All {
  [CmdletBinding()]
  param(
    [object] $validations
  )
  begin {
    if (-not ($validations) -or (
        (-not ($validations.PathsExist)) -and
        (-not ($validations.PathsNotExist)) -and
        (-not ($validations.CommandsReturn)) -and
        (-not ($validations.FilesContain))
      )
    ) {
      Write-Verbose ('{0} :: No validations specified.' -f $($MyInvocation.MyCommand.Name))
    }
  }
  process {
    return (
      # if no validations are specified, this function will return $false and cause the calling resource's set script to be run
      (
        (($validations.PathsExist) -and ($validations.PathsExist.Length -gt 0)) -or
        (($validations.PathsNotExist) -and ($validations.PathsNotExist.Length -gt 0)) -or
        (($validations.CommandsReturn) -and ($validations.CommandsReturn.Length -gt 0)) -or
        (($validations.FilesContain) -and ($validations.FilesContain.Length -gt 0))
      ) -and (
        Validate-PathsExistOrNotRequested -items $validations.PathsExist -verbose:$PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent
      ) -and (
        Validate-PathsNotExistOrNotRequested -items $validations.PathsNotExist -verbose:$PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent
      ) -and (
        Validate-CommandsReturnOrNotRequested -items $validations.CommandsReturn -verbose:$PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent
      ) -and (
        Validate-FilesContainOrNotRequested -items $validations.FilesContain -verbose:$PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent
      )
    )
  }
  end {}
}

function Validate-PathsExistOrNotRequested {
  [CmdletBinding()]
  param(
    [object[]] $items
  )
  begin {
    Write-Verbose ('{0} :: {1} validation{2} specified.' -f $($MyInvocation.MyCommand.Name), $items.Length, ('s','')[($items.Length -eq 1)])
  }
  process {
    # either no validation paths-exist are specified
    return ((-not ($items)) -or (
      # validation paths-exist are specified
      (($items) -and ($items.Length -gt 0)) -and
      # all validation paths-exist are satisfied (exist on the instance)
      (-not (@($items | % {
        if (Test-Path -Path $_ -ErrorAction SilentlyContinue) {
          Write-Verbose ('Path present: {0}' -f $_)
          $true
        } else {
          Write-Verbose ('Path absent: {0}' -f $_)
          $false
        }
      }) -contains $false))
    ))
  }
  end {}
}

function Validate-PathsNotExistOrNotRequested {
  [CmdletBinding()]
  param(
    [object[]] $items
  )
  begin {
    Write-Verbose ('{0} :: {1} validation{2} specified.' -f $($MyInvocation.MyCommand.Name), $items.Length, ('s','')[($items.Length -eq 1)])
  }
  process {
    # either no validation paths-exist are specified
    return ((-not ($items)) -or (
      # validation paths-exist are specified
      (($items) -and ($items.Length -gt 0)) -and
      # all validation paths-exist are satisfied (exist on the instance)
      (-not (@($items | % {
        if (-not (Test-Path -Path $_ -ErrorAction SilentlyContinue)) {
          Write-Verbose ('Path absent: {0}' -f $_)
          $true
        } else {
          Write-Verbose ('Path present: {0}' -f $_)
          $false
        }
      }) -contains $false))
    ))
  }
  end {}
}

function Validate-CommandsReturnOrNotRequested {
  [CmdletBinding()]
  param(
    [object[]] $items
  )
  begin {
    Write-Verbose ('{0} :: {1} validation{2} specified.' -f $($MyInvocation.MyCommand.Name), $items.Length, ('s','')[($items.Length -eq 1)])
  }
  process {
    # either no validation commands-return are specified
    return ((-not ($items)) -or (
      # validation commands-return are specified
      (($items) -and ($items.Length -gt 0)) -and
      # all validation commands-return are satisfied
      ((@($items | % {
        $cr = $_
        Write-Verbose ('Command: {0} {1}' -f $cr.Command, ($cr.Arguments -join ' '))
        if ($cr.Match) {
          Write-Verbose ('Search (match): {0}' -f $cr.Match)
          if (@(& $cr.Command $cr.Arguments 2>&1) -contains $cr.Match) {
            Write-Verbose ('Output (match): {0}' -f $_)
            $true
          } else {
            $false
          }
        } elseif ($cr.Like) {
          Write-Verbose ('Search (like): {0}' -f $cr.Like)
          if (@(& $cr.Command $cr.Arguments 2>&1) -like $cr.Like) {
            Write-Verbose ('Output (like): {0}' -f $_)
            $true
          } else {
            $false
          }
        } else {
          $false
        }
      }) -notcontains $false))
    ))
  }
  end {}
}

function Validate-FilesContainOrNotRequested {
  [CmdletBinding()]
  param(
    [object[]] $items
  )
  begin {
    Write-Verbose ('{0} :: {1} validation{2} specified.' -f $($MyInvocation.MyCommand.Name), $items.Length, ('s','')[($items.Length -eq 1)])
  }
  process {
    # either no validation files-contain are specified
    return ((-not ($items)) -or (
      # validation files-contain are specified
      (($items) -and ($items.Length -gt 0)) -and
      # all validation files-contain are satisfied
      (-not (@($items | % {
        $fc = $_
        Write-Verbose ('Path: {0}' -f $fc.Path)
        Write-Verbose ('Search: {0}' -f $fc.Match)
        (((Get-Content $fc.Path) | % {
          if ($_ -match $fc.Match) {
            Write-Verbose ('Contents matched: {0}' -f $_)
            $true
          } else {
            $false
          }
        }) -contains $true) # a line within the file contained a match
      }) -contains $false)) # no files failed to contain a match (see '-not' above)
    ))
  }
  end {}
}

function Log-Validation {
  [CmdletBinding()]
  param(
    [bool] $validationsSatisfied
  )
  begin {
    Write-Verbose @('Validations not satisfied','Validations satisfied')[$validationsSatisfied]
  }
  process {
    return $validationsSatisfied
  }
  end {}
}
