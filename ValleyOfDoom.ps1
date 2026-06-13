# Enhanced ValleyOfDoom PC-Tuning Script for Hidden Execution
# Author: SkillzAura
# Date: 2026-03-09

# Admin elevation check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

# Configuration
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Setup logging to organized folder structure
$LogPath = "C:\ProgramData\Aura\OptimizationLogs"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$LogFile = Join-Path $LogPath "ValleyOfDoom-$(Get-Date -Format 'yyyy-MM-dd_hh-mm-ss-tt').log"

# Setup status file path
$StatusPath = "C:\ProgramData\Aura\StatusLogs"
if (!(Test-Path $StatusPath)) { New-Item -ItemType Directory -Path $StatusPath -Force | Out-Null }
$StatusFile = Join-Path $StatusPath "VOD.status"

# Initialize variables
$outFile = $null
$extractPath = $null
$modifiedSettings = @()
$unchangedAlreadyTrue = @()
$unchangedAlreadyFalse = @()
$registryOutputLines = @()

# Logging function for file output
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
}

try {
    Write-Log "Starting ValleyOfDoom PC-Tuning process" "INFO"

    # Check internet connectivity
    Write-Log "Checking internet connection..." "INFO"
    if (-not (Test-NetConnection -ComputerName "github.com" -Port 443 -InformationLevel Quiet)) {
        throw "No internet connection or github.com is unreachable"
    }
    Write-Log "Internet connection verified" "SUCCESS"

    # Download ValleyOfDoom PC-Tuning archive
    $URL = "https://github.com/valleyofdoom/PC-Tuning/archive/refs/heads/main.zip"
    $outFile = Join-Path $env:TEMP "PC-Tuning-main.zip"
    $extractPath = Join-Path $env:TEMP "PC-Tuning-main"

    Write-Log "Downloading PC-Tuning archive..." "INFO"

    $webClient = New-Object System.Net.WebClient
    try {
        $webClient.DownloadFile($URL, $outFile)
    } finally {
        $webClient.Dispose()
    }

    # Validate download
    if (!(Test-Path $outFile)) {
        throw "Download failed - file not found at: $outFile"
    }

    $fileInfo = Get-Item $outFile
    if ($fileInfo.Length -lt 100KB) {
        throw "Downloaded file appears incomplete ($($fileInfo.Length) bytes)"
    }

    Write-Log "Downloaded: $($fileInfo.Name) ($('{0:N2}' -f ($fileInfo.Length / 1MB)) MB)" "SUCCESS"

    # Extract archive
    Write-Log "Extracting archive..." "INFO"

    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Expand-Archive $outFile -DestinationPath $env:TEMP -Force
    Write-Log "Archive extracted" "SUCCESS"

    # Validate extraction
    $binSourcePath = Join-Path $extractPath "bin"
    if (!(Test-Path $binSourcePath)) {
        throw "Extraction failed - bin directory not found"
    }

    $extractedFiles = Get-ChildItem $binSourcePath -Recurse -File
    Write-Log "Bin directory contains $($extractedFiles.Count) files" "INFO"

    # Move bin directory to C:\Windows
    Write-Log "Moving bin directory to C:\Windows..." "INFO"
    $binDestPath = "C:\Windows\bin"

    if (Test-Path $binDestPath) {
        Remove-Item $binDestPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed existing C:\Windows\bin" "INFO"
    }

    Move-Item $binSourcePath $binDestPath -Force

    if (!(Test-Path $binDestPath)) {
        throw "Failed to move bin directory to C:\Windows\bin"
    }

    Write-Log "Bin directory moved to C:\Windows\bin" "SUCCESS"

    # === Modify registry-options.json ===
    Write-Log "Configuring registry-options.json..." "INFO"
    $jsonFilePath = Join-Path $binDestPath "registry-options.json"

    if (!(Test-Path $jsonFilePath)) {
        throw "registry-options.json not found at: $jsonFilePath"
    }

    # Read as proper JSON object
    $jsonContent = Get-Content -Path $jsonFilePath -Raw | ConvertFrom-Json

    # Keys to set true (all optimization toggles)
    $keysToSetTrue = @(
        "disable windows update"
        "disable automatic windows updates"
        "disable driver installation via windows update"
        "disable automatic store app updates"
        "disable gamebarpresencewriter"
        "disable background apps"
        "disable transparency effects"
        "disable notifications network usage"
        "disable windows marking file attachments with information about their zone of origin"
        "disable malicious software removal tool updates"
        "disable sticky keys"
        "disable pointer acceleration"
        "disable fast startup"
        "disable customer experience improvement program"
        "disable windows error reporting"
        "disable activity feed"
        "disable advertising id"
        "disable autoplay"
        "disable cloud content"
        "disable account-based explorer features"
        "disable mdm enrollment"
        "disable microsoft store push to install feature"
        "mitigate web-based search info"
        "disable sending inking and typing data to microsoft"
        "disable automatic maintenance"
        "disable program compatibility assistant"
        "disable remote assistance"
        "disable sign-in and lock last interactive user after a restart"
        "show file extensions"
        "disable widgets"
        "disable telemetry"
        "disable retrieval of online tips and help in the immersive control panel"
        "disable typing insights"
        "disable suggestions in the search box and in search home"
        "disable computer is out of support message"
        "disable fault tolerant heap"
    )

    # Keys to set false
    $keysToSetFalse = @(
        "disable windows defender"
        "disable clipboard history"
    )

    # Handle both flat and nested "options" structures
    $optionsObject = if ($jsonContent.PSObject.Properties.Name -contains "options") {
        $jsonContent.options
    } else {
        $jsonContent
    }

    # Iterate and modify values
    foreach ($property in $optionsObject.PSObject.Properties) {
        $key = $property.Name
        $currentValue = $property.Value

        if ($keysToSetTrue -contains $key) {
            if ($currentValue -eq $false) {
                $optionsObject.$key = $true
                $modifiedSettings += $key
                Write-Log "SET TRUE: $key" "SUCCESS"
            } else {
                $unchangedAlreadyTrue += $key
                Write-Log "ALREADY TRUE: $key" "SKIPPED"
            }
        } elseif ($keysToSetFalse -contains $key) {
            if ($currentValue -eq $true) {
                $optionsObject.$key = $false
                $modifiedSettings += "$key (set to FALSE)"
                Write-Log "SET FALSE: $key" "SUCCESS"
            } else {
                $unchangedAlreadyFalse += $key
                Write-Log "ALREADY FALSE: $key" "SKIPPED"
            }
        }
    }

    # Write modified JSON back
    $jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFilePath -Encoding UTF8

    Write-Log "Modified: $($modifiedSettings.Count) | Already true: $($unchangedAlreadyTrue.Count) | Already false: $($unchangedAlreadyFalse.Count)" "INFO"

    # === Execute apply-registry.ps1 and capture output ===
    Write-Log "Executing apply-registry.ps1..." "INFO"
    $applyRegistryPath = Join-Path $binDestPath "apply-registry.ps1"

    if (!(Test-Path $applyRegistryPath)) {
        throw "apply-registry.ps1 not found at: $applyRegistryPath"
    }

    # Capture stdout and stderr
    $stdOutFile = Join-Path $env:TEMP "apply-registry-stdout.txt"
    $stdErrFile = Join-Path $env:TEMP "apply-registry-stderr.txt"

    $registryProcess = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-ExecutionPolicy Bypass -NoProfile -NoLogo -File `"$applyRegistryPath`"" `
        -Wait -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdOutFile `
        -RedirectStandardError $stdErrFile

    # Read captured output
    $stdOut = if (Test-Path $stdOutFile) { Get-Content $stdOutFile -Raw } else { "" }
    $stdErr = if (Test-Path $stdErrFile) { Get-Content $stdErrFile -Raw } else { "" }

    # Clean up temp output files
    Remove-Item $stdOutFile, $stdErrFile -Force -ErrorAction SilentlyContinue

    # Parse and log apply-registry output
    if ($stdOut) {
        $registryOutputLines = $stdOut -split "`r?`n" | Where-Object { $_.Trim() -ne "" }
        Write-Log "=== apply-registry.ps1 Output ===" "INFO"
        foreach ($line in $registryOutputLines) {
            Write-Log "  $line" "INFO"
        }
        Write-Log "=== End apply-registry.ps1 Output ===" "INFO"
    }

    if ($stdErr) {
        $stderrLines = $stdErr -split "`r?`n" | Where-Object { $_.Trim() -ne "" }
        Write-Log "=== apply-registry.ps1 Errors ===" "WARNING"
        foreach ($line in $stderrLines) {
            Write-Log "  $line" "WARNING"
        }
        Write-Log "=== End apply-registry.ps1 Errors ===" "WARNING"
    }

    if ($registryProcess.ExitCode -ne 0) {
        Write-Log "apply-registry.ps1 exit code: $($registryProcess.ExitCode)" "WARNING"
    } else {
        Write-Log "apply-registry.ps1 completed successfully (exit code: 0)" "SUCCESS"
    }

    # === Summary ===
    Write-Log "=== ValleyOfDoom Configuration Summary ===" "INFO"
    Write-Log "Settings changed: $($modifiedSettings.Count)" "INFO"
    Write-Log "Unchanged (already true): $($unchangedAlreadyTrue.Count)" "INFO"
    Write-Log "Unchanged (already false - Keep Enabled): $($unchangedAlreadyFalse.Count)" "INFO"
    Write-Log "Total targeted: $($modifiedSettings.Count + $unchangedAlreadyTrue.Count + $unchangedAlreadyFalse.Count)" "INFO"

    if ($modifiedSettings.Count -gt 0) {
        Write-Log "Changed settings:" "INFO"
        foreach ($s in $modifiedSettings) { Write-Log "  - $s" "SUCCESS" }
    }

    if ($unchangedAlreadyTrue.Count -gt 0) {
        Write-Log "Already true (no change needed):" "INFO"
        foreach ($s in $unchangedAlreadyTrue) { Write-Log "  - $s" "SKIPPED" }
    }

    if ($unchangedAlreadyFalse.Count -gt 0) {
        Write-Log "Already false (kept as-is):" "INFO"
        foreach ($s in $unchangedAlreadyFalse) { Write-Log "  - $s" "SKIPPED" }
    }

    # Create status file
    $statusData = @{
        InstallDate                = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
        Status                     = "SUCCESS"
        SettingsChanged            = $modifiedSettings
        UnchangedAlreadyTrue       = $unchangedAlreadyTrue
        UnchangedAlreadyFalse      = $unchangedAlreadyFalse
        ChangedCount               = $modifiedSettings.Count
        AlreadyTrueCount           = $unchangedAlreadyTrue.Count
        AlreadyFalseCount          = $unchangedAlreadyFalse.Count
        TotalTargeted              = $modifiedSettings.Count + $unchangedAlreadyTrue.Count + $unchangedAlreadyFalse.Count
        RegistryExitCode           = $registryProcess.ExitCode
        ApplyRegistryOutput        = $registryOutputLines
        BinPath                    = $binDestPath
        LogFile                    = $LogFile
    }

    $statusData | ConvertTo-Json -Depth 3 | Out-File $StatusFile -Force

    Write-Log "Process completed successfully" "SUCCESS"
    Write-Log "Status file created: $StatusFile" "INFO"

} catch {
    Write-Log "Process failed: $($_.Exception.Message)" "ERROR"

    @{
        InstallDate          = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
        Status               = "FAILED"
        Error                = $_.Exception.Message
        SettingsChanged      = $modifiedSettings
        ChangedCount         = $modifiedSettings.Count
        LogFile              = $LogFile
    } | ConvertTo-Json -Depth 3 | Out-File $StatusFile -Force

    exit 1
} finally {
    if ($outFile -and (Test-Path $outFile)) {
        Remove-Item $outFile -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up downloaded archive" "INFO"
    }

    if ($extractPath -and (Test-Path $extractPath)) {
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up extraction directory" "INFO"
    }

    Write-Log "Cleanup completed" "INFO"
}

exit 0
