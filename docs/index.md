---
title: Home
nav_order: 0
next_url: /prerequisites.html
next_label: Prerequisites
---
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

And the best part: it takes **less than two minutes to apply the image**, even with all of these updates added to the media. After setting Windows up and going through Autopilot or a provisioning package, total elapsed time ~10 minutes (depending on what Intune or your device management tool is deploying).

The Full-Flash update (FFU) process can automatically download the latest release of Windows 11, the updates mentioned above, and creates a USB drive that can be used to quickly reimage a machine.

{% include page_nav.html %}
