If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

# Check if WMI service is disabled; if so, set to Manual. Then start it.
$wmiService = Get-Service winmgmt -ErrorAction SilentlyContinue
if ($wmiService.StartType -eq 'Disabled') {
    Set-Service winmgmt -StartupType Manual -ErrorAction SilentlyContinue
}
Start-Service winmgmt -ErrorAction SilentlyContinue

function Set-MTU {
# Set MTU Size
$Target = "google.com"
$StartSize = 1400
$tempFile = "$env:TEMP\pingtest.txt"
$WorkingSize = $null

for ($size = $StartSize; $size -le 1500; $size++) {
    Start-Process -FilePath "ping.exe" -ArgumentList "$Target -f -l $size -n 1" -NoNewWindow -Wait -RedirectStandardOutput $tempFile
    if ((Get-Content $tempFile) -notmatch "Packet needs to be fragmented") {
        $WorkingSize = $size
        break
    }
}

if ($WorkingSize) {
    $MTU = $WorkingSize + 28
    Get-NetIPInterface | Where-Object { $_.ConnectionState -eq "Connected" -and $_.AddressFamily -eq "IPv4" } | ForEach-Object {
        netsh interface ipv4 set subinterface "$($_.InterfaceAlias)" mtu=$MTU store=persistent
    }
}
}

function Set-IPV6-Static {
$ipconfig = ipconfig /all | Out-String -Stream

$adapterSections = @()
$insideAdapter = $false
$adapterBlock = @()
foreach ($line in $ipconfig) {
    if ($line -match "^[A-Za-z].*adapter\s+(.+?):\s*$") {
        if ($insideAdapter -and $adapterBlock.Count -gt 0) {
            if ($adapterBlock[0] -match "adapter\s+Ethernet:") {
                $adapterSections += ,@($adapterBlock)
            }
        }
        $insideAdapter = $true
        $adapterBlock = @($line)
    } elseif ($insideAdapter) {
        $adapterBlock += $line
    }
}
if ($insideAdapter -and $adapterBlock.Count -gt 0 -and $adapterBlock[0] -match "adapter\s+Ethernet:") {
    $adapterSections += ,@($adapterBlock)
}

if ($adapterSections.Count -eq 0) { exit 1 }

foreach ($section in $adapterSections) {
    $ipv6Global = $null
    $gatewayLinkLocal = $null

    foreach ($line in $section) {
        if ($null -eq $ipv6Global -and $line -match "^\s*IPv6 Address[\. ]*: ([0-9a-fA-F:]{4,39})(?:\([^\)]*\))?") {
            $addr = $matches[1]
            if ($addr -notmatch "^fe80" -and $addr -notmatch "%") {
                $ipv6Global = $addr
            }
        }
        if ($null -eq $gatewayLinkLocal -and $line -match "^\s*Default Gateway[\. ]*: ([0-9a-fA-F:]+(?:%\d+)?)") {
            $gw = $matches[1]
            if ($gw -match "^fe80") {
                $gatewayLinkLocal = $gw
            }
        }
    }

    if ($null -eq $ipv6Global) { continue }

    $hextets = $ipv6Global.Split(':')
    $prefix = ($hextets[0..3] -join ":")
    $hostPart = ($hextets[4..($hextets.Count - 1)] -join ":")
    if ($hostPart -eq "") {
        $staticIPv6 = "$prefix::"
    } else {
        $staticIPv6 = "${prefix}:$hostPart"
    }

    if ($null -eq $gatewayLinkLocal) {
        $staticGateway = $null
    } else {
        $staticGateway = ($gatewayLinkLocal -split '%')[0]
    }

    $adapter = Get-NetAdapter | Where-Object { $_.Name -eq "Ethernet" }
    if (!$adapter) { continue }
    $adapterAlias = $adapter.Name

    $dhcpv6s = Get-NetIPAddress -InterfaceAlias $adapterAlias -AddressFamily IPv6 | Where-Object {
        ($_.PrefixOrigin -eq 'Dhcp' -or $_.PrefixOrigin -eq 'RouterAdvertisement') -and $_.Address -notmatch '^fe80'
    }
    foreach ($ip in $dhcpv6s) {
        Remove-NetIPAddress -InterfaceAlias $adapterAlias -AddressFamily IPv6 -IPAddress $ip.IPAddress -Confirm:$false
    }

    $exists = Get-NetIPAddress -InterfaceAlias $adapterAlias -AddressFamily IPv6 | Where-Object {
        $_.IPAddress -eq $staticIPv6
    }
    if ($exists) {
        Remove-NetIPAddress -InterfaceAlias $adapterAlias -AddressFamily IPv6 -IPAddress $staticIPv6 -Confirm:$false
    }

    try {
        New-NetIPAddress -InterfaceAlias $adapterAlias -IPAddress $staticIPv6 -PrefixLength 64 -AddressFamily IPv6 -ErrorAction Stop | Out-Null
    } catch { continue }

    if ($staticGateway) {
        $defaultRoute = Get-NetRoute -InterfaceAlias $adapterAlias -DestinationPrefix "::/0" -AddressFamily IPv6 -ErrorAction SilentlyContinue
        foreach ($rt in $defaultRoute) {
            Remove-NetRoute -InterfaceAlias $adapterAlias -DestinationPrefix "::/0" -NextHop $rt.NextHop -Confirm:$false
        }
        try {
            New-NetRoute -InterfaceAlias $adapterAlias -DestinationPrefix "::/0" -NextHop $staticGateway -AddressFamily IPv6 -ErrorAction Stop | Out-Null
        } catch {}
    }
}
}

$procName = (Get-NetAdapter "Ethernet").InterfaceDescription
if ($procName.Contains('Realtek')) {
    $replacePath = "C:\Windows\Setup\Scripts\files\Replace"
    $exe = Get-ChildItem -Path $replacePath -Filter "install_*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $exe) {
        $exe = Get-Item "$replacePath\Ethernet.exe" -ErrorAction SilentlyContinue
    }

    if ($exe) {
        $ethernetProcess = Start-Process $exe.FullName -ArgumentList "/S" -PassThru
        $ethernetProcess | Wait-Process
    }

    $procName = (Get-NetAdapter "Ethernet").InterfaceDescription
}

elseif ($procName.Contains('Intel')) {
    # skip installer; proceed to .inf install
}
else {
# Exits if Intel or Realtek isn't found (Does not set Ethernet Settings)
    Remove-Item "$env:TEMP\Ethernet.status" -Force
    exit
}

# Intel .inf installation block (shared for both realtek+intel fallback and intel direct)
if ($procName.Contains('Intel')) {
    $unzipLocation = "C:\Windows\Setup\Scripts\files\Replace"
    $releaseFolder = Get-ChildItem -Path $unzipLocation -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*Release*" } |
        Select-Object -First 1

    if ($releaseFolder) {
        $setupFile = Get-ChildItem -Path $releaseFolder.FullName -Recurse -Filter "setupbd.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($setupFile) {
            $process = Start-Process -FilePath $setupFile.FullName -ArgumentList "/s", "/nr" -PassThru
            $process | Wait-Process
        } else {
            Write-Host "setupbd.exe not found in Release folder"
        }
    } else {
        Write-Host "Release folder not found under: $unzipLocation"
    }
}
        $progresspreference = 'silentlycontinue'

        $key = "HKLM:SYSTEM\CurrentControlSet\services\NetBT\Parameters\Interfaces"
        Get-ChildItem $key | foreach { Set-ItemProperty -Path "$key\$($_.pschildname)" -Name NetbiosOptions -Value 2 }

Set-MTU

# Get active network adapter
$DeviceName = (Get-NetAdapter | Where-Object {
    $_.Status -eq "Up" -and $_.InterfaceDescription -match "Realtek|Intel"
}).Name

if (-not $DeviceName) {
    exit
}

# Get current IP configuration
$IPConfig = Get-NetIPAddress -InterfaceAlias $DeviceName -AddressFamily IPv4 -ErrorAction SilentlyContinue
$LocalIP = $IPConfig.IPAddress
$DHCPGateway = (Get-NetIPConfiguration -InterfaceAlias $DeviceName).IPv4DefaultGateway.NextHop
$PrefixLength = $IPConfig.PrefixLength

# Convert prefix length to subnet mask function (dynamic approach)
function Convert-PrefixToSubnetMask($prefix) {
    $binaryMask = '1' * $prefix + '0' * (32 - $prefix)   # Generate binary mask with 1's followed by 0's
    $subnetMask = @()
    
    # Split binary mask into 4 groups of 8 bits (since IPv4 has 32 bits)
    for ($i = 0; $i -lt 4; $i++) {
        $segment = $binaryMask.Substring($i * 8, 8)  # Extract 8 bits
        $subnetMask += [Convert]::ToInt32($segment, 2)  # Convert to decimal and add to the array
    }

    return ($subnetMask -join '.')
}

$SubnetMask = Convert-PrefixToSubnetMask $PrefixLength

# Validate IP addresses
function IsValidIP ($ip) {
    return $ip -match "^([0-9]{1,3}\.){3}[0-9]{1,3}$" -and ($ip -split '\.')[0..3] -notmatch "[^0-9]" -and ($ip -split '\.') -notcontains {$_ -gt 255}
}

if (-not (IsValidIP $LocalIP) -or -not (IsValidIP $DHCPGateway)) {
    exit
}

# Change IP configuration using netsh
Start-Process -FilePath "netsh" -ArgumentList "interface ip set address name=`"$DeviceName`" static $LocalIP $SubnetMask $DHCPGateway" -NoNewWindow -Wait

Set-IPV6-Static

        Disable-NetAdapterBinding -Name "*" -ComponentID ms_lldp -ErrorAction SilentlyContinue
        Disable-NetAdapterBinding -Name "*" -ComponentID ms_lltdio -ErrorAction SilentlyContinue
        Disable-NetAdapterBinding -Name "*" -ComponentID ms_implat -ErrorAction SilentlyContinue
        Disable-NetAdapterBinding -Name "*" -ComponentID ms_rspndr -ErrorAction SilentlyContinue
        Disable-NetAdapterBinding -Name "*" -ComponentID ms_server -ErrorAction SilentlyContinue
        Disable-NetAdapterBinding -Name "*" -ComponentID ms_msclient -ErrorAction SilentlyContinue

        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Advanced EEE" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "ARP Offload" -DisplayValue "Enabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "*Efficient Ethernet" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Flow Control" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Gigabit Lite" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Green Ethernet" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Interrupt Moderation" -DisplayValue "Enabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "IPv4 Checksum Offload" -DisplayValue "Rx & Tx Enabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Jumbo Frame" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Large Send Offload v2*" -DisplayValue "Enabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "NS Offload" -DisplayValue "Enabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "*Power Saving*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "*Priority & VLAN" -DisplayValue "Priority & VLAN Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Receive Buffers" -DisplayValue "1024" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Recv Segment Coalescing*" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "*Speed & Duplex" -DisplayValue "1.0 Gbps Full Duplex" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "TCP Checksum Offload*" -DisplayValue "Rx & Tx Enabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Transmit Buffers" -DisplayValue "1024" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "UDP Checksum Offload*" -DisplayValue "Rx & Tx Enabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Wake on Magic Packet" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Wake on pattern match" -DisplayValue "Disabled" -ErrorAction SilentlyContinue

        Set-NetAdapterAdvancedProperty -Name "*" -DisplayName "Interrupt Moderation Rate" -DisplayValue "Extreme" -ErrorAction SilentlyContinue

        Set-DnsClientServerAddress -InterfaceAlias "*" -ServerAddresses ("1.1.1.1","1.0.0.1")
        Set-DNSClientServerAddress -InterfaceAlias "*" -ServerAddresses ("2606:4700:4700::1111","2606:4700:4700::1001")

        netsh int tcp set global rss = enabled
        netsh int ipv4 set dynamicport tcp start=1025 num=64511
        netsh int ipv4 set dynamicport udp start=1025 num=64511
        netsh int tcp set supplemental Template=Datacenter CongestionProvider=bbr2
        netsh int tcp set supplemental Template=Compat CongestionProvider=bbr2
        netsh int tcp set supplemental Template=DatacenterCustom CongestionProvider=bbr2
        netsh int tcp set supplemental Template=InternetCustom CongestionProvider=bbr2
 
        $basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\"
        $networkKeys = Get-ChildItem -Path $basePath | Where-Object {
            (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).Class -eq "Net"
        }

        foreach ($key in $networkKeys) {
            for ($i = 0; $i -le 99; $i++) {
                $subKey = "{0:D4}" -f $i
                $subKeyPath = Join-Path -Path $key.PSPath -ChildPath $subKey

                if (Test-Path $subKeyPath) {
                    $props = Get-ItemProperty -Path $subKeyPath -ErrorAction SilentlyContinue
                    if ($props.DriverDesc -match "Realtek|Intel") {

                        $bufferNames = @("TransmitBuffers", "*TransmitBuffers", "ReceiveBuffers", "*ReceiveBuffers")

                        foreach ($name in $bufferNames) {
                            try {
                                if ((Get-ItemProperty -Path $subKeyPath -Name $name -ErrorAction SilentlyContinue) -ne $null) {
                                    Set-ItemProperty -Path $subKeyPath -Name $name -Value 1024
                                } else {
                                    New-ItemProperty -Path $subKeyPath -Name $name -PropertyType DWord -Value 1024 -Force | Out-Null
                                }

                                $maxPath = "$subKeyPath\Ndi\params\$name"
                                if (Test-Path $maxPath) {
                                    Set-ItemProperty -Path $maxPath -Name "Max" -Value 9999 -Force
                                }
                            } catch {}
                        }

                        $rssValues = @{
                            "*RSS"                    = "1"
                            "*RssBaseProcNumber"     = "2"
                            "*NumRssQueues"          = "2"
                            "*MaxRssProcessors"      = "2"
                            "*RSSProfile"      = "4"
                        }

                        foreach ($rss in $rssValues.GetEnumerator()) {
                            try {
                                Set-ItemProperty -Path $subKeyPath -Name $rss.Key -Value $rss.Value -Force
                            } catch {}
                        }

                        $extraValues = @{
                            "AdvancedEEE"                     = "0"
                            "*EEE"                            = "0"
                            "*PMARPOffload"                   = "0"
                            "*PMNSOffload"                    = "0"
                            "AutoDisableGigabit"              = "0"
                            "EnableGreenEthernet"             = "0"
                            "*FlowControl"                    = "3"
                            "GigaLite"                        = "0"
                            "*InterruptModeration"            = "1"
                            "*IPChecksumOffloadIPv4"          = "3"
                            "PowerSavingMode"                 = "0"
                            "*PriorityVlanTag"                = "1"
                            "*ModernStandbyWoLMagicPacket"    = "0"
                            "*WakeOnPattern"                  = "0"
                            "*WakeOnMagicPacket"              = "0"
                        }

                        foreach ($item in $extraValues.GetEnumerator()) {
                            try {
                                Set-ItemProperty -Path $subKeyPath -Name $item.Key -Value $item.Value -Force
                            } catch {}
                        }
                    }
                }
            }
        }

        netsh interface ip delete arpcache
        ipconfig /flushdns

        Remove-Item "$env:TEMP\Ethernet.status" -Force
        exit
