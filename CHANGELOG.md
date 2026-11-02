# CHANGELOG

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
