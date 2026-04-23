If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) 
{	Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit	}

$ProgressPreference = 'SilentlyContinue'

# RW-Everything
$URL = "https://rweverything.com/downloads/RwPortableX64V1.7.zip"
$outFile = "$env:temp\RwPortableX64V1.7.zip"
(New-Object System.Net.WebClient).DownloadFile($URL, $outFile)

Expand-Archive "$outFile" -DestinationPath "$ENV:Temp\RwPortableX64V1.7" -Force
New-Item -Path "C:\Program Files" -Name "RW-Everything" -ItemType Directory -ErrorAction SilentlyContinue 
Move-Item "$env:temp\RwPortableX64V1.7\Win64\Portable\*" "C:\Program Files\RW-Everything" -Force
Remove-Item "$Env:Temp\RwPortable*" -Recurse -Force

$ShortcutPath = "C:\Program Files\RW-Everything\Rw.lnk" 
$TargetPath = "C:\Program Files\RW-Everything\Rw.exe"

$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $TargetPath
$Shortcut.WorkingDirectory = "C:\Program Files\RW-Everything"
$Shortcut.WindowStyle = 7  # 7 = Minimized
$Shortcut.Save()

# NvStrapsRebar
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\NvStrapsRebar"
$URL2            = "https://github.com/terminatorul/NvStrapsReBar/releases/latest/download/NvStrapsReBar.exe"
$outFile2        = "$folderPath\NvStrapsReBar.exe"
$urlShortcutPath = "$folderPath\NvStrapsReBar.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL2, $outFile2)

@"
[InternetShortcut]
URL=$URL2
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# Create Shortcut for Checking Resizeable Bar
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut("$folderPath\Check Resizeable Bar.lnk")
$shortcut.TargetPath = 'C:\Windows\Setup\Scripts\files\Softwares\GPU-Z\GPU-Z.exe'
$shortcut.Save()

# Cleanmgr+
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus"
$URL3            = "https://github.com/builtbybel/CleanmgrPlus/releases/latest/download/cleanmgrplus.zip"
$outFile3        = "$folderPath\cleanmgrplus.zip"
$urlShortcutPath = "$folderPath\Cleanmgr+.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL3, $outFile3)

Expand-Archive -Path $outFile3 -DestinationPath $folderPath -Force

@"
[InternetShortcut]
URL=$URL3
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath


Remove-Item "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\cleanmgrplus.zip" -Force
Remove-Item "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\scripts\Windows Downloads.csc" -Force

$MultilineComment = @"
[RunOnce]
RunOnce=1
DateRun=24.01.2022
[Settings]
CommandLineParamCleanmgr=Cleanmgr /sageset:1   
CustomCleaner=Path with Parameter
RunCleanmgr=0
AutomateCleanmgr=0
RunCustomCleaner=0
FinalTask=0
RunAlwaysInElevatedMode=1
EnableIEInDepthCleanup=0
UserFileHistoryAge=360
ShowDetailedPreview=1
AutoPreviewCleaner=1
ShowDescription=1
UIColorDefault=Dark (default)
[Items]
Scripts=-1;-1;-1;0;-1;0;0;-1;-1;0;0;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1
Windows=-1;-1;-1;-1;-1;-1;0;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;-1;0
[WindowState]
Left=-120
Top=-120
Height=15720
Width=29040
"@
Set-Content -Path "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\bin\cleanmgr+.ini" -Value $MultilineComment -Force

New-Item -ItemType "File" -Path "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\scripts\Brave Cache.csc" -Force
$MultilineComment = @"
[Info]
Title=Brave
Description=Clean-up Brave Cache
Author=Builtbybel
AuthorURL=http://www.builtbybel.com

[Files]
Task=TaskKill|brave.exe|WARNING
File1=DeleteDir|%LocalAppData%\BraveSoftware\Brave-Browser\User Data\Default\Cache
File2=DeleteDir|%LocalAppData%\BraveSoftware\Brave-Browser\User Data\Default\GPUCache
File3=DeleteDir|%LocalAppData%\BraveSoftware\Brave-Browser\User Data\Default\Service Worker
File4=DeleteDir|%LocalAppData%\BraveSoftware\Brave-Browser\User Data\ShaderCache
File5=DeleteDir|%LocalAppData%\BraveSoftware\Brave-Browser\User Data\Default\Code Cache
File6=DeleteDir|%LocalAppData%\BraveSoftware\Brave-Browser\User Data\GrShaderCache
File7=DeleteDir|%LocalAppData%\BraveSoftware\Brave-Browser\User Data\GraphiteDawnCache
File8=DeleteDir|%LocalAppData%\BraveSoftware\Brave-Browser\User Data\Default\DawnCache
File9=DeleteDir|%LocalAppData%\BraveSoftware\Brave-Browser\User Data\Greaselion\Temp
"@
Set-Content -Path "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\scripts\Brave Cache.csc" -Value $MultilineComment -Force

New-Item -ItemType "File" -Path "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\scripts\Discord.csc" -Force
$MultilineComment = @"
[Info]
Title=Discord
Description=Clean-up Discord
Author=Builtbybel
AuthorURL=http://www.builtbybel.com

[Files]
Task=TaskKill|discord.exe|WARNING
File1=DeleteDir|%LocalAppData%\Discord\$app$\modules\discord_cloudsync-1
File2=DeleteDir|%LocalAppData%\Discord\$app$\discord_dispatch-1
File3=DeleteDir|%LocalAppData%\Discord\$app$\discord_erlpack-1
File4=DeleteDir|%LocalAppData%\Discord\$app$\discord_game_utils-1
File5=DeleteDir|%LocalAppData%\Discord\$app$\discord_hook-1
File6=DeleteDir|%LocalAppData%\Discord\$app$\discord_krisp-1
File7=DeleteDir|%LocalAppData%\Discord\$app$\discord_overlay2-1
File8=DeleteDir|%LocalAppData%\Discord\$app$\discord_spellcheck-1
"@
Set-Content -Path "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\scripts\Discord.csc" -Value $MultilineComment -Force

New-Item -ItemType "File" -Path "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\scripts\Spotify Cache.csc" -Force
$MultilineComment = @"
[Info]
Title=Spotify
Description=Clean-up Spotify Cache
Author=Builtbybel
AuthorURL=http://www.builtbybel.com

[Files]
Task=TaskKill|spotify.exe|WARNING
File1=DeleteDir|%LocalAppData%\Spotify\Storage
File2=DeleteDir|%LocalAppData%\Spotify\Data
File3=DeleteDir|%LocalAppData%\Spotify\Browser\c43a0e624fb3e57b882f7f65a6a29fe32701363b\Cache
File4=DeleteDir|%LocalAppData%\Spotify\Browser\c43a0e624fb3e57b882f7f65a6a29fe32701363b\Code Cache
File5=DeleteDir|%LocalAppData%\Spotify\Browser\Cache
File6=DeleteDir|%LocalAppData%\Spotify\Browser\Code Cache
File7=DeleteDir|%LocalAppData%\Spotify\Browser\DawnCache
File8=DeleteDir|%LocalAppData%\Spotify\Browser\GPUCache
File9=DeleteFile|%AppData%\Spotify\Spotify.bak
"@
Set-Content -Path "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\scripts\Spotify Cache.csc" -Value $MultilineComment -Force

New-Item -ItemType "File" -Path "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\scripts\Valorant Logs.csc" -Force
$MultilineComment = @"
[Info]
Title=Valorant Logs
Description=Clean-up Valorant Cache
Author=Builtbybel
AuthorURL=http://www.builtbybel.com

[Files]
File1=DeleteFile|%LocalAppData%\VALORANT\Saved\Logs\*.log
File2=DeleteDir|%LocalAppData%\VALORANT\Saved\Config\CrashReportClient
File3=DeleteFile|%LocalAppData%\Riot Games\Install VALORANT\Logs\Agent\*.log
File4=DeleteFile|%LocalAppData%\Riot Games\Install VALORANT\Logs\Launcher\*.log
File5=DeleteFile|%LocalAppData%\Riot Games\Riot Client\Logs\Agent\*.log
File6=DeleteFile|%LocalAppData%\Riot Games\Riot Client\Logs\Launcher\*.log
File7=DeleteFile|%LocalAppData%\Riot Games\Riot Client\Logs\Riot Client Logs\*.log
File8=DeleteFile|%LocalAppData%\Riot Games\Riot Client\Logs\Riot Client UX Logs\*.log
File9=DeleteFile|%LocalAppData%\Riot Games\Riot Client\Logs\Riot Client UX Logs\RiotClient UX Renderer Logs\*.log
File10=DeleteFile|C:\Program Files\Riot Vanguard\Logs\*.log
"@
Set-Content -Path "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\scripts\Valorant Logs.csc" -Value $MultilineComment -Force

$MultilineComment = @"
[Info]
Title=Windows Shadow Copies
Description=Shadow Copy is a technology included in Microsoft Windows that can take manual or automatic backups of computer files and volumes, even when they are in use. This will clean-up the all Shadow Copies from all volumes.
Author=Builtbybel
AuthorURL=http://www.builtbybel.com
Warning=This will remove all Shadow Copies from all volumes.

[Files]
Task1=Exec|%WinDir%\SysNative\vssadmin delete shadows /all /quiet
"@
Set-Content -Path "C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\scripts\Windows Shadow Copies.csc" -Value $MultilineComment -Force

# Cleanmgr+ Shortcuts
$exePath     = 'C:\Windows\Setup\Scripts\files\Softwares\cleanmgrplus\Cleanmgr+.exe'
$wsh         = New-Object -ComObject WScript.Shell

# 1) User Start Menu Programs
$tweaksFolder = Join-Path $Env:AppData 'Microsoft\Windows\Start Menu\Programs\_Tweaks'
if (-not (Test-Path $tweaksFolder)) {
    New-Item -ItemType Directory -Path $tweaksFolder -Force
}
$sc1 = $wsh.CreateShortcut( (Join-Path $tweaksFolder 'Cleanmgr+.lnk') )
$sc1.TargetPath       = $exePath
$sc1.WorkingDirectory = Split-Path $exePath
$sc1.IconLocation     = "$exePath,0"
$sc1.Save()

# 2) User Pinned Start Menu
$pinnedFolder = Join-Path $Env:AppData 'Microsoft\Internet Explorer\Quick Launch\User Pinned\StartMenu'
if (-not (Test-Path $pinnedFolder)) {
    New-Item -ItemType Directory -Path $pinnedFolder -Force
}
$sc2 = $wsh.CreateShortcut( (Join-Path $pinnedFolder 'Cleanmgr+.lnk') )
$sc2.TargetPath       = $exePath
$sc2.WorkingDirectory = Split-Path $exePath
$sc2.IconLocation     = "$exePath,0"
$sc2.Save()

# CRU
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\CRU"
$urlMain         = "https://www.monitortests.com/download/cru/cru-1.5.2.zip"
$outMain         = Join-Path $folderPath "cru-1.5.2.zip"
$shortcutPath    = Join-Path $folderPath "CRU.url"

# Prepare folders
if (-not (Test-Path $folderPath)) {
    New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
}

# Download and extract main CRU
(New-Object System.Net.WebClient).DownloadFile($urlMain, $outMain)
Expand-Archive -Path $outMain -DestinationPath $folderPath -Force
Get-ChildItem $folderPath -Include "*.zip","*.txt","restart.exe" -Recurse | Remove-Item -Force -Recurse
@"  
[InternetShortcut]
URL=$urlMain
"@ | Set-Content -Encoding ASCII -Path $shortcutPath

# Download and extract All CRU Profiles from GitHub Releases
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/SkillzAura/CRUProfiles/releases"

foreach ($release in $releases) {
    foreach ($asset in $release.assets) {
        if ($asset.name.EndsWith(".zip")) {
            $tempZip = Join-Path $env:TEMP $asset.name
            (New-Object System.Net.WebClient).DownloadFile($asset.browser_download_url, $tempZip)
            Expand-Archive -Path $tempZip -DestinationPath $folderPath -Force
            Remove-Item $tempZip -Force
        }
    }
}

# Shortcut
$exePath      = 'C:\Windows\Setup\Scripts\files\Softwares\CRU\cru.exe'
$tweaksFolder = Join-Path $Env:AppData 'Microsoft\Windows\Start Menu\Programs\_Tweaks'

if (-not (Test-Path $tweaksFolder)) {
    New-Item -ItemType Directory -Path $tweaksFolder -Force
}

$shortcutLocation = Join-Path $tweaksFolder 'CRU.lnk'
$wsh              = New-Object -ComObject WScript.Shell
$sc               = $wsh.CreateShortcut($shortcutLocation)

$sc.TargetPath       = $exePath
$sc.WorkingDirectory = Split-Path $exePath
$sc.IconLocation     = "$exePath,0"
$sc.Save()

# GPU-Z
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\GPU-Z"
$URL5            = "https://ftp.nluug.nl/pub/games/PC/guru3d/generic/GPU-Z-[Guru3D.com].zip"
$outFile5        = "$folderPath\GPU-Z.zip"
$tempExtractPath = "$env:TEMP\GPU-Z"
$urlShortcutPath = "$folderPath\GPU-Z.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL5, $outFile5)

Expand-Archive -Path $outFile5 -DestinationPath $tempExtractPath -Force

$exe = Get-ChildItem -Path $tempExtractPath -Filter "GPU-Z*.exe" | Select-Object -First 1
if ($exe) {
    Move-Item -Path $exe.FullName -Destination "$folderPath\GPU-Z.exe" -Force
}

Remove-Item -Path $outFile5 -Force
Remove-Item -Path $tempExtractPath -Recurse -Force

# Standalone Mode
reg add "HKCU\Software\techPowerUp\GPU-Z" /v Install_Dir /t REG_SZ /d "no" /f

@"
[InternetShortcut]
URL=$URL5
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath


# DeviceCleanUpCmd
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\DeviceCleanupCmd"
$URL6            = "https://www.uwe-sieber.de/files/DeviceCleanupCmd.zip"
$outFile6        = "$folderPath\DeviceCleanupCmd.zip"
$urlShortcutPath = "$folderPath\DeviceCleanupCmd.url"

# 1) ensure folder exists
if (-not (Test-Path $folderPath)) {
    New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
}

# 2) download & extract
(New-Object System.Net.WebClient).DownloadFile($URL6, $outFile6)
Expand-Archive -Path $outFile6 -DestinationPath $folderPath -Force

# 3) drop the ZIP
Remove-Item -Path "$folderPath\*.zip" -Force

# 4) remove everything except the EXE and the .url
Remove-Item -Path "$folderPath\*" `
            -Recurse `
            -Force `
            -Exclude "DeviceCleanupCmd.exe","*.url"

# 5) recreate your .url shortcut
@"
[InternetShortcut]`r`n
URL=$URL6
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# 6) create a Start-up shortcut
$exePath          = Join-Path $folderPath 'DeviceCleanupCmd.exe'
$shortcutLocation = Join-Path "$env:AppData\Microsoft\Windows\Start Menu\Programs\Startup" 'DeviceCleanup.lnk'
$wsh              = New-Object -ComObject WScript.Shell
$sc               = $wsh.CreateShortcut($shortcutLocation)
$sc.TargetPath    = $exePath
$sc.Arguments     = 'SWD\* SW\{* -s -n *'
$sc.WorkingDirectory = $folderPath
$sc.IconLocation  = "$exePath,0"
$sc.WindowStyle   = 7
$sc.Save()

# GoInterruptPolicy
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\GoInterruptPolicy"
$URL7            = "https://github.com/spddl/GoInterruptPolicy/releases/latest/download/GoInterruptPolicy.exe"
$outFile7        = "$folderPath\GoInterruptPolicy.exe"
$urlShortcutPath = "$folderPath\GoInterruptPolicy.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL7, $outFile7)

@"
[InternetShortcut]
URL=$URL7
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# Shortcut
$exePath      = 'C:\Windows\Setup\Scripts\files\Softwares\GoInterruptPolicy\GoInterruptPolicy.exe'
$tweaksFolder = Join-Path $Env:AppData 'Microsoft\Windows\Start Menu\Programs\_Tweaks'

if (-not (Test-Path $tweaksFolder)) {
    New-Item -ItemType Directory -Path $tweaksFolder -Force
}

$shortcutLocation = Join-Path $tweaksFolder 'GoInterruptPolicy.lnk'
$wsh              = New-Object -ComObject WScript.Shell
$sc               = $wsh.CreateShortcut($shortcutLocation)

$sc.TargetPath       = $exePath
$sc.WorkingDirectory = Split-Path $exePath
$sc.IconLocation     = "$exePath,0"
$sc.Save()


# APPxPackageManager
$folderPath = "C:\Windows\Setup\Scripts\files\Softwares\AppxPackagesManager"
$outFile9 = "$folderPath\AppxPackagesManager.exe"
$URL9 = "https://github.com/valleyofdoom/AppxPackagesManager/releases/latest/download/AppxPackagesManager.exe"
$urlShortcutPath = "$folderPath\AppxPackagesManager.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL9, $outFile9)

@"
[InternetShortcut]
URL=$URL9
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# Shortcut
$exePath       = 'C:\Windows\Setup\Scripts\files\Softwares\AppxPackagesManager\AppxPackagesManager.exe'
$tweaksFolder  = Join-Path $Env:AppData 'Microsoft\Windows\Start Menu\Programs\_Tweaks'

if (-not (Test-Path $tweaksFolder)) {
    New-Item -ItemType Directory -Path $tweaksFolder -Force
}

$shortcutLocation = Join-Path $tweaksFolder 'AppxPackagesManager.lnk'
$wsh              = New-Object -ComObject WScript.Shell
$sc               = $wsh.CreateShortcut($shortcutLocation)

$sc.TargetPath       = $exePath
$sc.WorkingDirectory = Split-Path $exePath
$sc.IconLocation     = "$exePath,0"
$sc.Save()

# RevoUninstaller
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\Revo Uninstaller\x64"
$URL10           = "https://download.revouninstaller.com/download/RevoUninstaller_Portable.zip"
$tempZipPath     = "$env:Temp\RevoUninstaller_Portable.zip"
$tempExtractPath = "$env:Temp\RevoUninstaller_Portable"
$outExePath      = "$folderPath\RevoUn.exe"
$urlShortcutPath = "$folderPath\RevoUninstaller.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL10, $tempZipPath)

Expand-Archive -Path $tempZipPath -DestinationPath $tempExtractPath -Force

Move-Item "$tempExtractPath\RevoUninstaller_Portable\x64\RevoUn.exe" $outExePath -Force

Remove-Item -Path $tempExtractPath, $tempZipPath -Recurse -Force

@"
[InternetShortcut]
URL=$URL10
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# Create Shortcut in StartMenu
$startMenuPrograms = Join-Path $env:AppData 'Microsoft\Windows\Start Menu\Programs'
if (-not (Test-Path $startMenuPrograms)) {
    New-Item -ItemType Directory -Path $startMenuPrograms -Force | Out-Null
}
$shortcutPath = Join-Path $startMenuPrograms 'Revo Uninstaller.lnk'
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $outExePath
$shortcut.WorkingDirectory = $folderPath
$shortcut.IconLocation = $outExePath
$shortcut.Description = 'Launch Revo Uninstaller Portable'
$shortcut.Save()

# Create Settings File
$targetDir = 'C:\Windows\Setup\Scripts\files\Softwares\Revo Uninstaller'
if (-not (Test-Path $targetDir)) {
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
}

$settingsfile = @'
[General\]
Language file=english.ini
WebLang=ENG
SC=1
AdIconPath=
AdButCaption=Upgrade to Pro
AdButLink=https://www.revouninstaller.com/frpromo/
AU on startup=0
AdStatus=Download our Android App
AdStatusLink=https://www.revouninstaller.com/revo-uninstaller-mobile-qr-and-link/
Last Update Check=20-2-2024
Skip Info=0
Skip Warn=0
[View\]
Small Icons=0
Show Text=1
Small Icons in Details=0
[Uninstaller\]
ViewType=2
Show System Updates=0
Show System Components=0
FastLoadMode=0
Use Reg Install Date=0
Create System Restore Pont=0
Disable scan after uninstall=0
Maximize uninstall wizard=0
Select leftovers by default=1
StopRunExe=1
DelToBin=1
Sort by column=0
Sort type=1
[Junk Files\General\]
Delete to bin=0
Ignore last 24 fours=1
[Uninstaller\RegExclude]
HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID=4
HKEY_CURRENT_USER\*\SOFTWARE\Classes\CLSID=4
HKEY_LOCAL_MACHINE\SOFTWARE\Classes\TypeLib=4
HKEY_CURRENT_USER\*\SOFTWARE\Classes\TypeLib=4
HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Interface=4
HKEY_CURRENT_USER\*\SOFTWARE\Classes\Interface=4
HKEY_LOCAL_MACHINE\SOFTWARE\Classes\AppID=4
HKEY_CURRENT_USER\*\SOFTWARE\Classes\AppID=4
HKEY_LOCAL_MACHINE\SOFTWARE\Classes=4
HKEY_CURRENT_USER\*\SOFTWARE\Classes=4
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall=4
HKEY_CURRENT_USER\*\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall=4
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services=4
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum=4
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control=4
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Shell=12
HKEY_CURRENT_USER\*\SOFTWARE\Microsoft\Windows\Shell=12
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\ShellNoRoam=12
HKEY_CURRENT_USER\*\SOFTWARE\Microsoft\Windows\ShellNoRoam=12
[Uninstaller\FolderExclude]
%LocalAppData%\.minecraft=1
[Junk Files\General\Extensions]
*.tmp=1
*.temp=1
*.old=1
*.gid=1
*.fts=1
*.$$$=1
*.---=1
*.??$=1
*.___=1
*.~mp=1
*._mp=1
*.$db=1
*.db$=1
*.dmp=1
thumbs.db=1
~*.*=1
*.??~=1
[Junk Files\Exclude\]
*/sendto/=1
*/i386/=1
*/resources/themes/=1
*/temporary internet files/=1
*/application data/aim/=1
*/system32/usmt/=1
*/system32/dtclog/=1
*/norton antivirus/quarantine/=1
*/temp/incredimail/=1
%CommonProgramFiles%/=1
%ProgramFiles%/uninstall information/=1
%windir%/security/=1
?:/recycle?/=1
?:/_restore/=1
?:/system volume information/=1
*/system32/catroot2/=1
*/symantec shared/virusdefs/=1
*/paprport/data/=1
*/chaos32/=1
*/microsoft/money/webcache/=1
*/microsoft/office/data/=1
*/microsoft publisher/pagewiz/=1
*/application data/microsoft/=1
?:/$recycle*/=1
*.~enc=1
%windir%/twain_32/=1
%CommonProgramFiles(x86)%/=1
%ProgramFiles(x86)%/uninstall information/=1
%windir%/system32/catroot/=1
%windir%/ServiceProfiles/LocalService/AppData/Local/FontCache/=1
%LocalAppData%\.minecraft=1
'@
$settingsfile | Out-File 'C:\Windows\Setup\Scripts\files\Softwares\Revo Uninstaller\settings.ini' -Encoding ASCII -Force

# Autoruns
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\Autoruns"
$URL11           = "https://download.sysinternals.com/files/Autoruns.zip"
$outFile11       = "$folderPath\Autoruns.zip"
$urlShortcutPath = "$folderPath\Autoruns.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL11, $outFile11)

Expand-Archive -Path $outFile11 -DestinationPath $folderPath

Get-ChildItem -Path $folderPath -Exclude "Autoruns64.exe","*.url" -Recurse |
    Remove-Item -Force -Recurse

@"
[InternetShortcut]
URL=$URL11
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

reg add "HKEY_CURRENT_USER\Software\Sysinternals\Autoruns" /v "EulaAccepted" /t REG_DWORD /d "1" /f
reg add "HKEY_CURRENT_USER\Software\Sysinternals\Autoruns" /v "Theme" /t REG_SZ /d "DarkTheme" /f

# Autoruns Shortcut
$exePath       = Join-Path 'C:\Windows\Setup\Scripts\files\Softwares\Autoruns' 'Autoruns64.exe'

# 1) User Start Menu
$startMenu     = Join-Path $Env:AppData 'Microsoft\Windows\Start Menu\Programs\_Tweaks'
if (-not (Test-Path $startMenu)) {
    New-Item -ItemType Directory -Path $startMenu -Force
}
$shortcut1     = Join-Path $startMenu 'Autoruns.lnk'
$wsh           = New-Object -ComObject WScript.Shell
$sc            = $wsh.CreateShortcut($shortcut1)
$sc.TargetPath       = $exePath
$sc.WorkingDirectory = Split-Path $exePath
$sc.IconLocation     = "$exePath,0"
$sc.Save()

# 2) User Pinned Start Menu
$pinnedStart   = Join-Path $Env:AppData 'Microsoft\Internet Explorer\Quick Launch\User Pinned\StartMenu'
if (-not (Test-Path $pinnedStart)) {
    New-Item -ItemType Directory -Path $pinnedStart -Force
}
$shortcut2     = Join-Path $pinnedStart 'Autoruns.lnk'
$sc            = $wsh.CreateShortcut($shortcut2)
$sc.TargetPath       = $exePath
$sc.WorkingDirectory = Split-Path $exePath
$sc.IconLocation     = "$exePath,0"
$sc.Save()


# HWInfo
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\HWInfo"
$URL12           = "https://sourceforge.net/projects/hwinfo/files/latest/download"
$outFile12       = "$folderPath\HWInfo.zip"
$urlShortcutPath = "$folderPath\HWInfo.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL12, $outFile12)

Expand-Archive -Path $outFile12 -DestinationPath $folderPath -Force

Get-ChildItem -Path $folderPath -Exclude "HWiNFO64.exe","*.url" -Recurse |
    Remove-Item -Force -Recurse

@"
[InternetShortcut]
URL=$URL12
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

New-Item -ItemType "File" -Path "C:\Windows\Setup\Scripts\files\Softwares\HWInfo\HWiNFO64.INI" -Force

$MultilineComment = @"
[Settings]
Theme=1
AutoUpdateBetaDisable=1
AutoUpdate=0
SensorsOnly=1
ShowWelcomeAndProgress=0
"@
Set-Content -Path "C:\Windows\Setup\Scripts\files\Softwares\HWInfo\HWiNFO64.INI" -Value $MultilineComment -Force

# Create Shortcut
$extractPath = "C:\Windows\Setup\Scripts\files\Softwares\HWInfo"
$exePath = Join-Path $extractPath 'HWiNFO64.exe'
$shortcutLocation = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\HWInfo.lnk"
$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($shortcutLocation)
$sc.TargetPath = $exePath
$sc.WorkingDirectory = $extractPath
$sc.IconLocation = "$exePath,0"
$sc.Save()

$userPinnedFolder = Join-Path $Env:AppData 'Microsoft\Internet Explorer\Quick Launch\User Pinned\StartMenu'
if (-not (Test-Path $userPinnedFolder)) {
    New-Item -ItemType Directory -Path $userPinnedFolder -Force
}

$exePath         = 'C:\Windows\Setup\Scripts\files\Softwares\HWInfo\HWiNFO64.exe'
$pinnedShortcut  = Join-Path $userPinnedFolder 'HWInfo.lnk'
$wsh             = New-Object -ComObject WScript.Shell
$sc              = $wsh.CreateShortcut($pinnedShortcut)

$sc.TargetPath       = $exePath
$sc.WorkingDirectory = 'C:\Windows\Setup\Scripts\files\Softwares\HWInfo'
$sc.IconLocation     = "$exePath,0"
$sc.Save()

# USB Tree View
$folderPath = "C:\Windows\Setup\Scripts\files\Softwares\UsbTreeView"
$URL13 = "https://www.uwe-sieber.de/files/UsbTreeView_x64.zip"
$outFile13 = "$folderPath\UsbTreeView.zip"
$tempExtractPath = "$env:Temp\UsbTreeView"
$urlShortcutPath = "$folderPath\UsbTreeView.url"

# Ensure directory exists
if (!(Test-Path -Path $folderPath)) {
    New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
}

# Download the file
Invoke-WebRequest -Uri $URL13 -OutFile $outFile13

# Extract to temp folder
Expand-Archive -Path $outFile13 -DestinationPath $tempExtractPath -Force

# Locate the .exe dynamically within the extracted files
$exeFile = Get-ChildItem -Path $tempExtractPath -Filter "UsbTreeView.exe" -Recurse | Select-Object -First 1

if ($exeFile) {
    Move-Item -Path $exeFile.FullName -Destination "$folderPath\UsbTreeView.exe" -Force
}

# Clean up temp files
Remove-Item -Path $tempExtractPath -Recurse -Force
Remove-Item -Path $outFile13 -Force

# Remove any other junk left under $folderPath
Get-ChildItem -Path $folderPath -Recurse |
    Where-Object { $_.Extension -notin ".exe", ".url" } |
    Remove-Item -Recurse -Force

# Create the .url shortcut
@"
[InternetShortcut]
URL=$URL13
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# Serviwin
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\Serviwin"
$URL14           = "https://www.nirsoft.net/utils/serviwin-x64.zip"
$tempZipPath     = "$env:Temp\serviwin-x64.zip"
$outExePath      = "$folderPath\serviwin.exe"
$urlShortcutPath = "$folderPath\Serviwin.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL14, $tempZipPath)

Expand-Archive -Path $tempZipPath -DestinationPath $env:Temp -Force

Move-Item "$env:Temp\serviwin.exe" $outExePath -Force

Remove-Item "$env:Temp\serviwin*" -Recurse -Force

@"
[InternetShortcut]
URL=$URL14
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# RegistryChangesView
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\RegistryChangesView"
$URL15           = "https://www.nirsoft.net/utils/registrychangesview-x64.zip"
$tempZipPath     = "$env:Temp\registrychangesview-x64.zip"
$tempExtractPath = "$env:Temp\RegistryChangesView"
$outExePath      = "$folderPath\RegistryChangesView.exe"
$urlShortcutPath = "$folderPath\RegistryChangesView.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL15, $tempZipPath)

Expand-Archive -Path $tempZipPath -DestinationPath $tempExtractPath -Force

Move-Item "$tempExtractPath\RegistryChangesView.exe" $outExePath -Force

Remove-Item -Path $tempExtractPath,$tempZipPath -Recurse -Force

@"
[InternetShortcut]
URL=$URL15
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# WizTree
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\WizTree"
$response        = Invoke-WebRequest -Uri "https://diskanalyzer.com/download" -UseBasicParsing
if ($response.Content -match 'href="files/wiztree_(\d+_\d+)_portable.zip"') {
    $version      = $matches[1]
    $portableLink = "https://diskanalyzer.com/files/wiztree_${version}_portable.zip"
    $outputFile   = "$folderPath\wiztree_${version}_portable.zip"
    $urlShortcut  = "$folderPath\WizTree.url"

    if (!(Test-Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
    }

    Invoke-WebRequest -Uri $portableLink -OutFile $outputFile
    Expand-Archive -Path $outputFile -DestinationPath $folderPath -Force
    Remove-Item $outputFile -Force

    Get-ChildItem $folderPath |
        Where-Object { $_.Name -ne 'WizTree64.exe' -and $_.Extension -ne '.url' } |
        Remove-Item -Recurse -Force

    @"
[InternetShortcut]
URL=https://diskanalyzer.com/download
"@ | Set-Content -Encoding ASCII -Path $urlShortcut
}

# Create Shortcut in Programs
$shortcutLocation = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\WizTree.lnk"
$exePath          = Join-Path $folderPath 'WizTree64.exe'
$wsh              = New-Object -ComObject WScript.Shell
$sc               = $wsh.CreateShortcut($shortcutLocation)
$sc.TargetPath    = $exePath
$sc.WorkingDirectory = $folderPath
$sc.IconLocation     = "$exePath,0"
$sc.Save()

# Create Shortcut in Pinned Start Menu
$userPinnedFolder = Join-Path $Env:AppData 'Microsoft\Internet Explorer\Quick Launch\User Pinned\StartMenu'
if (-not (Test-Path $userPinnedFolder)) {
    New-Item -ItemType Directory -Path $userPinnedFolder -Force
}

$pinnedShortcut = Join-Path $userPinnedFolder 'WizTree.lnk'
$sc = $wsh.CreateShortcut($pinnedShortcut)
$sc.TargetPath       = $exePath
$sc.WorkingDirectory = $folderPath
$sc.IconLocation     = "$exePath,0"
$sc.Save()


# AnyDesk
$folderPath = "C:\Windows\Setup\Scripts\files\Softwares\AnyDesk"
$outFile16 = "$folderPath\AnyDesk.exe"
$URL16 = "https://download.anydesk.com/AnyDesk.exe"
$urlShortcutPath = "$folderPath\AnyDesk.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL16, $outFile16)

@"
[InternetShortcut]
URL=$URL16

"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath


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

(New-Object System.Net.WebClient).DownloadFile($URL17, $tempZipPath)

Expand-Archive -Path $tempZipPath -DestinationPath $tempExtractPath -Force

Move-Item "$tempExtractPath\DevManView.exe" $outExePath -Force

Remove-Item -Path "$tempExtractPath","$tempZipPath" -Recurse -Force

@"
[InternetShortcut]
URL=$URL17
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# Disable Devices
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "High Definition Audio Controller"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Composite Bus Enumerator"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Microsoft GS Wavetable Synth"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Microsoft Kernel Debug Network Adapter"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Generic USB Hub"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "WAN Miniport*" /use_wildcard
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Microsoft Hyper-V Virtualization Infrastructure Driver"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Microsoft Storage Spaces Controller"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Root Print Queue"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Microsoft Virtual Drive Enumerator"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "NDIS Virtual Network Adapter Enumerator"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "PCI Device"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Remote Desktop Device Redirector Bus"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Sonar APO"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "UMBus Root Bus Enumerator"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Generic USB Hub"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "Platform Security Processor"
cmd /c "C:\Windows\Setup\Scripts\files\Softwares\DevManView\DevManView.exe" /disable "*Host Controller - %3 (Microsoft);(NVIDIA*" /use_wildcard

# SnippingTool
$URL18       = "https://github.com/SkillzAura/SnippingTool/releases/latest/download/SnippingTool.zip"
$outFile18   = Join-Path $env:TEMP 'SnippingTool.zip'
(New-Object System.Net.WebClient).DownloadFile($URL18, $outFile18)

$extractDir  = Join-Path $env:TEMP 'snippingtool'
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
New-Item -ItemType Directory -Path $extractDir -Force
Expand-Archive -Path $outFile18 -DestinationPath $extractDir -Force
Remove-Item $outFile18 -Force

Move-Item -Path (Join-Path $extractDir 'SnippingTool.exe') `
          -Destination 'C:\Windows\System32\SnippingTool.exe' -Force

$muiSource   = Join-Path $extractDir 'SnippingTool.exe.mui'
$muiDestDir  = 'C:\Windows\System32\en-US'
if (-not (Test-Path $muiDestDir)) {
    New-Item -ItemType Directory -Path $muiDestDir -Force
}
$destMui     = Join-Path $muiDestDir 'SnippingTool.exe.mui'

& "C:\Windows\Setup\Scripts\files\MinSudo" --NoLogo --TrustedInstaller --Privileged Powershell -Command `
    "Move-Item -Path `"$muiSource`" -Destination `"$destMui`" -Force"

Remove-Item $extractDir -Recurse -Force

# Create Taskbar shortcut for SnippingTool
$exePath         = 'C:\Windows\System32\SnippingTool.exe'
$taskbarFolder   = Join-Path $Env:AppData 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
if (-not (Test-Path $taskbarFolder)) {
    New-Item -ItemType Directory -Path $taskbarFolder -Force
}
$shortcutLocation = Join-Path $taskbarFolder 'Snipping Tool.lnk'
$wsh              = New-Object -ComObject WScript.Shell
$sc               = $wsh.CreateShortcut($shortcutLocation)
$sc.TargetPath       = $exePath
$sc.WorkingDirectory = Split-Path $exePath
$sc.IconLocation     = "$exePath,0"
$sc.Save()

# StartAllBack License CMD
$folderPath      = "C:\Windows\Setup\Scripts\files\Softwares\StartAllBack License"
$URL19            = "https://github.com/WitherOrNot/StartXBack/releases/latest/download/startxback.cmd"
$outFile19        = "$folderPath\startxback.cmd"
$urlShortcutPath = "$folderPath\StartAllBack License CMD.url"

if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

(New-Object System.Net.WebClient).DownloadFile($URL19, $outFile19)

@"
[InternetShortcut]
URL=$URL19
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# xtw
$folderPath = "C:\Windows\Setup\Scripts\files\Softwares\xtw"
$URL20 = "https://github.com/valleyofdoom/xtw/releases/latest/download/xtw.zip"
$outFile20 = "$env:Temp\xtw.zip"
$tempExtractPath = "$env:Temp\xtw_temp"
$urlShortcutPath = "$folderPath\xtw.url"

# Ensure directory exists
if (!(Test-Path -Path $folderPath)) {
    $null = New-Item -ItemType Directory -Path $folderPath -Force
}

# Download the file to TEMP
Invoke-WebRequest -Uri $URL20 -OutFile $outFile20

# Extract to temp folder
Expand-Archive -Path $outFile20 -DestinationPath $tempExtractPath -Force

# Move the whole 'xtw' folder from the zip into the destination folder
# This creates the \xtw\xtw\ structure you want
$innerFolder = Get-ChildItem -Path $tempExtractPath | Where-Object { $_.PSIsContainer } | Select-Object -First 1
if ($innerFolder) {
    Move-Item -Path $innerFolder.FullName -Destination $folderPath -Force
}

# --- Create Shortcuts in the first xtw folder ---
$WshShell = New-Object -ComObject WScript.Shell

# 1. Shortcut for the .bat file
$batPath = "$folderPath\xtw\xtw_etl_collection.bat"
$batShortcut = $WshShell.CreateShortcut("$folderPath\Run ETL Collection.lnk")
$batShortcut.TargetPath = $batPath
$batShortcut.WorkingDirectory = "$folderPath\xtw"
$batShortcut.Save()

# 2. Shortcut for the .txt report
$txtPath = "$folderPath\xtw\xtw-report.txt"
$txtShortcut = $WshShell.CreateShortcut("$folderPath\Open xtw Report.lnk")
$txtShortcut.TargetPath = $txtPath
$txtShortcut.Save()

# 3. Create the .url shortcut
@"
[InternetShortcut]
URL=$URL20
"@ | Set-Content -Encoding ASCII -Path $urlShortcutPath

# Clean up temp files
Remove-Item -Path $tempExtractPath -Recurse -Force
Remove-Item -Path $outFile20 -Force

New-Item -Path "$env:TEMP\Softwares.status" -ItemType File -Force

exit