If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) 
{	Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit	}

# Stop OneDrive Processes
Stop-Process -Name "Onedrive*" -Force
Stop-Process -Name "FileCoAuth*" -Force
Stop-Process -Name "msedge*" -Force
Stop-Process -Name "UserOOBEBroker*" -Force

if (Test-Path "$env:systemroot\System32\OneDriveSetup.exe") {
    & "$env:systemroot\System32\OneDriveSetup.exe" /uninstall
}
if (Test-Path "$env:systemroot\SysWOW64\OneDriveSetup.exe") {
    & "$env:systemroot\SysWOW64\OneDriveSetup.exe" /uninstall
}

Wait-Process -Name "OnedriveSetup*"

Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$env:programdata\Microsoft OneDrive"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$env:userprofile\OneDrive"
Remove-Item -Force -ErrorAction SilentlyContinue "$env:userprofile\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk"
C:\Windows\Setup\Scripts\files\MinSudo --NoLogo --TrustedInstaller --Privileged Powershell Remove-Item -Recurse -Force "$env:localappdata\Microsoft\OneDrive"

reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /f

reg load "hku\Default" "C:\Users\Default\NTUSER.DAT"
reg delete "HKEY_USERS\Default\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f
reg unload "hku\Default"

Get-ScheduledTask -TaskPath '\' -TaskName 'OneDrive*' -ea SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
Get-ScheduledTask -TaskName "*OneDrive*" | Disable-ScheduledTask

C:\Windows\Setup\Scripts\files\MinSudo --NoLogo --TrustedInstaller --Privileged Powershell Remove-Item "C:\Windows\System32\OneDriveSetup.exe" -Force
C:\Windows\Setup\Scripts\files\MinSudo --NoLogo --TrustedInstaller --Privileged Powershell Remove-Item "C:\Windows\System32\OneDrive.ico" -Force
C:\Windows\Setup\Scripts\files\MinSudo --NoLogo --TrustedInstaller --Privileged Powershell Remove-Item "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\OneDrive" -Force -Recurse -ErrorAction SilentlyContinue

New-Item -Path "$env:TEMP\Uninstall-OneDrive.status" -ItemType File -Force

exit