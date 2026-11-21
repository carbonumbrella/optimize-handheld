# CHANGELOG

## 2026-11-22 - 1.2.0: BitLocker / Device Encryption management

- Added dedicated BitLocker mode (`-Mode BitLocker`) and interactive menu option 6 in `Optimize-Handheld.cmd` to inspect encryption status on drive C: and disable BitLocker / device encryption.
- Disabling BitLocker eliminates continuous background AES encryption overhead, lowering CPU usage and reducing storage I/O latency during handheld gaming.
- Added inventory status reporting for BitLocker on drive C: in audit mode.

## 2026-11-19 - 1.1.0: Power (S4 Hibernation), Memory (16 GB Pagefile), Display (Maintain Aspect Ratio)

- Added Power category to Standard tier: configures full S4 hibernation, sets standby idle timeout to 0 (disabling Modern Standby S0 sleep), sets hibernation idle timeouts to 10m on DC and 60m on AC, remaps power and sleep buttons to hibernate, disables wake timers, unhides power settings in GUI, and disables Fast Startup (HiberbootEnabled = 0).
- Added Memory category to Standard tier: disables Windows AutomaticManagedPagefile, establishes a static 16 GB pagefile (16384 MB min and max), and disables ClearPageFileAtShutdown to eliminate micro-stuttering and memory exhaustion in AAA titles.
- Added Display category to Standard tier: automates GPU display scaling to Maintain Aspect Ratio (DISPLAYCONFIG_SCALING_ASPECTRATIOCENTEREDMAX via Windows CCD API) so non-native resolutions (e.g., 720p/800p) preserve aspect ratio without geometry distortion.
- Added Undo support for Power and Memory categories in state file.

## 2026-11-02 - 1.0.3: OneDrive block moved to Full

- `DisableFileSyncNGSC` is now in the new Full-tier category PoliciesExtra: it stops sync for anyone who uses OneDrive,
  and Standard must be safe for anyone. This replaces the 1.0.2 decision to keep it in Standard.
- A machine tuned earlier keeps the block until it is lifted by hand or by Undo; a Standard audit no longer reports it.

## 2026-11-02 - 1.0.2: savings check

- New menu item and `-Mode Savings`, no UAC. Apply saves `baseline-<date>.json` after the confirmation, before any change.
- The comparison uses the oldest Apply, so a later Full run still counts from the original state. Apply logs of older
  versions serve as a baseline, since that is the only record on machines already tuned; they hold only the top 20.
- The total RAM difference depends on open programs and uptime, so the list of processes gone is shown next to it.
- OneDrive stays in Standard (user's decision). The README now says the policy blocks sync and how to lift it: Store
  cannot help, since the app is not removed.

## 2026-11-02 - Field test on a Claw 8 EX AI+ (Arc G3 Extreme, 1.0.0, Standard)

- First real run of the registry, service, capability and feature steps: no failures, and the audit after the reboot
  shows every Standard item in place (the only WOULD lines are Full-tier items). Undo is still untested on real data.
- Standard is enough there: with 31.5 GB of RAM, Full would add about 300 MB and take audio services and small apps.
- Open: DisableFileSyncNGSC blocks OneDrive sync, while the README only mentions auto-install.

## 2026-11-02 - 1.0.1: confirmation accepts yes in any case

- A run on a Claw 8 EX AI+ was cancelled at the prompt with no explanation, and the check was case-sensitive. The prompt
  now accepts yes in any case and on the Russian layout, since it guards against accidents only, and a cancel logs the
  answer and says nothing changed.
- The "never changed" log section matched MSTeams through the Steam filter, though Standard removes Teams.

## 2026-11-01 - First version

- Built from the Claw 8 AI+ ledger (WinMCPHuawei\BootCD\SYSTEM-CHANGES.md). Personal or device-only items are left
  out on purpose: WinRM and RemoteAdmin, GPU memory, ICC profile, BIOS, the local AI stack, update pin, auto-rotation.
- Allow-list only: exact package names plus the single `WindowsWorkload.*` prefix.
- Two levels: Standard is safe for anyone; Full equals the reference Claw. WMIC moved to Full because vendor
  installers can call it. Quick Assist and media apps moved to Full because people use them.
- Security settings (Defender, VBS/HVCI) are not touched: never changed on the reference Claw, and they trade safety.
- The search web-content policy is left out: it freed no memory on the reference Claw.
- Per-user settings go to the owner of explorer.exe, since an elevated window can run under another admin.
