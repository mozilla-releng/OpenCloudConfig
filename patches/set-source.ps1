if (${env:PROCESSOR_ARCHITEW6432} -eq 'ARM64') {
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Mozilla\OpenCloudConfig\Source' -Type 'String' -Name 'Revision' -Value 'master'
}