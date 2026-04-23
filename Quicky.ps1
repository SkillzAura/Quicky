#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Quicky - Fast PC Optimizer for Gaming / LAN Tournaments
.DESCRIPTION
    Applies performance-focused Windows settings without resetting the PC.
    Optimizes power plan, visual effects, services, network stack, and more
    so the machine is ready for competitive play in seconds.
.NOTES
    Run once from an elevated PowerShell session:
        iex "& { $(iwr -useb https://raw.githubusercontent.com/SkillzAura/Quicky/main/Quicky.ps1) }"
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Helpers ─────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host "[Quicky] $Message" -ForegroundColor Cyan
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = 'DWord'
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

# ─── 1. High-Performance Power Plan ─────────────────────────────────────────

Write-Step "Setting High Performance power plan..."
$highPerf = powercfg -list | Select-String 'High performance'
if ($highPerf) {
    $guid = ($highPerf -split '\s+')[3]
    powercfg -setactive $guid | Out-Null
} else {
    powercfg -setactive SCHEME_MIN | Out-Null
}
# Disable USB selective suspend
powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
powercfg -setactive SCHEME_CURRENT | Out-Null

# ─── 2. Visual Effects – Performance Mode ────────────────────────────────────

Write-Step "Optimizing visual effects for performance..."
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' `
    -Name 'VisualFXSetting' -Value 2

$perfKey = 'HKCU:\Control Panel\Desktop'
Set-RegistryValue -Path $perfKey -Name 'DragFullWindows'     -Value '0' -Type String
Set-RegistryValue -Path $perfKey -Name 'MenuShowDelay'        -Value '0' -Type String
Set-RegistryValue -Path $perfKey -Name 'UserPreferencesMask' `
    -Value ([byte[]](0x90,0x12,0x01,0x80)) -Type Binary

Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' `
    -Name 'MinAnimate' -Value '0' -Type String

Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
    -Name 'TaskbarAnimations' -Value 0
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\DWM' `
    -Name 'EnableAeroPeek'   -Value 0
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\DWM' `
    -Name 'AlwaysHibernateThumbnails' -Value 0

# ─── 3. Windows Game Mode & Hardware-Accelerated GPU Scheduling ──────────────

Write-Step "Enabling Game Mode and GPU scheduling..."
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\GameBar' `
    -Name 'AutoGameModeEnabled' -Value 1
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\GameBar' `
    -Name 'AllowAutoGameMode'   -Value 1
Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' `
    -Name 'HwSchMode' -Value 2    # Hardware-accelerated GPU scheduling

# ─── 4. Disable Xbox Game Bar Overhead ───────────────────────────────────────

Write-Step "Minimising Xbox Game Bar overhead..."
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' `
    -Name 'AppCaptureEnabled'  -Value 0
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' `
    -Name 'AllowGameDVR'       -Value 0

# ─── 5. Network Optimizations ────────────────────────────────────────────────

Write-Step "Tuning network stack for low latency..."
# Disable Nagle's algorithm for lower TCP latency
$tcpKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
Get-ChildItem $tcpKey | ForEach-Object {
    Set-RegistryValue -Path $_.PSPath -Name 'TcpAckFrequency' -Value 1
    Set-RegistryValue -Path $_.PSPath -Name 'TCPNoDelay'      -Value 1
}
# Disable Network Throttling Index (allows full NIC bandwidth for games)
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' `
    -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF
# Prioritize Games in the system profile
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
    -Name 'Affinity'          -Value 0
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
    -Name 'Background Only'   -Value 'False' -Type String
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
    -Name 'Clock Rate'        -Value 10000
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
    -Name 'GPU Priority'      -Value 8
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
    -Name 'Priority'          -Value 6
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
    -Name 'Scheduling Category' -Value 'High' -Type String
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' `
    -Name 'SFIO Priority'     -Value 'High' -Type String

# ─── 6. Disable Unnecessary Background Services ──────────────────────────────

Write-Step "Disabling unnecessary background services..."
$servicesToDisable = @(
    'DiagTrack',           # Connected User Experiences and Telemetry
    'SysMain',             # Superfetch (can cause stutters on SSDs)
    'WSearch',             # Windows Search indexer
    'TabletInputService',  # Touch Keyboard and Handwriting
    'Fax',                 # Fax service
    'XblAuthManager',      # Xbox Live Auth (background)
    'XblGameSave',         # Xbox Live Game Save
    'XboxNetApiSvc'        # Xbox Live Networking
)
foreach ($svc in $servicesToDisable) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Stop-Service  -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service   -Name $svc -StartupType Disabled
        }
    } catch {
        # Service may not exist on all Windows editions — skip silently
    }
}

# ─── 7. Notifications & Focus Assist ─────────────────────────────────────────

Write-Step "Enabling Focus Assist / suppressing notifications..."
# Focus Assist: alarms only (value 2).
# The internal CloudStore key uses a non-deterministic sub-key, so enumerate it.
$qhBase = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount'
Get-ChildItem -Path $qhBase -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -eq 'Current' -and $_.PSPath -match 'quiethourssettings' } |
    ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name 'Data' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    }

# Suppress action-center notification badges
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' `
    -Name 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' -Value 0
Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' `
    -Name 'NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK' -Value 0

# ─── 8. Disable Automatic Windows Updates During Session ─────────────────────

Write-Step "Pausing Windows Update (active hours / AU policy)..."
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' `
    -Name 'NoAutoUpdate' -Value 1

# ─── 9. Timer Resolution ─────────────────────────────────────────────────────

Write-Step "Requesting high-resolution system timer (0.5 ms)..."
# Instruct Windows to keep the multimedia timer at its finest resolution
Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' `
    -Name 'SystemResponsiveness' -Value 0

# ─── 10. Clean Temporary Files ───────────────────────────────────────────────

Write-Step "Removing temporary files to free disk space..."
$tempPaths = @(
    $env:TEMP,
    $env:TMP,
    "$env:SystemRoot\Temp",
    "$env:SystemRoot\Prefetch"
)
foreach ($path in $tempPaths) {
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ─── Done ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║         Quicky optimization complete!            ║" -ForegroundColor Green
Write-Host "║  Your PC is now tuned for tournament play.       ║" -ForegroundColor Green
Write-Host "║  A restart is recommended for all changes to     ║" -ForegroundColor Green
Write-Host "║  take full effect.                               ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
