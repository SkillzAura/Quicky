If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) 
{	Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit	}

Add-Type -AssemblyName System.Windows.Forms

# Function to update the registry value for MouseSensitivity
function Update-RegistryValue {
    param (
        [int]$DPI
    )
    
    # Mapping DPI to MouseSensitivity
    $sensitivityValue = switch ($DPI) {
        800     { 10 }
        1600    { 6 }
        3200    { 4 }
        6400    { 3 }
        12800   { 2 }
        25600   { 2 } # Added 25600 DPI with value 2
        default { return }
    }

    # Registry path and key name
    $registryPath = "HKCU:\Control Panel\Mouse"
    $registryKey = "MouseSensitivity"
    
    # Set the registry value
    Set-ItemProperty -Path $registryPath -Name $registryKey -Value $sensitivityValue

    # Display a custom dark mode success message
    Show-DarkMessageBox "DPI $DPI selected! MouseSensitivity set to $sensitivityValue. Changes will take effect after restarting the computer."
}

# Function to show a custom dark-themed message box with a distinct appearance
function Show-DarkMessageBox {
    param (
        [string]$message
    )
    
    # Create the custom success message box form
    $messageBox = New-Object System.Windows.Forms.Form
    $messageBox.Text = "Success"
    $messageBox.Size = New-Object System.Drawing.Size(300, 150)
    $messageBox.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $messageBox.BackColor = "#3A3A3A"  # Lighter dark background for the popup
    $messageBox.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $messageBox.MaximizeBox = $false
    $messageBox.MinimizeBox = $false

    # Message label
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $message
    $label.ForeColor = "White"
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $label.Size = New-Object System.Drawing.Size(260, 60)
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $messageBox.Controls.Add($label)

    # OK button
    $buttonOK = New-Object System.Windows.Forms.Button
    $buttonOK.Text = "OK"
    $buttonOK.Size = New-Object System.Drawing.Size(75, 30)
    $buttonOK.Location = New-Object System.Drawing.Point(110, 80)
    $buttonOK.BackColor = "#505050"  # A bit lighter button background to differentiate it
    $buttonOK.ForeColor = "White"
    $buttonOK.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $buttonOK.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    
    # Close both the popup and the main form when OK is clicked
    $buttonOK.Add_Click({
        $messageBox.Close()
        $global:mainForm.Close()  # Close the main form after the popup
    })
    $messageBox.Controls.Add($buttonOK)

    # Show custom message box
    $messageBox.ShowDialog()
}

# Create a new form with increased width
$global:mainForm = New-Object System.Windows.Forms.Form
$mainForm.Text = "DPI to Sensitivity Converter"
$mainForm.Size = New-Object System.Drawing.Size(340, 400)
$mainForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$mainForm.BackColor = "#2C2C2C"  # Dark background for the main form

# Label for the main title
$label = New-Object System.Windows.Forms.Label
$label.Text = "Set your DPI"
$label.ForeColor = "White"
$label.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$label.AutoSize = $true
$label.TextAlign = "MiddleCenter"
$label.Location = New-Object System.Drawing.Point(90, 20)
$mainForm.Controls.Add($label)

# Label for the description
$descriptionLabel = New-Object System.Windows.Forms.Label
$descriptionLabel.Text = "Setting Mouse Sensitivity values will make your DPI in Windows feel like 800 DPI. Only use this while playing games with Raw Input."
$descriptionLabel.ForeColor = "White"
$descriptionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$descriptionLabel.AutoSize = $true
$descriptionLabel.MaximumSize = New-Object System.Drawing.Size(300, 0)
$descriptionLabel.Location = New-Object System.Drawing.Point(30, 60)
$mainForm.Controls.Add($descriptionLabel)

# Create buttons for each DPI setting
$button800 = New-Object System.Windows.Forms.Button
$button800.Text = "800 (Default)"
$button800.Size = New-Object System.Drawing.Size(100, 40)
$button800.Location = New-Object System.Drawing.Point(50, 140)
$button800.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$button800.BackColor = "#444444"
$button800.ForeColor = "White"
$button800.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$button800.Add_Click({ Update-RegistryValue -DPI 800 })

$button1600 = New-Object System.Windows.Forms.Button
$button1600.Text = "1600 DPI"
$button1600.Size = New-Object System.Drawing.Size(100, 40)
$button1600.Location = New-Object System.Drawing.Point(170, 140)
$button1600.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$button1600.BackColor = "#444444"
$button1600.ForeColor = "White"
$button1600.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$button1600.Add_Click({ Update-RegistryValue -DPI 1600 })

$button3200 = New-Object System.Windows.Forms.Button
$button3200.Text = "3200 DPI"
$button3200.Size = New-Object System.Drawing.Size(100, 40)
$button3200.Location = New-Object System.Drawing.Point(50, 190)
$button3200.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$button3200.BackColor = "#444444"
$button3200.ForeColor = "White"
$button3200.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$button3200.Add_Click({ Update-RegistryValue -DPI 3200 })

$button6400 = New-Object System.Windows.Forms.Button
$button6400.Text = "6400 DPI"
$button6400.Size = New-Object System.Drawing.Size(100, 40)
$button6400.Location = New-Object System.Drawing.Point(170, 190)
$button6400.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$button6400.BackColor = "#444444"
$button6400.ForeColor = "White"
$button6400.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$button6400.Add_Click({ Update-RegistryValue -DPI 6400 })

$button12800 = New-Object System.Windows.Forms.Button
$button12800.Text = "12800 DPI"
$button12800.Size = New-Object System.Drawing.Size(100, 40)
$button12800.Location = New-Object System.Drawing.Point(50, 240)
$button12800.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$button12800.BackColor = "#444444"
$button12800.ForeColor = "White"
$button12800.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$button12800.Add_Click({ Update-RegistryValue -DPI 12800 })

$button25600 = New-Object System.Windows.Forms.Button
$button25600.Text = "25600 DPI"
$button25600.Size = New-Object System.Drawing.Size(100, 40)
$button25600.Location = New-Object System.Drawing.Point(170, 240)
$button25600.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$button25600.BackColor = "#444444"
$button25600.ForeColor = "White"
$button25600.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$button25600.Add_Click({ Update-RegistryValue -DPI 25600 })

# Add buttons to the form
$mainForm.Controls.Add($button800)
$mainForm.Controls.Add($button1600)
$mainForm.Controls.Add($button3200)
$mainForm.Controls.Add($button6400)
$mainForm.Controls.Add($button12800)
$mainForm.Controls.Add($button25600)

# Show the form
$mainForm.ShowDialog()

New-Item -Path "$env:TEMP\Set-Windows-Sens.status" -ItemType File -Force
exit
