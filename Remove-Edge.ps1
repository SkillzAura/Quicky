# Enhanced Microsoft Edge Removal Script
# Author: SkillzAura
# Date: 2026-03-09
# Version: 3.3

# Admin elevation check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

# Configuration
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

# Force TLS 1.2 (critical for GitHub downloads on fresh Windows installs)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Setup logging to organized folder structure
$LogPath = "C:\ProgramData\Aura\OptimizationLogs"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$LogFile = Join-Path $LogPath "Remove-Edge-$(Get-Date -Format 'yyyy-MM-dd_hh-mm-ss-tt').log"

# Setup status file path
$StatusPath = "C:\ProgramData\Aura\StatusLogs"
if (!(Test-Path $StatusPath)) { New-Item -ItemType Directory -Path $StatusPath -Force | Out-Null }
$StatusFile = Join-Path $StatusPath "Remove-Edge.status"

# Initialize tracking variables
$operationsCompleted = @()
$operationsFailed = @()
$operationsSkipped = @()
$script:MinSudo = $null
$script:MinSudoAcquired = $false
$script:MinSudoExclusionFolder = $null
$script:MinSudoFinalPath = "C:\Windows\MinSudo.exe"

# Logging function for file output
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
}

# Helper: Run a script block and track success/failure
function Invoke-Step {
    param(
        [string]$StepName,
        [scriptblock]$Action
    )
    try {
        Write-Log "Executing: $StepName" "INFO"
        & $Action
        Write-Log "Completed: $StepName" "SUCCESS"
        $script:operationsCompleted += $StepName
    } catch {
        Write-Log "Failed: $StepName - $($_.Exception.Message)" "ERROR"
        $script:operationsFailed += $StepName
    }
}

# Helper: Run MinSudo commands safely (skips if MinSudo unavailable)
function Invoke-MinSudo {
    param(
        [string]$StepName,
        [string]$Arguments
    )

    if (-not $script:MinSudoAcquired -or -not $script:MinSudo -or !(Test-Path $script:MinSudo)) {
        Write-Log "Skipped (MinSudo unavailable): $StepName" "WARNING"
        $script:operationsSkipped += "$StepName (MinSudo unavailable)"
        return
    }

    try {
        Write-Log "Executing (MinSudo): $StepName" "INFO"
        $process = Start-Process -FilePath $script:MinSudo -ArgumentList "--NoLogo --TrustedInstaller --Privileged $Arguments" -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($process.ExitCode -ne 0) {
            Write-Log "MinSudo exit code $($process.ExitCode) for: $StepName" "WARNING"
        }
        Write-Log "Completed (MinSudo): $StepName" "SUCCESS"
        $script:operationsCompleted += $StepName
    } catch {
        Write-Log "Failed (MinSudo): $StepName - $($_.Exception.Message)" "ERROR"
        $script:operationsFailed += $StepName
    }
}

# Helper: Remove file/folder safely
function Remove-PathSafely {
    param(
        [string]$Path,
        [string]$Description
    )
    try {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Log "Removed: $Description ($Path)" "SUCCESS"
            $script:operationsCompleted += "Remove path: $Description"
        } else {
            Write-Log "Path not found (skipped): $Description ($Path)" "INFO"
            $script:operationsSkipped += "Remove path: $Description (not found)"
        }
    } catch {
        Write-Log "Failed to remove: $Description ($Path) - $($_.Exception.Message)" "ERROR"
        $script:operationsFailed += "Remove path: $Description"
    }
}

# Helper: Delete registry key via reg.exe
function Remove-RegKey {
    param(
        [string]$KeyPath,
        [string]$Description
    )
    try {
        $result = reg delete $KeyPath /f 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Deleted registry key: $Description ($KeyPath)" "SUCCESS"
            $script:operationsCompleted += "Delete reg key: $Description"
        } else {
            Write-Log "Registry key not found or already removed: $Description ($KeyPath)" "INFO"
            $script:operationsSkipped += "Delete reg key: $Description (not found)"
        }
    } catch {
        Write-Log "Failed to delete registry key: $Description ($KeyPath) - $($_.Exception.Message)" "ERROR"
        $script:operationsFailed += "Delete reg key: $Description"
    }
}

# Helper: Download file with WebClient (most reliable on fresh Windows)
function Invoke-FileDownload {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description
    )

    # Method 1: System.Net.WebClient (handles redirects, no IE dependency)
    try {
        Write-Log "Downloading $Description via WebClient: $Url" "INFO"
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Aura-Optimizer/3.3")
        $webClient.DownloadFile($Url, $OutFile)
        $webClient.Dispose()

        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 10KB) {
            Write-Log "Downloaded $Description successfully ($('{0:N2}' -f ((Get-Item $OutFile).Length / 1MB)) MB)" "SUCCESS"
            return $true
        }
    } catch {
        Write-Log "WebClient download failed for $Description`: $($_.Exception.Message)" "WARNING"
        if ($webClient) { $webClient.Dispose() }
    }

    # Method 2: Invoke-WebRequest with -UseBasicParsing
    try {
        Write-Log "Retrying $Description via Invoke-WebRequest..." "INFO"
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop

        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 10KB) {
            Write-Log "Downloaded $Description successfully ($('{0:N2}' -f ((Get-Item $OutFile).Length / 1MB)) MB)" "SUCCESS"
            return $true
        }
    } catch {
        Write-Log "Invoke-WebRequest download failed for $Description`: $($_.Exception.Message)" "WARNING"
    }

    return $false
}

# Helper: Acquire MinSudo from C:\Windows, %TEMP%, or download from NanaRun GitHub releases
function Get-MinSudo {
    $finalPath = $script:MinSudoFinalPath

    # Check if MinSudo already exists at final destination (C:\Windows\MinSudo.exe)
    if (Test-Path $finalPath) {
        $fileSize = (Get-Item $finalPath).Length
        if ($fileSize -gt 10KB) {
            Write-Log "MinSudo.exe found at final path: $finalPath ($fileSize bytes)" "SUCCESS"
            return $finalPath
        } else {
            Write-Log "MinSudo.exe at final path is too small ($fileSize bytes), re-downloading..." "WARNING"
            Remove-Item $finalPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Check if MinSudo exists in %TEMP% from another script
    $tempMinSudo = Join-Path $env:TEMP "MinSudo.exe"
    if (Test-Path $tempMinSudo) {
        $fileSize = (Get-Item $tempMinSudo).Length
        if ($fileSize -gt 10KB) {
            Write-Log "MinSudo.exe found in TEMP: $tempMinSudo ($fileSize bytes), moving to $finalPath" "INFO"
            try {
                Copy-Item -Path $tempMinSudo -Destination $finalPath -Force
                Add-MpPreference -ExclusionPath $finalPath -ErrorAction SilentlyContinue
                Write-Log "Added Defender exclusion for: $finalPath" "SUCCESS"
                return $finalPath
            } catch {
                Write-Log "Failed to move MinSudo from TEMP: $($_.Exception.Message)" "WARNING"
            }
        }
    }

    Write-Log "MinSudo.exe not found, downloading from NanaRun GitHub releases..." "INFO"

    # Create an excluded folder in %TEMP% for downloading
    $exclusionFolder = Join-Path $env:TEMP "AuraMinSudo-$(Get-Random)"
    $script:MinSudoExclusionFolder = $exclusionFolder

    try {
        # Create the download folder
        New-Item -ItemType Directory -Path $exclusionFolder -Force | Out-Null
        Write-Log "Created download folder: $exclusionFolder" "INFO"

        # Add Defender exclusion for the download folder BEFORE downloading
        try {
            Add-MpPreference -ExclusionPath $exclusionFolder -ErrorAction Stop
            Write-Log "Added Defender exclusion for download folder: $exclusionFolder" "SUCCESS"
        } catch {
            Write-Log "Could not add Defender exclusion for download folder: $($_.Exception.Message)" "WARNING"
        }

        # Also add exclusion for the final destination BEFORE moving
        try {
            Add-MpPreference -ExclusionPath $finalPath -ErrorAction Stop
            Write-Log "Added Defender exclusion for final path: $finalPath" "SUCCESS"
        } catch {
            Write-Log "Could not add Defender exclusion for final path: $($_.Exception.Message)" "WARNING"
        }

        # Brief pause to let Defender register the exclusions
        Start-Sleep -Seconds 2

        $zipPath = Join-Path $exclusionFolder "NanaRun.zip"
        $extractPath = Join-Path $exclusionFolder "NanaRun-Extract"
        $downloaded = $false

        # === Method 1: Scrape /releases/latest page (full releases only) ===
        Write-Log "Method 1: Scraping /releases/latest page..." "INFO"

        try {
            $releasesHtml = Invoke-WebRequest -Uri "https://github.com/M2Team/NanaRun/releases/latest" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $pageContent = $releasesHtml.Content

            # Extract tag from redirected URL
            $tag = $null
            $resolvedUrl = $releasesHtml.BaseResponse.ResponseUri
            if (-not $resolvedUrl) {
                $resolvedUrl = $releasesHtml.BaseResponse.RequestMessage.RequestUri
            }

            $resolvedString = "$resolvedUrl"
            if ($resolvedString -match '/releases/tag/([^/"]+)') {
                $tag = $matches[1]
                Write-Log "Found latest release tag from redirect: $tag" "SUCCESS"
            }

            # Fallback: parse tag from HTML
            if (-not $tag) {
                if ($pageContent -match '/M2Team/NanaRun/releases/tag/([^"''&/]+)') {
                    $tag = $matches[1]
                    Write-Log "Found latest release tag from HTML: $tag" "SUCCESS"
                }
            }

            if ($tag) {
                # Find the NanaRun zip from page links (wildcard match)
                $zipLink = $releasesHtml.Links | Where-Object { $_.href -like "*/download/$tag/NanaRun*" -and $_.href -like "*.zip" } | Select-Object -First 1

                $zipFileName = $null
                if ($zipLink) {
                    $zipFileName = ($zipLink.href -split '/')[-1]
                    Write-Log "Found NanaRun zip from links: $zipFileName" "SUCCESS"
                }

                # Fallback: parse from HTML content
                if (-not $zipFileName) {
                    if ($pageContent -match '/M2Team/NanaRun/releases/download/[^/]+/(NanaRun[^"''&\s]+\.zip)') {
                        $zipFileName = $matches[1]
                        Write-Log "Found NanaRun zip from HTML: $zipFileName" "SUCCESS"
                    }
                }

                if ($zipFileName) {
                    $downloadUrl = "https://github.com/M2Team/NanaRun/releases/download/$tag/$zipFileName"
                    Write-Log "Constructed download URL: $downloadUrl" "INFO"
                    $downloaded = Invoke-FileDownload -Url $downloadUrl -OutFile $zipPath -Description "NanaRun ($zipFileName)"
                }
            }
        } catch {
            Write-Log "Method 1 failed: $($_.Exception.Message)" "WARNING"
        }

        # === Method 2: Scrape /releases page (catches pre-releases too) ===
        if (-not $downloaded) {
            Write-Log "Method 2: Scraping /releases page (includes pre-releases)..." "INFO"

            try {
                $allReleasesHtml = Invoke-WebRequest -Uri "https://github.com/M2Team/NanaRun/releases" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop

                # Find the first NanaRun*.zip download link on the releases page
                $zipLink = $allReleasesHtml.Links | Where-Object { $_.href -like "*/download/*/NanaRun*" -and $_.href -like "*.zip" } | Select-Object -First 1

                if ($zipLink) {
                    $zipFileName = ($zipLink.href -split '/')[-1]
                    # Construct full URL from relative href
                    $downloadUrl = if ($zipLink.href -match '^https?://') {
                        $zipLink.href
                    } else {
                        "https://github.com$($zipLink.href)"
                    }
                    Write-Log "Found NanaRun zip from releases page: $zipFileName" "SUCCESS"
                    Write-Log "Download URL: $downloadUrl" "INFO"
                    $downloaded = Invoke-FileDownload -Url $downloadUrl -OutFile $zipPath -Description "NanaRun ($zipFileName)"
                } else {
                    Write-Log "No NanaRun zip links found on releases page" "WARNING"
                }
            } catch {
                Write-Log "Method 2 failed: $($_.Exception.Message)" "WARNING"
            }
        }

        # === Method 3: Scrape /tags page and try expanded_assets ===
        if (-not $downloaded) {
            Write-Log "Method 3: Scraping /tags page and expanded_assets..." "INFO"

            try {
                $tagsHtml = Invoke-WebRequest -Uri "https://github.com/M2Team/NanaRun/tags" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                $tagMatches = [regex]::Matches($tagsHtml.Content, '/M2Team/NanaRun/releases/tag/([^"''&/]+)')

                if ($tagMatches.Count -gt 0) {
                    $latestTag = $tagMatches[0].Groups[1].Value
                    Write-Log "Found tag from tags page: $latestTag" "INFO"

                    # Try expanded_assets to find the actual zip name
                    try {
                        $assetsHtml = Invoke-WebRequest -Uri "https://github.com/M2Team/NanaRun/releases/expanded_assets/$latestTag" -UseBasicParsing -TimeoutSec 30 -ErrorAction SilentlyContinue
                        if ($assetsHtml) {
                            $assetLink = $assetsHtml.Links | Where-Object { $_.href -like "*.zip" -and $_.href -like "*NanaRun*" } | Select-Object -First 1
                            if ($assetLink) {
                                $zipFileName = ($assetLink.href -split '/')[-1]
                                $downloadUrl = if ($assetLink.href -match '^https?://') {
                                    $assetLink.href
                                } else {
                                    "https://github.com$($assetLink.href)"
                                }
                                Write-Log "Found NanaRun zip from expanded_assets: $zipFileName" "SUCCESS"
                                $downloaded = Invoke-FileDownload -Url $downloadUrl -OutFile $zipPath -Description "NanaRun ($zipFileName)"
                            }
                        }
                    } catch {
                        Write-Log "expanded_assets scraping failed: $($_.Exception.Message)" "WARNING"
                    }

                    # Fallback: try the release page for this specific tag
                    if (-not $downloaded) {
                        try {
                            $tagReleaseHtml = Invoke-WebRequest -Uri "https://github.com/M2Team/NanaRun/releases/tag/$latestTag" -UseBasicParsing -TimeoutSec 30 -ErrorAction SilentlyContinue
                            if ($tagReleaseHtml) {
                                $assetLink = $tagReleaseHtml.Links | Where-Object { $_.href -like "*/download/$latestTag/NanaRun*" -and $_.href -like "*.zip" } | Select-Object -First 1
                                if ($assetLink) {
                                    $zipFileName = ($assetLink.href -split '/')[-1]
                                    $downloadUrl = if ($assetLink.href -match '^https?://') {
                                        $assetLink.href
                                    } else {
                                        "https://github.com$($assetLink.href)"
                                    }
                                    Write-Log "Found NanaRun zip from tag release page: $zipFileName" "SUCCESS"
                                    $downloaded = Invoke-FileDownload -Url $downloadUrl -OutFile $zipPath -Description "NanaRun ($zipFileName)"
                                }
                            }
                        } catch {
                            Write-Log "Tag release page scraping failed: $($_.Exception.Message)" "WARNING"
                        }
                    }
                }
            } catch {
                Write-Log "Method 3 failed: $($_.Exception.Message)" "WARNING"
            }
        }

        if (-not $downloaded) {
            throw "All NanaRun download methods failed"
        }

        # Validate zip
        $zipFileInfo = Get-Item $zipPath
        if ($zipFileInfo.Length -lt 50KB) {
            throw "Downloaded NanaRun zip appears to be incomplete ($($zipFileInfo.Length) bytes)"
        }
        Write-Log "NanaRun zip downloaded: $('{0:N2}' -f ($zipFileInfo.Length / 1MB)) MB" "SUCCESS"

        # Extract the zip inside the excluded folder
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
        Write-Log "Extracted NanaRun zip" "SUCCESS"

        # Log extraction contents for debugging
        $extractedFiles = Get-ChildItem -Path $extractPath -Recurse -File
        Write-Log "Extracted files ($($extractedFiles.Count) total):" "INFO"
        foreach ($item in $extractedFiles) {
            Write-Log "  $($item.FullName)" "INFO"
        }

        # Find MinSudo.exe inside x64 folder first
        $minSudoSource = Get-ChildItem -Path $extractPath -Recurse -Filter "MinSudo.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -like "*x64*" } |
            Select-Object -First 1

        if (-not $minSudoSource) {
            Write-Log "MinSudo.exe not found in x64 subfolder, searching all folders..." "WARNING"
            $minSudoSource = Get-ChildItem -Path $extractPath -Recurse -Filter "MinSudo.exe" -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }

        if (-not $minSudoSource) {
            throw "MinSudo.exe not found inside extracted NanaRun archive"
        }

        Write-Log "Found MinSudo.exe at: $($minSudoSource.FullName)" "INFO"

        # Move MinSudo.exe to C:\Windows (already excluded above)
        Copy-Item -Path $minSudoSource.FullName -Destination $finalPath -Force
        Write-Log "Copied MinSudo.exe to: $finalPath" "SUCCESS"

        # Validate the copied file
        if (!(Test-Path $finalPath)) {
            throw "MinSudo.exe copy to $finalPath failed"
        }

        $copiedSize = (Get-Item $finalPath).Length
        Write-Log "MinSudo.exe at final path: $copiedSize bytes" "INFO"

        return $finalPath

    } catch {
        Write-Log "Failed to acquire MinSudo: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

try {
    Write-Log "Starting Microsoft Edge Removal Process" "INFO"
    Write-Log "Script Version: 3.3" "INFO"

    # ============================================================
    # STEP 1: Acquire MinSudo (non-fatal if it fails)
    # ============================================================
    Write-Log "=== Step 1: Acquiring MinSudo ===" "INFO"

    $script:MinSudo = Get-MinSudo

    if ($script:MinSudo -and (Test-Path $script:MinSudo)) {
        $script:MinSudoAcquired = $true
        Write-Log "MinSudo ready at: $($script:MinSudo)" "SUCCESS"
    } else {
        $script:MinSudoAcquired = $false
        Write-Log "MinSudo could not be acquired - TrustedInstaller operations will be skipped" "WARNING"
        $operationsFailed += "Acquire MinSudo"
    }

    # ============================================================
    # STEP 2: Kill all WebView processes first, then Edge processes
    # ============================================================
    Write-Log "=== Step 2: Terminating WebView and Edge Processes ===" "INFO"

    Invoke-Step "Stop msedgewebview2 processes" {
        $webviewProcs = Get-Process -Name "msedgewebview2" -ErrorAction SilentlyContinue
        if ($webviewProcs) {
            Stop-Process -Name "msedgewebview2" -Force -ErrorAction Stop
            Write-Log "Stopped $($webviewProcs.Count) msedgewebview2 process(es)" "INFO"
        } else {
            Write-Log "No msedgewebview2 processes running" "INFO"
        }
    }

    Invoke-Step "Stop MicrosoftEdgeUpdate processes" {
        $updateProcs = Get-Process -Name "MicrosoftEdgeUpdate" -ErrorAction SilentlyContinue
        if ($updateProcs) {
            Stop-Process -Name "MicrosoftEdgeUpdate" -Force -ErrorAction Stop
            Write-Log "Stopped $($updateProcs.Count) MicrosoftEdgeUpdate process(es)" "INFO"
        } else {
            Write-Log "No MicrosoftEdgeUpdate processes running" "INFO"
        }
    }

    Invoke-Step "Stop msedge processes" {
        $edgeProcs = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
        if ($edgeProcs) {
            Stop-Process -Name "msedge" -Force -ErrorAction Stop
            Write-Log "Stopped $($edgeProcs.Count) msedge process(es)" "INFO"
        } else {
            Write-Log "No msedge processes running" "INFO"
        }
    }

    Invoke-Step "Stop MicrosoftEdge processes" {
        $edgeProcs = Get-Process -Name "MicrosoftEdge*" -ErrorAction SilentlyContinue
        if ($edgeProcs) {
            $edgeProcs | Stop-Process -Force -ErrorAction Stop
            Write-Log "Stopped $($edgeProcs.Count) MicrosoftEdge process(es)" "INFO"
        } else {
            Write-Log "No MicrosoftEdge processes running" "INFO"
        }
    }

    Invoke-Step "Stop Edge-related processes by description" {
        $edgeDescProcs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Description -like "*Edge*" }
        if ($edgeDescProcs) {
            $edgeDescProcs | Stop-Process -Force -ErrorAction Stop
            Write-Log "Stopped $($edgeDescProcs.Count) Edge-related process(es) by description" "INFO"
        } else {
            Write-Log "No Edge-related processes found by description" "INFO"
        }
    }

    Start-Sleep -Seconds 3

    # ============================================================
    # STEP 3: Remove Edge AppX packages via MinSudo (Edge + WebView)
    # ============================================================
    Write-Log "=== Step 3: Removing Edge and WebView AppX Packages ===" "INFO"

    Invoke-MinSudo "Remove Edge Stable AppX package" 'Powershell "Get-AppxPackage -AllUsers *MicrosoftEdge.Stable* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue"'
    Invoke-MinSudo "Remove Edge WebView AppX package" 'Powershell "Get-AppxPackage -AllUsers *MicrosoftEdgeWebview* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue"'
    Invoke-MinSudo "Remove Edge Dev AppX package" 'Powershell "Get-AppxPackage -AllUsers *MicrosoftEdge.Dev* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue"'
    Invoke-MinSudo "Remove Edge Beta AppX package" 'Powershell "Get-AppxPackage -AllUsers *MicrosoftEdge.Beta* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue"'

    # ============================================================
    # STEP 4: Run Edge's own uninstaller
    # ============================================================
    Write-Log "=== Step 4: Running Edge Uninstaller ===" "INFO"

    Invoke-Step "Run Edge setup.exe uninstaller" {
        $edgeInstallerPaths = Get-ChildItem "C:\Program Files (x86)\Microsoft\Edge\Application\*\Installer" -ErrorAction SilentlyContinue
        if ($edgeInstallerPaths) {
            foreach ($path in $edgeInstallerPaths) {
                $setupExe = Join-Path $path.FullName "setup.exe"
                if (Test-Path $setupExe) {
                    Write-Log "Found Edge uninstaller: $setupExe" "INFO"
                    $process = Start-Process -FilePath $setupExe -ArgumentList "-uninstall -system-level -verbose-logging -force-uninstall" -Wait -PassThru -ErrorAction Stop
                    Write-Log "Edge uninstaller exited with code: $($process.ExitCode)" "INFO"
                } else {
                    Write-Log "setup.exe not found in: $($path.FullName)" "WARNING"
                }
            }
        } else {
            Write-Log "No Edge installer directories found" "INFO"
        }
    }

    # ============================================================
    # STEP 5: Run WebView's own uninstaller
    # ============================================================
    Write-Log "=== Step 5: Running WebView Uninstaller ===" "INFO"

    Invoke-Step "Run WebView setup.exe uninstaller" {
        $webviewInstallerPaths = Get-ChildItem "C:\Program Files (x86)\Microsoft\EdgeWebView\Application\*\Installer" -ErrorAction SilentlyContinue
        if ($webviewInstallerPaths) {
            foreach ($path in $webviewInstallerPaths) {
                $setupExe = Join-Path $path.FullName "setup.exe"
                if (Test-Path $setupExe) {
                    Write-Log "Found WebView uninstaller: $setupExe" "INFO"
                    $process = Start-Process -FilePath $setupExe -ArgumentList "-uninstall -system-level -verbose-logging -force-uninstall" -Wait -PassThru -ErrorAction Stop
                    Write-Log "WebView uninstaller exited with code: $($process.ExitCode)" "INFO"
                } else {
                    Write-Log "setup.exe not found in: $($path.FullName)" "WARNING"
                }
            }
        } else {
            Write-Log "No WebView installer directories found" "INFO"
        }
    }

    Start-Sleep -Seconds 3

    # ============================================================
    # STEP 6: Remove Edge and WebView shortcuts and user data
    # ============================================================
    Write-Log "=== Step 6: Removing Edge Shortcuts and User Data ===" "INFO"

    Remove-PathSafely "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk" "Start Menu shortcut"
    Remove-PathSafely "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk" "Quick Launch shortcut"
    Remove-PathSafely "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk" "Taskbar pinned shortcut"
    Remove-PathSafely "$env:PUBLIC\Desktop\Microsoft Edge.lnk" "Public desktop shortcut"
    Remove-PathSafely "C:\Windows\System32\config\systemprofile\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk" "System profile Quick Launch shortcut"
    Remove-PathSafely "$env:LOCALAPPDATA\Microsoft\Edge" "Edge local app data"
    Remove-PathSafely "$env:LOCALAPPDATA\Microsoft\EdgeWebView" "EdgeWebView local app data"
    Remove-PathSafely "C:\ProgramData\Microsoft\EdgeUpdate" "EdgeUpdate data"

    # ============================================================
    # STEP 7: Remove Edge system files via MinSudo (requires TrustedInstaller)
    # ============================================================
    Write-Log "=== Step 7: Removing Edge System Files (TrustedInstaller) ===" "INFO"

    Invoke-MinSudo "Remove Edge WebView system folder" 'Powershell "Remove-Item ''C:\Windows\System32\Microsoft-Edge-WebView'' -Recurse -Force -ErrorAction SilentlyContinue"'
    Invoke-MinSudo "Remove EdgeUpdate program files" 'Powershell "Remove-Item ''C:\Program Files (x86)\Microsoft\EdgeUpdate'' -Recurse -Force -ErrorAction SilentlyContinue"'
    Invoke-MinSudo "Remove EdgeWebView program files" 'Powershell "Remove-Item ''C:\Program Files (x86)\Microsoft\EdgeWebView'' -Recurse -Force -ErrorAction SilentlyContinue"'
    Invoke-MinSudo "Remove Edge program files" 'Powershell "Remove-Item ''C:\Program Files (x86)\Microsoft\Edge'' -Recurse -Force -ErrorAction SilentlyContinue"'
    Invoke-MinSudo "Remove all Edge-related program files" 'Powershell "Get-ChildItem ''C:\Program Files (x86)\Microsoft'' -Directory -Filter ''*Edge*'' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue"'

    # ============================================================
    # STEP 8: Remove Edge and WebView services from registry
    # ============================================================
    Write-Log "=== Step 8: Removing Edge Services ===" "INFO"

    Invoke-Step "Remove Edge Update services" {
        $edgeServices = Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services\edgeupdate*" -ErrorAction SilentlyContinue
        if ($edgeServices) {
            foreach ($svc in $edgeServices) {
                Remove-Item -Path $svc.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed service registry: $($svc.Name)" "INFO"
            }
        } else {
            Write-Log "No edgeupdate services found" "INFO"
        }
    }

    Invoke-Step "Remove MicrosoftEdge services" {
        $edgeServices = Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services\MicrosoftEdge*" -ErrorAction SilentlyContinue
        if ($edgeServices) {
            foreach ($svc in $edgeServices) {
                Remove-Item -Path $svc.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed service registry: $($svc.Name)" "INFO"
            }
        } else {
            Write-Log "No MicrosoftEdge services found" "INFO"
        }
    }

    Invoke-Step "Remove EdgeWebView services" {
        $webviewServices = Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services\*EdgeWebView*" -ErrorAction SilentlyContinue
        if ($webviewServices) {
            foreach ($svc in $webviewServices) {
                Remove-Item -Path $svc.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed WebView service registry: $($svc.Name)" "INFO"
            }
        } else {
            Write-Log "No EdgeWebView services found" "INFO"
        }
    }

    # ============================================================
    # STEP 9: Clean Edge registry keys (user-level)
    # ============================================================
    Write-Log "=== Step 9: Cleaning Edge Registry Keys ===" "INFO"

    Invoke-Step "Remove HKCU Edge software keys" {
        $keys = Get-ChildItem -Path "HKCU:\Software\Microsoft\*Edge*" -ErrorAction SilentlyContinue
        if ($keys) {
            foreach ($key in $keys) {
                Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed: $($key.Name)" "INFO"
            }
        } else {
            Write-Log "No HKCU Edge software keys found" "INFO"
        }
    }

    Invoke-Step "Remove WOW6432Node Edge keys" {
        $keys = Get-ChildItem -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\*Edge*" -ErrorAction SilentlyContinue
        if ($keys) {
            foreach ($key in $keys) {
                Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed: $($key.Name)" "INFO"
            }
        } else {
            Write-Log "No WOW6432Node Edge keys found" "INFO"
        }
    }

    Invoke-Step "Remove Edge URL association keys" {
        $keys = Get-ChildItem -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\microsoft-edge*" -ErrorAction SilentlyContinue
        if ($keys) {
            foreach ($key in $keys) {
                Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed: $($key.Name)" "INFO"
            }
        } else {
            Write-Log "No Edge URL association keys found" "INFO"
        }
    }

    Invoke-Step "Remove MSEdge HKLM class keys" {
        $keys = Get-ChildItem -Path "HKLM:\SOFTWARE\Classes\MSEdge*" -ErrorAction SilentlyContinue
        if ($keys) {
            foreach ($key in $keys) {
                Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed: $($key.Name)" "INFO"
            }
        } else {
            Write-Log "No MSEdge class keys found" "INFO"
        }
    }

    Remove-RegKey "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\{1FD49718-1D00-4B19-AF5F-070AF6D5D54C}" "Edge CLSID"
    Remove-RegKey "HKEY_LOCAL_MACHINE\SOFTWARE\Clients\StartMenuInternet\Microsoft Edge" "Edge StartMenuInternet client"
    Remove-RegKey "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects" "Browser Helper Objects"

    # ============================================================
    # STEP 10: Remove Edge Application Association Toasts
    # ============================================================
    Write-Log "=== Step 10: Removing Edge Application Association Toasts ===" "INFO"

    Invoke-Step "Remove Edge Application Association Toasts" {
        $toastsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts"
        if (Test-Path $toastsKey) {
            $values = Get-ItemProperty -Path $toastsKey -ErrorAction SilentlyContinue
            $removedCount = 0
            foreach ($valueName in $values.PSObject.Properties.Name) {
                if ($valueName -like "MSEdge*") {
                    Remove-ItemProperty -Path $toastsKey -Name $valueName -ErrorAction SilentlyContinue
                    $removedCount++
                }
            }
            Write-Log "Removed $removedCount MSEdge toast association(s)" "INFO"
        } else {
            Write-Log "ApplicationAssociationToasts key not found" "INFO"
        }
    }

    # ============================================================
    # STEP 11: Remove Edge from OpenWithProgIds
    # ============================================================
    Write-Log "=== Step 11: Removing Edge from OpenWithProgIds ===" "INFO"

    Invoke-Step "Remove Edge from file type ProgIds" {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $SID = $currentUser.User.Value
        Write-Log "Current user SID: $SID" "INFO"

        $progIdPaths = @(
            "Registry::HKEY_CLASSES_ROOT\.htm\OpenWithProgIds",
            "Registry::HKEY_CLASSES_ROOT\.html\OpenWithProgIds",
            "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\.mhtml\OpenWithProgIds",
            "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\.pdf\OpenWithProgids",
            "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\.webp\OpenWithProgids",
            "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts",
            "Registry::HKEY_USERS\$SID\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts"
        )

        foreach ($regPath in $progIdPaths) {
            if (Test-Path $regPath) {
                $properties = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                $removedCount = 0
                foreach ($propName in $properties.PSObject.Properties.Name) {
                    if ($propName -like "MSEdge*") {
                        Remove-ItemProperty -Path $regPath -Name $propName -ErrorAction SilentlyContinue
                        $removedCount++
                    }
                }
                if ($removedCount -gt 0) {
                    Write-Log "Removed $removedCount MSEdge ProgId entries from: $regPath" "INFO"
                }
            }
        }
    }

    # ============================================================
    # STEP 12: Remove Edge uninstall entries and scheduled tasks via MinSudo
    # ============================================================
    Write-Log "=== Step 12: Removing Edge Uninstall Entries and Task Cache ===" "INFO"

    Invoke-MinSudo "Remove Edge Update uninstall key" 'reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f'
    Invoke-MinSudo "Remove EdgeWebView uninstall key" 'reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebview" /f'
    Invoke-MinSudo "Remove Edge uninstall key" 'reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f'
    Invoke-MinSudo "Remove EdgeUpdateTaskMachineCore from task cache" 'reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\MicrosoftEdgeUpdateTaskMachineCore" /f'
    Invoke-MinSudo "Remove EdgeUpdateTaskMachineUA from task cache" 'reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\MicrosoftEdgeUpdateTaskMachineUA" /f'
    Invoke-MinSudo "Remove WOW6432Node MicrosoftEdge key" 'Powershell "reg delete ''HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\MicrosoftEdge'' /f"'

    # ============================================================
    # STEP 13: Remove remaining registry keys via reg.exe
    # ============================================================
    Write-Log "=== Step 13: Removing Remaining Edge Registry Keys ===" "INFO"

    Remove-RegKey "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Active Setup\Installed Components\{9459C573-B17A-45AE-9F64-1857B5D58CEE}" "Edge Active Setup component"
    Remove-RegKey "HKEY_CURRENT_USER\Software\Classes\microsoft-edge-holographic" "Edge holographic class"
    Remove-RegKey "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MicrosoftEdgeUpdate.exe" "EdgeUpdate IFEO"

    # ============================================================
    # STEP 14: Disable Edge scheduled tasks
    # ============================================================
    Write-Log "=== Step 14: Disabling Edge Scheduled Tasks ===" "INFO"

    Invoke-Step "Disable Edge scheduled tasks" {
        $edgeTasks = Get-ScheduledTask -TaskName "*Edge*" -ErrorAction SilentlyContinue
        if ($edgeTasks) {
            $disabledCount = 0
            foreach ($task in $edgeTasks) {
                try {
                    Disable-ScheduledTask -TaskName $task.TaskName -ErrorAction SilentlyContinue | Out-Null
                    Write-Log "Disabled scheduled task: $($task.TaskName)" "INFO"
                    $disabledCount++
                } catch {
                    Write-Log "Failed to disable task: $($task.TaskName) - $($_.Exception.Message)" "WARNING"
                }
            }
            Write-Log "Disabled $disabledCount Edge scheduled task(s)" "INFO"
        } else {
            Write-Log "No Edge scheduled tasks found" "INFO"
        }
    }

    # ============================================================
    # STEP 15: Prevent Edge from reinstalling
    # ============================================================
    Write-Log "=== Step 15: Preventing Edge Reinstallation ===" "INFO"

    Invoke-Step "Set registry to prevent Edge reinstall" {
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\EdgeUpdate" /v "DoNotUpdateToEdgeWithChromium" /t REG_DWORD /d 1 /f >$null 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Set DoNotUpdateToEdgeWithChromium = 1" "SUCCESS"
        }

        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "CreateDesktopShortcutDefault" /t REG_DWORD /d 0 /f >$null 2>&1
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "RemoveDesktopShortcutDefault" /t REG_DWORD /d 1 /f >$null 2>&1
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "InstallDefault" /t REG_DWORD /d 0 /f >$null 2>&1
        # Block Edge WebView2 Updates specifically via App GUID
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "Update{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" /t REG_DWORD /d 0 /f >$null 2>&1
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "Install{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" /t REG_DWORD /d 0 /f >$null 2>&1
        # Block ALL automatic updates globally via EdgeUpdate policy
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "UpdateDefault" /t REG_DWORD /d 0 /f >$null 2>&1

        Write-Log "Applied Edge reinstallation prevention policies" "SUCCESS"
    }

# ============================================================
    # STEP 15.5: Create Dummy File Blocks for Edge Directories
    # ============================================================
    Write-Log "=== Step 15.5: Creating Dummy File Blocks ===" "INFO"

    Invoke-Step "Create dummy files to prevent folder recreation" {
        $pathsToBlock = @(
            "C:\Program Files (x86)\Microsoft\Edge",
            "C:\Program Files (x86)\Microsoft\EdgeWebView",
            "C:\Program Files (x86)\Microsoft\EdgeUpdate"
        )

        foreach ($path in $pathsToBlock) {
            # Only create the block if the folder was successfully deleted
            if (-not (Test-Path $path)) {
                try {
                    # Create a blank file with no extension
                    New-Item -ItemType File -Path $path -Force -ErrorAction Stop | Out-Null
                    
                    # Set to ReadOnly and System to prevent the updater from overwriting it
                    Set-ItemProperty -Path $path -Name Attributes -Value "ReadOnly, System" -ErrorAction Stop
                    
                    Write-Log "Created locked dummy file at: $path" "SUCCESS"
                } catch {
                    Write-Log "Failed to create dummy file at $path - $($_.Exception.Message)" "WARNING"
                }
            } else {
                Write-Log "Directory still exists, cannot create dummy file block at: $path" "WARNING"
            }
        }
    }

    # ============================================================
    # STEP 16: Verify Edge and WebView removal
    # ============================================================
    Write-Log "=== Step 16: Verifying Edge and WebView Removal ===" "INFO"

    $edgeStillExists = $false
    $webviewStillExists = $false

    $edgeExePaths = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($exePath in $edgeExePaths) {
        if (Test-Path $exePath) {
            Write-Log "Edge executable still found at: $exePath" "WARNING"
            $edgeStillExists = $true
        }
    }

    $webviewExePaths = @(
        "C:\Program Files (x86)\Microsoft\EdgeWebView\Application\msedgewebview2.exe",
        "$env:LOCALAPPDATA\Microsoft\EdgeWebView\Application\msedgewebview2.exe"
    )
    foreach ($exePath in $webviewExePaths) {
        if (Test-Path $exePath) {
            Write-Log "WebView executable still found at: $exePath" "WARNING"
            $webviewStillExists = $true
        }
    }

    $edgeAppx = Get-AppxPackage -Name "*MicrosoftEdge.Stable*" -ErrorAction SilentlyContinue
    if ($edgeAppx) {
        Write-Log "Edge AppX package still present" "WARNING"
        $edgeStillExists = $true
    }

    $webviewAppx = Get-AppxPackage -Name "*MicrosoftEdgeWebview*" -ErrorAction SilentlyContinue
    if ($webviewAppx) {
        Write-Log "WebView AppX package still present" "WARNING"
        $webviewStillExists = $true
    }

    if (-not $edgeStillExists) {
        Write-Log "Edge removal verification: No Edge components detected" "SUCCESS"
    } else {
        Write-Log "Edge removal verification: Some Edge components may still be present (may require reboot)" "WARNING"
    }

    if (-not $webviewStillExists) {
        Write-Log "WebView removal verification: No WebView components detected" "SUCCESS"
    } else {
        Write-Log "WebView removal verification: Some WebView components may still be present (may require reboot)" "WARNING"
    }

    # ============================================================
    # Summary
    # ============================================================
    $totalOperations = $operationsCompleted.Count + $operationsFailed.Count + $operationsSkipped.Count
    $successCount = $operationsCompleted.Count
    $failedCount = $operationsFailed.Count
    $skippedCount = $operationsSkipped.Count

    Write-Log "=== Microsoft Edge Removal Summary ===" "INFO"
    Write-Log "Total operations: $totalOperations" "INFO"
    Write-Log "Successful: $successCount" "SUCCESS"
    Write-Log "Failed: $failedCount" "INFO"
    Write-Log "Skipped: $skippedCount" "INFO"

    if ($operationsFailed.Count -gt 0) {
        Write-Log "Failed operations:" "WARNING"
        foreach ($op in $operationsFailed) {
            Write-Log "  - $op" "WARNING"
        }
    }

    if ($operationsSkipped.Count -gt 0) {
        Write-Log "Skipped operations:" "INFO"
        foreach ($op in $operationsSkipped) {
            Write-Log "  - $op" "INFO"
        }
    }

    $overallStatus = if ($failedCount -eq 0 -and $successCount -gt 0) {
        "SUCCESS"
    } elseif ($successCount -gt 0 -and $failedCount -gt 0) {
        "PARTIAL_SUCCESS"
    } elseif ($failedCount -gt 0 -and $successCount -eq 0) {
        "FAILED"
    } else {
        "NO_CHANGES"
    }

    @{
        InstallDate = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
        Status = $overallStatus
        TotalOperations = $totalOperations
        SuccessfulOperations = $successCount
        FailedOperations = $failedCount
        SkippedOperations = $skippedCount
        EdgeStillDetected = $edgeStillExists
        WebViewStillDetected = $webviewStillExists
        MinSudoAcquired = $script:MinSudoAcquired
        MinSudoPath = if ($script:MinSudoAcquired) { $script:MinSudo } else { $null }
        CompletedOperations = $operationsCompleted
        FailedOperationDetails = if ($operationsFailed.Count -gt 0) { $operationsFailed } else { $null }
        SkippedOperationDetails = if ($operationsSkipped.Count -gt 0) { $operationsSkipped } else { $null }
        LogFile = $LogFile
        ScriptVersion = "3.3"
    } | ConvertTo-Json -Depth 3 | Out-File $StatusFile -Force

    Write-Log "Microsoft Edge removal completed with status: $overallStatus" "SUCCESS"
    Write-Log "Status file created: $StatusFile" "INFO"

} catch {
    Write-Log "Microsoft Edge removal failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.Exception.StackTrace)" "ERROR"

    @{
        InstallDate = Get-Date -Format "yyyy-MM-dd hh:mm:ss tt"
        Status = "FAILED"
        Error = $_.Exception.Message
        MinSudoAcquired = $script:MinSudoAcquired
        CompletedOperations = $operationsCompleted
        FailedOperations = $operationsFailed
        SkippedOperations = $operationsSkipped
        LogFile = $LogFile
        ScriptVersion = "3.3"
    } | ConvertTo-Json -Depth 3 | Out-File $StatusFile -Force

    exit 1
} finally {
    # Cleanup: Remove the TEMP exclusion folder and its Defender exclusion
    if ($script:MinSudoExclusionFolder) {
        # Remove the folder itself
        if (Test-Path $script:MinSudoExclusionFolder) {
            Remove-Item $script:MinSudoExclusionFolder -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Cleaned up download folder: $($script:MinSudoExclusionFolder)" "INFO"
        }

        # Remove the Defender exclusion for the TEMP download folder (no longer needed)
        try {
            Remove-MpPreference -ExclusionPath $script:MinSudoExclusionFolder -ErrorAction SilentlyContinue
            Write-Log "Removed Defender exclusion for download folder" "INFO"
        } catch {
            Write-Log "Could not remove Defender exclusion for download folder: $($_.Exception.Message)" "WARNING"
        }
    }

    # NOTE: We intentionally KEEP the C:\Windows\MinSudo.exe exclusion and file
    # so other scripts (Remove-AI.ps1, etc.) can reuse it without re-downloading

    Write-Log "Remove-Edge script execution completed" "INFO"
}

exit 0
