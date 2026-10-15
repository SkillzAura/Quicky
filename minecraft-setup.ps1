# minecraft-setup.ps1
# Single-file silent deployer for Minecraft and Lunar Client settings

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
$ZipUrl = "https://github.com/SkillzAura/Quicky/releases/download/lan-setup/mc_config.zip"
$TempZip = "$env:TEMP\mc_config.zip"
$BackupDir = "$env:TEMP\mc_configs_backup"
$StatusOut = Join-Path ([Environment]::GetFolderPath("Desktop")) "MC-Setup-Status.txt"

$stepsOk   = New-Object System.Collections.Generic.List[string]$stepsFail = New-Object System.Collections.Generic.List[string]

function Add-OK([string]$s){ $stepsOk.Add($s) }
function Add-Fail([string]$s){ $stepsFail.Add($s) }

function Run-Step {
    param([string]$Name,[scriptblock]$Action)
    try { & $Action; Add-OK $Name } catch { Add-Fail "$Name :: $($_.Exception.Message)" }
}

# =========================
# Close apps first
# =========================
Run-Step "Force-close blocking games" {
    $kill = @("javaw", "Lunar Client", "lunarclient")
    foreach($p in $kill){ Get-Process -Name$p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
}

# =========================
# Download & Extract
# =========================
Run-Step "Download and extract mc_config.zip" {
    Invoke-WebRequest -Uri $ZipUrl -OutFile$TempZip -UseBasicParsing
    
    if (Test-Path $BackupDir) { Remove-Item -Path$BackupDir -Recurse -Force }
    Expand-Archive -Path $TempZip -DestinationPath$BackupDir -Force
}

# =========================
# Apply Settings
# =========================
Run-Step "Apply .minecraft settings" {
    $MinecraftPath = "$env:APPDATA\.minecraft"
    $SrcPath = "$BackupDir\mc\.minecraft"
    
    if (Test-Path $SrcPath) {
        if (!(Test-Path $MinecraftPath)) { New-Item -ItemType Directory -Path$MinecraftPath -Force | Out-Null }
        Copy-Item -Path "$SrcPath\*" -Destination $MinecraftPath -Force
    } else {
        throw "Source .minecraft folder not found in zip."
    }
}

Run-Step "Install Resource Packs" {
    $RPPath = "$env:APPDATA\.minecraft\resourcepacks"
    $SrcRP = "$BackupDir\mc\resourcepacks"
    
    if (Test-Path $SrcRP) {
        if (!(Test-Path $RPPath)) { New-Item -ItemType Directory -Path$RPPath -Force | Out-Null }
        Copy-Item -Path "$SrcRP\*" -Destination $RPPath -Recurse -Force
    } else {
        throw "Source resourcepacks folder not found in zip."
    }
}

Run-Step "Apply Lunar Settings" {
    $LunarGamePath = "$env:USERPROFILE\.lunarclient\settings\game"
    $SrcLunar = "$BackupDir\mc\lunar"
    
    if (Test-Path $SrcLunar) {
        if (Test-Path $LunarGamePath) {
            $ProfileDirs = Get-ChildItem -Path$LunarGamePath -Directory
            if ($ProfileDirs) {
                $TargetProfile =$ProfileDirs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                Copy-Item -Path "$SrcLunar\*" -Destination $TargetProfile.FullName -Recurse -Force
            } else {
                throw "No profile folders found."
            }
        } else {
            throw "Lunar settings folder not found."
        }
    } else {
        throw "Source lunar folder not found in zip."
    }
}

# =========================
# Cleanup
# =========================
Run-Step "Cleanup temporary ZIP" {
    if (Test-Path $TempZip) { Remove-Item -Path$TempZip -Force -ErrorAction SilentlyContinue }
}

# =========================
# Final short desktop status
# =========================
Run-Step "Write short desktop status file" {
    $final = New-Object System.Collections.Generic.List[string]$final.Add("Minecraft LAN Setup Completed")
    $final.Add("Backup stored at: $BackupDir")
    $final.Add("Successful: $($stepsOk.Count)")
    $final.Add("Failed: $($stepsFail.Count)")
    $final.Add("")
    $final.Add("[OK]")
    foreach ($ok in$stepsOk) { $final.Add("- $ok") }

    if ($stepsFail.Count -gt 0) {$final.Add("")
        $final.Add("[FAILED]")
        foreach ($fail in$stepsFail) { $final.Add("- $fail") }
    }
    Set-Content -Path $StatusOut -Value$final.ToArray() -Encoding UTF8
}

exit 0