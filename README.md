# Quicky ⚡

**Fast PC Optimizer for Gaming / LAN Tournaments**

Quicky applies a curated set of Windows performance tweaks in seconds — no reinstall, no reset required.
Ideal for quickly preparing a machine at a LAN event or tournament.

---

## What it does

| Area | Tweak |
|------|-------|
| **Power** | Activates the *High Performance* power plan; disables USB selective suspend |
| **Visual Effects** | Switches to *Adjust for best performance* mode; disables animations |
| **Game Mode** | Enables Windows Game Mode and Hardware-Accelerated GPU Scheduling |
| **Game DVR** | Disables background Xbox Game Bar capture overhead |
| **Network** | Disables Nagle's algorithm (TCP low-latency); sets Games profile priority |
| **Services** | Stops & disables telemetry, Search indexer, Superfetch, Xbox services |
| **Notifications** | Enables Focus Assist (alarms only); suppresses toast notifications |
| **Windows Update** | Pauses automatic updates for the current session |
| **Timer Resolution** | Requests finest multimedia timer resolution (≈0.5 ms) |
| **Temp Files** | Clears `%TEMP%`, `%TMP%`, `C:\Windows\Temp`, and Prefetch |

All changes are registry/service tweaks — **nothing is wiped or uninstalled**.

---

## Usage

Open **PowerShell as Administrator** and paste:

```powershell
iex "& { $(iwr -useb https://raw.githubusercontent.com/SkillzAura/Quicky/main/Quicky.ps1) }"
```

> **Security note:** Before running any remote script you should review its source code first.
> You can inspect `Quicky.ps1` in this repository before executing it.
> The one-liner above fetches the script directly from the `main` branch of this repo.

A restart is recommended after the script finishes so that all changes take full effect.

---

## Requirements

* Windows 10 or Windows 11
* PowerShell 5.1+ (built-in on all modern Windows versions)
* **Administrator** privileges (the script will refuse to run without them)

---

## License

[MIT](LICENSE) — free to use, modify, and distribute.
