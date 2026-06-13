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
