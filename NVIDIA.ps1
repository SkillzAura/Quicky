# Run as Administrator
If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Check if WMI service is disabled; if so, set to Manual. Then start it.
$wmiService = Get-Service winmgmt -ErrorAction SilentlyContinue
if ($wmiService.StartType -eq 'Disabled') {
    Set-Service winmgmt -StartupType Manual -ErrorAction SilentlyContinue
}
Start-Service winmgmt -ErrorAction SilentlyContinue

# Detect if system has an NVIDIA GPU (VEN_10DE)
$procPNP = Get-WmiObject Win32_VideoController | Select-Object -ExpandProperty PNPDeviceID -ErrorAction SilentlyContinue
if (!$procPNP -or -not ($procPNP -join ' ' -match 'VEN_10DE')) {
    # If not NVIDIA, create a status file and exit
    New-Item -Path "$env:TEMP\NVIDIA.status" -ItemType File -Force
    exit
}

# -- Utility Functions --

function Get-LatestNvidiaDriver {
    $isLaptop = $false
    try {
        $chassis = Get-WmiObject -Class Win32_SystemEnclosure | Select-Object -ExpandProperty ChassisTypes
        $isLaptop = ($chassis | Where-Object {$_ -in 8,9,10,14}).Count -gt 0
    } catch {}
    $pfid = 929 # Modern GPU (can be edited if you need specific one)
    $uri = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=120&pfid=$pfid&osID=57&languageCode=1033&isWHQL=1&dch=1&sort1=0&numberOfResults=1"
    $response = Invoke-RestMethod -Uri $uri
    $latestVersion = $response.IDS.downloadInfo.Version | Select-Object -First 1
    return @{
        Version   = $latestVersion
        IsLaptop  = $isLaptop
    }
}

function Download-File {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination
    )
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $Destination
}

function Use-Portable7z {
    param(
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string]$OutFolder,
        [string]$FilesToExtract = ""
    )
    $tempZip = "$env:TEMP\7za.zip"
    $sevenZipExe = "$env:TEMP\7za.exe"
    if (-not (Test-Path $sevenZipExe)) {
        $sevenZipUrl = "https://www.7-zip.org/a/7za920.zip"
        Invoke-WebRequest -Uri $sevenZipUrl -OutFile $tempZip
        Expand-Archive -Path $tempZip -DestinationPath $env:TEMP -Force
        Remove-Item $tempZip -Force
    }
    if (Test-Path $OutFolder) { Remove-Item $OutFolder -Recurse -Force }
    New-Item $OutFolder -ItemType Directory | Out-Null
    $args = @("x", "`"$Archive`"", "-o`"$OutFolder`"")
    if ($FilesToExtract) { $args += $FilesToExtract }
    $proc = Start-Process -FilePath $sevenZipExe -ArgumentList $args -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "Extraction failed." }
}

function Remove-Portable7z {
    $sevenZipExe = "$env:TEMP\7za.exe"
    if (Test-Path $sevenZipExe) { Remove-Item $sevenZipExe -Force }
}

function Disable-NvidiaTelemetry-And-Cleanup {
    # Disable scheduled tasks
    $telemetryTasks = @(
        '*NvDriverUpdateCheckDaily*', '*NVIDIA GeForce Experience SelfUpdate*', '*NvProfileUpdaterDaily*', '*NvProfileUpdaterOnLogon*',
        '*NvTmRep_CrashReport1*', '*NvTmRep_CrashReport2*', '*NvTmRep_CrashReport3*', '*NvTmRep_CrashReport4*', '*NvNodeLauncher*'
    )
    foreach ($task in $telemetryTasks) {
        try { Get-ScheduledTask -TaskName $task | Disable-ScheduledTask } catch {}
    }
    # Disable frameview and NVIDIA sound (nvvad)
    $paths = @(
        "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\FvSvc",
        "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\nvvad_WaveExtensible"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Set-ItemProperty -Path $path -Name "Start" -Value 4 -Type DWord
        }
    }


    # Remove NVIDIA logging/temp dirs
$toDelete = @(
    "$env:USERPROFILE\AppData\Local\Temp\NvidiaLogging"
)
foreach ($item in $toDelete) {
    Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue
}

    # Remove any leftover driver EXEs from Temp
    Get-ChildItem -Path $env:TEMP -Filter "NvidiaDriver-*.exe" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    # Remove NVIDIA Telemetry DLL if driver was stripped
    $driverRepos = Get-ChildItem -Path "$env:windir\System32\DriverStore\FileRepository\nv_dispi*" -Directory -ErrorAction SilentlyContinue
    foreach ($repo in $driverRepos) {
        $dll = Join-Path $repo.FullName "NvTelemetry64.dll"
        if (Test-Path $dll) {
            takeown /f "$dll" | Out-Null
            icacls "$dll" /grant administrators:F /t | Out-Null
            Remove-Item "$dll" -Force -ErrorAction SilentlyContinue
        }
    }
}

function Enable-Nvidia-MSI-Mode {
    # Enables MSI mode for NVIDIA display device
    try {
        $display = Get-PnpDevice -Class Display | Where-Object { $_.Status -eq 'OK' } | Select-Object -First 1
        if ($display) {
            $instanceId = $display.InstanceId
            $regPath = "HKLM\SYSTEM\ControlSet001\Enum\$instanceId\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            reg.exe add $regPath /v "MSISupported" /t REG_DWORD /d 1 /f | Out-Null
        }
    } catch { Write-Host "MSI Mode: Could not enable (device or reg key missing)" }
}

function Create-Nip-File {
$folder = 'C:\Windows\Setup\Scripts\files\Softwares\nvidiaProfileInspector'
if (-not (Test-Path $folder)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}
$NipFile = @'
<?xml version="1.0" encoding="utf-16"?>
<ArrayOfProfile>
  <Profile>
    <ProfileName>Base Profile</ProfileName>
    <Executeables />
    <Settings>
      <ProfileSetting>
        <SettingNameInfo> </SettingNameInfo>
        <SettingID>390467</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo />
        <SettingID>983226</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo />
        <SettingID>983227</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo />
        <SettingID>983295</SettingID>
        <SettingValue>AAAAQAAAAAA=</SettingValue>
        <ValueType>Binary</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Shader Cache</SettingNameInfo>
        <SettingID>1675263</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Negative LOD bias</SettingNameInfo>
        <SettingID>1686376</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Trilinear optimization</SettingNameInfo>
        <SettingID>3066610</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Sharpening Value</SettingNameInfo>
        <SettingID>3070157</SettingID>
        <SettingValue>50</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Sharpening - Denoising Factor</SettingNameInfo>
        <SettingID>3070158</SettingID>
        <SettingValue>17</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Sharpening Filter</SettingNameInfo>
        <SettingID>5867816</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync Tear Control</SettingNameInfo>
        <SettingID>5912412</SettingID>
        <SettingValue>2525368439</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Preferred refresh rate</SettingNameInfo>
        <SettingID>6600001</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>NVIDIA Predefined Ambient Occlusion Usage</SettingNameInfo>
        <SettingID>6701881</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo> </SettingNameInfo>
        <SettingID>6710836</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo> </SettingNameInfo>
        <SettingID>6710885</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Ambient Occlusion</SettingNameInfo>
        <SettingID>6714153</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo> </SettingNameInfo>
        <SettingID>6776373</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo> </SettingNameInfo>
        <SettingID>6776937</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Maximum pre-rendered frames</SettingNameInfo>
        <SettingID>8102046</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Anisotropic filter optimization</SettingNameInfo>
        <SettingID>8703344</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>SILK Smoothness</SettingNameInfo>
        <SettingID>9990737</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable sample interleaving (MFAA)</SettingNameInfo>
        <SettingID>10011052</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vertical Sync</SettingNameInfo>
        <SettingID>11041231</SettingID>
        <SettingValue>138504007</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Sharpening Value for NIS 2.0</SettingNameInfo>
        <SettingID>11250465</SettingID>
        <SettingValue>50</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable NIS 2.0</SettingNameInfo>
        <SettingID>11250721</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable NIS2 App Count</SettingNameInfo>
        <SettingID>11250737</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Shader disk cache maximum size</SettingNameInfo>
        <SettingID>11306135</SettingID>
        <SettingValue>4294967295</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Quality</SettingNameInfo>
        <SettingID>13510289</SettingID>
        <SettingValue>20</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo> </SettingNameInfo>
        <SettingID>14019014</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo> </SettingNameInfo>
        <SettingID>14019015</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Texture filtering - Anisotropic sample optimization</SettingNameInfo>
        <SettingID>15151633</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable NIS 2.0 KMD NOTIFICATION</SettingNameInfo>
        <SettingID>28027939</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Virtual Reality pre-rendered frames</SettingNameInfo>
        <SettingID>269553971</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Whisper Mode</SettingNameInfo>
        <SettingID>269573258</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Whisper Mode Application FPS</SettingNameInfo>
        <SettingID>269573259</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Flag to control smooth AFR behavior</SettingNameInfo>
        <SettingID>270198627</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic filtering setting</SettingNameInfo>
        <SettingID>270426537</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>SLI indicator</SettingNameInfo>
        <SettingID>271085649</SettingID>
        <SettingValue>877871204</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>NVIDIA predefined SLI mode</SettingNameInfo>
        <SettingID>271830721</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>NVIDIA predefined SLI mode on DirectX 10</SettingNameInfo>
        <SettingID>271830722</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>SLI rendering mode</SettingNameInfo>
        <SettingID>271830737</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Number of GPUs to use on SLI rendering mode</SettingNameInfo>
        <SettingID>271834321</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>NVIDIA predefined number of GPUs to use on SLI rendering mode</SettingNameInfo>
        <SettingID>271834322</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>NVIDIA predefined number of GPUs to use on SLI rendering mode on DirectX 10</SettingNameInfo>
        <SettingID>271834323</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>NVIDIA Predefined FXAA Usage</SettingNameInfo>
        <SettingID>271895433</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>List of Universal GPU ids</SettingNameInfo>
        <SettingID>271929336</SettingID>
        <SettingValue>none</SettingValue>
        <ValueType>String</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>No override of Anisotropic filtering</SettingNameInfo>
        <SettingID>272354485</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>NVIDIA Quality upscaling</SettingNameInfo>
        <SettingID>272909380</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Application Profile Notification Popup Timeout</SettingNameInfo>
        <SettingID>272979126</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Power management mode</SettingNameInfo>
        <SettingID>274197361</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Do not display this profile in the Control Panel</SettingNameInfo>
        <SettingID>275602687</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable FXAA</SettingNameInfo>
        <SettingID>276089202</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable Ansel</SettingNameInfo>
        <SettingID>276158834</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - SLI AA</SettingNameInfo>
        <SettingID>276495451</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Gamma correction</SettingNameInfo>
        <SettingID>276652957</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Mode</SettingNameInfo>
        <SettingID>276757595</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Platform Boost</SettingNameInfo>
        <SettingID>277041150</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>FRL Low Latency</SettingNameInfo>
        <SettingID>277041152</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Frame Rate Limiter</SettingNameInfo>
        <SettingID>277041154</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Background Application Max Frame Rate</SettingNameInfo>
        <SettingID>277041157</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Background Application Max Frame Rate only for NVCPL to maintain the previous slider value when the BG_FRL_FPS is set to Disabled.</SettingNameInfo>
        <SettingID>277041158</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Frame Rate Limiter for NVCPL</SettingNameInfo>
        <SettingID>277041162</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Toggle the VRR global feature</SettingNameInfo>
        <SettingID>278196567</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Display the PhysX indicator</SettingNameInfo>
        <SettingID>278196591</SettingID>
        <SettingValue>877871204</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>VRR requested state</SettingNameInfo>
        <SettingID>278196727</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Display the VRR Overlay Indicator</SettingNameInfo>
        <SettingID>278262127</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Variable refresh Rate</SettingNameInfo>
        <SettingID>279476686</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>G-SYNC</SettingNameInfo>
        <SettingID>279476687</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo> </SettingNameInfo>
        <SettingID>281106605</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic filtering mode</SettingNameInfo>
        <SettingID>282245910</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Transparency Supersampling</SettingNameInfo>
        <SettingID>282364549</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Setting</SettingNameInfo>
        <SettingID>282555346</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Behavior Flags</SettingNameInfo>
        <SettingID>283958146</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>CUDA Sysmem Fallback Policy</SettingNameInfo>
        <SettingID>283962569</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Optimus flags for enabled applications</SettingNameInfo>
        <SettingID>284810368</SettingID>
        <SettingValue>16</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable application for Optimus</SettingNameInfo>
        <SettingID>284810369</SettingID>
        <SettingValue>16</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Shim Rendering Mode Options per application for Optimus</SettingNameInfo>
        <SettingID>284810372</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Transparency Multisampling</SettingNameInfo>
        <SettingID>284962204</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Memory Allocation Policy</SettingNameInfo>
        <SettingID>286335539</SettingID>
        <SettingValue>2</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Overlay Indicator</SettingNameInfo>
        <SettingID>286335574</SettingID>
        <SettingValue>51</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Stereo - swap mode</SettingNameInfo>
        <SettingID>288568115</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Stereo - Enable</SettingNameInfo>
        <SettingID>296394393</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Stereo - Swap eyes</SettingNameInfo>
        <SettingID>296633180</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Stereo - Display mode</SettingNameInfo>
        <SettingID>300489313</SettingID>
        <SettingValue>4294967295</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Buffer-flipping mode</SettingNameInfo>
        <SettingID>538927519</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Force Stereo shuttering</SettingNameInfo>
        <SettingID>541956620</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Enable overlay</SettingNameInfo>
        <SettingID>543959236</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>OpenGL GDI compatibility</SettingNameInfo>
        <SettingID>544392611</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Antialiasing - Line gamma</SettingNameInfo>
        <SettingID>545898348</SettingID>
        <SettingValue>16</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Deep color for 3D applications</SettingNameInfo>
        <SettingID>546816758</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Exported Overlay pixel types</SettingNameInfo>
        <SettingID>547022447</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Unified back/depth buffer</SettingNameInfo>
        <SettingID>547524693</SettingID>
        <SettingValue>4294967295</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Threaded optimization</SettingNameInfo>
        <SettingID>549528094</SettingID>
        <SettingValue>2</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Preferred OpenGL GPU</SettingNameInfo>
        <SettingID>550564838</SettingID>
        <SettingValue>id,2.0:1F0810DE,00002B00,GF - (352,6,161,6144) @ (0)</SettingValue>
        <ValueType>String</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Vulkan/OpenGL present method</SettingNameInfo>
        <SettingID>550932728</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Triple buffering</SettingNameInfo>
        <SettingID>553505273</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo>Extension String version</SettingNameInfo>
        <SettingID>553612435</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
      <ProfileSetting>
        <SettingNameInfo />
        <SettingID>1343646814</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
    </Settings>
  </Profile>
  <Profile>
    <ProfileName>Desktop Windows Manager</ProfileName>
    <Executeables>
      <string>dwm.exe</string>
    </Executeables>
    <Settings>
      <ProfileSetting>
        <SettingNameInfo>Power management mode</SettingNameInfo>
        <SettingID>274197361</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
    </Settings>
  </Profile>
  <Profile>
    <ProfileName>Grand Theft Auto V</ProfileName>
    <Executeables>
      <string>gta5.exe</string>
    </Executeables>
    <Settings>
      <ProfileSetting>
        <SettingNameInfo>Anisotropic filtering mode</SettingNameInfo>
        <SettingID>282245910</SettingID>
        <SettingValue>0</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
    </Settings>
  </Profile>
  <Profile>
    <ProfileName>Windows Explorer</ProfileName>
    <Executeables>
      <string>explorer.exe</string>
    </Executeables>
    <Settings>
      <ProfileSetting>
        <SettingNameInfo>Power management mode</SettingNameInfo>
        <SettingID>274197361</SettingID>
        <SettingValue>1</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
    </Settings>
  </Profile>
</ArrayOfProfile>
'@
$NipFile | Out-File -FilePath 'C:\Windows\Setup\Scripts\files\Softwares\nvidiaProfileInspector\Aura.nip' -Encoding UTF8 -Force
}

function Import-NIP-Profile {
    $baseDir = "C:\Windows\Setup\Scripts\files\Softwares\nvidiaProfileInspector"
    $npiExe = "$baseDir\nvidiaProfileInspector.exe"
    $nipFile = "$baseDir\Aura.nip"

    # Remove all files except .lnk, .url, and .nip (to force a fresh install)
    if (Test-Path $baseDir) {
        Get-ChildItem $baseDir -Recurse -File | Where-Object { $_.Extension -notin ".lnk", ".url", ".nip" } | Remove-Item -Force
    } else {
        New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
    }

    # Always download and extract the latest nvidiaProfileInspector
    $URL = "https://github.com/Orbmu2k/nvidiaProfileInspector/releases/latest/download/nvidiaProfileInspector.zip"
    $outFile = "$baseDir\nvidiaProfileInspector.zip"
    (New-Object System.Net.WebClient).DownloadFile($URL, $outFile)
    Expand-Archive "$baseDir\nvidiaProfileInspector*.zip" -DestinationPath $baseDir -Force
    Remove-Item $outFile

    # Create a .url Internet shortcut in $baseDir
    $shortcutPath = Join-Path $baseDir 'nvidiaProfileInspector.url'
    @"
[InternetShortcut]
URL=https://github.com/Orbmu2k/nvidiaProfileInspector/releases/latest/download/nvidiaProfileInspector.zip
"@ | Out-File -FilePath $shortcutPath -Encoding ASCII -Force

if ((Test-Path $npiExe) -and (Test-Path $nipFile)) {
    cmd /c "$npiExe $nipFile -silent /f >nul 2>&1"
}
}


function Remove-SetupCfg-Lines {
    param([Parameter(Mandatory)][string]$CfgPath)
    if (Test-Path $CfgPath) {
        # Read the config as raw text
        $lines = Get-Content $CfgPath
        # Remove all lines that exactly match the unwanted XML (with/without tabs or spaces at start)
        $lines = $lines | Where-Object {
            $_.Trim() -notin @(
                '<file name="${{EulaHtmlFile}}"/>',
                '<file name="${{FunctionalConsentFile}}"/>',
                '<file name="${{PrivacyPolicyFile}}"/>'
            )
        }
        # Write back the filtered lines
        Set-Content $CfgPath $lines
    }
}

function Set-Nvidia-Tweaks {
    # Disable Nvidia tray icon
    reg add "HKCU\Software\NVIDIA Corporation\NvTray" /v "StartOnLogin" /t REG_DWORD /d "0" /f

    # Set PhysX to GPU
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak" /v "NvCplPhysxAuto" /t REG_DWORD /d "0" /f

    # Disable Telemetry (probably for GFE)
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\Startup\SendTelemetryData" /ve /t REG_DWORD /d 0 /f

    # Disable Geforce Experience Updates
    reg add "HKCU\Software\NVIDIA Corporation\Global\GFExperience" /v "NotifyNewDisplayUpdates" /t REG_DWORD /d "0" /f
    reg add "HKCU\Software\NVIDIA Corporation\Global\NvCplApi\Policies" /v "ContextUIPolicy" /t REG_DWORD /d "0" /f
    reg add "HKCU\Software\NVIDIA Corporation\NvTray" /v "StartOnLogin" /t REG_DWORD /d "0" /f

    # Remove Desktop Context Menu
    reg delete "HKLM\Software\Classes\Directory\Background\ShellEx\ContextMenuHandlers\NvCplDesktopContext" /f
}

function Set-Nvidia-ColorSettings {
    # Get all monitor Device IDs (7-char code)
    $dList = @()
    $monitorDevices = pnputil /enum-devices | Select-String -Pattern 'DISPLAY'
    foreach ($device in $monitorDevices) {
        $deviceId = $device.ToString() -replace '^.*?DISPLAY\\(.*?)\\.*$', '$1'
        if ($deviceId.Length -eq 7 -and !$dList.Contains($deviceId)) {
            $dList += $deviceId
        }
    }

    # Build reg paths for each monitor
    $paths = @()
    for ($i = 0; $i -lt $dList.Length; $i++) {
        $item = Get-ChildItem -Path 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\nvlddmkm\State\DisplayDatabase\' |
            Where-Object { $_.Name -like "*$($dList[$i])*" } | Select-Object -First 1
        $paths += $item
    }

    # Function to run reg add with admin permissions
    function Run-Trusted([String]$command) {
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
        $base64Command = [Convert]::ToBase64String($bytes)
        sc.exe config TrustedInstaller binPath= "cmd.exe /c powershell.exe -encodedcommand $base64Command" | Out-Null
        sc.exe start TrustedInstaller | Out-Null
        sc.exe config TrustedInstaller binpath= "C:\Windows\servicing\trustedinstaller.exe" | Out-Null
        Stop-Service -Name TrustedInstaller -Force -ErrorAction SilentlyContinue
    }

    # Set NVIDIA Color for all found displays (RGB)
    foreach ($path in $paths) {
        try {
            $colorConfig = Get-ItemPropertyValue "registry::$($path.Name)" -Name ColorformatConfig -ErrorAction Stop
            $colorConfig[10] = 0
            $colorConfig[12] = 0
            $colorConfig[16] = 3
            $hexValue = ($colorConfig | ForEach-Object { '{0:X2}' -f $_ }) -join ''
            $command = "Reg.exe add $($path.Name) /v `"ColorformatConfig`" /t REG_BINARY /d `"$hexValue`" /f"
            Run-Trusted -command $command
        } catch {
            $value = 'db02000014000000000a00080000000003010000'
            $command = "Reg.exe add $($path.Name) /v `"ColorformatConfig`" /t REG_BINARY /d `"$value`" /f"
            Run-Trusted -command $command
        }
    }
}

function Set-Nvidia-ClassKey-Tweaks {
    $basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class"

    # Find the Class Key where Class is 'Display'
    $displayClassKeys = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).Class -eq "Display"
    }

    foreach ($classKey in $displayClassKeys) {
        # Check all subkeys like 0000, 0001, etc.
        for ($i = 0; $i -le 99; $i++) {
            $subKey = "{0:D4}" -f $i
            $subKeyPath = Join-Path -Path $classKey.PSPath -ChildPath $subKey

            if (Test-Path $subKeyPath) {
                $props = Get-ItemProperty -Path $subKeyPath -ErrorAction SilentlyContinue

                if ($props.DriverDesc -match "nvidia") {
                    $regEdits = @{
                        "RMHdcpKeyglobZero"    = 1
                        "RMCtxswLog"           = 0
                        "DisableDynamicPstate" = 1
                    }

                    foreach ($key in $regEdits.Keys) {
                        try {
                            if (Get-ItemProperty -Path $subKeyPath -Name $key -ErrorAction SilentlyContinue) {
                                Set-ItemProperty -Path $subKeyPath -Name $key -Value $regEdits[$key]
                            } else {
                                New-ItemProperty -Path $subKeyPath -Name $key -PropertyType DWord -Value $regEdits[$key] -Force | Out-Null
                            }
                        } catch {}
                    }
                }
            }
        }
    }
}

function Set-Nvidia-MonitorScaling {
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration"
    $monitorKeys = Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue
    foreach ($monitorKey in $monitorKeys) {
        $subKeys = Get-ChildItem -Path $monitorKey.PSPath -Recurse -ErrorAction SilentlyContinue
        foreach ($key in $subKeys) {
            try {
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if ($props.PSObject.Properties.Name -contains "Scaling") {
                    Set-ItemProperty -Path $key.PSPath -Name "Scaling" -Value 2 -Force
                }
            } catch {}
        }
    }
}

function Set-Nvidia-VideoColorSettings { 
    $basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class"

    # Find the Class Key where Class is 'Display'
    $displayClassKeys = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).Class -eq "Display"
    }

    foreach ($classKey in $displayClassKeys) {
        # Check all subkeys like 0000, 0001, etc.
        for ($i = 0; $i -le 99; $i++) {
            $subKey = "{0:D4}" -f $i
            $subKeyPath = Join-Path -Path $classKey.PSPath -ChildPath $subKey

            if (Test-Path $subKeyPath) {
                $props = Get-ItemProperty -Path $subKeyPath -ErrorAction SilentlyContinue

                if ($props.DriverDesc -match "nvidia") {
                    # Set all desired registry values
                    $regEdits = @{
                        "_User_SUB0_DFP1_XALG_Color_Range" = @{ Value = [byte[]](0,0,0,0,0,0,0,0); Type = "Binary" }
                        "_User_SUB0_DFP1_XEN_Contrast"      = @{ Value = 0x80000001; Type = "DWord" }
                        "_User_SUB0_DFP1_XEN_RGB_Gamma_B"   = @{ Value = 0x80000001; Type = "DWord" }
                        "_User_SUB0_DFP1_XEN_RGB_Gamma_G"   = @{ Value = 0x80000001; Type = "DWord" }
                        "_User_SUB0_DFP1_XEN_RGB_Gamma_R"   = @{ Value = 0x80000001; Type = "DWord" }
                        "_User_SUB0_DFP1_XEN_Color_Range"   = @{ Value = 0x80000001; Type = "DWord" }
                        "_User_SUB0_DFP1_XEN_Brightness"    = @{ Value = 0x80000001; Type = "DWord" }
                        "_User_SUB0_DFP1_XEN_Saturation"    = @{ Value = 0x80000001; Type = "DWord" }
                        "_User_SUB0_DFP1_XEN_Hue"           = @{ Value = 0x80000001; Type = "DWord" }
                    }

                    foreach ($key in $regEdits.Keys) {
                        $value = $regEdits[$key].Value
                        $type  = $regEdits[$key].Type

                        try {
                            if (Get-ItemProperty -Path $subKeyPath -Name $key -ErrorAction SilentlyContinue) {
                                Set-ItemProperty -Path $subKeyPath -Name $key -Value $value -Type $type
                            } else {
                                New-ItemProperty -Path $subKeyPath -Name $key -PropertyType $type -Value $value -Force | Out-Null
                            }
                        } catch {
                            Write-Host "Failed to set $key on $subKeyPath"
                        }
                    }
                }
            }
        }
    }
}

function Start-Services {
$services = @("PlugPlay", "DeviceInstall")

foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.StartType.ToString().ToLower() -eq 'disabled') {
            $regPath = "HKLM\SYSTEM\CurrentControlSet\Services\$svc"
            Start-Process reg -ArgumentList "add `"$regPath`" /v Start /t REG_DWORD /d 3 /f" -Wait -Verb RunAs
            Start-Sleep -Seconds 1
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        }
        if ($service.Status -eq 'Stopped') {
            try {
                Start-Service -Name $svc -ErrorAction SilentlyContinue
            } catch {
                # Silently ignore errors
            }
        }
    }
}
}

# --- MAIN WORKFLOW ---

Start-Services

$driverInfo = Get-LatestNvidiaDriver
$latestVersion = $driverInfo.Version
$isLaptop = $driverInfo.IsLaptop
$arch = if ([Environment]::Is64BitOperatingSystem) { "64bit" } else { "32bit" }

if ($isLaptop) {
    $driverUrl = "https://international.download.nvidia.com/Windows/$latestVersion/$latestVersion-notebook-win10-win11-$arch-international-dch-whql.exe"
} else {
    $driverUrl = "https://international.download.nvidia.com/Windows/$latestVersion/$latestVersion-desktop-win10-win11-$arch-international-dch-whql.exe"
}

$driverExe = Join-Path $env:TEMP "NvidiaDriver-$latestVersion.exe"
Download-File -Url $driverUrl -Destination $driverExe

# STRIP DRIVER? Set to $false for full install
$stripDriver = $true

# Use NVCleanstall folder as in Zoic
$extractFolder = "$env:USERPROFILE\AppData\Local\Temp\NVCleanstall"
if ($stripDriver) {
    $filesToExtract = "Display.Driver NVI2 EULA.txt ListDevices.txt setup.cfg setup.exe"
    Use-Portable7z -Archive $driverExe -OutFolder $extractFolder -FilesToExtract $filesToExtract
} else {
    Use-Portable7z -Archive $driverExe -OutFolder $extractFolder
}

# --- REMOVE LINES FROM setup.cfg (EULA, Functional Consent, Privacy Policy) ---
$cfgPath = Join-Path $extractFolder 'setup.cfg'
Remove-SetupCfg-Lines -CfgPath $cfgPath

Start-Process "$extractFolder\setup.exe" -ArgumentList "-clean -s -y" -Wait

# Wait for all NVIDIA installer processes to finish before continuing
while (Get-Process | Where-Object { $_.Description -like "NVIDIA Install*" }) {
    Start-Sleep -Seconds 1
}

# Post-install: Telemetry disable and cleanup
Disable-NvidiaTelemetry-And-Cleanup

# Post-install: Apply NVIDIA registry tweaks
Set-Nvidia-Tweaks

# Create Nvidia Profile
Create-Nip-File

# Post-install: Import NIP profile
Import-NIP-Profile

# Set NVIDIA Color Settings for all monitors
Set-Nvidia-ColorSettings

# Post-install: Enable MSI mode
Enable-Nvidia-MSI-Mode

# Disable HDCP, Logging and Power Saving (Increases Temps)
Set-Nvidia-ClassKey-Tweaks

# Set Scaling Mode to No scaling
Set-Nvidia-MonitorScaling

# Set Nvidia Video Color Settings
Set-Nvidia-VideoColorSettings

# Disable Nvidia USB Controller
pnputil /disable-device "PCI\VEN_10DE&DEV_1ADA&SUBSYS_868E1043&REV_A1\4&3622C94C&0&0219"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "*Host Controller - %3 (Microsoft);(NVIDIA*" /use_wildcard

# Final Cleanup
Remove-Portable7z
Remove-Item $extractFolder -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $driverExe -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files\NVIDIA Corporation\Installer*" -Recurse -Force -ErrorAction SilentlyContinue

New-Item -Path "$env:TEMP\NVIDIA.status" -ItemType File -Force

exit