<# 
    Script: Enable-Remoting.ps1
    Purpose: Enable PSRemoting and Windows Update Remoting 
             (for use in MECM Task Sequences)
#>

# Force enable PowerShell Remoting
Write-Output "Enabling PowerShell Remoting..."
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Allow WinRM service to auto-start
Write-Output "Configuring WinRM service..."
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

# Open required firewall rules
Write-Output "Configuring Firewall rules for PSRemoting..."
Enable-NetFirewallRule -DisplayGroup "Windows Remote Management"

# Enable Windows Update Remoting (DCOM/WU COM interfaces)
Write-Output "Enabling Windows Update Remoting..."
# Add registry key that allows remote COM calls for Windows Update Agent
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" `
    -Name "EnableRemoting" -PropertyType DWord -Value 1 -Force | Out-Null

# Optional: Make sure WU service is enabled
Set-Service -Name wuauserv -StartupType Manual

Write-Output "Remoting features enabled successfully."
exit 0
