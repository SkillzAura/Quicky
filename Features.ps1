# Enhanced Windows Features Management Script for Hidden Execution
# Author: SkillzAura
# Date: 2025-12-09
# Version: 2.1

# Admin elevation check
if (! ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

# Configuration
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

# Setup logging to organized folder structure
$LogPath = "C:\ProgramData\Aura\OptimizationLogs"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$LogFile = Join-Path $LogPath "Features-$(Get-Date -Format 'yyyy-MM-dd_hh-mm-ss-tt').log"

# Setup status file path
$StatusPath = "C:\ProgramData\Aura\StatusLogs"
if (!(Test-Path $StatusPath)) { New-Item -ItemType Directory -Path $StatusPath -Force | Out-Null }
$StatusFile = Join-Path $StatusPath "Features.status"

# Initialize tracking arrays
$disabledFeaturesArr = New-Object System.Collections.ArrayList
$removedCapabilitiesArr = New-Object System.Collections.ArrayList
$failedFeaturesArr = New-Object System.Collections.ArrayList
$failedCapabilitiesArr = New-Object System.Collections.ArrayList
$skippedFeaturesArr = New-Object System.Collections.ArrayList
$skippedCapabilitiesArr = New-Object System.Collections.ArrayList

# Logging function for file output
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Bypasses Add-Content lock errors during rapid loops using native .NET
    $retryCount = 0
    while ($retryCount -lt 3) {
        try {
            [System.IO.File]::AppendAllText($LogFile, "$logEntry`r`n")
            break
        } catch {
            # If locked by an Antivirus scan, wait a split second and retry
            Start-Sleep -Milliseconds 50
            $retryCount++
        }
    }
}

# Function to disable Windows optional feature with proper error handling
function Disable-OptionalFeatureWithLogging {
    param([string]$FeatureName)
    
    try {
        Write-Log "Checking feature: $FeatureName" "INFO"
        # We still use the PS cmdlet just to CHECK the status because it's fast and silent
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        
        if ($null -eq $feature) {
            Write-Log "Feature not found: $FeatureName" "SKIPPED"
            [void]$skippedFeaturesArr.Add(@{Name = $FeatureName; Reason = "Feature not found"})
            return
        }
        
        if ($feature.State -eq "Disabled" -or $feature.State -eq "DisabledWithPayloadRemoved") {
            Write-Log "Feature already disabled: $FeatureName" "SKIPPED"
            [void]$skippedFeaturesArr.Add(@{Name = $FeatureName; Reason = "Already disabled"})
            return
        }
        
        Write-Log "Disabling feature: $FeatureName" "INFO"
        
        # --- THE FIX: Using DISM to execute silently ---
        $dismArgs = "/Online /Disable-Feature /FeatureName:$FeatureName /Remove /NoRestart /Quiet"
        $process = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -WindowStyle Hidden -Wait -PassThru
        
        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            throw "DISM execution failed with exit code $($process.ExitCode)"
        }
        # -----------------------------------------------
        
        Write-Log "Successfully disabled feature: $FeatureName" "SUCCESS"
        [void]$disabledFeaturesArr.Add($FeatureName)
        
    } catch {
        $errorMsg = $_.Exception.Message
        if (-not $errorMsg) { $errorMsg = $_.ToString() } # Catches our custom throw
        Write-Log "Failed to disable feature $FeatureName - $errorMsg" "ERROR"
        [void]$failedFeaturesArr.Add(@{Name = $FeatureName; Error = $errorMsg})
    }
}

# Function to remove Windows capability with proper error handling
function Remove-CapabilityWithLogging {
    param([string]$CapabilityName)
    
    try {
        Write-Log "Checking capability: $CapabilityName" "INFO"
        # Still using PS to check status
        $capability = Get-WindowsCapability -Online -Name $CapabilityName -ErrorAction SilentlyContinue
        
        if ($null -eq $capability) {
            $capability = Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$CapabilityName*" } | Select-Object -First 1
        }
        
        if ($null -eq $capability) {
            Write-Log "Capability not found: $CapabilityName" "SKIPPED"
            [void]$skippedCapabilitiesArr.Add(@{Name = $CapabilityName; Reason = "Capability not found"})
            return
        }
        
        if ($capability.State -eq "NotPresent") {
            Write-Log "Capability already removed: $($capability.Name)" "SKIPPED"
            [void]$skippedCapabilitiesArr.Add(@{Name = $capability.Name; Reason = "Already removed"})
            return
        }
        
        Write-Log "Removing capability: $($capability.Name)" "INFO"
        
        # --- THE FIX: Using DISM to execute silently ---
        $dismArgs = "/Online /Remove-Capability /CapabilityName:$($capability.Name) /NoRestart /Quiet"
        $process = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -WindowStyle Hidden -Wait -PassThru
        
        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            throw "DISM execution failed with exit code $($process.ExitCode)"
        }
        # -----------------------------------------------
        
        Write-Log "Successfully removed capability: $($capability.Name)" "SUCCESS"
        [void]$removedCapabilitiesArr.Add($capability.Name)
        
    } catch {
        $errorMsg = $_.Exception.Message
        if (-not $errorMsg) { $errorMsg = $_.ToString() }
        Write-Log "Failed to remove capability $CapabilityName - $errorMsg" "ERROR"
        [void]$failedCapabilitiesArr.Add(@{Name = $CapabilityName; Error = $errorMsg})
    }
}

# Function to remove Windows package with proper error handling
function Remove-PackageWithLogging {
    param([string]$PackagePattern)
    
    try {
        Write-Log "Searching for packages matching: $PackagePattern" "INFO"
        $packages = Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -like $PackagePattern }
        
        if ($null -eq $packages -or $packages.Count -eq 0) {
            Write-Log "No packages found matching: $PackagePattern" "SKIPPED"
            return
        }
        
        foreach ($package in $packages) {
            try {
                Write-Log "Removing package: $($package.PackageName)" "INFO"
                
                # --- THE FIX: Using DISM to execute silently ---
                $dismArgs = "/Online /Remove-Package /PackageName:$($package.PackageName) /NoRestart /Quiet"
                $process = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -WindowStyle Hidden -Wait -PassThru
                
                if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
                    throw "DISM execution failed with exit code $($process.ExitCode)"
                }
                # -----------------------------------------------
                
                Write-Log "Successfully removed package: $($package.PackageName)" "SUCCESS"
                [void]$removedCapabilitiesArr.Add("Package: $($package.PackageName)")
            } catch {
                $errorMsg = $_.Exception.Message
                if (-not $errorMsg) { $errorMsg = $_.ToString() }
                Write-Log "Failed to remove package $($package.PackageName) - $errorMsg" "ERROR"
                [void]$failedCapabilitiesArr.Add(@{Name = "Package: $($package.PackageName)"; Error = $errorMsg})
            }
        }
    } catch {
        # This was the missing catch block and closing braces
        $errorMsg = $_.Exception.Message
        Write-Log "Failed to search for packages $PackagePattern - $errorMsg" "ERROR"
    }
}
try {
    Write-Log "Starting Windows Features Management Process" "INFO"
    Write-Log "Script Version: 2.1" "INFO"
    
    # Wait for Remove-AI.status file before proceeding
    Write-Log "Waiting for Remove-AI.status dependency..." "INFO"
    $dependencyStatusFile = Join-Path $StatusPath "Remove-AI.status"
    $waitTimeout = 600
    $waitStart = Get-Date
    
    while (-not (Test-Path $dependencyStatusFile)) {
        $elapsed = (Get-Date) - $waitStart
        if ($elapsed.TotalSeconds -gt $waitTimeout) {
            Write-Log "Timeout waiting for Remove-AI.status - proceeding anyway" "WARNING"
            break
        }
        Start-Sleep -Seconds 2
    }
    
    if (Test-Path $dependencyStatusFile) {
        Write-Log "Remove-AI.status found - proceeding with features management" "SUCCESS"
    }
    
    # === Disable Windows Optional Features ===
    Write-Log "=== Disabling Windows Optional Features ===" "INFO"
    
    $featuresToDisable = @(
        "MSRDC-Infrastructure"
        "WorkFolders-Client"
        "Printing-Foundation-Features"
        "SmbDirect"
        "SearchEngine-Client-Package"
        "MediaPlayback"
        "Microsoft-RemoteDesktopConnection"
        "Printing-PrintToPDFServices-Features"
        "WCF-Services45"
        "MicrosoftWindowsPowerShellV2Root"
        "Recall"
    )
    
    foreach ($feature in $featuresToDisable) {
        Disable-OptionalFeatureWithLogging -FeatureName $feature
    }
    
    Write-Log "Completed Windows Optional Features processing" "INFO"
    
    # === Remove Windows Capabilities ===
    Write-Log "=== Removing Windows Capabilities ===" "INFO"
    
    # All capability names - EXACT from your list with NO spaces after dots
    $allCapabilities = @(
        "App.StepsRecorder~~~~0.0.1.0"
        "Browser.InternetExplorer~~~~0.0.11.0"
        "MathRecognizer~~~~0.0.1.0"
        "Media.WindowsMediaPlayer~~~~0.0.12.0"
        "OneCoreUAP.OneSync~~~~0.0.1.0"
        "Microsoft.Windows.WordPad~~~~0.0.1.0"
        "Print.Management.Console~~~~0.0.1.0"
        "Microsoft.Wallpapers.Extended~~~~0.0.1.0"
        "Microsoft.Windows.Notepad.System~~~~0.0.1.0"
        "OpenSSH.Client~~~~0.0.1.0"
        "WMIC~~~~"
        "Microsoft.Windows.PowerShell.ISE~~~~0.0.1.0"
        "Microsoft.Windows.Ethernet.Client.Intel.E1i68x64~~~~0.0.1.0"
        "Microsoft.Windows.Ethernet.Client.Intel.E2f68~~~~0.0.1.0"
        "Microsoft.Windows.Ethernet.Client.Realtek.Rtcx21x64~~~~0.0.1.0"
        "Microsoft.Windows.Ethernet.Client.Vmware.Vmxnet3~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Broadcom.Bcmpciedhd63~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Broadcom.Bcmwl63al~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Broadcom.Bcmwl63a~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwbw02~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwew00~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwew01~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwlv64~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwns64~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwsw00~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwtw02~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwtw04~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwtw06~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwtw08~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Intel.Netwtw10~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Marvel.Mrvlpcie8897~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Qualcomm.Athw8x~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Qualcomm.Athwnx~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Qualcomm.Qcamain10x64~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Ralink.Netr28x~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Realtek.Rtl8187se~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Realtek.Rtl8192se~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Realtek.Rtl819xp~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Realtek.Rtl85n64~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Realtek.Rtwlane01~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Realtek.Rtwlane13~~~~0.0.1.0"
        "Microsoft.Windows.Wifi.Client.Realtek.Rtwlane~~~~0.0.1.0"
        "Windows.Kernel.LA57~~~~0.0.1.0"
        "Language.Handwriting~~~en-US~0.0.1.0"
        "Language.OCR~~~en-US~0.0.1.0"
        "Language.Speech~~~en-US~0.0.1.0"
        "Language.TextToSpeech~~~en-US~0.0.1.0"
        "Hello.Face.20134~~~~0.0.1.0"
    )
    
    Write-Log "Processing all capabilities..." "INFO"
    foreach ($capability in $allCapabilities) {
        Remove-CapabilityWithLogging -CapabilityName $capability
    }
    
    Write-Log "Completed Windows Capabilities processing" "INFO"
    
    # === Remove Windows Packages ===
    Write-Log "=== Removing Windows Packages ===" "INFO"
    Remove-PackageWithLogging -PackagePattern "*Hello-Face*"
    Write-Log "Completed Windows Packages processing" "INFO"
    
    # === Generate Summary ===
    $totalFeatures = $featuresToDisable.Count
    $totalCapabilities = $allCapabilities.Count
    
    $featuresDisabled = $disabledFeaturesArr.Count
    $featuresSkipped = $skippedFeaturesArr.Count
    $featuresFailed = $failedFeaturesArr.Count
    
    $capabilitiesRemoved = $removedCapabilitiesArr.Count
    $capabilitiesSkipped = $skippedCapabilitiesArr.Count
    $capabilitiesFailed = $failedCapabilitiesArr.Count
    
    Write-Log "=== Windows Features Management Summary ===" "INFO"
    Write-Log "Features - Disabled: $featuresDisabled, Skipped:  $featuresSkipped, Failed:  $featuresFailed" "INFO"
    Write-Log "Capabilities - Removed: $capabilitiesRemoved, Skipped: $capabilitiesSkipped, Failed: $capabilitiesFailed" "INFO"
    
    if ($disabledFeaturesArr.Count -gt 0) {
        $disabledList = $disabledFeaturesArr -join ', '
        Write-Log "Disabled features: $disabledList" "INFO"
    }
    
    if ($removedCapabilitiesArr.Count -gt 0) {
        $removedList = $removedCapabilitiesArr -join ', '
        Write-Log "Removed capabilities: $removedList" "INFO"
    }
    
    if ($failedFeaturesArr.Count -gt 0) {
        Write-Log "Failed features:" "WARNING"
        foreach ($failed in $failedFeaturesArr) {
            Write-Log "  - $($failed.Name): $($failed.Error)" "WARNING"
        }
    }
    
    if ($failedCapabilitiesArr.Count -gt 0) {
        Write-Log "Failed capabilities:" "WARNING"
        foreach ($failed in $failedCapabilitiesArr) {
            Write-Log "  - $($failed.Name): $($failed.Error)" "WARNING"
        }
    }
    
    # Determine overall status
    $totalSuccess = $featuresDisabled + $capabilitiesRemoved
    $totalFailed = $featuresFailed + $capabilitiesFailed
    $totalSkipped = $featuresSkipped + $capabilitiesSkipped
    
    $overallStatus = if ($totalFailed -eq 0 -and $totalSuccess -gt 0) {
        "SUCCESS"
    } elseif ($totalSuccess -gt 0 -and $totalFailed -gt 0) {
        "PARTIAL_SUCCESS"
    } elseif ($totalSuccess -eq 0 -and $totalFailed -eq 0) {
        "NO_CHANGES"
    } else {
        "FAILED"
    }
    
    # Create comprehensive status file
    $statusData = @{
        InstallDate = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
        Status = $overallStatus
        Summary = @{
            FeaturesDisabled = $featuresDisabled
            FeaturesSkipped = $featuresSkipped
            FeaturesFailed = $featuresFailed
            CapabilitiesRemoved = $capabilitiesRemoved
            CapabilitiesSkipped = $capabilitiesSkipped
            CapabilitiesFailed = $capabilitiesFailed
            TotalSuccess = $totalSuccess
            TotalFailed = $totalFailed
            TotalSkipped = $totalSkipped
        }
        DisabledFeatures = @($disabledFeaturesArr)
        RemovedCapabilities = @($removedCapabilitiesArr)
        FailedFeatures = if ($failedFeaturesArr.Count -gt 0) { @($failedFeaturesArr) } else { $null }
        FailedCapabilities = if ($failedCapabilitiesArr.Count -gt 0) { @($failedCapabilitiesArr) } else { $null }
        LogFile = $LogFile
        ScriptVersion = "2.1"
    }
    
    $statusData | ConvertTo-Json -Depth 4 | Out-File $StatusFile -Force
    
    Write-Log "Windows Features Management completed with status: $overallStatus" "SUCCESS"
    Write-Log "Status file created: $StatusFile" "INFO"
    
} catch {
    $errorMsg = $_.Exception.Message
    $stackTrace = $_.Exception.StackTrace
    Write-Log "Windows Features Management failed:  $errorMsg" "ERROR"
    Write-Log "Stack trace:  $stackTrace" "ERROR"
    
    # Create error status file
    $errorData = @{
        InstallDate = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
        Status = "FAILED"
        Error = $errorMsg
        DisabledFeatures = @($disabledFeaturesArr)
        RemovedCapabilities = @($removedCapabilitiesArr)
        FailedFeatures = @($failedFeaturesArr)
        FailedCapabilities = @($failedCapabilitiesArr)
        LogFile = $LogFile
        ScriptVersion = "2.1"
    }
    
    $errorData | ConvertTo-Json -Depth 4 | Out-File $StatusFile -Force
    
    exit 1
}

exit 0