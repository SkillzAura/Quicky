# Enhanced Windows AI Components Removal Script
# Author: SkillzAura
# Date: 2025-12-10
# Version: 2.0

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
$LogFile = Join-Path $LogPath "Remove-AI-$(Get-Date -Format 'yyyy-MM-dd_hh-mm-ss-tt').log"

# Setup status file path
$StatusPath = "C:\ProgramData\Aura\StatusLogs"
if (!(Test-Path $StatusPath)) { New-Item -ItemType Directory -Path $StatusPath -Force | Out-Null }
$StatusFile = Join-Path $StatusPath "Remove-AI.status"

# Initialize tracking variables
$operationsCompleted = @()
$operationsFailed = @()
$minSudoPath = "C:\Windows\Setup\Scripts\files\MinSudo.exe"
$remoteScriptUrl = "https://raw.githubusercontent.com/zoicware/RemoveWindowsAI/main/RemoveWindowsAi.ps1"
$job = $null

# Logging function for file output
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
}

try {
    Write-Log "Starting Windows AI Components Removal Process" "INFO"
    Write-Log "Script Version: 2.0" "INFO"
    
    # === Step 1: Stop WindowsCopilotRuntimeActions Process ===
    Write-Log "=== Step 1: Stopping WindowsCopilotRuntimeActions Process ===" "INFO"
    
    try {
        $copilotProcess = Get-Process -Name 'WindowsCopilotRuntimeActions' -ErrorAction SilentlyContinue
        
        if ($copilotProcess) {
            Write-Log "Found WindowsCopilotRuntimeActions process (PID: $($copilotProcess.Id))" "INFO"
            Stop-Process -Name 'WindowsCopilotRuntimeActions' -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            
            # Verify process stopped
            $stillRunning = Get-Process -Name 'WindowsCopilotRuntimeActions' -ErrorAction SilentlyContinue
            if ($stillRunning) {
                Write-Log "WindowsCopilotRuntimeActions process still running after termination attempt" "WARNING"
                $operationsFailed += "Stop WindowsCopilotRuntimeActions process"
            } else {
                Write-Log "WindowsCopilotRuntimeActions process terminated successfully" "SUCCESS"
                $operationsCompleted += "Stop WindowsCopilotRuntimeActions process"
            }
        } else {
            Write-Log "WindowsCopilotRuntimeActions process not running" "INFO"
            $operationsCompleted += "Stop WindowsCopilotRuntimeActions process (not running)"
        }
    } catch {
        Write-Log "Failed to stop WindowsCopilotRuntimeActions:  $($_.Exception.Message)" "WARNING"
        $operationsFailed += "Stop WindowsCopilotRuntimeActions process: $($_.Exception.Message)"
    }
    
    # === Step 2: Rename WindowsCopilotRuntimeActions.exe using MinSudo ===
    Write-Log "=== Step 2: Renaming WindowsCopilotRuntimeActions.exe ===" "INFO"
    
    try {
        # Validate MinSudo.exe exists
        if (!(Test-Path $minSudoPath)) {
            throw "MinSudo.exe not found at: $minSudoPath"
        }
        
        Write-Log "MinSudo.exe found at: $minSudoPath" "INFO"
        
        # Find WindowsCopilotRuntimeActions directory
        $copilotAppDir = Get-ChildItem 'C:\Windows\SystemApps' -Directory -Filter 'MicrosoftWindows.Client.CBS*' -ErrorAction Stop | Select-Object -First 1
        
        if ($copilotAppDir) {
            $copilotExePath = Join-Path $copilotAppDir.FullName 'WindowsCopilotRuntimeActions.exe'
            Write-Log "Copilot app directory found: $($copilotAppDir.FullName)" "INFO"
            
            if (Test-Path $copilotExePath) {
                Write-Log "WindowsCopilotRuntimeActions.exe found at: $copilotExePath" "INFO"
                
                # Build MinSudo command
                $renameCommand = "Rename-Item '$copilotExePath' 'WindowsCopilotRuntimeActions.exee' -Force -ErrorAction SilentlyContinue"
                $minSudoArgs = @(
                    "--NoLogo"
                    "--TrustedInstaller"
                    "--Privileged"
                    "Powershell"
                    "-Command"
                    "`"$renameCommand`""
                )
                
                Write-Log "Executing MinSudo with TrustedInstaller privileges..." "INFO"
                
                # Execute MinSudo
                $minSudoProcess = Start-Process -FilePath $minSudoPath -ArgumentList $minSudoArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
                
                Write-Log "MinSudo completed with exit code: $($minSudoProcess.ExitCode)" "INFO"
                
                # Verify rename operation
                Start-Sleep -Seconds 2
                $renamedPath = Join-Path $copilotAppDir.FullName 'WindowsCopilotRuntimeActions.exee'
                
                if (Test-Path $renamedPath) {
                    Write-Log "WindowsCopilotRuntimeActions.exe successfully renamed to .exee" "SUCCESS"
                    $operationsCompleted += "Rename WindowsCopilotRuntimeActions.exe"
                } elseif (!(Test-Path $copilotExePath)) {
                    Write-Log "WindowsCopilotRuntimeActions.exe no longer exists (already renamed or removed)" "INFO"
                    $operationsCompleted += "Rename WindowsCopilotRuntimeActions.exe (already renamed)"
                } else {
                    Write-Log "WindowsCopilotRuntimeActions.exe still exists after rename attempt" "WARNING"
                    $operationsFailed += "Rename WindowsCopilotRuntimeActions.exe (file still exists)"
                }
            } else {
                Write-Log "WindowsCopilotRuntimeActions.exe not found in Copilot app directory" "INFO"
                $operationsCompleted += "Rename WindowsCopilotRuntimeActions.exe (file not found)"
            }
        } else {
            Write-Log "Copilot app directory not found in C:\Windows\SystemApps" "INFO"
            $operationsCompleted += "Rename WindowsCopilotRuntimeActions.exe (directory not found)"
        }
    } catch {
        Write-Log "Failed to rename WindowsCopilotRuntimeActions.exe: $($_.Exception.Message)" "ERROR"
        $operationsFailed += "Rename WindowsCopilotRuntimeActions.exe: $($_.Exception.Message)"
    }
    
    # === Step 3: Configure Registry Settings ===
    Write-Log "=== Step 3: Configuring Registry Settings ===" "INFO"
    
    try {
        $regPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        $regValue = "SettingsPageVisibility"
        $regData = "hide: aicomponents;home"
        
        Write-Log "Setting registry value: $regPath\$regValue = $regData" "INFO"
        
        $regResult = reg add $regPath /v $regValue /t REG_SZ /d $regData /f 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Registry setting applied successfully" "SUCCESS"
            $operationsCompleted += "Configure SettingsPageVisibility registry"
        } else {
            Write-Log "Registry command returned exit code: $LASTEXITCODE" "WARNING"
            $operationsFailed += "Configure SettingsPageVisibility registry:  Exit code $LASTEXITCODE"
        }
    } catch {
        Write-Log "Failed to configure registry:  $($_.Exception.Message)" "ERROR"
        $operationsFailed += "Configure SettingsPageVisibility registry: $($_.Exception.Message)"
    }
    
    # === Step 4: Execute Remote AI Removal Script ===
    Write-Log "=== Step 4: Executing Remote AI Removal Script ===" "INFO"
    
    try {
        # Check internet connectivity
        Write-Log "Checking internet connection to GitHub..." "INFO"
        
        try {
            $testConnection = Test-NetConnection -ComputerName "raw.githubusercontent.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
            if (-not $testConnection) {
                throw "Cannot reach raw.githubusercontent.com"
            }
            Write-Log "Internet connection verified" "SUCCESS"
        } catch {
            throw "Internet connectivity check failed: $($_.Exception.Message)"
        }
        
        # Download and execute remote script as job
        Write-Log "Downloading and executing remote script from:  $remoteScriptUrl" "INFO"
        
        $scriptBlock = {
            param($url)
            try {
                $scriptContent = Invoke-RestMethod -Uri $url -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
                $scriptBlock = [scriptblock]::Create($scriptContent)
                & $scriptBlock -nonInteractive -AllOptions
            } catch {
                throw "Remote script execution failed: $($_.Exception.Message)"
            }
        }
        
        $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $remoteScriptUrl
        Write-Log "Remote script started as job (Job ID: $($job.Id))" "INFO"
        
        # Wait for job with timeout (10 minutes)
        $jobTimeout = 600
        Write-Log "Waiting for remote script to complete (timeout: $jobTimeout seconds)..." "INFO"
        
        $jobResult = Wait-Job $job -Timeout $jobTimeout
        
        if ($jobResult) {
            Write-Log "Remote script job completed" "SUCCESS"
            
            # Receive job output
            $jobOutput = Receive-Job $job -ErrorAction SilentlyContinue
            
            if ($jobOutput) {
                Write-Log "Remote script output:" "INFO"
                $jobOutput | ForEach-Object { Write-Log "  $_" "INFO" }
            }
            
            # Check job state
            if ($job.State -eq "Completed") {
                Write-Log "Remote AI removal script completed successfully" "SUCCESS"
                $operationsCompleted += "Execute remote AI removal script"
            } elseif ($job.State -eq "Failed") {
                $jobError = $job.ChildJobs[0].JobStateInfo.Reason.Message
                Write-Log "Remote script job failed: $jobError" "ERROR"
                $operationsFailed += "Execute remote AI removal script: Job failed - $jobError"
            } else {
                Write-Log "Remote script job ended with state: $($job.State)" "WARNING"
                $operationsFailed += "Execute remote AI removal script:  Unexpected job state - $($job.State)"
            }
        } else {
            Write-Log "Remote script job timed out after $jobTimeout seconds" "WARNING"
            Stop-Job $job -ErrorAction SilentlyContinue
            $operationsFailed += "Execute remote AI removal script:  Timeout after $jobTimeout seconds"
        }
        
    } catch {
        Write-Log "Failed to execute remote AI removal script: $($_.Exception.Message)" "ERROR"
        $operationsFailed += "Execute remote AI removal script: $($_.Exception.Message)"
    }
    
    # === Generate Summary ===
    $totalOperations = $operationsCompleted.Count + $operationsFailed.Count
    $successCount = $operationsCompleted.Count
    $failedCount = $operationsFailed.Count
    
    Write-Log "=== Windows AI Components Removal Summary ===" "INFO"
    Write-Log "Total operations:  $totalOperations" "INFO"
    Write-Log "Successful operations: $successCount" "SUCCESS"
    Write-Log "Failed operations: $failedCount" "INFO"
    
    if ($operationsCompleted.Count -gt 0) {
        Write-Log "Completed operations:" "INFO"
        foreach ($op in $operationsCompleted) {
            Write-Log "  - $op" "SUCCESS"
        }
    }
    
    if ($operationsFailed.Count -gt 0) {
        Write-Log "Failed operations:" "WARNING"
        foreach ($op in $operationsFailed) {
            Write-Log "  - $op" "WARNING"
        }
    }
    
    # Determine overall status
    $overallStatus = if ($failedCount -eq 0 -and $successCount -gt 0) {
        "SUCCESS"
    } elseif ($successCount -gt 0 -and $failedCount -gt 0) {
        "PARTIAL_SUCCESS"
    } elseif ($failedCount -gt 0 -and $successCount -eq 0) {
        "FAILED"
    } else {
        "NO_CHANGES"
    }
    
    # Create comprehensive status file
    $statusData = @{
        InstallDate = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
        Status = $overallStatus
        TotalOperations = $totalOperations
        SuccessfulOperations = $successCount
        FailedOperations = $failedCount
        CompletedOperations = $operationsCompleted
        FailedOperationDetails = if ($operationsFailed.Count -gt 0) { $operationsFailed } else { $null }
        LogFile = $LogFile
        ScriptVersion = "2.0"
    }
    
    $statusData | ConvertTo-Json -Depth 3 | Out-File $StatusFile -Force
    
    Write-Log "Windows AI Components removal completed with status: $overallStatus" "SUCCESS"
    Write-Log "Status file created:  $StatusFile" "INFO"
    
} catch {
    Write-Log "Windows AI Components removal failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace:  $($_.Exception.StackTrace)" "ERROR"
    
    # Create error status file
    $errorData = @{
        InstallDate = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
        Status = "FAILED"
        Error = $_.Exception.Message
        CompletedOperations = $operationsCompleted
        FailedOperations = $operationsFailed
        LogFile = $LogFile
        ScriptVersion = "2.0"
    }
    
    $errorData | ConvertTo-Json -Depth 3 | Out-File $StatusFile -Force
    
    exit 1
} finally {
    # Cleanup
    if ($job) {
        try {
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            Write-Log "Cleaned up background job" "INFO"
        } catch {
            Write-Log "Failed to clean up job: $($_.Exception.Message)" "WARNING"
        }
    }
    
    Write-Log "Remove-AI script execution completed" "INFO"
}

exit 0