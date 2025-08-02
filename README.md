**Update 2025-08-01:** [2507.2 UI Preview is now available](https://github.com/rbalsleyMSFT/FFU/releases) - click the link to get the build and check out the Youtube walk-through.

# Using Full Flash Update (FFU) files to speed up Windows deployment

What if you could have a Windows image (Windows 10/11 or Server) that has:

- The latest Windows cumulative update
- The latest .NET cumulative update
- The latest Windows Defender Platform and Definition Updates
- The latest version of Microsoft Edge
- The latest version of OneDrive (Per-Machine)
- The latest version of Microsoft 365 Apps/Office
- The latest drivers from any of the major OEMs (Dell, HP, Lenovo, Microsoft) (yes, the latest, not some out of date enterprise CAB file from years ago)
- Winget support so you can integrate any app available from Winget directly in your image
- ARM64 support for the latest Copilot+ PCs
- The ability to bring your own drivers and apps if necessary
- Custom WinRE support

And the best part: it takes less than two minutes to apply the image, even with all of these updates added to the media. After setting Windows up and going through Autopilot or a provisioning package, total elapsed time ~10 minutes (depending on what Intune or your device management tool is deploying).

The Full-Flash update (FFU) process can automatically download the latest release of Windows 11, the updates mentioned above, and creates a USB drive that can be used to quickly reimage a machine.

# Getting Started

- Download the latest [release](https://github.com/rbalsleyMSFT/FFU/releases)
- Extract the FFUDevelopment folder from the ZIP file (recommend to C:\FFUDevelopment)
- Follow the doc: C:\FFUDevelopment\Docs\BuildDeployFFU.docx

## YouTube Detailed Walkthrough

The first 15 minutes of the following video includes a quick start demo to get started. Below the video are a list of chapters. This video was taken with the 2407.2 build. Features released after that will not be demonstrated in the video.

[![Reimage Windows Fast with Full-Flash Update (FFU))](https://img.youtube.com/vi/rqXRbgeeKSQ/maxresdefault.jpg)](https://www.youtube.com/watch?v=rqXRbgeeKSQ "Reimage Windows Fast with Full-Flash Update (FFU))")

Chapters:

[00:00](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=0s) Begin

[03:21](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=201s) Quick Start Prereqs

[07:19](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=439s) Quick Start Demo

[14:12](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=852s) Script Parameters

[17:22](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=1042s) Obtaining Windows Media

[25:55](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=1555s) Adding Applications

[26:59](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=1619s) Adding M365 Apps/Office

[29:21](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=1761s) Adding Applications via Winget

[34:59](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=2099s) Bring your own Applications

[36:01](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=2161s) Customizing InstallAppsAndSysprep.cmd

[38:34](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=2314s) Demo - Application Configuration

[49:43](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=2983s) Drivers

[55:39](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=3339s) Automatically downloading drivers

[57:28](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=3448s) Microsoft Surface drivers

[58:55](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=3535s) Dell drivers

[01:01:45](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=3705s) Lenovo drivers

[01:03:16](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=3796s) HP drivers

[01:05:25](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=3925s) Bring your own drivers

[01:06:24](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=3984s) Demo - Drivers

[01:11:55](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=4315s) Multi-model driver support

[01:13:21](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=4401s) Device naming

[01:18:30](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=4710s) Device enrollment

[01:21:43](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=4903s) Autopilot

[01:24:57](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=5097s) Provisioning packages

[01:26:54](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=5214s) Custom WinRE

[01:29:59](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=5399s) Demo - Putting it all together (Deep dive)

[01:32:06](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=5526s) Downloading Lenovo 500w drivers

[01:33:28](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=5608s) Downloading apps via Winget

[01:36:54](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=5814s) Downloading Office, Defender, Edge, OneDrive

[01:38:15](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=5895s) Building the Apps.iso

[01:39:08](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=5948s) Applying Windows to the VHDX

[01:40:16](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=6016s) Downloading and applying cumulative updates

[01:41:44](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=6104s) Building the VM

[01:48:13](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=6493s) Capturing the FFU

[01:53:38](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=6818s) Creating USB drive

[01:58:41](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=7121s) Deploying FFU

[02:11:48](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=7908s) Troubleshooting

[02:14:30](https://www.youtube.com/watch?v=rqXRbgeeKSQ&t=8070s) EDU Endpoint Office Hours
