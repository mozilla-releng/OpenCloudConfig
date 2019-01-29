<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

Add-Type -As System.IO.Compression.FileSystem

function New-ZipFile {
  #.Synopsis
  #  Create a new zip file, optionally appending to an existing zip...
  [CmdletBinding()]
  param(
    # The path of the zip to create
    [Parameter(Position=0, Mandatory=$true)]
    $ZipFilePath,
 
    # Items that we want to add to the ZipFile
    [Parameter(Position=1, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias("PSPath","Item")]
    [string[]]$InputObject = $Pwd,
 
    # Append to an existing zip file, instead of overwriting it
    [Switch]$Append,
 
    # The compression level (defaults to Optimal):
    #   Optimal - The compression operation should be optimally compressed, even if the operation takes a longer time to complete.
    #   Fastest - The compression operation should complete as quickly as possible, even if the resulting file is not optimally compressed.
    #   NoCompression - No compression should be performed on the file.
    [System.IO.Compression.CompressionLevel]$Compression = "Optimal"
  )
  begin {
    # Make sure the folder already exists
    [string]$File = Split-Path $ZipFilePath -Leaf
    [string]$Folder = $(if($Folder = Split-Path $ZipFilePath) { Resolve-Path $Folder } else { $Pwd })
    $ZipFilePath = Join-Path $Folder $File
    # If they don't want to append, make sure the zip file doesn't already exist.
    if(!$Append) {
      if(Test-Path $ZipFilePath) { Remove-Item $ZipFilePath }
    }
    $Archive = [System.IO.Compression.ZipFile]::Open( $ZipFilePath, "Update" )
  }
  process {
    foreach($path in $InputObject) {
      foreach($item in Resolve-Path $path) {
        # Push-Location so we can use Resolve-Path -Relative
        Push-Location (Split-Path $item)
        # This will get the file, or all the files in the folder (recursively)
        foreach($file in Get-ChildItem $item -Recurse -File -Force | % FullName) {
          # Calculate the relative file path
          $relative = (Resolve-Path $file -Relative).TrimStart(".\")
          # Add the file to the zip
          $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Archive, $file, $relative, $Compression)
        }
        Pop-Location
      }
    }
  }
  end {
    $Archive.Dispose()
    Get-Item $ZipFilePath
  }
}