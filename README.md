[English](README.md) | [Русский](README_RU.md)

> **[Download Latest Release (ZIP Asset)](https://github.com/carbonumbrella/optimize-handheld/releases/latest/download/HandheldTune.zip)** | **[Release Notes & Files](https://github.com/carbonumbrella/optimize-handheld/releases/latest)**

# Optimize-Handheld

[![release](https://img.shields.io/github/v/release/carbonumbrella/optimize-handheld?include_prereleases&label=release)](https://github.com/carbonumbrella/optimize-handheld/releases)

Windows 10/11 debloat, memory optimization, and tuning script for handheld gaming PCs: designed primarily for MSI Claw (Claw 8 AI+, Claw 7 AI+, Claw A1M), but also compatible with other handheld devices. Built based on optimizations verified on the reference Claw 8 AI+.

## How to Run

Extract the archive to any folder and run `Optimize-Handheld.cmd` as Administrator (or right-click `Optimize-Handheld.ps1` -> Run with PowerShell):

1. **Audit:** Inspects the system and changes nothing. Start here.
2. **Apply Standard:** Recommended safe configuration.
3. **Apply Full:** Standard tier plus optional vendor services, WMIC, and legacy apps.
4. **Undo:** Roll back the latest applied state.
5. **Check savings:** Compares RAM and disk space freed compared to baseline (requires reboot).
6. **Disable BitLocker:** Checks encryption status and decrypts system drive C: to reduce background SSD and CPU load during gaming.

The script requests Administrator privileges automatically. Before applying changes, it prompts for confirmation by typing `YES` (case and keyboard layout tolerant: `yes`, `YES`, and `нуы` are accepted; any other input aborts) and attempts to create a Windows System Restore point. After applying, restart the device and run Audit again to verify.

## What It Changes

| Category | Tier | Description |
|---|---|---|
| Apps | Standard | Removes Clipchamp, Cortana, Bing News, Bing Weather, Bing Search, Get Help, Tips, Office Hub, Solitaire, new Outlook, People, Power Automate, To Do, Dev Home, Mail and Calendar, Feedback Hub, Teams |
| AI | Standard | Removes Copilot app and on-device Windows AI packages (Recall, Click to Do), disables them via Group Policy, prevents Chrome from background downloading Gemini Nano |
| Policies | Standard | Disables app suggestions, advertising ID, Bing web search in Start, widgets |
| Telemetry | Standard | Disables diagnostic telemetry, DiagTrack service, background data collection tasks |
| Capabilities | Standard | Removes Steps Recorder, Internet Explorer, WordPad, Math Recognizer, PowerShell ISE, legacy wallpapers, PowerShell 2.0, Work Folders |
| UserTweaks | Standard | Disables advertising ID, Start menu recommendations, taskbar widgets button |
| RamTrim | Standard | Disables Edge startup boost/background mode and Cross-device Resume |
| LoginKeyboard | Standard | Enables touch keyboard on the Windows lock screen (disables ARSO policy) |
| Power | Standard | Full S4 hibernation: disables S0 Modern Standby (timeout 0), sets auto-hibernation after 10 min on battery and 60 min on AC, maps power/sleep buttons to hibernate, disables wake timers and Fast Startup |
| Memory | Standard | Static 16 GB pagefile (16384 MB), disables automatic dynamic pagefile resizing and pagefile wiping on shutdown |
| Display | Standard | GPU hardware display scaling set to Maintain Aspect Ratio (DISPLAYCONFIG_SCALING_ASPECTRATIOCENTEREDMAX) for lower resolutions without distortion |
| AppsExtra | Full | Removes Maps, Phone Link, CrossDevice, WebExperience, Media Player, Movies and TV, Clock, Voice Recorder, Sticky Notes, Quick Assist |
| PoliciesExtra | Full | Blocks OneDrive synchronization via policy (OneDrive app stays, but background sync stops) |
| TelemetryExtra | Full | Disables Compatibility Appraiser and Disk Diagnostics tasks |
| CapabilitiesExtra | Full | Removes WMIC and legacy Windows Media Player (some vendor installers require WMIC) |
| RamTrimVendor | Full | Disables startup of Logitech Options+ updater service and Intel Graphics tray autostart. Intel DSA and DTS/intelliGo audio services are now optional categories and left enabled by default |
| VendorDSA | Optional | Disables Intel Driver & Support Assistant background services (prompted in Full mode or via -DisableDSA) |
| VendorAudio | Optional | Disables DTS and intelliGo audio effect background services (prompted in Full mode or via -DisableAudioEffects). Sound profile will change! |

**Protected Services (Never Touched):** Xbox, Game Bar, Gaming Services, Microsoft Store, winget, Edge, Windows Terminal, Calculator, Photos, Camera, Paint, Snipping Tool, Notepad, Family Safety, Windows Update, Windows Defender, hardware drivers, and vendor utilities (MSI Center M, ClawTweaks, HidHide, Armoury Crate, Legion Space). Only explicitly listed items are modified.

## Manual Steps

**ClawTweaks requires Memory Integrity (HVCI) disabled.** The script does not modify this kernel security setting. If you use ClawTweaks, disable it manually: Windows Security -> Device security -> Core isolation details -> Memory integrity (Off), then restart.

## Disabling BitLocker (Device Encryption)

Windows 11 enables automatic BitLocker device encryption on many portable PCs out of the box. This places a constant background AES encryption overhead on CPU cores and the SSD controller during game asset streaming.

Menu option **6 (Disable BitLocker)** checks protection status on drive C: and initiates background decryption. Decryption runs transparently in the background without requiring a system reboot.

## Savings Verification

The script records baseline memory and disk usage upon Apply. Selecting option **5 (Check savings)** compares current usage with the baseline without requiring Administrator privileges:

1. Apply the script and reboot the device.
2. Allow Windows to finish background loading (2 to 3 minutes).
3. Run `Optimize-Handheld.cmd` and select option **5**.

## Command Line Usage

```powershell
# Standard apply
.\Optimize-Handheld.ps1 -Mode Apply -Level Standard

# Custom category selection
.\Optimize-Handheld.ps1 -Mode Apply -Level Standard -Skip Capabilities,AI

# Rollback
.\Optimize-Handheld.ps1 -Mode Undo
```

## Logs and Rollback

Every execution writes a timestamped log to `logs\<mode>-<date>.log`. Previous registry and service states are recorded in `logs\state-<date>.json`. The **Undo** action restores registry settings, services, scheduled tasks, and Windows capabilities. Uninstalled Store apps can be reinstalled from the Microsoft Store.

## License

MIT License, see [LICENSE](LICENSE).
