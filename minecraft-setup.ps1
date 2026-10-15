# minecraft-setup.ps1
# Single-file silent deployer for Minecraft and Lunar Client settings
# Usage: iwr -useb https://raw.githubusercontent.com/SkillzAura/Quicky/main/minecraft-setup.ps1 | iex

$ScriptUrl = "https://raw.githubusercontent.com/SkillzAura/Quicky/main/minecraft-setup.ps1"

# =========================
# Admin Elevation (works for both file and iwr | iex)
# =========================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')
if (-not $isAdmin) {
    if ($PSCommandPath) {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        $argList = "-NoProfile -ExecutionPolicy Bypass -Command `"iwr -useb $ScriptUrl | iex`""
    }
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
}

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# =========================
# Paths and Status
# =========================
$ZipUrl    = "https://github.com/SkillzAura/Quicky/releases/download/Minecraft/mc_config.zip"
$TempZip   = Join-Path $env:TEMP "mc_config.zip"
$BackupDir = Join-Path $env:TEMP "mc_configs_backup"
$StatusOut = Join-Path ([Environment]::GetFolderPath("Desktop")) "MC-Setup-Status.txt"

$stepsOk   = New-Object System.Collections.Generic.List[string]
$stepsFail = New-Object System.Collections.Generic.List[string]

function Add-OK([string]$s)   { $stepsOk.Add($s) }
function Add-Fail([string]$s) { $stepsFail.Add($s) }

function Run-Step {
    param([string]$Name, [scriptblock]$Action)
    try { & $Action; Add-OK $Name } catch { Add-Fail "$Name :: $($_.Exception.Message)" }
}

# =========================
# Close apps first
# =========================
Run-Step "Force-close blocking games" {
    $kill = @("javaw", "Lunar Client", "lunarclient")
    foreach ($p in $kill) {
        Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

# =========================
# Download & Extract (copies kept in %TEMP% for manual fixing)
# =========================
Run-Step "Download and extract mc_config.zip" {
    Invoke-WebRequest -Uri $ZipUrl -OutFile $TempZip -UseBasicParsing

    if (Test-Path $BackupDir) { Remove-Item -Path $BackupDir -Recurse -Force }
    Expand-Archive -Path $TempZip -DestinationPath $BackupDir -Force
}

# =========================
# Apply Settings
# =========================
Run-Step "Apply .minecraft settings" {
    $MinecraftPath = Join-Path $env:APPDATA ".minecraft"
    $SrcPath = Join-Path $BackupDir "mc\.minecraft"

    if (Test-Path $SrcPath) {
        if (!(Test-Path $MinecraftPath)) { New-Item -ItemType Directory -Path $MinecraftPath -Force | Out-Null }
        Copy-Item -Path "$SrcPath\*" -Destination $MinecraftPath -Recurse -Force
    } else {
        throw "Source .minecraft folder not found in zip."
    }
}

Run-Step "Install Resource Packs" {
    $RPPath = Join-Path $env:APPDATA ".minecraft\resourcepacks"
    $SrcRP  = Join-Path $BackupDir "mc\resourcepacks"

    if (Test-Path $SrcRP) {
        if (!(Test-Path $RPPath)) { New-Item -ItemType Directory -Path $RPPath -Force | Out-Null }
        Copy-Item -Path "$SrcRP\*" -Destination $RPPath -Recurse -Force
    } else {
        throw "Source resourcepacks folder not found in zip."
    }
}

Run-Step "Apply Lunar Settings" {
    $LunarGamePath = Join-Path $env:USERPROFILE ".lunarclient\settings\game"
    $SrcLunar = Join-Path $BackupDir "mc\lunar"

    if (!(Test-Path $SrcLunar))      { throw "Source lunar folder not found in zip." }
    if (!(Test-Path $LunarGamePath)) { throw "Lunar settings folder not found: $LunarGamePath" }

    # Pick ONE profile folder (profile*, most recently modified); fall back to any folder
    $ProfileDirs = Get-ChildItem -Path $LunarGamePath -Directory
    $Candidates  = $ProfileDirs | Where-Object { $_.Name -like "profile*" }
    if (!$Candidates) { $Candidates = $ProfileDirs }
    if (!$Candidates) { throw "No profile folders found." }

    $TargetProfile = $Candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Copy-Item -Path "$SrcLunar\*" -Destination $TargetProfile.FullName -Recurse -Force
}

# =========================
# Final short desktop status
# =========================
Run-Step "Write short desktop status file" {
    $final = New-Object System.Collections.Generic.List[string]
    $final.Add("Minecraft LAN Setup Completed")
    $final.Add("Zip copy stored at: $TempZip")
    $final.Add("Extracted copy stored at: $BackupDir")
    $final.Add("Successful: $($stepsOk.Count)")
    $final.Add("Failed: $($stepsFail.Count)")
    $final.Add("")
    $final.Add("[OK]")
    foreach ($ok in $stepsOk) { $final.Add("- $ok") }

    if ($stepsFail.Count -gt 0) {
        $final.Add("")
        $final.Add("[FAILED]")
        foreach ($fail in $stepsFail) { $final.Add("- $fail") }
    }
    Set-Content -Path $StatusOut -Value $final.ToArray() -Encoding UTF8
}

Write-Host "Done. OK: $($stepsOk.Count)  Failed: $($stepsFail.Count)  (see Desktop\MC-Setup-Status.txt)"
Start-Sleep -Seconds 3
