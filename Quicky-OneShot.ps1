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
# Paths / Status
# =========================
$FilesRoot = "C:\Windows\Setup\Scripts\files"
$SoftRoot  = Join-Path $FilesRoot "Softwares"
$StatusOut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Quicky-Status.txt"
$stepsOk   = New-Object System.Collections.Generic.List[string]
$stepsFail = New-Object System.Collections.Generic.List[string]

function Add-OK([string]$s){ $stepsOk.Add($s) }
function Add-Fail([string]$s){ $stepsFail.Add($s) }

function Run-Step {
    param([string]$Name,[scriptblock]$Action)
    try { & $Action; Add-OK $Name } catch { Add-Fail "$Name :: $($_.Exception.Message)" }
}

# =========================
# Ensure base folder + exclusions + required binaries
# =========================
Run-Step "Create files root + Defender exclusion" {
    if (!(Test-Path $FilesRoot)) { New-Item -ItemType Directory -Path $FilesRoot -Force | Out-Null }
    Add-MpPreference -ExclusionPath $FilesRoot -ErrorAction SilentlyContinue
}

Run-Step "Download Power.exe + MinSudo.exe to files root" {
    Invoke-WebRequest -Uri "https://github.com/SkillzAura/Quicky/releases/download/Power/Power.exe" -OutFile (Join-Path $FilesRoot "Power.exe")
    Invoke-WebRequest -Uri "https://github.com/SkillzAura/Quicky/releases/download/Minsudo/MinSudo.exe" -OutFile (Join-Path $FilesRoot "MinSudo.exe")
}

# =========================
# Close apps first (requested)
# =========================
Run-Step "Force-close blocking apps/processes" {
    $kill = @("msedge","msedgewebview2","MicrosoftEdgeUpdate","RTSSSetup","RTSS","MSIAfterburner")
    foreach($p in $kill){ Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
}

# =========================
# Disable ALL scheduled tasks (requested)
# =========================
Run-Step "Disable all scheduled tasks" {
    schtasks /query /fo LIST 2>$null | ForEach-Object {
        if ($_ -like "TaskName:*") {
            $tn = $_.Split(":",2)[1].Trim()
            if ($tn) { schtasks /change /tn "$tn" /disable >$null 2>&1 }
        }
    }
}

# =========================
# Services (ONLY requested subset)
# =========================
Run-Step "Apply selected services only" {
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\SysMain"  /v Start /t REG_DWORD /d 4 /f >$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\WSearch"  /v Start /t REG_DWORD /d 4 /f >$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\DusmSvc"  /v Start /t REG_DWORD /d 4 /f >$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\lfsvc"    /v Start /t REG_DWORD /d 4 /f >$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Spooler"  /v Start /t REG_DWORD /d 4 /f >$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\msisadrv" /v Start /t REG_DWORD /d 4 /f >$null
}

# =========================
# Registry.reg apply all EXCEPT NVME Native Drivers blocks
# =========================
Run-Step "Apply Registry.reg excluding NVME native driver blocks" {
    $src = Join-Path $FilesRoot "Registry.reg"
    if (!(Test-Path $src)) { throw "Missing Registry.reg in $FilesRoot" }

    $tmp = Join-Path $env:TEMP "Registry.filtered.reg"
    $lines = Get-Content -Path $src

    $skip = $false
    $out  = New-Object System.Collections.Generic.List[string]

    foreach($line in $lines){
        if ($line -match '^\s*;\s*Enable NVME Native Drivers') { $skip = $true; continue }
        if ($line -match '^\s*;\s*NVME Native Driver Safemode Fix') { $skip = $true; continue }

        # stop skipping when next major commented section starts
        if ($skip -and $line -match '^\s*;\s+[A-Z].+') {
            # continue skipping only for the two target sections; reset on next section
            $skip = $false
        }

        if (-not $skip) { $out.Add($line) }
    }

    Set-Content -Path $tmp -Value $out -Encoding Unicode
    reg import "$tmp" >$null 2>&1
}

# =========================
# ValleyOfDoom (run as-is from source file)
# =========================
Run-Step "Run ValleyOfDoom as-is" {
    $vod = Join-Path $FilesRoot "ValleyOfDoom.ps1"
    if (!(Test-Path $vod)) { throw "Missing ValleyOfDoom.ps1" }
    powershell -ExecutionPolicy Bypass -NoProfile -File "$vod"
}

# =========================
# Remove-Edge (run as-is from source file)
# =========================
Run-Step "Run Remove-Edge as-is" {
    $re = Join-Path $FilesRoot "Remove-Edge.ps1"
    if (!(Test-Path $re)) { throw "Missing Remove-Edge.ps1" }
    powershell -ExecutionPolicy Bypass -NoProfile -File "$re"
}

# =========================
# Softwares: ONLY Autoruns + GoInterruptPolicy, open both
# =========================
Run-Step "Install Autoruns + GoInterruptPolicy only" {
    if (!(Test-Path $SoftRoot)) { New-Item -ItemType Directory -Path $SoftRoot -Force | Out-Null }

    # Autoruns
    $autorunsDir = Join-Path $SoftRoot "Autoruns"
    if (!(Test-Path $autorunsDir)) { New-Item -ItemType Directory -Path $autorunsDir -Force | Out-Null }
    $autorunsZip = Join-Path $autorunsDir "Autoruns.zip"
    Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Autoruns.zip" -OutFile $autorunsZip
    Expand-Archive -Path $autorunsZip -DestinationPath $autorunsDir -Force
    Remove-Item $autorunsZip -Force -ErrorAction SilentlyContinue
    reg add "HKEY_CURRENT_USER\Software\Sysinternals\Autoruns" /v "EulaAccepted" /t REG_DWORD /d 1 /f >$null 2>&1

    # GoInterruptPolicy
    $goDir = Join-Path $SoftRoot "GoInterruptPolicy"
    if (!(Test-Path $goDir)) { New-Item -ItemType Directory -Path $goDir -Force | Out-Null }
    $goExe = Join-Path $goDir "GoInterruptPolicy.exe"
    Invoke-WebRequest -Uri "https://github.com/spddl/GoInterruptPolicy/releases/latest/download/GoInterruptPolicy.exe" -OutFile $goExe

    # Open both
    $autorunsExe = Join-Path $autorunsDir "Autoruns64.exe"
    if (Test-Path $autorunsExe) { Start-Process $autorunsExe -ErrorAction SilentlyContinue }
    if (Test-Path $goExe) { Start-Process $goExe -ErrorAction SilentlyContinue }
}

# =========================
# Afterburner: install, DO NOT edit maintenance.bat, open app
# =========================
Run-Step "Install Afterburner (no maintenance.bat edit) + open" {
    $url = "https://ftp.nluug.nl/pub/games/PC/guru3d/afterburner/[Guru3D]-MSIAfterburnerSetup466Beta5Build16555.zip"
    $zip = Join-Path $env:TEMP "MSIAfterburner.zip"
    $redistPath = "C:\Program Files (x86)\MSI Afterburner\Redist"
    $rtssFile = Join-Path $redistPath "RTSSSetup.exe"

    Invoke-WebRequest -Uri $url -OutFile $zip
    if (!(Test-Path $redistPath)) { New-Item -ItemType Directory -Path $redistPath -Force | Out-Null }

    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $redistPath
    $watcher.Filter = "RTSSSetup.exe"
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName
    $watcher.EnableRaisingEvents = $true
    $evt = Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action {
        Start-Sleep -Milliseconds 100
        if (Test-Path $using:rtssFile) { Remove-Item $using:rtssFile -Force -ErrorAction SilentlyContinue }
    }

    Expand-Archive "$zip" -DestinationPath "$env:TEMP" -Force
    $setup = Get-ChildItem "$env:TEMP" -Filter "MSIAfterburnerSetup*" -File | Select-Object -First 1
    if ($setup) { Start-Process -FilePath $setup.FullName -ArgumentList "/S" -Wait }

    Get-Process -Name "RTSSSetup" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if (Test-Path $rtssFile) { Remove-Item $rtssFile -Force -ErrorAction SilentlyContinue }

    try { Unregister-Event -SourceIdentifier $evt.Name -ErrorAction SilentlyContinue } catch {}
    $watcher.Dispose()

    $ab = "C:\Program Files (x86)\MSI Afterburner\MSIAfterburner.exe"
    if (Test-Path $ab) { Start-Process $ab }
}

# =========================
# Sound: apply all from Sound.ps1
# =========================
Run-Step "Apply Sound settings (all)" {
    $min = Join-Path $FilesRoot "MinSudo.exe"
    $baseKeys = @(
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
    )
    foreach ($baseKey in $baseKeys) {
        $guidKeys = Get-ChildItem -Path "Registry::$baseKey" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '{[0-9a-f\-]+}' }
        foreach ($key in $guidKeys) {
            $guid = Split-Path $key.Name -Leaf
            $propsPath = "$baseKey\$guid\Properties"
            $fxPath = "$baseKey\$guid\FxProperties"
            & $min --NoLogo --TrustedInstaller --Privileged reg add "$propsPath" /v "{b3f8fa53-0004-438e-9003-51a46e139bfc},3" /t REG_DWORD /d 0 /f
            & $min --NoLogo --TrustedInstaller --Privileged reg add "$propsPath" /v "{b3f8fa53-0004-438e-9003-51a46e139bfc},4" /t REG_DWORD /d 0 /f
            & $min --NoLogo --TrustedInstaller --Privileged reg add "$fxPath" /v "{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5" /t REG_DWORD /d 1 /f
        }
    }

    Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class" -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).class -eq "Media"
    } | ForEach-Object {
        Get-ChildItem -Path $_.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $p = Join-Path $_.PSPath "PowerSettings"
            if (Test-Path $p) {
                Set-ItemProperty -Path $p -Name "ConservationIdleTime" -Value ([byte[]](0,0,0,0)) -Type Binary
                Set-ItemProperty -Path $p -Name "PerformanceIdleTime"  -Value ([byte[]](0,0,0,0)) -Type Binary
                Set-ItemProperty -Path $p -Name "IdlePowerState"      -Value ([byte[]](0,0,0,0)) -Type Binary
            }
        }
    }
}

# =========================
# Ethernet: ONLY apply from line 229 onward in your source
# (skip installs + static ip + prior setup)
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
    # minimal stub + importable file path, replace with your full NIP if desired
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
    Invoke-WebRequest -Uri "https://github.com/Orbmu2k/nvidiaProfileInspector/releases/latest/download/nvidiaProfileInspector.zip" -OutFile $zip
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
# Performance-Tweaks with requested skips
# skip:
# - Disable Generic USB Hub
# - HDAUDIO\FUNC_01... disable
# - Disable Mitigations block
# =========================
Run-Step "Apply Performance-Tweaks with requested skips" {
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

    # Keep the rest of devices except skipped ones
    $devices = @(
        "SWD\MSRRAS\MS_PPPOEMINIPORT","SWD\MSRRAS\MS_PPTPMINIPORT","SWD\MSRRAS\MS_AGILEVPNMINIPORT","SWD\MSRRAS\MS_NDISWANBH",
        "SWD\MSRRAS\MS_NDISWANIP","SWD\MSRRAS\MS_SSTPMINIPORT","SWD\MSRRAS\MS_NDISWANIPV6","SWD\MSRRAS\MS_L2TPMINIPORT",
        "ROOT\KDNIC\0000","SWD\MMDEVAPI\MICROSOFTGSWAVETABLESYNTH","ROOT\MEDIA\0000","ROOT\COMPOSITEBUS\0000",
        "PCI\VEN_8086&DEV_2668&SUBSYS_76808384&REV_01\3&267A616A&0&28","PCI\VEN_10DE&DEV_10F9&SUBSYS_868E1043&REV_A1\4&3622C94C&0&0119",
        "ROOT\VDRVROOT\0000","ROOT\NDISVIRTUALBUS\0000","ROOT\RDPBUS\0000","ROOT\UMBUS\0000",
        "SWD\PRINTENUM\PRINTQUEUES","SWD\PRINTENUM\{E70E9471-8340-42BE-AC0A-A20FA6D23978}",
        "ACPI\PNP0501\0","PCI\VEN_1022&DEV_1486&SUBSYS_7C561462&REV_00\4&4BC21C8&0&0141","USB\VID_1462&PID_7C56\A02020051102",
        "{36fc9e60-c465-11cf-8056-444553540000}","{745a17a0-74d3-11d0-b6fe-00a0c90f57da}"
    )
    foreach($d in $devices){ pnputil /disable-device "$d" >$null 2>&1 }
    pnputil /remove-device "ROOT\KDNIC\0000" >$null 2>&1

    # QoS policies (as source)
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
# Power plan: apply all
# =========================
Run-Step "Apply Power-Plan all" {
    $pp = Join-Path $FilesRoot "Power-Plan.ps1"
    if (!(Test-Path $pp)) { throw "Missing Power-Plan.ps1" }
    powershell -ExecutionPolicy Bypass -NoProfile -File "$pp"
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
