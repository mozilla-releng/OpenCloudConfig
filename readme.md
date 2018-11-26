# Open Cloud Config (OCC)

[![Docker pulls](https://img.shields.io/docker/pulls/grenade/opencloudconfig.svg?style=plastic)](https://hub.docker.com/r/grenade/opencloudconfig/)
[![Deploy status](https://github.taskcluster.net/v1/repository/mozilla-releng/OpenCloudConfig/master/badge.svg)](https://github.taskcluster.net/v1/repository/mozilla-releng/OpenCloudConfig/master/latest)

## Issues
To file bugs, raise issues or request features, please use: [b.m.o/infra-ops/occ](https://bugzilla.mozilla.org/enter_bug.cgi?product=Infrastructure%20%26%20Operations&component=Relops%3A%20OpenCloudConfig).

## Usage

OCC is a small, fast, lightweight tool for creating Windows cloud (they don't really have to be in a cloud though) instances with a specific configuration in a repeatable, source controlled manner. Think of it as Puppet or Chef, without all the orchestration. There isn't even anything to install. It's implemented in a few powershell scripts, hosted in this repository.

OCC has no dependencies other than powershell so you shouldn't have to install anything on the instances where you want it to run. In EC2 for example, you can provide a single command in your userdata (and a great big json manifest out on the web somewhere), in order to build a specific instance configuration at startup.

Powershell [Desired State Configuration](https://msdn.microsoft.com/en-us/powershell/dsc/overview) (DSC) is used as the provider.

Which manifest to run is currently determined by the ssh key associated with the instance in AWS EC2 (key naming convention). There are currently manifests for:

- **Gecko Build Worker Types:**
  - Stable:
    - [gecko-1-b-win2012](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-1-b-win2012.json) Windows Server 2012 r2 - 64 bit - SCM Level 1
    - [gecko-2-b-win2012](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-2-b-win2012.json) Windows Server 2012 r2 - 64 bit - SCM Level 2
    - [gecko-3-b-win2012](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-3-b-win2012.json) Windows Server 2012 r2 - 64 bit - SCM Level 3
    - [gecko-3-b-win2012-c4](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-3-b-win2012-c4.json) Windows Server 2012 r2 - 64 bit - SCM Level 3
    - [gecko-3-b-win2012-c5](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-3-b-win2012-c5.json) Windows Server 2012 r2 - 64 bit - SCM Level 3
  - Experimental:
    - [gecko-1-b-win2012-beta](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-1-b-win2012-beta.json) Windows Server 2012 r2 - 64 bit - SCM Level 1
- **Gecko Test Worker Types:**
  - Stable:
    - [gecko-t-win7-32](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-t-win7-32.json) Windows 7 - 32 bit
    - [gecko-t-win7-32-gpu](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-t-win7-32-gpu.json) Windows 7 - 32 bit with GPU
    - [gecko-t-win10-64](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-t-win10-64.json) Windows 10 - 64 bit
    - [gecko-t-win10-64-gpu](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-t-win10-64-gpu.json) Windows 10 - 64 bit with GPU
  - Experimental:
    - [gecko-t-win7-32-beta](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-t-win7-32-beta.json) Windows 7 - 32 bit
    - [gecko-t-win10-64-beta](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-t-win10-64-beta.json) Windows 10 - 64 bit
    - [gecko-t-win10-64-gpu-b](https://github.com/mozilla-releng/OpenCloudConfig/blob/master/userdata/Manifest/gecko-t-win10-64-gpu-b.json) Windows 10 - 64 bit with GPU

Running the following command at an elevated powershell prompt (or providing it as EC2 userdata) will start OCC on an instance:

    Invoke-Expression (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/rundsc.ps1')

Instance configuration is defined in json format and currently includes implementations for these instance configuration mechanisms (most source parameters are expected to be a URL):

- **[DirectoryCreate](https://github.com/search?q=DirectoryCreate+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Create an empty folder or validate that it already exists

  *example*:
  ```
  {
    "ComponentName": "TempDirectory",
    "ComponentType": "DirectoryCreate",
    "Path": "C:\\Temp"
  }
  ```
- **[DirectoryDelete](https://github.com/search?q=DirectoryDelete+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Delete a folder and all contents or validate that it does not exist

  *example*:
  ```
  {
    "ComponentName": "TempDirectory",
    "ComponentType": "DirectoryDelete",
    "Path": "C:\\Temp"
  }
  ```
- **[DirectoryCopy](https://github.com/search?q=DirectoryCopy+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Copy a folder and all its contents or validate that destination is identical to source (including contents)

  *example*:
  ```
  {
    "ComponentName": "AliceDirectory",
    "ComponentType": "DirectoryCopy",
    "Source": "C:\\Users\\Bob",
    "Target": "C:\\Users\\Alice"
  }
  ```
- **[CommandRun](https://github.com/search?q=CommandRun+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Run a command from the cmd (COMSPEC) command prompt. Provides an optional mechanism for first performing a validation step to check if the command *should* be run

  *example*:
  ```
  {
    "ComponentName": "pip-upgrade-virtualenv",
    "ComponentType": "CommandRun",
    "Command": "C:\\Python27\\python.exe",
    "Arguments": [
      "-m",
      "pip",
      "install",
      "--upgrade",
      "virtualenv==15.0.1"
    ],
    "DependsOn": [
      {
        "ComponentType": "ExeInstall",
        "ComponentName": "PythonSetup"
      }
    ],
    "Validate": {
      "CommandsReturn": [
        {
          "Command": "C:\\Python27\\python.exe",
          "Arguments": [
            "-m",
            "pip",
            "show",
            "virtualenv"
          ],
          "Match": "Version: 15.0.1"
        }
      ]
    }
  }
  ```
- **[FileDownload](https://github.com/search?q=FileDownload+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Download a file from source or validate that a file with the same name exists at destination

  *example*:
  ```
  {
    "ComponentName": "Win32ToolToolManifest",
    "ComponentType": "ChecksumFileDownload",
    "Source": "https://hg.mozilla.org/mozilla-central/raw-file/tip/browser/config/tooltool-manifests/win32/releng.manifest",
    "Target": "C:\\Windows\\Temp\\releng.manifest.win32.tt"
  }
  ```
- **[ChecksumFileDownload](https://github.com/search?q=DirectoryCopy+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Download a file from source or validate that a file with the same name and SHA1 signature exists at destination

  *example*:
  ```
  {
    "ComponentName": "VisualStudio2015AdminDeployment",
    "ComponentType": "ChecksumFileDownload",
    "Source": "https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Configuration/VisualStudio2015/AdminDeployment.xml",
    "Target": "C:\\Windows\\Temp\\VisualStudio2015AdminDeployment.xml"
  }
  ```
- **[SymbolicLink](https://github.com/search?q=SymbolicLink+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Create a symbolic link (file or directory) or validate that it already exists

  *example*:
  ```
  {
    "ComponentName": "Home",
    "ComponentType": "SymbolicLink",
    "Target": "C:\\Users",
    "Link": "C:\\home"
  }
  ```
- **[ExeInstall](https://github.com/search?q=DirectoryCopy+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Install an executable or validate that it has already been installed (using optional validation commands)

  *example*:
  ```
  {
    "ComponentName": "VisualStudio2015Community",
    "ComponentType": "ExeInstall",
    "Url": "http://download.microsoft.com/download/0/B/C/0BC321A4-013F-479C-84E6-4A2F90B11269/vs_community.exe",
    "Arguments": [
      "/Passive",
      "/NoRestart",
      "/AdminFile",
      "C:\\Windows\\Temp\\VisualStudio2015AdminDeployment.xml",
      "/Log",
      "C:\\log\\VisualStudio2015CommunityInstall.log"
    ],
    "DependsOn": [
      {
        "ComponentType": "ChecksumFileDownload",
        "ComponentName": "VisualStudio2015AdminDeployment"
      }
    ],
    "Validate": {
      "PathsExist": [
        "C:\\Program Files (x86)\\Microsoft Visual Studio 14.0\\Common7\\IDE\\devenv.exe",
        "C:\\Program Files (x86)\\Microsoft Visual Studio 14.0\\VC\\bin\\mspdb140.dll",
        "C:\\Program Files (x86)\\Microsoft Visual Studio 14.0\\VC\\bin\\amd64\\mspdb140.dll"
      ]
    }
  }
  ```
- **[MsiInstall](https://github.com/search?q=MsiInstall+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Install an MSI or validate that it has already been installed (using product identifier)

  *example*:
  ```
  {
    "ComponentName": "BinScope",
    "ComponentType": "MsiInstall",
    "Comment": "https://dxr.mozilla.org/mozilla-central/search?q=BinScope&redirect=false&case=false",
    "Url": "https://download.microsoft.com/download/2/6/A/26AAA1DE-D060-4246-93B5-7D7C877E4F8F/BinScopeSetup.msi",
    "Name": "SDL BinScope",
    "ProductId": "B137EB8C-FA6C-4DA7-95F0-A9B6FFE67A64"
  }
  ```
- **[WindowsFeatureInstall](https://github.com/search?q=WindowsFeatureInstall+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Install a Windows feature or validate that it is already installed

  *example*:
  ```
  {
    "ComponentName": "NET-Framework-Core",
    "ComponentType": "WindowsFeatureInstall",
    "Name": "NET-Framework-Core",
    "DependsOn": [
      {
        "ComponentType": "ServiceControl",
        "ComponentName": "Start-wuauserv"
      }
    ]
  }
  ```
- **[ZipInstall](https://github.com/search?q=ZipInstall+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Extract a compressed archive from source to destination or validate that archive contents already exist at destination
- **[ServiceControl](https://github.com/search?q=ServiceControl+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Set service startup type and trigger the expected service state or validate that the startup type and service are already in the expected state

  *example*:
  ```
  {
    "ComponentName": "Start-wuauserv",
    "ComponentType": "ServiceControl",
    "Comment": "Required by NET-Framework-Core",
    "Name": "wuauserv",
    "StartupType": "Manual",
    "State": "Running"
  }
  ```
- **[EnvironmentVariableSet](https://github.com/search?q=EnvironmentVariableSet+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Set an environment variable or validate that it has been set to the provided value

  *example*:
  ```
  {
    "ComponentName": "env-MOZILLABUILD",
    "ComponentType": "EnvironmentVariableSet",
    "DependsOn": [
      {
        "ComponentType": "ExeInstall",
        "ComponentName": "MozillaBuildSetup"
      }
    ],
    "Name": "MOZILLABUILD",
    "Value": "C:\\mozilla-build",
    "Target": "Machine"
  }
  ```
- **[EnvironmentVariableUniqueAppend](https://github.com/search?q=EnvironmentVariableUniqueAppend+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Append one or more values to a collection environment variable delimited by semicolon or validate that the variable already contains the required value(s)

  *example*:
  ```
  {
    "ComponentName": "env-PATH",
    "ComponentType": "EnvironmentVariableUniqueAppend",
    "DependsOn": [
      {
        "ComponentType": "ExeInstall",
        "ComponentName": "PythonSetup"
      }
    ],
    "Name": "PATH",
    "Values": [
      "C:\\Python27\\python",
      "C:\\Python27\\python\\Scripts"
    ],
    "Target": "Machine"
  }
  ```
- **[EnvironmentVariableUniquePrepend](https://github.com/search?q=EnvironmentVariableUniquePrepend+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Prepend one or more values to a collection environment variable delimited by semicolon or validate that the variable already contains the required value(s)

  *example*:
  ```
  {
    "ComponentName": "env-PATH",
    "ComponentType": "EnvironmentVariableUniquePrepend",
    "DependsOn": [
      {
        "ComponentType": "ExeInstall",
        "ComponentName": "MozillaBuildSetup"
      }
    ],
    "Name": "PATH",
    "Values": [
      "C:\\mozilla-build\\7zip",
      "C:\\mozilla-build\\info-zip",
      "C:\\mozilla-build\\kdiff3",
      "C:\\mozilla-build\\moztools-x64\\bin",
      "C:\\mozilla-build\\mozmake",
      "C:\\mozilla-build\\msys\\bin",
      "C:\\mozilla-build\\msys\\local\\bin",
      "C:\\mozilla-build\\nsis-3.0b1",
      "C:\\mozilla-build\\nsis-2.46u",
      "C:\\mozilla-build\\python",
      "C:\\mozilla-build\\python\\Scripts",
      "C:\\mozilla-build\\upx391w",
      "C:\\mozilla-build\\wget",
      "C:\\mozilla-build\\yasm"
    ],
    "Target": "Machine"
  }
  ```
- **[RegistryKeySet](https://github.com/search?q=RegistryKeySet+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Set a registry key or validate that the key already exists

  *example*:
  ```
  {
    "ComponentName": "reg-WindowsErrorReportingLocalDumps",
    "ComponentType": "RegistryKeySet",
    "Comment": "",
    "Key": "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\Windows Error Reporting",
    "ValueName": "LocalDumps"
  }
  ```
- **[RegistryValueSet](https://github.com/search?q=RegistryValueSet+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Set a registry key and value or validate that the key already exists and contains the specified value  (optionally assigning ownership of the registry key to a user sid specified by the SetOwner property. useful when a key has been protected from change using ACLs and/or obscure ownership)

  *example*:
  ```
  {
    "ComponentName": "RegServiceStartupType_Disabled_WinDefend",
    "ComponentType": "RegistryValueSet",
    "Comment": "https://bugzilla.mozilla.org/show_bug.cgi?id=1509722",
    "Key": "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\WinDefend",
    "SetOwner": "S-1-5-32-544",
    "ValueName": "Start",
    "ValueType": "Dword",
    "ValueData": "0x4",
    "Hex": true
  }
  ```
- **[FirewallRule](https://github.com/search?q=FirewallRule+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Set a firewall rule or validate that the rule already exists

  *example*:
  ```
  {
    "ComponentName": "LiveLog-Get",
    "ComponentType": "FirewallRule",
    "Protocol": "TCP",
    "LocalPort": 60022,
    "Direction": "Inbound",
    "Action": "Allow"
  }
  ```
- **[ReplaceInFile](https://github.com/search?q=ReplaceInFile+language%3Apowershell+repo%3Amozilla-releng%2FOpenCloudConfig&type=Code)**:
  Replace text in a file (optionally using a powershell expression or variable)

  *example*:
  ```
  {
    "ComponentName": "SetNxlogAggregator",
    "ComponentType": "ReplaceInFile",
    "Path": "C:\\Program Files (x86)\\nxlog\\conf\\nxlog.conf",
    "Match": "DatacenterToken",
    "Replace": "$env:datacenter"
  }
  ```

# OpenCloudConfig CI

When a commit is pushed to the
[mozilla-releng/OpenCloudConfig](https://github.com/mozilla-releng/OpenCloudConfig/)
master branch, a set of tasks will be run.

## Previous tasks

To see previous tasks that have run, visit the [commits
page](https://github.com/mozilla-releng/OpenCloudConfig/commits/master) and
look for green ticks, or heaven forbid, red crosses.

## Implementation

Those tasks are generated from the `/.taskclsuter.yml` file in the root of this
repository via a
[taskcluster-github](https://github.com/taskcluster/taskcluster-github)
integration.

### AMI building

They will build [Amazon Machine
Images](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html) for a
set of [taskcluster worker
types](https://docs.taskcluster.net/manual/task-execution/worker-types), which
are defined in the `/userdata/Manifest` directory of this git repository. Each
json manifest file represents one specific worker type.

### Updating live worker type definitions

In addition to rebuilding the AMIs, the CI will also update [live production
AWS worker type definitions](https://tools.taskcluster.net/aws-provisioner) to
use the new images.

## Deployment commit message syntax

Deployment tasks can be run (or prevented from running) based on the syntax of the commit message on the master branch commit head.

### Specifying which worker type amis to deploy

- to update all OCC worker types:

  `deploy: all`

- to update all OCC **beta** worker types:

  `deploy: beta`

- to update the gecko-1-b-win2012 & gecko-2-b-win2012 worker types (provide a space delimited list in your deploy message):

  `deploy: gecko-1-b-win2012 gecko-2-b-win2012`

### Specifying a different repository (or branch) to build amis from

When testing potentially problematic changes, it is useful to deploy from a forked repository or a development branch to beta workers.

- to deploy to beta workers from the bz1234567 branch of the main repository:

  `beta-source: mozilla-releng OpenCloudConfig bz1234567`

- to deploy to beta workers from grenade's dev-hack branch in his private fork:

  `beta-source: grenade OpenCloudConfig dev-hack`

### Examples

This can be easily accomplished using two or three messages in the commit command; the first the regular commit message, and subsequent lines for the
deployment instructions, e.g.:

```
git commit -m 'Something important for GPU beta worker types' \
           -m 'deploy: gecko-t-win10-64-gpu-b gecko-t-win7-32-gpu-b'
```

```
git commit -m 'Some change from my fork to be tested on beta worker types' \
           -m 'deploy: beta' \
           -m 'beta-source: my-gh-username my-gh-repo my-dev-branch'
```

> Note - a task will still be created for each possible workertype, however it will immediately exit when it runs, if it is not included in the deploy syntax.

> Also note, if you do not include deploy syntax in your commit, nothing will be deployed. This is to safeguard automatic deploys from pushes where a deployment is not intended.

## Redeploying without changes

If you find yourself needing to retrigger a deployment, or deploy to an
additional worker type, but without making source code changes, this can be
accomplished with an empty commit as follows:

```
git commit --allow-empty \
           -m "Doing this because I'm special." \
           -m 'deploy: gecko-t-win10-64-gpu-b gecko-t-win7-32-gpu-b'
```

## AMI retention

OCC will automatically retain 10 previous images when building new images, so
that rollback is possible via manual updating of the aws provisioner worker
type definitions. However if you wish to rollback many versions, you may need
to rebuild. In any case it is best to follow up a rollback with a `git revert`
and push to master branch, so that the OCC repository is always in sync with
the production versions.

# OpenCloudConfig architecture

Here are some of the more important files in this repository.

| File | Description |
| ---- | ----------- |
| `/ci/update-workertype.sh` | CI script to rebuild AMIs and update live production worker type definitions. |
| `/userdata/xDynamicConfig.ps1` | Defines the allowed `ComponentType`s accepted by OpenCloudConfig, as documented above. |
| `/userdata/rundsc.ps1` | Script to run on vanilla environment, to apply configuration. |
| `/userdata/HaltOnIdle.ps1` | Checks machine activity and decides whether to terminate it due to inactivity / bad state / etc. |
