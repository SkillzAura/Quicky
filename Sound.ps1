If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) 
{	Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit	}

$baseKeys = @(
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
)

foreach ($baseKey in $baseKeys) {
    $guidKeys = Get-ChildItem -Path "Registry::$baseKey" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '{[0-9a-f\-]+}' }

    foreach ($key in $guidKeys) {
        $guid = Split-Path $key.Name -Leaf
        $propsPath = "$baseKey\$guid\Properties"
        $fxPath = "$baseKey\$guid\FxProperties"

        # Set Properties values to 0
        & "C:\Windows\Setup\Scripts\files\MinSudo.exe" --NoLogo --TrustedInstaller --Privileged reg add "$propsPath" /v "{b3f8fa53-0004-438e-9003-51a46e139bfc},3" /t REG_DWORD /d 0 /f
        & "C:\Windows\Setup\Scripts\files\MinSudo.exe" --NoLogo --TrustedInstaller --Privileged reg add "$propsPath" /v "{b3f8fa53-0004-438e-9003-51a46e139bfc},4" /t REG_DWORD /d 0 /f

        # Add FxProperties value set to 1
        & "C:\Windows\Setup\Scripts\files\MinSudo.exe" --NoLogo --TrustedInstaller --Privileged reg add "$fxPath" /v "{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5" /t REG_DWORD /d 1 /f
    }
}

# Find 'Media' class keys and modify PowerSettings for numeric subkeys
Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class" -ErrorAction SilentlyContinue | Where-Object {
    (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).class -eq "Media"
} | ForEach-Object {
    Get-ChildItem -Path $_.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
        $powerSettingsPath = Join-Path -Path $_.PSPath -ChildPath "PowerSettings"
        if (Test-Path $powerSettingsPath) {
            Set-ItemProperty -Path $powerSettingsPath -Name "ConservationIdleTime" -Value ([byte[]](0,0,0,0)) -Type Binary
            Set-ItemProperty -Path $powerSettingsPath -Name "PerformanceIdleTime" -Value ([byte[]](0,0,0,0)) -Type Binary
            Set-ItemProperty -Path $powerSettingsPath -Name "IdlePowerState" -Value ([byte[]](0,0,0,0)) -Type Binary
        }
    }
}

Start-Process "mmsys.cpl"
do { $proc = Get-CimInstance Win32_Process -Filter "Name='rundll32.exe'" | Where-Object { $_.CommandLine -match "mmsys\.cpl" } } while ($proc)

New-Item -Path "$env:TEMP\Sound-Settings.status" -ItemType File -Force

exit