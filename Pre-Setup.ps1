# Pre-Setup.ps1
# Prepares the OS by disabling UAC, Driver Updates, and Vulnerable Blocklists before main tuning
# Automatically restarts the PC upon completion

# =========================
# Admin Elevation Check
# =========================
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    exit
}

$ErrorActionPreference = "Continue"

# =========================
# Registry Helper Function
# =========================
# Safely creates the path if it doesn't exist, then applies the key
function Set-RegKey {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force | Out-Null
}

Write-Host "Applying Pre-Setup Registry Tweaks..." -ForegroundColor Cyan

# =========================
# Disable UAC
# =========================
Set-RegKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 0

# =========================
# Disable Driver Installation via Windows Update
# =========================
Set-RegKey -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ExcludeWUDriversInQualityUpdate" -Value 1
Set-RegKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "SearchOrderConfig" -Value 0
Set-RegKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -Value 1
Set-RegKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Value 1
Set-RegKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 0
Set-RegKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Value 1

# =========================
# CMD As Default Host
# =========================
Set-RegKey -Path "HKCU:\Console\%%Startup" -Name "DelegationConsole" -Value "{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}" -Type String
Set-RegKey -Path "HKCU:\Console\%%Startup" -Name "DelegationTerminal" -Value "{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}" -Type String

# =========================
# Disable Vulnerable Driver Blocklist
# =========================
Set-RegKey -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config" -Name "VulnerableDriverBlocklistEnable" -Value 0

# =========================
# Restart Sequence
# =========================
Write-Host ""
Write-Host "Pre-Setup Complete!" -ForegroundColor Green
Write-Host "Restarting computer in 5 seconds to lock in UAC and Driver settings..." -ForegroundColor Yellow

Restart-Computer -Force
