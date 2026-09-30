>[!NOTE]
>This fork was created to isolate the tools used in the original repository to more easily create custom setups.

# Getting Started

If you're new to FFU Builder or new to the FFU Builder UI version, check out the [Quick Start Guide](https://rbalsleymsft.github.io/FFU/quickstart.html). 

 If you have a flash drive with 32GB or more the fastest way to get started would be to use the `BuildFFUVM_UI.ps1` to create the FFU and `Create-PEMedia.ps1` script with `USBImagingToolCreator.ps1` to create the bootable medium. 

# Requirements

Hyper-V Enabled in features

`Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All`

Poweshell 7

`winget install --id Microsoft.PowerShell --source winget --installer-type wix`

# Custom Guide

## 1. Setup Bootable Medium (or PXE with WinPE)

 If you have 16GB or less you likely will not be able to fit an FFU file on it with WinPE, but could serve the files via SMB or another drive.

To create custom PE media follow these steps.

#### Create partitioned flash disk

   Run `diskpart` in PowerShell, then:

   ```
   list disk
   REM Replace X with your USB disk number
   select disk X
   clean
   convert mbr
   create partition primary size=2048
   active
   format fs=fat32 quick label="Boot"
   assign
   create partition primary
   format fs=ntfs quick label="Deploy"
   assign
   exit
   ```

#### Create PE Media

Use the `Create-Custom-PEMedia.ps1` script to create a `WinPE_ffu` folder. You'll copy everything from `WinPE_ffu\media` to the `BOOT` partition of the flash drive. This will make the drive bootable.

## 2. Create Virtual Machine

>[!Warning]
>Do not attach the VM to the internet[^1]

The [PSTools](https://github.com/13ruce1337/pstools) repository has a script (`provision_windows.ps1`) that can quickly spin up a VM after replacing the location for the Windows ISO at the top. You'll need to download the Windows ISO from Microsoft[^2]. There are also instructions for using an `autounattend.xml` for further automation.

## 3. Customize Virtual Machine

This might be a good spot to snapshot then add any applications needed for the build.

## 4. Creation of FFU

* Harden VHDX
   Run the below command after copying the `sysprep-ffu.xml` into `C:\Build\`

> [!NOTE] `C:\Build\sysprep-ffu.xml` will be removed
   
   `C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /unattend:C:\Build\sysprep-ffu.xml`
* Make FFU
   On the host or machine that has the VHDX run `make_ffu.ps1` after filling in the variables.

## 5. Flashing the FFU file

* After you create the FFU file, copy it to the USB stick or mountable medium. If you used the `USBImagingToolCreator.ps1`, copy it over to the Deploy partition. 

[^1]: When the VM connects to the internet it starts the process of updating. This starts a service that doesn't allow sysprep to work.
[^2]: Microsoft doesn't provide a direct link to download. You'll likely have to use the Media Creation Tool or similar to get the ISO.