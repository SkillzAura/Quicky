# Quicky-OneShot.ps1
# Single-file quick settings applier for LAN tournament use
# Built from your source scripts with requested skips/modifications

# =========================
# Admin Elevation
# =========================
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    exit
}

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# =========================
# Paths and Status
# =========================
$FilesRoot = "C:\Windows\Setup\Scripts\files"
$SoftRoot  = Join-Path $FilesRoot "Softwares"
$StatusOut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Quicky-Status.txt"
$stepsOk   = New-Object System.Collections.Generic.List[string]
$stepsFail = New-Object System.Collections.Generic.List[string]
$psLnk     = 'C:\Windows\System32\WindowsPowerShell\v1.0\PS.lnk'

function Add-OK([string]$s){ $stepsOk.Add($s) }
function Add-Fail([string]$s){ $stepsFail.Add($s) }

function Run-Step {
    param([string]$Name,[scriptblock]$Action)
    try { & $Action; Add-OK $Name } catch { Add-Fail "$Name :: $($_.Exception.Message)" }
}

# =========================
# Create Minimized Powershell Shortcut
# =========================
Run-Step "Create Minimized Powershell Shortcut (PS.lnk)" {
    $WshShell = New-Object -ComObject WScript.Shell
    $shortcut = $WshShell.CreateShortcut($psLnk)
    $shortcut.TargetPath       = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.WorkingDirectory = "$env:HOMEDRIVE$env:HOMEPATH"
    $shortcut.WindowStyle      = 7
    $shortcut.Save()
}

# =========================
# Ensure base folder + exclusions + required binaries
# =========================
Run-Step "Create files root + Defender exclusion" {
    if (!(Test-Path $FilesRoot)) { New-Item -ItemType Directory -Path $FilesRoot -Force | Out-Null }
    Add-MpPreference -ExclusionPath $FilesRoot -ErrorAction SilentlyContinue
}

Run-Step "Download dependencies, scripts, and binaries to files root" {
    $repoBase = "https://raw.githubusercontent.com/SkillzAura/Quicky/main"
    
    $filesToDownload = @(
        "Registry.reg",
        "ValleyOfDoom.ps1",
        "Remove-Edge.ps1",
        "Power-Plan.ps1",
        "disable-scheduled-tasks.ps1",
        "Afterburner.ps1",
        "Sound.ps1",
        "Set-Windows-Sens.ps1",
        "Brave.ps1",
        "Remove-Bloatware.ps1",
        "Uninstall-OneDrive.ps1",
        "disable-process-mitigations.bat"
    )

    foreach ($file in $filesToDownload) {
        Invoke-WebRequest -Uri "$repoBase/$file" -OutFile (Join-Path $FilesRoot $file) -UseBasicParsing
    }

    Invoke-WebRequest -Uri "https://github.com/SkillzAura/Quicky/releases/download/Power/Power.exe" -OutFile (Join-Path $FilesRoot "Power.exe") -UseBasicParsing
    Invoke-WebRequest -Uri "https://github.com/SkillzAura/Quicky/releases/download/Minsudo/MinSudo.exe" -OutFile (Join-Path $FilesRoot "MinSudo.exe") -UseBasicParsing
}

# =========================
# Close apps first (requested)
# =========================
Run-Step "Force-close blocking apps/processes" {
    $kill = @("msedge","msedgewebview2","MicrosoftEdgeUpdate","RTSSSetup","RTSS","MSIAfterburner")
    foreach($p in $kill){ Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
}

# =========================
# Windows Cleanup: Parallel Background Execution
# =========================
Run-Step "Run cleanup scripts in parallel (Bloat, OneDrive)" {
    $cleanupScripts = @("Remove-Bloatware.ps1", "Uninstall-OneDrive.ps1")
    foreach ($script in $cleanupScripts) {
        $scriptPath = Join-Path $FilesRoot $script
        if (Test-Path $scriptPath) {
            Start-Process -FilePath $psLnk -ArgumentList "-windowstyle hidden -ExecutionPolicy Bypass -NoLogo -File `"$scriptPath`""
        } else {
            throw "Missing $script"
        }
    }
}

# =========================
# Services (With Laptop/VM Safety Check)
# =========================
Run-Step "Apply selected services (with msisadrv safety check)" {
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\SysMain"  /v Start /t REG_DWORD /d 4 /f >$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\WSearch"  /v Start /t REG_DWORD /d 4 /f >$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\DusmSvc"  /v Start /t REG_DWORD /d 4 /f >$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\lfsvc"    /v Start /t REG_DWORD /d 4 /f >$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Spooler"  /v Start /t REG_DWORD /d 4 /f >$null
    
    $SystemInfo = Get-WmiObject -Class Win32_ComputerSystem
    $SystemType = $SystemInfo.PCSystemType
    $IsVirtualMachine = $SystemInfo.Manufacturer -match "Microsoft|VMware|VirtualBox" -or $SystemInfo.Model -match "Virtual"

    if (-not $IsVirtualMachine -and $SystemType -ne 2) {
        $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\msisadrv"
        Set-ItemProperty -Path $RegPath -Name "Start" -Value 4 -ErrorAction SilentlyContinue
    }
}

# =========================
# Disable Scheduled Tasks (External minimized)
# =========================
Run-Step "Run disable-scheduled-tasks.ps1 externally" {
    $dst = Join-Path $FilesRoot "disable-scheduled-tasks.ps1"
    if (!(Test-Path $dst)) { throw "Missing disable-scheduled-tasks.ps1" }
    Start-Process -FilePath $psLnk -ArgumentList "-windowstyle hidden -ExecutionPolicy Bypass -NoLogo -File `"$dst`""
}

# =========================
# Registry.reg apply all
# =========================
Run-Step "Apply Registry.reg" {
    $src = Join-Path $FilesRoot "Registry.reg"
    if (!(Test-Path $src)) { throw "Missing Registry.reg in $FilesRoot" }
    reg import "$src" >$null 2>&1
}

# =========================
# Remove-Edge (External minimized)
# =========================
Run-Step "Run Remove-Edge externally" {
    $re = Join-Path $FilesRoot "Remove-Edge.ps1"
    if (!(Test-Path $re)) { throw "Missing Remove-Edge.ps1" }
    Start-Process -FilePath $psLnk -ArgumentList "-windowstyle hidden -ExecutionPolicy Bypass -NoLogo -File `"$re`""
}

# =========================
# Brave Browser Installation
# =========================
Run-Step "Run Brave externally" {
    $brave = Join-Path $FilesRoot "Brave.ps1"
    if (!(Test-Path $brave)) { throw "Missing Brave.ps1" }
    Start-Process -FilePath $psLnk -ArgumentList "-windowstyle hidden -ExecutionPolicy Bypass -NoLogo -File `"$brave`""
}

# =========================
# ValleyOfDoom (External minimized)
# =========================
Run-Step "Run ValleyOfDoom externally" {
    $vod = Join-Path $FilesRoot "ValleyOfDoom.ps1"
    if (!(Test-Path $vod)) { throw "Missing ValleyOfDoom.ps1" }
    Start-Process -FilePath $psLnk -ArgumentList "-windowstyle hidden -ExecutionPolicy Bypass -NoLogo -File `"$vod`""
}

# =========================
# Softwares: Autoruns, GoInterruptPolicy, and DevManView
# =========================
Run-Step "Install Softwares (Autoruns, GoInterruptPolicy, DevManView)" {
    if (!(Test-Path $SoftRoot)) { New-Item -ItemType Directory -Path $SoftRoot -Force | Out-Null }

    # Autoruns
    $autorunsDir = Join-Path $SoftRoot "Autoruns"
    if (!(Test-Path $autorunsDir)) { New-Item -ItemType Directory -Path $autorunsDir -Force | Out-Null }
    $autorunsZip = Join-Path $autorunsDir "Autoruns.zip"
    Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Autoruns.zip" -OutFile $autorunsZip -UseBasicParsing
    Expand-Archive -Path $autorunsZip -DestinationPath $autorunsDir -Force
    Remove-Item $autorunsZip -Force -ErrorAction SilentlyContinue
    reg add "HKEY_CURRENT_USER\Software\Sysinternals\Autoruns" /v "EulaAccepted" /t REG_DWORD /d 1 /f >$null 2>&1

    # GoInterruptPolicy
    $goDir = Join-Path $SoftRoot "GoInterruptPolicy"
    if (!(Test-Path $goDir)) { New-Item -ItemType Directory -Path $goDir -Force | Out-Null }
    $goExe = Join-Path $goDir "GoInterruptPolicy.exe"
    Invoke-WebRequest -Uri "https://github.com/spddl/GoInterruptPolicy/releases/latest/download/GoInterruptPolicy.exe" -OutFile $goExe -UseBasicParsing

    # DevManView
    $folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\DevManView"
    $URL17           = "https://www.nirsoft.net/utils/devmanview-x64.zip"
    $tempZipPath     = "$env:Temp\DevManView.zip"
    $tempExtractPath = "$env:Temp\DevManView"
    $outExePath      = "$folderPath\DevManView.exe"
    $urlShortcutPath = "$folderPath\DevManView.url"

    if (!(Test-Path -Path $folderPath)) {
        $null = New-Item -ItemType Directory -Path $folderPath -Force
    }

    Invoke-WebRequest -Uri $URL17 -OutFile $tempZipPath -UseBasicParsing
    Expand-Archive -Path $tempZipPath -DestinationPath $tempExtractPath -Force
    Move-Item "$tempExtractPath\DevManView.exe" $outExePath -Force
    Remove-Item -Path "$tempExtractPath","$tempZipPath" -Recurse -Force

@"
[InternetShortcut]
URL=$URL17
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

    # Open Autoruns and GoInterruptPolicy
    $autorunsExe = Join-Path $autorunsDir "Autoruns64.exe"
    if (Test-Path $autorunsExe) { Start-Process $autorunsExe -ErrorAction SilentlyContinue }
    if (Test-Path $goExe) { Start-Process $goExe -ErrorAction SilentlyContinue }
}

# =========================
# Sound: External minimized
# =========================
Run-Step "Run Sound externally" {
    $sndScript = Join-Path $FilesRoot "Sound.ps1"
    if (!(Test-Path $sndScript)) { throw "Missing Sound.ps1" }
    Start-Process -FilePath $psLnk -ArgumentList "-windowstyle hidden -ExecutionPolicy Bypass -NoLogo -File `"$sndScript`""
}

# =========================
# Set-Windows-Sens: External minimized
# =========================
Run-Step "Run Set-Windows-Sens externally" {
    $sensScript = Join-Path $FilesRoot "Set-Windows-Sens.ps1"
    if (!(Test-Path $sensScript)) { throw "Missing Set-Windows-Sens.ps1" }
    Start-Process -FilePath $psLnk -ArgumentList "-windowstyle hidden -ExecutionPolicy Bypass -NoLogo -File `"$sensScript`""
}

# =========================
# NVIDIA: NO driver install; only requested functions/settings
# =========================
function Disable-NvidiaTelemetry-And-Cleanup {
    $telemetryTasks = @(
        '*NvDriverUpdateCheckDaily*','*NVIDIA GeForce Experience SelfUpdate*','*NvProfileUpdaterDaily*','*NvProfileUpdaterOnLogon*',
        '*NvTmRep_CrashReport1*','*NvTmRep_CrashReport2*','*NvTmRep_CrashReport3*','*NvTmRep_CrashReport4*','*NvNodeLauncher*'
    )
    foreach ($task in $telemetryTasks) { try { Get-ScheduledTask -TaskName $task | Disable-ScheduledTask -ErrorAction SilentlyContinue } catch {} }

    $paths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\FvSvc",
        "HKLM:\SYSTEM\CurrentControlSet\Services\nvvad_WaveExtensible"
    )
    foreach ($path in $paths) { if (Test-Path $path) { Set-ItemProperty -Path $path -Name Start -Value 4 -Type DWord } }
}

function Enable-Nvidia-MSI-Mode {
    try {
        $display = Get-PnpDevice -Class Display | Where-Object { $_.Status -eq 'OK' -and $_.InstanceId -match 'VEN_10DE' } | Select-Object -First 1
        if ($display) {
            $regPath = "HKLM\SYSTEM\ControlSet001\Enum\$($display.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            reg.exe add $regPath /v MSISupported /t REG_DWORD /d 1 /f >$null
        }
    } catch {}
}

function Create-Nip-File {
    $folder = Join-Path $SoftRoot "nvidiaProfileInspector"
    if (!(Test-Path $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    @'
<?xml version="1.0" encoding="utf-16"?>
<ArrayOfProfile></ArrayOfProfile>
'@ | Out-File -FilePath (Join-Path $folder "Aura.nip") -Encoding UTF8 -Force
}

function Import-NIP-Profile {
    $baseDir = Join-Path $SoftRoot "nvidiaProfileInspector"
    $npiExe = Join-Path $baseDir "nvidiaProfileInspector.exe"
    $nipFile = Join-Path $baseDir "Aura.nip"

    if (!(Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir -Force | Out-Null }

    $zip = Join-Path $baseDir "nvidiaProfileInspector.zip"
    Invoke-WebRequest -Uri "https://github.com/Orbmu2k/nvidiaProfileInspector/releases/latest/download/nvidiaProfileInspector.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $baseDir -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue

    if ((Test-Path $npiExe) -and (Test-Path $nipFile)) {
        cmd /c "`"$npiExe`" `"$nipFile`" -silent /f >nul 2>&1"
    }
}

function Set-Nvidia-Tweaks {
    reg add "HKCU\Software\NVIDIA Corporation\NvTray" /v StartOnLogin /t REG_DWORD /d 0 /f >$null 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak" /v NvCplPhysxAuto /t REG_DWORD /d 0 /f >$null 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\Startup\SendTelemetryData" /ve /t REG_DWORD /d 0 /f >$null 2>&1
    reg add "HKCU\Software\NVIDIA Corporation\Global\GFExperience" /v NotifyNewDisplayUpdates /t REG_DWORD /d 0 /f >$null 2>&1
    reg add "HKCU\Software\NVIDIA Corporation\Global\NvCplApi\Policies" /v ContextUIPolicy /t REG_DWORD /d 0 /f >$null 2>&1
    reg delete "HKLM\Software\Classes\Directory\Background\ShellEx\ContextMenuHandlers\NvCplDesktopContext" /f >$null 2>&1
}

function Set-Nvidia-ClassKey-Tweaks {
    $basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class"
    $displayClassKeys = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).Class -eq "Display"
    }

    foreach ($classKey in $displayClassKeys) {
        for ($i=0; $i -le 99; $i++) {
            $subKey = "{0:D4}" -f $i
            $subKeyPath = Join-Path $classKey.PSPath $subKey
            if (Test-Path $subKeyPath) {
                $props = Get-ItemProperty -Path $subKeyPath -ErrorAction SilentlyContinue
                if ($props.DriverDesc -match "nvidia") {
                    foreach ($kv in @{RMHdcpKeyglobZero=1;RMCtxswLog=0;DisableDynamicPstate=1}.GetEnumerator()) {
                        New-ItemProperty -Path $subKeyPath -Name $kv.Key -PropertyType DWord -Value $kv.Value -Force | Out-Null
                    }
                }
            }
        }
    }
}

Run-Step "Apply NVIDIA settings only (no driver install)" {
    $isNvidia = (Get-WmiObject Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PNPDeviceID) -join ' ' -match 'VEN_10DE'
    if ($isNvidia) {
        Disable-NvidiaTelemetry-And-Cleanup
        Enable-Nvidia-MSI-Mode
        Create-Nip-File
        Import-NIP-Profile
        Set-Nvidia-Tweaks
        Set-Nvidia-ClassKey-Tweaks

        pnputil /disable-device "PCI\VEN_10DE&DEV_1ADA&SUBSYS_868E1043&REV_A1\4&3622C94C&0&0219" >$null 2>&1
        $devman = Join-Path $SoftRoot "DevManView\DevManView.exe"
        if (Test-Path $devman) {
            cmd /c "`"$devman`" /disable `"*Host Controller - %3 (Microsoft);(NVIDIA*`" /use_wildcard" >$null 2>&1
        }
    }
}

# =========================
# Performance-Tweaks with requested list
# =========================
Run-Step "Apply Performance-Tweaks" {
    Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
    Disable-MMAgent -PageCombining -ErrorAction SilentlyContinue

    bcdedit /set nx alwaysoff >$null 2>&1
    bcdedit /set hypervisorlaunchtype off >$null 2>&1
    bcdedit /set disabledynamictick yes >$null 2>&1
    bcdedit /set bootux disabled >$null 2>&1

    fsutil behavior set disable8dot3 1 >$null 2>&1
    fsutil behavior set disablelastaccess 1 >$null 2>&1
    fsutil behavior set disablecompression 1 >$null 2>&1
    fsutil behavior set disableencryption 1 >$null 2>&1
    fsutil behavior set quotanotify 10800 >$null 2>&1
    fsutil behavior set disabledeletenotify 0 >$null 2>&1

    $devices = @(
        "SWD\MSRRAS\MS_PPPOEMINIPORT","SWD\MSRRAS\MS_PPTPMINIPORT","SWD\MSRRAS\MS_AGILEVPNMINIPORT",
        "SWD\MSRRAS\MS_NDISWANBH","SWD\MSRRAS\MS_NDISWANIP","SWD\MSRRAS\MS_SSTPMINIPORT",
        "SWD\MSRRAS\MS_NDISWANIPV6","SWD\MSRRAS\MS_L2TPMINIPORT","ROOT\KDNIC\0000",
        "SWD\MMDEVAPI\MICROSOFTGSWAVETABLESYNTH","ROOT\MEDIA\0000","ROOT\COMPOSITEBUS\0000",
        "PCI\VEN_10DE&DEV_10F9&SUBSYS_868E1043&REV_A1\4&3622C94C&0&0119","ROOT\VDRVROOT\0000",
        "ROOT\NDISVIRTUALBUS\0000","ROOT\RDPBUS\0000","ROOT\UMBUS\0000",
        "SWD\PRINTENUM\PRINTQUEUES","SWD\PRINTENUM\{E70E9471-8340-42BE-AC0A-A20FA6D23978}",
        "ACPI\PNP0501\0","PCI\VEN_1022&DEV_1486&SUBSYS_7C561462&REV_00\4&4BC21C8&0&0141",
        "USB\VID_1462&PID_7C56\A02020051102"
    )
    
    foreach($d in $devices){ pnputil /disable-device "$d" >$null 2>&1 }
    pnputil /remove-device "ROOT\KDNIC\0000" >$null 2>&1

    $games = @(
        @{N="Valorant";E="VALORANT-Win64-Shipping.exe"},
        @{N="Kovaaks";E="FPSAimTrainer-Win64-Shipping.exe"},
        @{N="GTAEnhanced";E="GTA5_Enhanced.exe"},
        @{N="CS2";E="cs2.exe"},
        @{N="ApexLegends";E="r5apex.exe"},
        @{N="Fortnite";E="FortniteClient-Win64-Shipping.exe"},
        @{N="ForzaHorizon5";E="ForzaHorizon5.exe"},
        @{N="MarvelRivals";E="Marvel-Win64-Shipping.exe"},
        @{N="Battlefield2042";E="bf2042.exe"},
        @{N="CallOfDuty";E="cod.exe"},
        @{N="Overwatch";E="Overwatch.exe"},
        @{N="java";E="java.exe"},
        @{N="javaw";E="javaw.exe"},
        @{N="TheFinals";E="Discovery.exe"},
        @{N="R6Siege";E="RainbowSix.exe"},
        @{N="osu";E="osu!.exe"}
    )
    foreach($g in $games){ New-NetQosPolicy -Name $g.N -AppPathNameMatchCondition $g.E -DSCPAction 46 -ErrorAction SilentlyContinue | Out-Null }
}

# =========================
# Power plan: apply all (External minimized)
# =========================
Run-Step "Run Power-Plan externally" {
    $pp = Join-Path $FilesRoot "Power-Plan.ps1"
    if (!(Test-Path $pp)) { throw "Missing Power-Plan.ps1" }
    Start-Process -FilePath $psLnk -ArgumentList "-windowstyle hidden -ExecutionPolicy Bypass -NoLogo -File `"$pp`""
}

# =========================
# disable-process-mitigations.bat as-is using Power.exe wrapper
# =========================
Run-Step "Run disable-process-mitigations.bat via Power.exe" {
    $batSrc = Join-Path $FilesRoot "disable-process-mitigations.bat"
    if (!(Test-Path $batSrc)) { throw "Missing disable-process-mitigations.bat" }

    $power = Join-Path $FilesRoot "Power.exe"
    if (!(Test-Path $power)) { throw "Missing Power.exe" }

    cmd /c "`"$power`" /SW:0 `"$batSrc`""
}

# =========================
# Maintenance.bat Creation
# =========================
Run-Step "Create maintenance.bat and startup shortcut" {
    $mBat = "C:\Windows\maintenance.bat"
    $batContent = @'
@echo off
:: request administrator privileges
DISM >nul 2>&1 || (
    PowerShell Start -Verb RunAs '%0' 2> nul || (
        echo error: right-click on the "%~f0" script and select "Run as administrator"
        pause
    )
    exit /b 1
)

:: cleanup
Rundll32.exe c:\windows\system32\pnpclean.dll,RunDLL_PnpClean /DEVICES /DRIVERS /FILES /MAXCLEAN
exit
'@
    Set-Content -Path $mBat -Value $batContent -Encoding ASCII

    $startupFolder = [Environment]::GetFolderPath('Startup')
    $mBatLink = Join-Path $startupFolder "maintenance.lnk"
    
    $WshShell = New-Object -ComObject WScript.Shell
    $shortcut = $WshShell.CreateShortcut($mBatLink)
    $shortcut.TargetPath = $mBat
    $shortcut.WindowStyle = 7
    $shortcut.Save()
}

# =========================
# Afterburner: External minimized
# =========================
Run-Step "Run Afterburner externally" {
    $abScript = Join-Path $FilesRoot "Afterburner.ps1"
    if (!(Test-Path $abScript)) { throw "Missing Afterburner.ps1" }
    Start-Process -FilePath $psLnk -ArgumentList "-windowstyle hidden -ExecutionPolicy Bypass -NoLogo -File `"$abScript`""
}

# =========================
# WAIT FOR BACKGROUND TASKS TO FINISH
# =========================
Write-Host "Checking for background powershell tasks to finish..." -ForegroundColor Cyan

# Robust WMI check: Loops until no other powershell.exe is actively running a script from your files folder
while ($true) {
    $runningTasks = Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" | Where-Object { 
        $_.CommandLine -like "*\Windows\Setup\Scripts\files\*" -and $_.ProcessId -ne $PID 
    }
    
    if (-not $runningTasks) {
        break
    }
    Start-Sleep -Seconds 2
}

# =========================
# Ethernet: Execute AFTER all background tasks
# =========================
Run-Step "Apply Ethernet post-229 tuning only" {
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_lldp -ErrorAction SilentlyContinue
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_lltdio -ErrorAction SilentlyContinue
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_implat -ErrorAction SilentlyContinue
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_rspndr -ErrorAction SilentlyContinue
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_server -ErrorAction SilentlyContinue
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_msclient -ErrorAction SilentlyContinue

    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Advanced EEE" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "ARP Offload" -DisplayValue "Enabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "*Efficient Ethernet" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Flow Control" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Gigabit Lite" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Green Ethernet" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Interrupt Moderation" -DisplayValue "Enabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "IPv4 Checksum Offload" -DisplayValue "Rx & Tx Enabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Jumbo Frame" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Large Send Offload v2*" -DisplayValue "Enabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "NS Offload" -DisplayValue "Enabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "*Power Saving*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "*Priority & VLAN" -DisplayValue "Priority & VLAN Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Receive Buffers" -DisplayValue "1024" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Recv Segment Coalescing*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "*Speed & Duplex" -DisplayValue "1.0 Gbps Full Duplex" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "TCP Checksum Offload*" -DisplayValue "Rx & Tx Enabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Transmit Buffers" -DisplayValue "1024" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "UDP Checksum Offload*" -DisplayValue "Rx & Tx Enabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Wake on Magic Packet" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Wake on pattern match" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Interrupt Moderation Rate" -DisplayValue "Extreme" -ErrorAction SilentlyContinue

    Set-DnsClientServerAddress -InterfaceAlias "*" -ServerAddresses ("1.1.1.1","1.0.0.1") -ErrorAction SilentlyContinue
    Set-DnsClientServerAddress -InterfaceAlias "*" -ServerAddresses ("2606:4700:4700::1111","2606:4700:4700::1001") -ErrorAction SilentlyContinue

    netsh int tcp set global rss=enabled >$null 2>&1
    netsh int ipv4 set dynamicport tcp start=1025 num=64511 >$null 2>&1
    netsh int ipv4 set dynamicport udp start=1025 num=64511 >$null 2>&1
    netsh int tcp set supplemental Template=Datacenter CongestionProvider=bbr2 >$null 2>&1
    netsh int tcp set supplemental Template=Compat CongestionProvider=bbr2 >$null 2>&1
    netsh int tcp set supplemental Template=DatacenterCustom CongestionProvider=bbr2 >$null 2>&1
    netsh int tcp set supplemental Template=InternetCustom CongestionProvider=bbr2 >$null 2>&1

    ipconfig /flushdns >$null 2>&1
}

# =========================
# Final short desktop status
# =========================
Run-Step "Write short desktop status file" {
    $final = @()
    $final += "Quicky OneShot Completed"
    $final += "Successful: $($stepsOk.Count)"
    $final += "Failed: $($stepsFail.Count)"
    $final += ""
    $final += "[OK]"
    $final += ($stepsOk | ForEach-Object { "- $_" })
    if ($stepsFail.Count -gt 0) {
        $final += ""
        $final += "[FAILED]"
        $final += ($stepsFail | ForEach-Object { "- $_" })
    }
    Set-Content -Path $StatusOut -Value $final -Encoding UTF8
}

exit 0
