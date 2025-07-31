# Using Full Flash Update (FFU) files to speed up Windows deployment

What if you could have a Windows image (Windows 10/11/Server/LTSC) that has:

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

And the best part: **it takes less than two minutes** to apply the image, even with all of these updates added to the media. After setting Windows up and going through Autopilot or a provisioning package, total elapsed time ~10 minutes (depending on what Intune or your device management tool is deploying).

The Full-Flash update (FFU) process can automatically download the latest release of Windows 11, the updates mentioned above, and creates a USB drive that can be used to quickly reimage a machine.

# Updates

2507.1 has been released to preview! This is a major update that brings a new user interface to preview.

Docs are coming, but will take a bit to write them. The youtube video is a must watch for a complete demo on how to use the UI and the changes made to apps (InstallAppsAndSysprep.cmd is gone) and drivers. I'll be recording a more formalized deep dive with slides that go a bit deeper into how things work, but the UI walkthrough should get most people going.

# Getting Started

- Download the latest [release](https://github.com/rbalsleyMSFT/FFU/releases)
- Extract the FFUDevelopment folder from the ZIP file (recommend to C:\FFUDevelopment)
- Watch the Youtube video (updated docs for the UI coming soon)

## YouTube Detailed Walkthrough

Here's a detailed overview of the new UI process. 

[![Reimage Windows Fast with FFU Builder 2507.1 Preview](https://img.youtube.com/vi/oozG1aVcg9M/maxresdefault.jpg)](https://youtu.be/oozG1aVcg9M "Reimage Windows Fast with FFU Builder 2507.1 Preview")

Chapters:

[00:00](https://www.youtube.com/watch?v=oozG1aVcg9M&t=0s) Begin

[01:07](https://www.youtube.com/watch?v=oozG1aVcg9M&t=67s) Prereqs

[06:32](https://www.youtube.com/watch?v=oozG1aVcg9M&t=392s) Demo Begins

[07:16](https://www.youtube.com/watch?v=oozG1aVcg9M&t=436s) Running the BuildFFUVM_UI.ps1 script

[08:15](https://www.youtube.com/watch?v=oozG1aVcg9M&t=495s) UI Overview

[10:13](https://www.youtube.com/watch?v=oozG1aVcg9M&t=613s) Hyper-V Settings

[16:04](https://www.youtube.com/watch?v=oozG1aVcg9M&t=964s) Windows Settings

[22:35](https://www.youtube.com/watch?v=oozG1aVcg9M&t=1355s) Updates

[24:49](https://www.youtube.com/watch?v=oozG1aVcg9M&t=1489s) Applications

[29:39](https://www.youtube.com/watch?v=oozG1aVcg9M&t=1779s) Install Winget Applications

[45:29](https://www.youtube.com/watch?v=oozG1aVcg9M&t=2729s) Bring Your Own Applications

[54:14](https://www.youtube.com/watch?v=oozG1aVcg9M&t=3254s) Apps Script Variables

[57:43](https://www.youtube.com/watch?v=oozG1aVcg9M&t=3463s) M365 Apps/Office

[59:01](https://www.youtube.com/watch?v=oozG1aVcg9M&t=3541s) Drivers

[01:01:22](https://www.youtube.com/watch?v=oozG1aVcg9M&t=3682s) Drivers.json example

[01:02:07](https://www.youtube.com/watch?v=oozG1aVcg9M&t=3727s) DriverMapping.json explanation

[01:06:08](https://www.youtube.com/watch?v=oozG1aVcg9M&t=3968s) Driver WIM Compression

[01:10:50](https://www.youtube.com/watch?v=oozG1aVcg9M&t=4250s) Build

[01:12:41](https://www.youtube.com/watch?v=oozG1aVcg9M&t=4361s) Build USB Drive

[01:20:07](https://www.youtube.com/watch?v=oozG1aVcg9M&t=4807s) Monitor

[01:20:32](https://www.youtube.com/watch?v=oozG1aVcg9M&t=4832s) Setting up the Demo Build

[01:24:10](https://www.youtube.com/watch?v=oozG1aVcg9M&t=5050s) Save/Load Config Files

[01:25:11](https://www.youtube.com/watch?v=oozG1aVcg9M&t=5111s) Kicking off the Demo Build/Going over the monitor tab

[01:32:26](https://www.youtube.com/watch?v=oozG1aVcg9M&t=5546s) Demoing the new FFU Builder Orchestrator

[01:35:25](https://www.youtube.com/watch?v=oozG1aVcg9M&t=5725s) New captureffu.ps1 console output

[01:42:29](https://www.youtube.com/watch?v=oozG1aVcg9M&t=6149s) Demo Build Complete

[01:42:42](https://www.youtube.com/watch?v=oozG1aVcg9M&t=6162s) How to configure a VM to test your newly built FFU

[01:48:58](https://www.youtube.com/watch?v=oozG1aVcg9M&t=6538s) The moment of truth: What does the new deployment experience look like?

[01:53:13](https://www.youtube.com/watch?v=oozG1aVcg9M&t=6793s) How to bypass OOBE using a provisioning package

[01:55:49](https://www.youtube.com/watch?v=oozG1aVcg9M&t=6949s) Preview Focus Areas

[02:04:04](https://www.youtube.com/watch?v=oozG1aVcg9M&t=7444s) Known Issues/Things to fix before GA

[02:05:38](https://www.youtube.com/watch?v=oozG1aVcg9M&t=7538s) Providing Feedback

[02:06:43](https://www.youtube.com/watch?v=oozG1aVcg9M&t=7603s) Thank you
