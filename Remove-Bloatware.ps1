If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) 
{	Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit	}

Get-AppxPackage -all *Clipchamp.Clipchamp* | Remove-AppxPackage -AllUsers
Get-AppxPackage -all *Disney* | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.549981C3F5F10 | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.BingNews | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.BingWeather | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.GetHelp | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.Getstarted | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.MSPaint | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.Microsoft3DViewer | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.MicrosoftOfficeHub | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.MicrosoftSolitaireCollection | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.MicrosoftStickyNotes | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.MixedReality.Portal | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.Office.OneNote | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.OneDriveSync | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.People | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.PowerAutomateDesktop | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.SkypeApp | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.Todos | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.Wallet | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.WindowsAlarms | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.WindowsCalculator | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.WindowsCamera | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.WindowsFeedbackHub | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.WindowsMaps | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.WindowsSoundRecorder | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.YourPhone | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.ZuneMusic | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.ZuneVideo | Remove-AppxPackage -AllUsers
Get-AppxPackage -all MicrosoftCorporationII.QuickAssist | Remove-AppxPackage -AllUsers
Get-AppxPackage -all MicrosoftTeams | Remove-AppxPackage -AllUsers
Get-AppxPackage -all MSTeams | Remove-AppxPackage -AllUsers
Get-AppxPackage -all MicrosoftWindows.Client.WebExperience | Remove-AppxPackage -AllUsers
Get-AppxPackage -all SpotifyAB.SpotifyMusic | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.WindowsCommunicationsApps | Remove-AppxPackage -AllUsers
Get-AppxPackage -all ReincubateLtd.CamoStudio | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.OutlookForWindows | Remove-AppxPackage -AllUsers
# Xbox Apps
Get-AppxPackage -all Microsoft.GamingApp | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.XboxIdentityProvider | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.XboxSpeechToTextOverlay | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.Xbox.TCUI | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.XboxGameOverlay | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.Microsoft.WebMediaExtensions | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.WebpImageExtension | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.StorePurchaseApp | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.HEVCVideoExtension | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.HEIFImageExtension | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.RawImageExtension | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.VP9VideoExtensions | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.Windows.DevHome | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.BingSearch | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.WindowsTerminal | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.Copilot | Remove-AppxPackage -AllUsers
Get-AppxPackage -all MicrosoftWindows.CrossDevice | Remove-AppxPackage -AllUsers
Get-AppxPackage -all Microsoft.WidgetsPlatformRuntime | Remove-AppxPackage -AllUsers
Get-AppxPackage -all *Microsoft.ApplicationCompatibilityEnhancements* | Remove-AppxPackage -AllUsers
Get-AppxPackage -all *Microsoft.Edge.GameAssist* | Remove-AppxPackage -AllUsers
Get-WindowsPackage -Online | Where PackageName -like *QuickAssist* | Remove-WindowsPackage -Online -NoRestart

cmd /c "MsiExec.exe /X{C6FD611E-7EFE-488C-A0E0-974C09EF6473} /qn >nul 2>&1"
Remove-Item "C:\Program Files\Microsoft Update Health Tools" -Force -Recurse -ErrorAction SilentlyContinue

New-Item -Path "$env:TEMP\Remove-Bloatware.status" -ItemType File -Force

exit