If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) 
{	Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit	}

$ProgressPreference = 'SilentlyContinue'
$URL = "https://ftp.nluug.nl/pub/games/PC/guru3d/afterburner/[Guru3D]-MSIAfterburnerSetup466Beta5Build16555.zip"
$outFile = "$ENV:Temp\MSIAfterburner.zip"
$redistPath = "C:\Program Files (x86)\MSI Afterburner\Redist"
$rtssFile = "$redistPath\RTSSSetup.exe"

(New-Object System.Net.WebClient).DownloadFile($URL, $outFile)

if (!(Test-Path -Path $redistPath)) {
    New-Item -ItemType Directory -Path $redistPath -Force | Out-Null
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $redistPath
$watcher.Filter = "RTSSSetup.exe"
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName
$watcher.EnableRaisingEvents = $true

$onCreated = Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action {
    Start-Sleep -Milliseconds 100
    if (Test-Path -Path $rtssFile) {
        # Retry logic if the file is in use
        $attempt = 0
        $maxAttempts = 5
        while ($attempt -lt $maxAttempts) {
            try {
                Remove-Item $rtssFile -Force
                break
            } catch {
                Start-Sleep -Seconds 1
                $attempt++
            }
        }
    }
}

Expand-Archive "$env:TEMP\MSIAfterburner.zip" -DestinationPath "$env:TEMP"
Start-Process -FilePath "$env:TEMP\MSIAfterburnerSetup*" -Args "/S"

Do {
    $rtssProcess = Get-Process -Name "RTSSSetup" -ErrorAction SilentlyContinue
    if ($rtssProcess) {
        Stop-Process -Id $rtssProcess.Id -Force
    }

    if (Test-Path -Path $rtssFile) {
        # Retry logic if the file is in use
        $attempt = 0
        $maxAttempts = 5
        while ($attempt -lt $maxAttempts) {
            try {
                Remove-Item $rtssFile -Force
                break
            } catch {
                Start-Sleep -Seconds 1
                $attempt++
            }
        }
    }

    Start-Sleep -Milliseconds 500
} Until (!(Get-Process -Name "MSIAfterburner*" -ErrorAction SilentlyContinue))

# Safely unregister the event using a try-catch block to avoid errors
try {
    Unregister-Event -SourceIdentifier $onCreated.Id -ErrorAction SilentlyContinue
} catch {
    # Handle any errors silently, no need to alert the user
}

# Dispose the watcher
$watcher.Dispose()

New-Item -Path "$env:C:\Program Files (x86)\MSI Afterburner" -Name "Profiles" -ItemType Directory -ErrorAction SilentlyContinue 
$MultilineComment = @"
[Settings]
Views=
LastUpdateCheck=66C0583Ah
Skin=MSICyborgWhite.usf
StartWithWindows=0
StartMinimized=1
HwPollPeriod=60000
LockProfiles=0
ShowHints=0
ShowTooltips=0
LCDFont=font4x6.dat
RememberSettings=0
FirstRun=0
FirstUserDefineClick=1
FirstServerRun=0
CurrentGpu=0
Sync=1
Link=1
LinkThermal=1
FanSync=1
CurrentFan=0
ShowOSDTime=0
CaptureOSD=1
Profile1Hotkey=00000000h
Profile2Hotkey=00000000h
Profile3Hotkey=00000000h
Profile4Hotkey=00000000h
Profile5Hotkey=00000000h
OSDToggleHotkey=00000000h
OSDOnHotkey=00000000h
OSDOffHotkey=00000000h
OSDServerBlockHotkey=00000000h
LimiterToggleHotkey=00000000h
LimiterOnHotkey=00000000h
LimiterOffHotkey=00000000h
ScreenCaptureHotkey=00000000h
VideoCaptureHotkey=00000000h
VideoPrerecordHotkey=00000000h
PTTHotkey=00000000h
PTT2Hotkey=00000000h
BeginRecordHotkey=00000000h
EndRecordHotkey=00000000h
BeginLoggingHotkey=00000000h
EndLoggingHotkey=00000000h
ClearHistoryHotkey=00000000h
BenchmarkPath=%ABDir%\Benchmark.txt
AppendBenchmark=1
ScreenCaptureFormat=bmp
ScreenCaptureFolder=
ScreenCaptureQuality=100
VideoCaptureFolder=
VideoCaptureFormat=MJPG
VideoCaptureQuality=85
VideoCaptureFramerate=30
VideoCaptureFramesize=00000002h
VideoCaptureThreads=FFFFFFFFh
AudioCaptureFlags=00000003h
VideoCaptureFlagsEx=00000000h
AudioCaptureFlags2=00000000h
VideoCaptureContainer=avi
VideoPrerecordSizeLimit=256
VideoPrerecordTimeLimit=600
AutoPrerecord=0
WindowX=560
WindowY=205
ProfileContents=1
Profile2D=-1
Profile3D=-1
SwAutoFanControl=0
SwAutoFanControlFlags=00000000h
SwAutoFanControlPeriod=5000
RestoreAfterSuspendedMode=1
PauseMonitoring=0
ShowPerformanceProfilerStatus=0
ShowPerformanceProfilerPanel=0
AttachMonitoringWindow=1
HideMonitoring=0
MonitoringWindowOnTop=1
LogPath=%ABDir%\HardwareMonitoring.hml
EnableLog=0
RecreateLog=0
LogLimit=10
OSDLayout=1
UnlockVoltageControl=1
UnlockVoltageMonitoring=1
OEM=0
ForceConstantVoltage=1
SingleTrayIconMode=0
Fahrenheit=0
Time24=0
LCDGraph=0
UpdateCheckingPeriod=0
LowLevelInterface=1
MMIOUserMode=1
HAL=1
Driver=1
Language=
LayeredWindowMode=1
LayeredWindowAlpha=244
ScaleFactor=100
Sources=-GPU usage,-Memory usage,-CPU1 temperature,-CPU2 temperature,-CPU3 temperature,-CPU4 temperature,-CPU5 temperature,-CPU6 temperature,-CPU7 temperature,-CPU8 temperature,-CPU temperature,-CPU1 usage,-CPU2 usage,-CPU3 usage,-CPU4 usage,-CPU5 usage,-CPU6 usage,-CPU7 usage,-CPU8 usage,-CPU usage,-CPU1 clock,-CPU2 clock,-CPU3 clock,-CPU4 clock,-CPU5 clock,-CPU6 clock,-CPU7 clock,-CPU8 clock,-CPU clock,-CPU1 power,-CPU2 power,-CPU3 power,-CPU4 power,-CPU5 power,-CPU6 power,-CPU7 power,-CPU8 power,-CPU power,-RAM usage,-Commit charge,-GPU temperature,-FB usage,-VID usage,-BUS usage,-Core clock,-Memory clock,-Power percent,-Power,-GPU voltage,-Fan speed,-Fan speed 2,-Fan tachometer,-Fan tachometer 2,-Temp limit,-Power limit,-Voltage limit,-No load limit,-CPU9 temperature,-CPU10 temperature,-CPU11 temperature,-CPU12 temperature,-CPU13 temperature,-CPU14 temperature,-CPU15 temperature,-CPU16 temperature,-CPU9 usage,-CPU10 usage,-CPU11 usage,-CPU12 usage,-CPU13 usage,-CPU14 usage,-CPU15 usage,-CPU16 usage,-CPU9 clock,-CPU10 clock,-CPU11 clock,-CPU12 clock,-CPU13 clock,-CPU14 clock,-CPU15 clock,-CPU16 clock,-CPU9 power,-CPU10 power,-CPU11 power,-CPU12 power,-CPU13 power,-CPU14 power,-CPU15 power,-CPU16 power
[ATIADLHAL]
UnofficialOverclockingMode=0
UnofficialOverclockingDrvReset=1
UnifiedActivityMonitoring=0
EraseStartupSettings=0
[Source GPU usage]
ShowInOSD=0
ShowInLCD=0
ShowInTray=0
AlarmThresholdMin=
AlarmThresholdMax=
AlarmFlags=0
AlarmTimeout=5000
AlarmApp=
AlarmAppCmdLine=
EnableDataFiltering=0
MaxLimit=100
MinLimit=0
Group=
Name=
TrayTextColor=FF0000h
TrayIconType=0
OSDItemType=0
GraphColor=00FF00h
Formula=
[Source CPU5 temperature]
ShowInOSD=0
ShowInLCD=0
ShowInTray=0
AlarmThresholdMin=
AlarmThresholdMax=
AlarmFlags=0
AlarmTimeout=5000
AlarmApp=
AlarmAppCmdLine=
EnableDataFiltering=0
MaxLimit=100
MinLimit=0
Group=
Name=
TrayTextColor=FF0000h
TrayIconType=0
OSDItemType=0
GraphColor=00FF00h
Formula=
"@
Set-Content -Path "$env:C:\Program Files (x86)\MSI Afterburner\Profiles\MSIAfterburner.cfg" -Value $MultilineComment -Force

Move-Item "$env:appdata\Microsoft\Windows\Start Menu\Programs\MSI Afterburner\MSI Afterburner.lnk" "AppData\Roaming\Microsoft\Windows\Start Menu\Programs" -Force
Remove-Item "$env:appdata\Microsoft\Windows\Start Menu\Programs\MSI Afterburner" -Recurse -Force
Remove-Item "C:\Program Files (x86)\MSI Afterburner\Localization" -Recurse -Force
Remove-Item "C:\Program Files (x86)\MSI Afterburner\Doc" -Recurse -Force
Remove-Item "C:\Program Files (x86)\MSI Afterburner\Help" -Recurse -Force
Remove-Item "C:\Program Files (x86)\MSI Afterburner\SDK\Doc" -Recurse -Force
Remove-Item "C:\Program Files (x86)\MSI Afterburner\SDK\Localization" -Recurse -Force
Remove-Item "C:\Program Files (x86)\MSI Afterburner\Sound" -Recurse -Force
Get-ChildItem -Path "C:\Program Files (x86)\MSI Afterburner\Skins" -exclude MSICyborgWhite.usf -Recurse | Remove-Item -Recurse -Force
Get-ChildItem -Path "$env:temp" -include "MSI*", "guru3d*" -Recurse | Remove-Item -Recurse -Force
Remove-Item "C:\Users\$env:username\Desktop\MSI Afterburner.lnk" -Force

# Define the file path
$filePath = "C:\Windows\Maintenance.bat"

# Define the command to insert
$lineToInsert = 'start "" "C:\Program Files (x86)\MSI Afterburner\MSIAfterburner.exe" /Profile1 /Q'

# Define the line to insert before
$targetLine = 'exit'

# Read file content
$content = Get-Content -Path $filePath

# Exit if line already exists
if ($content -contains $lineToInsert) { return }

# Find the index to insert at
$insertIndex = $content.IndexOf($targetLine)

# Insert only if target line exists
if ($insertIndex -ge 0) {
    $linesToInsert = @(
        $lineToInsert,
        ''
    )
    $newContent = $content[0..($insertIndex - 1)] + $linesToInsert + $content[$insertIndex..($content.Count - 1)]
    Set-Content -Path $filePath -Value $newContent
}

New-Item -Path "$env:TEMP\Afterburner.status" -ItemType File -Force

exit
