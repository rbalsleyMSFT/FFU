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

# Getting Started

If you're new to FFU Builder or new to the FFU Builder UI version, check out the [Quick Start Guide](https://rbalsleymsft.github.io/FFU/quickstart.html). 

This will be the fastest way to create your first FFU. There's a new [FFU Builder Quickstart Youtube video](https://youtu.be/38sUc3M5Yls) based on the 2604.1 release.

## Older Youtube Videos

[2602.1 UI Preview Quickstart Video](https://www.youtube.com/watch?v=kOIK5OmDugc) - Original quickstart video without the Fluent UI. 

[2507.1 UI Preview Video](https://www.youtube.com/watch?v=oozG1aVcg9M) - First UI Preview release video. This goes deeper than the quick start video, but is missing some features that have been added since 2507.1 was released.

[2407.2 Video](https://www.youtube.com/watch?v=rqXRbgeeKSQ) - This was the main deep-dive video on FFU Builder (before it had that name). This is a good deep dive into how the BuildFFUVM.ps1 script works, but a lot has changed since that build.
