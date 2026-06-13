# Enhanced Brave Browser Installation Script for Hidden Execution
# Author: SkillzAura
# Date: 2025-07-17

# Admin elevation check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

# Configuration
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'  # Changed from 'Stop' to avoid false positives

# Setup logging to organized folder structure
$LogPath = "C:\ProgramData\Aura\OptimizationLogs"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$LogFile = Join-Path $LogPath "Brave-$(Get-Date -Format 'yyyy-MM-dd_hh-mm-ss-tt').log"

# Setup status file path
$StatusPath = "C:\ProgramData\Aura\StatusLogs"
if (!(Test-Path $StatusPath)) { New-Item -ItemType Directory -Path $StatusPath -Force | Out-Null }
$StatusFile = Join-Path $StatusPath "Brave.status"

# Initialize variables early to prevent null reference errors
$installerPath = $null
$tempRegFile = $null
$installationFailed = $false

# Logging function for file output
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
}

# Function to check if an error is a real failure
function Test-RealError {
    param([string]$ErrorMessage)
    
    # List of "success" error messages that should not be treated as failures
    $successMessages = @(
        "The operation completed successfully",
        "Operation completed successfully",
        "Success"
    )
    
    foreach ($msg in $successMessages) {
        if ($ErrorMessage -like "*$msg*") {
            return $false
        }
    }
    return $true
}

try {
    Write-Log "Starting Brave Browser installation process" "INFO"
    
    # Check internet connectivity
    Write-Log "Checking internet connection..." "INFO"
    try {
        $connection = Test-NetConnection -ComputerName "laptop-updates.brave.com" -Port 443 -InformationLevel Quiet -ErrorAction Stop
        if (-not $connection) {
            $installationFailed = $true
            throw "No internet connection or brave.com is unreachable"
        }
    } catch {
        $installationFailed = $true
        throw "Internet connectivity check failed: $($_.Exception.Message)"
    }
    
    # Download and install Brave
    Write-Log "Downloading Brave Browser installer..." "INFO"
    $installerPath = Join-Path $env:TEMP "BraveBrowserSetup.exe"
    
    try {
        Invoke-WebRequest "https://laptop-updates.brave.com/latest/winx64" -OutFile $installerPath -TimeoutSec 60 -ErrorAction Stop
    } catch {
        $installationFailed = $true
        throw "Download failed: $($_.Exception.Message)"
    }
    
    # Validate download
    $fileInfo = Get-Item $installerPath
    if ($fileInfo.Length -lt 1MB) {
        $installationFailed = $true
        throw "Downloaded file appears to be incomplete (size: $($fileInfo.Length) bytes)"
    }
    
    Write-Log "Downloaded: $($fileInfo.Name) ($('{0:N2}' -f ($fileInfo.Length / 1MB)) MB)" "SUCCESS"
    
    # Install Brave
    Write-Log "Installing Brave Browser..." "INFO"
    try {
        $process = Start-Process -FilePath $installerPath -Args "/silent /install" -Verb RunAs -Wait -PassThru -ErrorAction Stop
        
        if ($process.ExitCode -ne 0) {
            $installationFailed = $true
            throw "Installation failed with exit code: $($process.ExitCode)"
        }
    } catch {
        if (Test-RealError $_.Exception.Message) {
            $installationFailed = $true
            throw "Installation process failed: $($_.Exception.Message)"
        } else {
            Write-Log "Installation completed (ignoring success message interpreted as error)" "INFO"
        }
    }
    
    # Verify installation using the WOW6432Node registry path
    Start-Sleep -Seconds 3
    Write-Log "Verifying Brave installation..." "INFO"
    
    $braveInstalled = $false
    $braveVersion = "Unknown"
    
    # Check WOW6432Node registry path for Brave
    $braveRegPath = "HKLM:\SOFTWARE\WOW6432Node\BraveSoftware\Update"
    if (Test-Path $braveRegPath) {
        try {
            $braveUpdateInfo = Get-ItemProperty -Path $braveRegPath -ErrorAction SilentlyContinue
            if ($braveUpdateInfo) {
                $braveInstalled = $true
                # Try to get version from the update registry
                if ($braveUpdateInfo.PSObject.Properties.Name -contains "version") {
                    $braveVersion = $braveUpdateInfo.version
                }
                Write-Log "Brave Browser installation verified in WOW6432Node registry" "SUCCESS"
            }
        } catch {
            Write-Log "Registry check warning: $($_.Exception.Message)" "WARNING"
        }
    }
    
    # Fallback: Check standard installation path
    if (-not $braveInstalled) {
        $braveExePath = Join-Path $env:ProgramFiles "BraveSoftware\Brave-Browser\Application\brave.exe"
        if (Test-Path $braveExePath) {
            $braveInstalled = $true
            try {
                $braveVersion = (Get-ItemProperty -Path $braveExePath).VersionInfo.ProductVersion
            } catch {
                $braveVersion = "Installed"
            }
            Write-Log "Brave Browser installation verified by executable presence" "SUCCESS"
        }
    }
    
    if (-not $braveInstalled) {
        $installationFailed = $true
        throw "Installation verification failed - Brave Browser not found"
    }
    
    Write-Log "Brave Browser installed successfully: Version $braveVersion" "SUCCESS"
    
    # Post-installation configuration
    Write-Log "Configuring Brave Browser..." "INFO"
    
    # Disable Brave services
    Write-Log "Disabling Brave services..." "INFO"
    try {
        Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services" -Name -ErrorAction SilentlyContinue | 
            Where-Object { $_ -like "*Brave*" } | 
            ForEach-Object { 
                try {
                    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$_" -Name "Start" -Value 4 -ErrorAction SilentlyContinue
                    Write-Log "Disabled service: $_" "SUCCESS"
                } catch {
                    if (Test-RealError $_.Exception.Message) {
                        Write-Log "Failed to disable service: $_ - $($_.Exception.Message)" "WARNING"
                    }
                }
            }
    } catch {
        Write-Log "Service configuration warning: $($_.Exception.Message)" "WARNING"
    }
    
    # Apply registry configurations
    Write-Log "Applying registry configurations..." "INFO"
    try {
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave" /v "HardwareAccelerationModeEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave" /v "BackgroundModeEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave" /v "UrlKeyedAnonymizedDataCollectionEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave" /v "SafeBrowsingExtendedReportingEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave" /v "SpellCheckServiceEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave" /v "HighEfficiencyModeEnabled" /t REG_DWORD /d "1" /f >$null 2>&1
        reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "TorDisabled" /t REG_DWORD /d "1" /f >$null 2>&1
        reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BraveRewardsDisabled" /t REG_DWORD /d "1" /f >$null 2>&1
        reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BraveWalletDisabled" /t REG_DWORD /d "1" /f >$null 2>&1
        reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BraveVPNDisabled" /t REG_DWORD /d "1" /f >$null 2>&1
        reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BraveAIChatEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
        reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BraveNewsDisabled" /t REG_DWORD /d "1" /f >$null 2>&1
        reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BraveSpeedreaderEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
        reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BraveStatsPingEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
        reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BravePlaylistEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
	# Disables Brave Talk (The private video conferencing utility widget)
	reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BraveTalkDisabled" /t REG_DWORD /d "1" /f >$null 2>&1
	# Disables P3A (Privacy-Preserving Product Analytics diagnostic pings)
	reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BraveP3AEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
	# Disables the Web Discovery Project (Stops sending anonymous site data to build Brave Search indexes)
	reg add "HKLM\SOFTWARE\Policies\BraveSoftware\Brave" /v "BraveWebDiscoveryEnabled" /t REG_DWORD /d "0" /f >$null 2>&1
        Write-Log "Applied Brave registry configurations" "SUCCESS"
    } catch {
        Write-Log "Registry configuration warning: $($_.Exception.Message)" "WARNING"
    }
    
    # Remove Active Setup component
    Write-Log "Removing Active Setup component..." "INFO"
    try {
        reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Active Setup\Installed Components\{AFE6A462-C574-4B8A-AF43-4CC60DF4563B}" /f >$null 2>&1
        Write-Log "Removed Active Setup component" "SUCCESS"
    } catch {
        Write-Log "Active Setup component removal warning: $($_.Exception.Message)" "WARNING"
    }
    
    # Remove desktop shortcuts
    Write-Log "Removing desktop shortcuts..." "INFO"
    try {
        Remove-Item "C:\Users\Public\Desktop\Brave.lnk" -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Users\$env:username\Desktop\Brave.lnk" -Force -ErrorAction SilentlyContinue
        Write-Log "Removed desktop shortcuts" "SUCCESS"
    } catch {
        Write-Log "Desktop shortcut removal warning: $($_.Exception.Message)" "WARNING"
    }
    
    # Create taskbar shortcut
    Write-Log "Creating taskbar shortcut..." "INFO"
    $exePath = Join-Path $Env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe'
    $taskbarFolder = Join-Path $Env:AppData 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    $shortcutLocation = Join-Path $taskbarFolder 'Brave.lnk'
    
    try {
        if (-not (Test-Path $taskbarFolder)) {
            New-Item -ItemType Directory -Path $taskbarFolder -Force | Out-Null
        }
        
        $wsh = New-Object -ComObject WScript.Shell
        $sc = $wsh.CreateShortcut($shortcutLocation)
        $sc.TargetPath = $exePath
        $sc.WorkingDirectory = Split-Path $exePath
        $sc.IconLocation = "$exePath,0"
        $sc.Save()
        
        # Release COM object immediately
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wsh) | Out-Null
        $wsh = $null
        
        Write-Log "Created taskbar shortcut: $shortcutLocation" "SUCCESS"
    } catch {
        if (Test-RealError $_.Exception.Message) {
            Write-Log "Taskbar shortcut creation warning: $($_.Exception.Message)" "WARNING"
        } else {
            Write-Log "Taskbar shortcut created successfully" "SUCCESS"
        }
    }
    
    # Configure taskbar registry
    Write-Log "Configuring taskbar registry..." "INFO"
    try {
        reg delete "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" /f >$null 2>&1
        reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins" /f >$null 2>&1
        
        # Create and apply taskbar registry file
        $tempRegFile = Join-Path $env:TEMP "Brave.reg"
        $regContent = @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband]
"FavoritesResolve"=hex:3e,06,00,00,4c,00,00,00,01,14,02,00,00,00,00,00,c0,00,\
  00,00,00,00,00,46,81,00,80,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,\
  00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,01,00,00,00,\
  00,00,00,00,00,00,00,00,00,00,00,00,ec,05,14,00,1f,80,9b,d4,34,42,45,02,f3,\
  4d,b7,80,38,93,94,34,56,e1,d6,05,00,00,3e,05,41,50,50,53,2c,05,08,00,03,00,\
  00,00,00,00,00,00,68,02,00,00,31,53,50,53,55,28,4c,9f,79,9f,39,4b,a8,d0,e1,\
  d4,2d,e1,d5,f3,5d,00,00,00,11,00,00,00,00,1f,00,00,00,25,00,00,00,4d,00,69,\
  00,63,00,72,00,6f,00,73,00,6f,00,66,00,74,00,2e,00,53,00,63,00,72,00,65,00,\
  65,00,6e,00,53,00,6b,00,65,00,74,00,63,00,68,00,5f,00,38,00,77,00,65,00,6b,\
  00,79,00,62,00,33,00,64,00,38,00,62,00,62,00,77,00,65,00,00,00,00,00,11,00,\
  00,00,27,00,00,00,00,0b,00,00,00,ff,ff,00,00,11,00,00,00,0e,00,00,00,00,13,\
  00,00,00,02,00,00,00,11,00,00,00,19,00,00,00,00,13,00,00,00,01,00,00,00,81,\
  00,00,00,15,00,00,00,00,1f,00,00,00,37,00,00,00,4d,00,69,00,63,00,72,00,6f,\
  00,73,00,6f,00,66,00,74,00,2e,00,53,00,63,00,72,00,65,00,65,00,6e,00,53,00,\
  6b,00,65,00,74,00,63,00,68,00,5f,00,31,00,31,00,2e,00,32,00,35,00,31,00,30,\
  00,2e,00,33,00,31,00,2e,00,30,00,5f,00,78,00,36,00,34,00,5f,00,5f,00,38,00,\
  77,00,65,00,6b,00,79,00,62,00,33,00,64,00,38,00,62,00,62,00,77,00,65,00,00,\
  00,00,00,65,00,00,00,05,00,00,00,00,1f,00,00,00,29,00,00,00,4d,00,69,00,63,\
  00,72,00,6f,00,73,00,6f,00,66,00,74,00,2e,00,53,00,63,00,72,00,65,00,65,00,\
  6e,00,53,00,6b,00,65,00,74,00,63,00,68,00,5f,00,38,00,77,00,65,00,6b,00,79,\
  00,62,00,33,00,64,00,38,00,62,00,62,00,77,00,65,00,21,00,41,00,70,00,70,00,\
  00,00,00,00,b9,00,00,00,0f,00,00,00,00,1f,00,00,00,54,00,00,00,43,00,3a,00,\
  5c,00,50,00,72,00,6f,00,67,00,72,00,61,00,6d,00,20,00,46,00,69,00,6c,00,65,\
  00,73,00,5c,00,57,00,69,00,6e,00,64,00,6f,00,77,00,73,00,41,00,70,00,70,00,\
  73,00,5c,00,4d,00,69,00,63,00,72,00,6f,00,73,00,6f,00,66,00,74,00,2e,00,53,\
  00,63,00,72,00,65,00,65,00,6e,00,53,00,6b,00,65,00,74,00,63,00,68,00,5f,00,\
  31,00,31,00,2e,00,32,00,35,00,31,00,30,00,2e,00,33,00,31,00,2e,00,30,00,5f,\
  00,78,00,36,00,34,00,5f,00,5f,00,38,00,77,00,65,00,6b,00,79,00,62,00,33,00,\
  64,00,38,00,62,00,62,00,77,00,65,00,00,00,1d,00,00,00,20,00,00,00,00,48,00,\
  00,00,c6,8c,5e,1b,6e,f1,2f,46,b8,00,19,5f,42,5e,04,f2,00,00,00,00,19,02,00,\
  00,31,53,50,53,4d,0b,d4,86,69,90,3c,44,81,9a,2a,54,09,0d,cc,ec,51,00,00,00,\
  0c,00,00,00,00,1f,00,00,00,1f,00,00,00,41,00,73,00,73,00,65,00,74,00,73,00,\
  5c,00,53,00,6e,00,69,00,70,00,70,00,69,00,6e,00,67,00,54,00,6f,00,6f,00,6c,\
  00,4d,00,65,00,64,00,54,00,69,00,6c,00,65,00,2e,00,70,00,6e,00,67,00,00,00,\
  00,00,51,00,00,00,02,00,00,00,00,1f,00,00,00,1f,00,00,00,41,00,73,00,73,00,\
  65,00,74,00,73,00,5c,00,53,00,6e,00,69,00,70,00,70,00,69,00,6e,00,67,00,54,\
  00,6f,00,6f,00,6c,00,41,00,70,00,70,00,4c,00,69,00,73,00,74,00,2e,00,70,00,\
  6e,00,67,00,00,00,00,00,51,00,00,00,0d,00,00,00,00,1f,00,00,00,20,00,00,00,\
  41,00,73,00,73,00,65,00,74,00,73,00,5c,00,53,00,6e,00,69,00,70,00,70,00,69,\
  00,6e,00,67,00,54,00,6f,00,6f,00,6c,00,57,00,69,00,64,00,65,00,54,00,69,00,\
  6c,00,65,00,2e,00,70,00,6e,00,67,00,00,00,11,00,00,00,04,00,00,00,00,13,00,\
  00,00,00,78,d4,ff,11,00,00,00,05,00,00,00,00,13,00,00,00,ff,ff,ff,ff,55,00,\
  00,00,13,00,00,00,00,1f,00,00,00,21,00,00,00,41,00,73,00,73,00,65,00,74,00,\
  73,00,5c,00,53,00,6e,00,69,00,70,00,70,00,69,00,6e,00,67,00,54,00,6f,00,6f,\
  00,6c,00,4c,00,61,00,72,00,67,00,65,00,54,00,69,00,6c,00,65,00,2e,00,70,00,\
  6e,00,67,00,00,00,00,00,11,00,00,00,0e,00,00,00,00,13,00,00,00,a1,04,00,00,\
  2d,00,00,00,0b,00,00,00,00,1f,00,00,00,0e,00,00,00,53,00,6e,00,69,00,70,00,\
  70,00,69,00,6e,00,67,00,20,00,54,00,6f,00,6f,00,6c,00,00,00,55,00,00,00,14,\
  00,00,00,00,1f,00,00,00,21,00,00,00,41,00,73,00,73,00,65,00,74,00,73,00,5c,\
  00,53,00,6e,00,69,00,70,00,70,00,69,00,6e,00,67,00,54,00,6f,00,6f,00,6c,00,\
  53,00,6d,00,61,00,6c,00,6c,00,54,00,69,00,6c,00,65,00,2e,00,70,00,6e,00,67,\
  00,00,00,00,00,00,00,00,00,31,00,00,00,31,53,50,53,b1,16,6d,44,ad,8d,70,48,\
  a7,48,40,2e,a4,3d,78,8c,15,00,00,00,64,00,00,00,00,15,00,00,00,7d,04,00,00,\
  00,00,00,00,00,00,00,00,49,00,00,00,31,53,50,53,30,f1,25,b7,ef,47,1a,10,a5,\
  f1,02,60,8c,9e,eb,ac,2d,00,00,00,0a,00,00,00,00,1f,00,00,00,0e,00,00,00,53,\
  00,6e,00,69,00,70,00,70,00,69,00,6e,00,67,00,20,00,54,00,6f,00,6f,00,6c,00,\
  00,00,00,00,00,00,2d,00,00,00,31,53,50,53,b3,77,ed,0d,14,c6,6c,45,ae,5b,28,\
  5b,38,d7,b0,1b,11,00,00,00,07,00,00,00,00,13,00,00,00,00,00,00,00,00,00,00,\
  00,00,00,00,00,00,00,22,00,00,00,1e,00,ef,be,02,00,55,00,73,00,65,00,72,00,\
  50,00,69,00,6e,00,6e,00,65,00,64,00,00,00,44,05,12,00,00,00,2b,00,ef,be,81,\
  2f,52,a3,cf,ea,dc,01,44,05,5e,00,00,00,1d,00,ef,be,02,00,4d,00,69,00,63,00,\
  72,00,6f,00,73,00,6f,00,66,00,74,00,2e,00,53,00,63,00,72,00,65,00,65,00,6e,\
  00,53,00,6b,00,65,00,74,00,63,00,68,00,5f,00,38,00,77,00,65,00,6b,00,79,00,\
  62,00,33,00,64,00,38,00,62,00,62,00,77,00,65,00,21,00,41,00,70,00,70,00,00,\
  00,44,05,00,00,00,00,00,00,36,03,00,00,4c,00,00,00,01,14,02,00,00,00,00,00,\
  c0,00,00,00,00,00,00,46,83,00,80,00,20,00,00,00,27,21,c8,9f,cf,ea,dc,01,13,\
  53,c8,9f,cf,ea,dc,01,25,b3,7a,4d,05,84,da,01,97,01,00,00,00,00,00,00,01,00,\
  00,00,00,00,00,00,00,00,00,00,00,00,00,00,a4,01,3a,00,1f,80,c8,27,34,1f,10,\
  5c,10,42,aa,03,2e,e4,52,87,d6,68,26,00,01,00,26,00,ef,be,12,00,00,00,d2,8f,\
  be,05,13,90,dc,01,c2,a3,0e,17,cd,ea,dc,01,7d,77,6e,26,cd,ea,dc,01,14,00,56,\
  00,31,00,00,00,00,00,b7,5c,29,82,11,00,54,61,73,6b,42,61,72,00,40,00,09,00,\
  04,00,ef,be,3c,5c,32,28,b7,5c,29,82,2e,00,00,00,5c,0b,02,00,00,00,01,00,00,\
  00,00,00,00,00,00,00,00,00,00,00,00,00,75,57,56,00,54,00,61,00,73,00,6b,00,\
  42,00,61,00,72,00,00,00,16,00,12,01,32,00,97,01,00,00,81,58,c4,3a,20,00,46,\
  69,6c,65,20,45,78,70,6c,6f,72,65,72,2e,6c,6e,6b,00,7c,00,09,00,04,00,ef,be,\
  b7,5c,29,82,b7,5c,29,82,2e,00,00,00,ea,03,00,00,00,00,04,00,00,00,00,00,00,\
  00,00,00,52,00,00,00,00,00,db,dc,91,00,46,00,69,00,6c,00,65,00,20,00,45,00,\
  78,00,70,00,6c,00,6f,00,72,00,65,00,72,00,2e,00,6c,00,6e,00,6b,00,00,00,40,\
  00,73,00,68,00,65,00,6c,00,6c,00,33,00,32,00,2e,00,64,00,6c,00,6c,00,2c,00,\
  2d,00,32,00,32,00,30,00,36,00,37,00,00,00,20,00,22,00,00,00,1e,00,ef,be,02,\
  00,55,00,73,00,65,00,72,00,50,00,69,00,6e,00,6e,00,65,00,64,00,00,00,20,00,\
  12,00,00,00,2b,00,ef,be,bf,65,ce,9f,cf,ea,dc,01,20,00,42,00,00,00,1d,00,ef,\
  be,02,00,4d,00,69,00,63,00,72,00,6f,00,73,00,6f,00,66,00,74,00,2e,00,57,00,\
  69,00,6e,00,64,00,6f,00,77,00,73,00,2e,00,45,00,78,00,70,00,6c,00,6f,00,72,\
  00,65,00,72,00,00,00,20,00,00,00,9b,00,00,00,1c,00,00,00,01,00,00,00,1c,00,\
  00,00,2d,00,00,00,00,00,00,00,9a,00,00,00,11,00,00,00,03,00,00,00,0f,e8,53,\
  1c,10,00,00,00,00,43,3a,5c,55,73,65,72,73,5c,61,75,72,61,5c,41,70,70,44,61,\
  74,61,5c,52,6f,61,6d,69,6e,67,5c,4d,69,63,72,6f,73,6f,66,74,5c,49,6e,74,65,\
  72,6e,65,74,20,45,78,70,6c,6f,72,65,72,5c,51,75,69,63,6b,20,4c,61,75,6e,63,\
  68,5c,55,73,65,72,20,50,69,6e,6e,65,64,5c,54,61,73,6b,42,61,72,5c,46,69,6c,\
  65,20,45,78,70,6c,6f,72,65,72,2e,6c,6e,6b,00,00,60,00,00,00,03,00,00,a0,58,\
  00,00,00,00,00,00,00,64,65,73,6b,74,6f,70,2d,32,69,6f,74,70,61,68,00,0c,98,\
  11,1a,19,f4,c4,41,b5,71,ae,be,a7,b5,25,86,dc,f1,11,a6,c2,56,f1,11,8e,0f,08,\
  00,27,ec,51,e3,0c,98,11,1a,19,f4,c4,41,b5,71,ae,be,a7,b5,25,86,dc,f1,11,a6,\
  c2,56,f1,11,8e,0f,08,00,27,ec,51,e3,45,00,00,00,09,00,00,a0,39,00,00,00,31,\
  53,50,53,b1,16,6d,44,ad,8d,70,48,a7,48,40,2e,a4,3d,78,8c,1d,00,00,00,68,00,\
  00,00,00,48,00,00,00,91,95,13,40,25,c0,a9,48,a3,af,5c,f2,60,ca,03,cf,00,00,\
  00,00,00,00,00,00,00,00,00,00,c4,02,00,00,4c,00,00,00,01,14,02,00,00,00,00,\
  00,c0,00,00,00,00,00,00,46,83,00,80,00,20,00,00,00,51,73,6c,a8,cf,ea,dc,01,\
  51,73,6c,a8,cf,ea,dc,01,d7,ee,69,a8,cf,ea,dc,01,0c,09,00,00,00,00,00,00,01,\
  00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,3a,01,3a,00,1f,80,c8,27,34,1f,\
  10,5c,10,42,aa,03,2e,e4,52,87,d6,68,26,00,01,00,26,00,ef,be,12,00,00,00,d2,\
  8f,be,05,13,90,dc,01,c2,a3,0e,17,cd,ea,dc,01,7d,77,6e,26,cd,ea,dc,01,14,00,\
  56,00,31,00,00,00,00,00,b7,5c,30,82,11,00,54,61,73,6b,42,61,72,00,40,00,09,\
  00,04,00,ef,be,3c,5c,32,28,b7,5c,30,82,2e,00,00,00,5c,0b,02,00,00,00,01,00,\
  00,00,00,00,00,00,00,00,00,00,00,00,00,00,af,02,0e,00,54,00,61,00,73,00,6b,\
  00,42,00,61,00,72,00,00,00,16,00,a8,00,32,00,0c,09,00,00,b7,5c,30,82,20,00,\
  42,72,61,76,65,2e,6c,6e,6b,00,44,00,09,00,04,00,ef,be,b7,5c,30,82,b7,5c,30,\
  82,2e,00,00,00,ed,03,00,00,00,00,04,00,00,00,00,00,00,00,00,00,00,00,00,00,\
  00,00,29,87,10,00,42,00,72,00,61,00,76,00,65,00,2e,00,6c,00,6e,00,6b,00,00,\
  00,18,00,22,00,00,00,1e,00,ef,be,02,00,55,00,73,00,65,00,72,00,50,00,69,00,\
  6e,00,6e,00,65,00,64,00,00,00,18,00,12,00,00,00,2b,00,ef,be,77,1b,6d,a8,cf,\
  ea,dc,01,18,00,18,00,00,00,1d,00,ef,be,02,00,42,00,72,00,61,00,76,00,65,00,\
  00,00,18,00,00,00,93,00,00,00,1c,00,00,00,01,00,00,00,1c,00,00,00,2d,00,00,\
  00,00,00,00,00,92,00,00,00,11,00,00,00,03,00,00,00,0f,e8,53,1c,10,00,00,00,\
  00,43,3a,5c,55,73,65,72,73,5c,61,75,72,61,5c,41,70,70,44,61,74,61,5c,52,6f,\
  61,6d,69,6e,67,5c,4d,69,63,72,6f,73,6f,66,74,5c,49,6e,74,65,72,6e,65,74,20,\
  45,78,70,6c,6f,72,65,72,5c,51,75,69,63,6b,20,4c,61,75,6e,63,68,5c,55,73,65,\
  72,20,50,69,6e,6e,65,64,5c,54,61,73,6b,42,61,72,5c,42,72,61,76,65,2e,6c,6e,\
  6b,00,00,60,00,00,00,03,00,00,a0,58,00,00,00,00,00,00,00,64,65,73,6b,74,6f,\
  70,2d,32,69,6f,74,70,61,68,00,0c,98,11,1a,19,f4,c4,41,b5,71,ae,be,a7,b5,25,\
  86,e6,f1,11,a6,c2,56,f1,11,8e,0f,08,00,27,ec,51,e3,0c,98,11,1a,19,f4,c4,41,\
  b5,71,ae,be,a7,b5,25,86,e6,f1,11,a6,c2,56,f1,11,8e,0f,08,00,27,ec,51,e3,45,\
  00,00,00,09,00,00,a0,39,00,00,00,31,53,50,53,b1,16,6d,44,ad,8d,70,48,a7,48,\
  40,2e,a4,3d,78,8c,1d,00,00,00,68,00,00,00,00,48,00,00,00,91,95,13,40,25,c0,\
  a9,48,a3,af,5c,f2,60,ca,03,cf,00,00,00,00,00,00,00,00,00,00,00,00,24,03,00,\
  00,4c,00,00,00,01,14,02,00,00,00,00,00,c0,00,00,00,00,00,00,46,83,00,80,00,\
  20,00,00,00,5e,e6,09,b7,cf,ea,dc,01,8c,0f,0a,b7,cf,ea,dc,01,a0,ee,06,b7,cf,\
  ea,dc,01,35,07,00,00,00,00,00,00,01,00,00,00,00,00,00,00,00,00,00,00,00,00,\
  00,00,98,01,3a,00,1f,80,c8,27,34,1f,10,5c,10,42,aa,03,2e,e4,52,87,d6,68,26,\
  00,01,00,26,00,ef,be,12,00,00,00,d2,8f,be,05,13,90,dc,01,c2,a3,0e,17,cd,ea,\
  dc,01,7d,77,6e,26,cd,ea,dc,01,14,00,56,00,31,00,00,00,00,00,b7,5c,3d,82,11,\
  00,54,61,73,6b,42,61,72,00,40,00,09,00,04,00,ef,be,3c,5c,32,28,b7,5c,3d,82,\
  2e,00,00,00,5c,0b,02,00,00,00,01,00,00,00,00,00,00,00,00,00,00,00,00,00,00,\
  00,a2,d8,ef,00,54,00,61,00,73,00,6b,00,42,00,61,00,72,00,00,00,16,00,06,01,\
  32,00,35,07,00,00,b7,5c,3d,82,20,00,53,70,6f,74,69,66,79,2e,6c,6e,6b,00,48,\
  00,09,00,04,00,ef,be,b7,5c,3d,82,b7,5c,3d,82,2e,00,00,00,ff,00,00,00,00,00,\
  12,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,60,d0,f2,00,53,00,70,00,6f,\
  00,74,00,69,00,66,00,79,00,2e,00,6c,00,6e,00,6b,00,00,00,1a,00,22,00,00,00,\
  1e,00,ef,be,02,00,55,00,73,00,65,00,72,00,50,00,69,00,6e,00,6e,00,65,00,64,\
  00,00,00,1a,00,12,00,00,00,2b,00,ef,be,a3,a0,0a,b7,cf,ea,dc,01,1a,00,70,00,\
  00,00,1d,00,ef,be,02,00,43,00,3a,00,5c,00,55,00,73,00,65,00,72,00,73,00,5c,\
  00,61,00,75,00,72,00,61,00,5c,00,41,00,70,00,70,00,44,00,61,00,74,00,61,00,\
  5c,00,52,00,6f,00,61,00,6d,00,69,00,6e,00,67,00,5c,00,53,00,70,00,6f,00,74,\
  00,69,00,66,00,79,00,5c,00,53,00,70,00,6f,00,74,00,69,00,66,00,79,00,2e,00,\
  65,00,78,00,65,00,00,00,1a,00,00,00,95,00,00,00,1c,00,00,00,01,00,00,00,1c,\
  00,00,00,2d,00,00,00,00,00,00,00,94,00,00,00,11,00,00,00,03,00,00,00,0f,e8,\
  53,1c,10,00,00,00,00,43,3a,5c,55,73,65,72,73,5c,61,75,72,61,5c,41,70,70,44,\
  61,74,61,5c,52,6f,61,6d,69,6e,67,5c,4d,69,63,72,6f,73,6f,66,74,5c,49,6e,74,\
  65,72,6e,65,74,20,45,78,70,6c,6f,72,65,72,5c,51,75,69,63,6b,20,4c,61,75,6e,\
  63,68,5c,55,73,65,72,20,50,69,6e,6e,65,64,5c,54,61,73,6b,42,61,72,5c,53,70,\
  6f,74,69,66,79,2e,6c,6e,6b,00,00,60,00,00,00,03,00,00,a0,58,00,00,00,00,00,\
  00,00,64,65,73,6b,74,6f,70,2d,32,69,6f,74,70,61,68,00,0c,98,11,1a,19,f4,c4,\
  41,b5,71,ae,be,a7,b5,25,86,f7,f1,11,a6,c2,56,f1,11,8e,0f,08,00,27,ec,51,e3,\
  0c,98,11,1a,19,f4,c4,41,b5,71,ae,be,a7,b5,25,86,f7,f1,11,a6,c2,56,f1,11,8e,\
  0f,08,00,27,ec,51,e3,45,00,00,00,09,00,00,a0,39,00,00,00,31,53,50,53,b1,16,\
  6d,44,ad,8d,70,48,a7,48,40,2e,a4,3d,78,8c,1d,00,00,00,68,00,00,00,00,48,00,\
  00,00,91,95,13,40,25,c0,a9,48,a3,af,5c,f2,60,ca,03,cf,00,00,00,00,00,00,00,\
  00,00,00,00,00,fa,02,00,00,4c,00,00,00,01,14,02,00,00,00,00,00,c0,00,00,00,\
  00,00,00,46,83,00,80,00,20,00,00,00,ba,17,3c,bb,cf,ea,dc,01,9f,45,3c,bb,cf,\
  ea,dc,01,ae,64,39,bb,cf,ea,dc,01,03,08,00,00,00,00,00,00,01,00,00,00,00,00,\
  00,00,00,00,00,00,00,00,00,00,6e,01,3a,00,1f,80,c8,27,34,1f,10,5c,10,42,aa,\
  03,2e,e4,52,87,d6,68,26,00,01,00,26,00,ef,be,12,00,00,00,d2,8f,be,05,13,90,\
  dc,01,c2,a3,0e,17,cd,ea,dc,01,7d,77,6e,26,cd,ea,dc,01,14,00,56,00,31,00,00,\
  00,00,00,b7,5c,42,82,11,00,54,61,73,6b,42,61,72,00,40,00,09,00,04,00,ef,be,\
  3c,5c,32,28,b7,5c,42,82,2e,00,00,00,5c,0b,02,00,00,00,01,00,00,00,00,00,00,\
  00,00,00,00,00,00,00,00,00,46,2e,51,00,54,00,61,00,73,00,6b,00,42,00,61,00,\
  72,00,00,00,16,00,dc,00,32,00,03,08,00,00,b7,5c,42,82,20,00,44,69,73,63,6f,\
  72,64,2e,6c,6e,6b,00,48,00,09,00,04,00,ef,be,b7,5c,42,82,b7,5c,42,82,2e,00,\
  00,00,ef,03,00,00,00,00,05,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,52,\
  e1,53,00,44,00,69,00,73,00,63,00,6f,00,72,00,64,00,2e,00,6c,00,6e,00,6b,00,\
  00,00,1a,00,22,00,00,00,1e,00,ef,be,02,00,55,00,73,00,65,00,72,00,50,00,69,\
  00,6e,00,6e,00,65,00,64,00,00,00,1a,00,12,00,00,00,2b,00,ef,be,bb,c7,3c,bb,\
  cf,ea,dc,01,1a,00,46,00,00,00,1d,00,ef,be,02,00,63,00,6f,00,6d,00,2e,00,73,\
  00,71,00,75,00,69,00,72,00,72,00,65,00,6c,00,2e,00,44,00,69,00,73,00,63,00,\
  6f,00,72,00,64,00,2e,00,44,00,69,00,73,00,63,00,6f,00,72,00,64,00,00,00,1a,\
  00,00,00,95,00,00,00,1c,00,00,00,01,00,00,00,1c,00,00,00,2d,00,00,00,00,00,\
  00,00,94,00,00,00,11,00,00,00,03,00,00,00,0f,e8,53,1c,10,00,00,00,00,43,3a,\
  5c,55,73,65,72,73,5c,61,75,72,61,5c,41,70,70,44,61,74,61,5c,52,6f,61,6d,69,\
  6e,67,5c,4d,69,63,72,6f,73,6f,66,74,5c,49,6e,74,65,72,6e,65,74,20,45,78,70,\
  6c,6f,72,65,72,5c,51,75,69,63,6b,20,4c,61,75,6e,63,68,5c,55,73,65,72,20,50,\
  69,6e,6e,65,64,5c,54,61,73,6b,42,61,72,5c,44,69,73,63,6f,72,64,2e,6c,6e,6b,\
  00,00,60,00,00,00,03,00,00,a0,58,00,00,00,00,00,00,00,64,65,73,6b,74,6f,70,\
  2d,32,69,6f,74,70,61,68,00,0c,98,11,1a,19,f4,c4,41,b5,71,ae,be,a7,b5,25,86,\
  ff,f1,11,a6,c2,56,f1,11,8e,0f,08,00,27,ec,51,e3,0c,98,11,1a,19,f4,c4,41,b5,\
  71,ae,be,a7,b5,25,86,ff,f1,11,a6,c2,56,f1,11,8e,0f,08,00,27,ec,51,e3,45,00,\
  00,00,09,00,00,a0,39,00,00,00,31,53,50,53,b1,16,6d,44,ad,8d,70,48,a7,48,40,\
  2e,a4,3d,78,8c,1d,00,00,00,68,00,00,00,00,48,00,00,00,91,95,13,40,25,c0,a9,\
  48,a3,af,5c,f2,60,ca,03,cf,00,00,00,00,00,00,00,00,00,00,00,00
"Favorites"=hex:00,ec,05,00,00,14,00,1f,80,9b,d4,34,42,45,02,f3,4d,b7,80,38,93,\
  94,34,56,e1,d6,05,00,00,3e,05,41,50,50,53,2c,05,08,00,03,00,00,00,00,00,00,\
  00,68,02,00,00,31,53,50,53,55,28,4c,9f,79,9f,39,4b,a8,d0,e1,d4,2d,e1,d5,f3,\
  5d,00,00,00,11,00,00,00,00,1f,00,00,00,25,00,00,00,4d,00,69,00,63,00,72,00,\
  6f,00,73,00,6f,00,66,00,74,00,2e,00,53,00,63,00,72,00,65,00,65,00,6e,00,53,\
  00,6b,00,65,00,74,00,63,00,68,00,5f,00,38,00,77,00,65,00,6b,00,79,00,62,00,\
  33,00,64,00,38,00,62,00,62,00,77,00,65,00,00,00,00,00,11,00,00,00,27,00,00,\
  00,00,0b,00,00,00,ff,ff,00,00,11,00,00,00,0e,00,00,00,00,13,00,00,00,02,00,\
  00,00,11,00,00,00,19,00,00,00,00,13,00,00,00,01,00,00,00,81,00,00,00,15,00,\
  00,00,00,1f,00,00,00,37,00,00,00,4d,00,69,00,63,00,72,00,6f,00,73,00,6f,00,\
  66,00,74,00,2e,00,53,00,63,00,72,00,65,00,65,00,6e,00,53,00,6b,00,65,00,74,\
  00,63,00,68,00,5f,00,31,00,31,00,2e,00,32,00,35,00,31,00,30,00,2e,00,33,00,\
  31,00,2e,00,30,00,5f,00,78,00,36,00,34,00,5f,00,5f,00,38,00,77,00,65,00,6b,\
  00,79,00,62,00,33,00,64,00,38,00,62,00,62,00,77,00,65,00,00,00,00,00,65,00,\
  00,00,05,00,00,00,00,1f,00,00,00,29,00,00,00,4d,00,69,00,63,00,72,00,6f,00,\
  73,00,6f,00,66,00,74,00,2e,00,53,00,63,00,72,00,65,00,65,00,6e,00,53,00,6b,\
  00,65,00,74,00,63,00,68,00,5f,00,38,00,77,00,65,00,6b,00,79,00,62,00,33,00,\
  64,00,38,00,62,00,62,00,77,00,65,00,21,00,41,00,70,00,70,00,00,00,00,00,b9,\
  00,00,00,0f,00,00,00,00,1f,00,00,00,54,00,00,00,43,00,3a,00,5c,00,50,00,72,\
  00,6f,00,67,00,72,00,61,00,6d,00,20,00,46,00,69,00,6c,00,65,00,73,00,5c,00,\
  57,00,69,00,6e,00,64,00,6f,00,77,00,73,00,41,00,70,00,70,00,73,00,5c,00,4d,\
  00,69,00,63,00,72,00,6f,00,73,00,6f,00,66,00,74,00,2e,00,53,00,63,00,72,00,\
  65,00,65,00,6e,00,53,00,6b,00,65,00,74,00,63,00,68,00,5f,00,31,00,31,00,2e,\
  00,32,00,35,00,31,00,30,00,2e,00,33,00,31,00,2e,00,30,00,5f,00,78,00,36,00,\
  34,00,5f,00,5f,00,38,00,77,00,65,00,6b,00,79,00,62,00,33,00,64,00,38,00,62,\
  00,62,00,77,00,65,00,00,00,1d,00,00,00,20,00,00,00,00,48,00,00,00,c6,8c,5e,\
  1b,6e,f1,2f,46,b8,00,19,5f,42,5e,04,f2,00,00,00,00,19,02,00,00,31,53,50,53,\
  4d,0b,d4,86,69,90,3c,44,81,9a,2a,54,09,0d,cc,ec,51,00,00,00,0c,00,00,00,00,\
  1f,00,00,00,1f,00,00,00,41,00,73,00,73,00,65,00,74,00,73,00,5c,00,53,00,6e,\
  00,69,00,70,00,70,00,69,00,6e,00,67,00,54,00,6f,00,6f,00,6c,00,4d,00,65,00,\
  64,00,54,00,69,00,6c,00,65,00,2e,00,70,00,6e,00,67,00,00,00,00,00,51,00,00,\
  00,02,00,00,00,00,1f,00,00,00,1f,00,00,00,41,00,73,00,73,00,65,00,74,00,73,\
  00,5c,00,53,00,6e,00,69,00,70,00,70,00,69,00,6e,00,67,00,54,00,6f,00,6f,00,\
  6c,00,41,00,70,00,70,00,4c,00,69,00,73,00,74,00,2e,00,70,00,6e,00,67,00,00,\
  00,00,00,51,00,00,00,0d,00,00,00,00,1f,00,00,00,20,00,00,00,41,00,73,00,73,\
  00,65,00,74,00,73,00,5c,00,53,00,6e,00,69,00,70,00,70,00,69,00,6e,00,67,00,\
  54,00,6f,00,6f,00,6c,00,57,00,69,00,64,00,65,00,54,00,69,00,6c,00,65,00,2e,\
  00,70,00,6e,00,67,00,00,00,11,00,00,00,04,00,00,00,00,13,00,00,00,00,78,d4,\
  ff,11,00,00,00,05,00,00,00,00,13,00,00,00,ff,ff,ff,ff,55,00,00,00,13,00,00,\
  00,00,1f,00,00,00,21,00,00,00,41,00,73,00,73,00,65,00,74,00,73,00,5c,00,53,\
  00,6e,00,69,00,70,00,70,00,69,00,6e,00,67,00,54,00,6f,00,6f,00,6c,00,4c,00,\
  61,00,72,00,67,00,65,00,54,00,69,00,6c,00,65,00,2e,00,70,00,6e,00,67,00,00,\
  00,00,00,11,00,00,00,0e,00,00,00,00,13,00,00,00,a1,04,00,00,2d,00,00,00,0b,\
  00,00,00,00,1f,00,00,00,0e,00,00,00,53,00,6e,00,69,00,70,00,70,00,69,00,6e,\
  00,67,00,20,00,54,00,6f,00,6f,00,6c,00,00,00,55,00,00,00,14,00,00,00,00,1f,\
  00,00,00,21,00,00,00,41,00,73,00,73,00,65,00,74,00,73,00,5c,00,53,00,6e,00,\
  69,00,70,00,70,00,69,00,6e,00,67,00,54,00,6f,00,6f,00,6c,00,53,00,6d,00,61,\
  00,6c,00,6c,00,54,00,69,00,6c,00,65,00,2e,00,70,00,6e,00,67,00,00,00,00,00,\
  00,00,00,00,31,00,00,00,31,53,50,53,b1,16,6d,44,ad,8d,70,48,a7,48,40,2e,a4,\
  3d,78,8c,15,00,00,00,64,00,00,00,00,15,00,00,00,7d,04,00,00,00,00,00,00,00,\
  00,00,00,49,00,00,00,31,53,50,53,30,f1,25,b7,ef,47,1a,10,a5,f1,02,60,8c,9e,\
  eb,ac,2d,00,00,00,0a,00,00,00,00,1f,00,00,00,0e,00,00,00,53,00,6e,00,69,00,\
  70,00,70,00,69,00,6e,00,67,00,20,00,54,00,6f,00,6f,00,6c,00,00,00,00,00,00,\
  00,2d,00,00,00,31,53,50,53,b3,77,ed,0d,14,c6,6c,45,ae,5b,28,5b,38,d7,b0,1b,\
  11,00,00,00,07,00,00,00,00,13,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,\
  00,00,12,00,00,00,2b,00,ef,be,81,2f,52,a3,cf,ea,dc,01,44,05,5e,00,00,00,1d,\
  00,ef,be,02,00,4d,00,69,00,63,00,72,00,6f,00,73,00,6f,00,66,00,74,00,2e,00,\
  53,00,63,00,72,00,65,00,65,00,6e,00,53,00,6b,00,65,00,74,00,63,00,68,00,5f,\
  00,38,00,77,00,65,00,6b,00,79,00,62,00,33,00,64,00,38,00,62,00,62,00,77,00,\
  65,00,21,00,41,00,70,00,70,00,00,00,44,05,22,00,00,00,1e,00,ef,be,02,00,55,\
  00,73,00,65,00,72,00,50,00,69,00,6e,00,6e,00,65,00,64,00,00,00,44,05,00,00,\
  00,a4,01,00,00,3a,00,1f,80,c8,27,34,1f,10,5c,10,42,aa,03,2e,e4,52,87,d6,68,\
  26,00,01,00,26,00,ef,be,12,00,00,00,d2,8f,be,05,13,90,dc,01,c2,a3,0e,17,cd,\
  ea,dc,01,7d,77,6e,26,cd,ea,dc,01,14,00,56,00,31,00,00,00,00,00,b7,5c,29,82,\
  11,00,54,61,73,6b,42,61,72,00,40,00,09,00,04,00,ef,be,3c,5c,32,28,b7,5c,29,\
  82,2e,00,00,00,5c,0b,02,00,00,00,01,00,00,00,00,00,00,00,00,00,00,00,00,00,\
  00,00,75,57,56,00,54,00,61,00,73,00,6b,00,42,00,61,00,72,00,00,00,16,00,12,\
  01,32,00,97,01,00,00,81,58,c4,3a,20,00,46,69,6c,65,20,45,78,70,6c,6f,72,65,\
  72,2e,6c,6e,6b,00,7c,00,09,00,04,00,ef,be,b7,5c,29,82,b7,5c,29,82,2e,00,00,\
  00,ea,03,00,00,00,00,04,00,00,00,00,00,00,00,00,00,52,00,00,00,00,00,db,dc,\
  91,00,46,00,69,00,6c,00,65,00,20,00,45,00,78,00,70,00,6c,00,6f,00,72,00,65,\
  00,72,00,2e,00,6c,00,6e,00,6b,00,00,00,40,00,73,00,68,00,65,00,6c,00,6c,00,\
  33,00,32,00,2e,00,64,00,6c,00,6c,00,2c,00,2d,00,32,00,32,00,30,00,36,00,37,\
  00,00,00,20,00,22,00,00,00,1e,00,ef,be,02,00,55,00,73,00,65,00,72,00,50,00,\
  69,00,6e,00,6e,00,65,00,64,00,00,00,20,00,12,00,00,00,2b,00,ef,be,bf,65,ce,\
  9f,cf,ea,dc,01,20,00,42,00,00,00,1d,00,ef,be,02,00,4d,00,69,00,63,00,72,00,\
  6f,00,73,00,6f,00,66,00,74,00,2e,00,57,00,69,00,6e,00,64,00,6f,00,77,00,73,\
  00,2e,00,45,00,78,00,70,00,6c,00,6f,00,72,00,65,00,72,00,00,00,20,00,00,00,\
  00,3a,01,00,00,3a,00,1f,80,c8,27,34,1f,10,5c,10,42,aa,03,2e,e4,52,87,d6,68,\
  26,00,01,00,26,00,ef,be,12,00,00,00,d2,8f,be,05,13,90,dc,01,c2,a3,0e,17,cd,\
  ea,dc,01,7d,77,6e,26,cd,ea,dc,01,14,00,56,00,31,00,00,00,00,00,b7,5c,30,82,\
  11,00,54,61,73,6b,42,61,72,00,40,00,09,00,04,00,ef,be,3c,5c,32,28,b7,5c,30,\
  82,2e,00,00,00,5c,0b,02,00,00,00,01,00,00,00,00,00,00,00,00,00,00,00,00,00,\
  00,00,af,02,0e,00,54,00,61,00,73,00,6b,00,42,00,61,00,72,00,00,00,16,00,a8,\
  00,32,00,0c,09,00,00,b7,5c,30,82,20,00,42,72,61,76,65,2e,6c,6e,6b,00,44,00,\
  09,00,04,00,ef,be,b7,5c,30,82,b7,5c,30,82,2e,00,00,00,ed,03,00,00,00,00,04,\
  00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,29,87,10,00,42,00,72,00,61,00,\
  76,00,65,00,2e,00,6c,00,6e,00,6b,00,00,00,18,00,22,00,00,00,1e,00,ef,be,02,\
  00,55,00,73,00,65,00,72,00,50,00,69,00,6e,00,6e,00,65,00,64,00,00,00,18,00,\
  12,00,00,00,2b,00,ef,be,77,1b,6d,a8,cf,ea,dc,01,18,00,18,00,00,00,1d,00,ef,\
  be,02,00,42,00,72,00,61,00,76,00,65,00,00,00,18,00,00,00,00,98,01,00,00,3a,\
  00,1f,80,c8,27,34,1f,10,5c,10,42,aa,03,2e,e4,52,87,d6,68,26,00,01,00,26,00,\
  ef,be,12,00,00,00,d2,8f,be,05,13,90,dc,01,c2,a3,0e,17,cd,ea,dc,01,7d,77,6e,\
  26,cd,ea,dc,01,14,00,56,00,31,00,00,00,00,00,b7,5c,3d,82,11,00,54,61,73,6b,\
  42,61,72,00,40,00,09,00,04,00,ef,be,3c,5c,32,28,b7,5c,3d,82,2e,00,00,00,5c,\
  0b,02,00,00,00,01,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,a2,d8,ef,00,\
  54,00,61,00,73,00,6b,00,42,00,61,00,72,00,00,00,16,00,06,01,32,00,35,07,00,\
  00,b7,5c,3d,82,20,00,53,70,6f,74,69,66,79,2e,6c,6e,6b,00,48,00,09,00,04,00,\
  ef,be,b7,5c,3d,82,b7,5c,3d,82,2e,00,00,00,ff,00,00,00,00,00,12,00,00,00,00,\
  00,00,00,00,00,00,00,00,00,00,00,60,d0,f2,00,53,00,70,00,6f,00,74,00,69,00,\
  66,00,79,00,2e,00,6c,00,6e,00,6b,00,00,00,1a,00,22,00,00,00,1e,00,ef,be,02,\
  00,55,00,73,00,65,00,72,00,50,00,69,00,6e,00,6e,00,65,00,64,00,00,00,1a,00,\
  12,00,00,00,2b,00,ef,be,a3,a0,0a,b7,cf,ea,dc,01,1a,00,70,00,00,00,1d,00,ef,\
  be,02,00,43,00,3a,00,5c,00,55,00,73,00,65,00,72,00,73,00,5c,00,61,00,75,00,\
  72,00,61,00,5c,00,41,00,70,00,70,00,44,00,61,00,74,00,61,00,5c,00,52,00,6f,\
  00,61,00,6d,00,69,00,6e,00,67,00,5c,00,53,00,70,00,6f,00,74,00,69,00,66,00,\
  79,00,5c,00,53,00,70,00,6f,00,74,00,69,00,66,00,79,00,2e,00,65,00,78,00,65,\
  00,00,00,1a,00,00,00,00,6e,01,00,00,3a,00,1f,80,c8,27,34,1f,10,5c,10,42,aa,\
  03,2e,e4,52,87,d6,68,26,00,01,00,26,00,ef,be,12,00,00,00,d2,8f,be,05,13,90,\
  dc,01,c2,a3,0e,17,cd,ea,dc,01,7d,77,6e,26,cd,ea,dc,01,14,00,56,00,31,00,00,\
  00,00,00,b7,5c,42,82,11,00,54,61,73,6b,42,61,72,00,40,00,09,00,04,00,ef,be,\
  3c,5c,32,28,b7,5c,42,82,2e,00,00,00,5c,0b,02,00,00,00,01,00,00,00,00,00,00,\
  00,00,00,00,00,00,00,00,00,46,2e,51,00,54,00,61,00,73,00,6b,00,42,00,61,00,\
  72,00,00,00,16,00,dc,00,32,00,03,08,00,00,b7,5c,42,82,20,00,44,69,73,63,6f,\
  72,64,2e,6c,6e,6b,00,48,00,09,00,04,00,ef,be,b7,5c,42,82,b7,5c,42,82,2e,00,\
  00,00,ef,03,00,00,00,00,05,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,52,\
  e1,53,00,44,00,69,00,73,00,63,00,6f,00,72,00,64,00,2e,00,6c,00,6e,00,6b,00,\
  00,00,1a,00,22,00,00,00,1e,00,ef,be,02,00,55,00,73,00,65,00,72,00,50,00,69,\
  00,6e,00,6e,00,65,00,64,00,00,00,1a,00,12,00,00,00,2b,00,ef,be,bb,c7,3c,bb,\
  cf,ea,dc,01,1a,00,46,00,00,00,1d,00,ef,be,02,00,63,00,6f,00,6d,00,2e,00,73,\
  00,71,00,75,00,69,00,72,00,72,00,65,00,6c,00,2e,00,44,00,69,00,73,00,63,00,\
  6f,00,72,00,64,00,2e,00,44,00,69,00,73,00,63,00,6f,00,72,00,64,00,00,00,1a,\
  00,00,00,ff
"FavoritesChanges"=dword:00000006
"FavoritesVersion"=dword:00000003
"@
        
        Set-Content -Path $tempRegFile -Value $regContent -Force
        
        $regResult = Start-Process -FilePath "reg.exe" -ArgumentList "import", "`"$tempRegFile`"" -Wait -PassThru -WindowStyle Hidden
        if ($regResult.ExitCode -eq 0) {
            Write-Log "Applied taskbar registry configuration" "SUCCESS"
        } else {
            Write-Log "Taskbar registry configuration may have issues (Exit code: $($regResult.ExitCode))" "WARNING"
        }
        
    } catch {
        if (Test-RealError $_.Exception.Message) {
            Write-Log "Taskbar registry configuration warning: $($_.Exception.Message)" "WARNING"
        } else {
            Write-Log "Taskbar registry configuration completed" "SUCCESS"
        }
    }
    
    # Disable scheduled tasks
    Write-Log "Disabling Brave scheduled tasks..." "INFO"
    $scheduledTasks = Get-ScheduledTask -TaskName "*Brave*" -ErrorAction SilentlyContinue
    $disabledTasksCount = 0
    
    foreach ($task in $scheduledTasks) {
        try {
            Disable-ScheduledTask -TaskName $task.TaskName -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Disabled scheduled task: $($task.TaskName)" "SUCCESS"
            $disabledTasksCount++
        } catch {
            if (Test-RealError $_.Exception.Message) {
                Write-Log "Failed to disable scheduled task: $($task.TaskName) - $($_.Exception.Message)" "WARNING"
            } else {
                Write-Log "Disabled scheduled task: $($task.TaskName)" "SUCCESS"
                $disabledTasksCount++
            }
        }
    }
    
    # Final verification before creating success status
    if ($installationFailed) {
        throw "Installation failed during one of the critical steps"
    }
    
    # Create status file with success
    $statusData = @{
        InstallDate = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
        Version = $braveVersion
        Status = "SUCCESS"
        LogFile = $LogFile
        RegistryPath = $braveRegPath
        ConfigurationApplied = $true
        TaskbarShortcutCreated = (Test-Path $shortcutLocation)
        ScheduledTasksDisabled = $disabledTasksCount
        InstallationVerified = $braveInstalled
    }
    
    $statusData | ConvertTo-Json | Out-File $StatusFile -Force
    
    Write-Log "Brave Browser installation and configuration completed successfully" "SUCCESS"
    Write-Log "Status file created: $StatusFile" "INFO"
    
} catch {
    # Only log real errors
    if (Test-RealError $_.Exception.Message) {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR"
        if ($_.Exception.StackTrace) {
            Write-Log "Stack trace: $($_.Exception.StackTrace)" "ERROR"
        }
        
        # Create error status file
        @{
            InstallDate = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
            Status = "FAILED"
            Error = $_.Exception.Message
            LogFile = $LogFile
        } | ConvertTo-Json | Out-File $StatusFile -Force
        
        exit 1
    } else {
        Write-Log "Installation completed successfully (ignoring false error message)" "SUCCESS"
        
        # Create success status file even if we caught a "success" error
        @{
            InstallDate = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
            Status = "SUCCESS"
            LogFile = $LogFile
            Note = "Completed successfully despite false error message"
        } | ConvertTo-Json | Out-File $StatusFile -Force
    }
} finally {
    # Cleanup with null checks
    if ($installerPath -and (Test-Path $installerPath)) {
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up installer file" "INFO"
    }
    
    if ($tempRegFile -and (Test-Path $tempRegFile)) {
        Remove-Item $tempRegFile -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up temporary registry file" "INFO"
    }
    
    # Clean up any remaining COM objects
    try {
        if ($wsh) { 
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wsh) | Out-Null 
            $wsh = $null
        }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    } catch {
        # Ignore cleanup errors
    }
}

exit 0