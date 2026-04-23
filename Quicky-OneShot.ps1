# Quicky-OneShot.ps1

# Ensure the directory exists
$scriptPath = 'C:\Windows\Setup\Scripts\files'
If (-Not (Test-Path -Path $scriptPath)) {
    New-Item -ItemType Directory -Path $scriptPath
}

# Add Defender exclusion
Add-MpPreference -ExclusionPath $scriptPath

# Download executables
Invoke-WebRequest -Uri 'https://github.com/SkillzAura/Quicky/releases/download/Power/Power.exe' -OutFile "$scriptPath\Power.exe"
Invoke-WebRequest -Uri 'https://github.com/SkillzAura/Quicky/releases/download/Minsudo/MinSudo.exe' -OutFile "$scriptPath\MinSudo.exe"

# ValleyOfDoom logic here
# (Download/execute source archive and apply registry options)

# Remove-Edge logic here
# (Use MinSudo for removal processes)

# Change service start-types using reg add
$services = @(
    'CryptSvc',
    'SysMain',
    'WSearch',
    'DusmSvc',
    'lfsvc',
    'Spooler',
    'msisadrv'
)
ForEach ($service in $services) {
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\$service" /v Start /t REG_DWORD /d 3 /f
}

# Sound configuration from Sound.ps1 (MMDevices properties + PowerSettings)
& "$scriptPath\MinSudo.exe" -Command "# Apply sound logic here"

# Install Autoruns and GoInterruptPolicy portions
# Create shortcuts and launch executables

# MSI Afterburner logic here
# Launch MSI Afterburner after install

# Ethernet settings logic here

# NVIDIA functions logic here

# Performance-Tweaks logic

# Apply Power-Plan settings

# Apply Registry.reg settings excluding specific sections

# Disable scheduled tasks
Get-ScheduledTask | Where-Object { $_.State -eq 'Ready' } | ForEach-Object { Disable-ScheduledTask -TaskName $_.TaskName }

# Create disable-process-mitigations.bat and execute
$batContent = 'Your BAT content here'
$batPath = [System.IO.Path]::Combine($env:TEMP, 'disable-process-mitigations.bat')
Set-Content -Path $batPath -Value $batContent
& "$scriptPath\Power.exe" /SW:0 "$batPath"

# Create status file
$statusFile = [System.IO.Path]::Combine($env:USERPROFILE, 'Desktop', 'Quicky-Status.txt')
"Modules completed: ..." | Out-File -FilePath $statusFile -Encoding UTF8

# Clean exit