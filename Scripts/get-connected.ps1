set-alias -Name Get-Connected -Value Get-ConnectedMFA

function Get-ConnectedMFA {
    $VoiceSKUs = "BUSINESS_VOICE_DIRECTROUTING", "MCOCV", "MCOEV", "BUSINESS_VOICE_DIRECTROUTING", "ENTERPRISEPREMIUM_NOPSTNCONF"
    write-host "Connecting to 365 Powershell..." -ForegroundColor Green
    Connect-MsolService
    Write-Host "Connecting to AzureAD Powershell..." -ForegroundColor Green
    Connect-AzureAD
    Write-Host "Connecting to Microsoft Teams Powershell..." -ForegroundColor Green
    Connect-MicrosoftTeams
}

function Disconnect-Sessions {
    Disconnect-MicrosoftTeams
    Disconnect-AzureAD
    [Microsoft.Online.Administration.Automation.ConnectMsolService]::ClearUserSessionState()
    Get-PSSession | Remove-PSSession
}