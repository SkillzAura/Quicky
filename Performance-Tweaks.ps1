If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) 
{	Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit	}

# Disable Memory Compression
Disable-MMAgent -MemoryCompression
# Disable Page Combining
Disable-MMAgent -PageCombining

# SleepStudy (UserNotPresentSession)
foreach ($log in @("SleepStudy", "Kernel-Processor-Power", "UserModePowerService")) {
    wevtutil gl "Microsoft-Windows-$log/Diagnostic" | Select-String "enabled"
}


# BCDEdit

bcdedit /set nx alwaysoff >$null 2>&1
bcdedit /set hypervisorlaunchtype off >$null 2>&1
bcdedit /set disabledynamictick yes >$null 2>&1
bcdedit /set bootux disabled >$null 2>&1

# FSUTIL
fsutil behavior set disable8dot3 1
fsutil behavior set disablelastaccess 1
fsutil behavior set disablecompression 1
fsutil behavior set disableencryption 1
fsutil behavior set quotanotify 10800
fsutil behavior set disabledeletenotify 0

# Disable Write-Cache Buffer Flushing

$keys = reg query "HKLM\SYSTEM\CurrentControlSet\Enum" /f "{4d36e967-e325-11ce-bfc1-08002be10318}" /d /s | Select-String "HKEY"

foreach ($key in $keys) {
    $keyPath = $key.ToString().Trim()
    reg add "$keyPath\Device Parameters\Disk" /v UserWriteCacheSetting /t reg_dword /d 1 /f
    reg add "$keyPath\Device Parameters\Disk" /v CacheIsPowerProtected /t reg_dword /d 1 /f
}

# Disable Devices in Device Manager
pnputil /disable-device "SWD\MSRRAS\MS_PPPOEMINIPORT"
pnputil /disable-device "SWD\MSRRAS\MS_PPTPMINIPORT"
pnputil /disable-device "SWD\MSRRAS\MS_AGILEVPNMINIPORT"
pnputil /disable-device "SWD\MSRRAS\MS_NDISWANBH"
pnputil /disable-device "SWD\MSRRAS\MS_NDISWANIP"
pnputil /disable-device "SWD\MSRRAS\MS_SSTPMINIPORT"
pnputil /disable-device "SWD\MSRRAS\MS_NDISWANIPV6"
pnputil /disable-device "SWD\MSRRAS\MS_L2TPMINIPORT"
pnputil /disable-device "ROOT\KDNIC\0000"
pnputil /remove-device "ROOT\KDNIC\0000"
pnputil /disable-device "SWD\MMDEVAPI\MICROSOFTGSWAVETABLESYNTH"
pnputil /disable-device "ROOT\MEDIA\0000"
pnputil /disable-device "ROOT\COMPOSITEBUS\0000"
pnputil /disable-device "PCI\VEN_10DE&DEV_10F9&SUBSYS_868E1043&REV_A1\4&3622C94C&0&0119"
pnputil /disable-device "ROOT\VDRVROOT\0000"
pnputil /disable-device "ROOT\NDISVIRTUALBUS\0000"
pnputil /disable-device "ROOT\RDPBUS\0000"
pnputil /disable-device "ROOT\UMBUS\0000"
pnputil /disable-device "SWD\PRINTENUM\PRINTQUEUES"
pnputil /disable-device "SWD\PRINTENUM\{E70E9471-8340-42BE-AC0A-A20FA6D23978}"
pnputil /disable-device "ACPI\PNP0501\0"
pnputil /disable-device "PCI\VEN_1022&DEV_1486&SUBSYS_7C561462&REV_00\4&4BC21C8&0&0141"
# Disable Bright Computech
pnputil /disable-device "USB\VID_1462&PID_7C56\A02020051102"

# Disable Mitigations
C:\Windows\Setup\Scripts\files\MinSudo --NoLogo --TrustedInstaller --Privileged Powershell Rename-Item "C:\Windows\System32\mcupdate_GenuineIntel.dll" "mcupdate_GenuineIntel.dlll" -Force
C:\Windows\Setup\Scripts\files\MinSudo --NoLogo --TrustedInstaller --Privileged Powershell Rename-Item "C:\Windows\System32\mcupdate_AuthenticAMD.dll" "mcupdate_AuthenticAMD.dlll" -Force

Stop-Process -Name "backgroundTaskHost" -Force -ErrorAction SilentlyContinue
C:\Windows\Setup\Scripts\files\MinSudo --NoLogo --TrustedInstaller --Privileged Powershell Rename-Item "C:\Windows\System32\backgroundTaskHost.exe" "backgroundTaskHost.exee" -Force

# Set QoS Policy For Games
New-NetQosPolicy -Name "Valorant" -AppPathNameMatchCondition "VALORANT-Win64-Shipping.exe" -DSCPAction 46
New-NetQosPolicy -Name "Kovaaks" -AppPathNameMatchCondition "FPSAimTrainer-Win64-Shipping.exe" -DSCPAction 46
New-NetQosPolicy -Name "GTAEnhanced" -AppPathNameMatchCondition "GTA5_Enhanced.exe" -DSCPAction 46
New-NetQosPolicy -Name "CS2" -AppPathNameMatchCondition "cs2.exe" -DSCPAction 46
New-NetQosPolicy -Name "ApexLegends" -AppPathNameMatchCondition "r5apex.exe" -DSCPAction 46
New-NetQosPolicy -Name "Fortnite" -AppPathNameMatchCondition "FortniteClient-Win64-Shipping.exe" -DSCPAction 46
New-NetQosPolicy -Name "ForzaHorizon5" -AppPathNameMatchCondition "ForzaHorizon5.exe" -DSCPAction 46
New-NetQosPolicy -Name "MarvelRivals" -AppPathNameMatchCondition "Marvel-Win64-Shipping.exe" -DSCPAction 46
New-NetQosPolicy -Name "Battlefield2042" -AppPathNameMatchCondition "bf2042.exe" -DSCPAction 46
New-NetQosPolicy -Name "CallOfDuty" -AppPathNameMatchCondition "cod.exe" -DSCPAction 46
New-NetQosPolicy -Name "Overwatch" -AppPathNameMatchCondition "Overwatch.exe" -DSCPAction 46
New-NetQosPolicy -Name "java" -AppPathNameMatchCondition "java.exe" -DSCPAction 46
New-NetQosPolicy -Name "javaw" -AppPathNameMatchCondition "javaw.exe" -DSCPAction 46
New-NetQosPolicy -Name "TheFinals" -AppPathNameMatchCondition "Discovery.exe" -DSCPAction 46
New-NetQosPolicy -Name "R6Siege" -AppPathNameMatchCondition "RainbowSix.exe" -DSCPAction 46
New-NetQosPolicy -Name "osu" -AppPathNameMatchCondition "osu!.exe" -DSCPAction 46

# Disable Extra ETS
$etsList = @(
    "NTFSLog",
    "WiFiDriverIHVSession",
    "WiFiDriverSession",
    "WiFiSession",
    "SleepStudyTraceSession",
    "1DSListener",
    "MpWppTracing",
    "NVIDIA-NVTOPPS-NoCat",
    "NVIDIA-NVTOPPS-Filter",
    "Circular Kernel Context Logger",
    "DiagLog",
    "LwtNetLog",
    "Microsoft-Windows-Rdp-Graphics-RdpIdd-Trace",
    "NetCore",
    "RadioMgr",
    "ReFSLog",
    "WdiContextLog",
    "ShadowPlay"
)

foreach ($session in $etsList) {
    & logman stop $session -ets
}

# Disable Gamebar Presence Writer
C:\Windows\Setup\Scripts\files\MinSudo --NoLogo --TrustedInstaller --Privileged Powershell reg add "HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter" /v ActivationType /t REG_DWORD /d 0 /f

New-Item -Path "$env:TEMP\Performance-Tweaks.status" -ItemType File -Force
