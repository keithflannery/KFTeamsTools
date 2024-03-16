set-alias -Name Get-Connected -Value Get-ConnectedMFA

function Get-ConnectedMFA {
    $voiceskus = "BUSINESS_VOICE_DIRECTROUTING", "MCOCV", "MCOEV", "BUSINESS_VOICE_DIRECTROUTING", "ENTERPRISEPREMIUM_NOPSTNCONF", "BUSINESS_VOICE_MED2", "BUSINESS_VOICE_MED2", "SPE_E5"
    Write-Host "Connecting to Microsoft Teams Powershell..." -ForegroundColor Green
    Connect-MicrosoftTeams
    Write-Host "Connecting to Microsoft Graph Powershell..." -ForegroundColor Green
    Connect-MgGraph -Scopes User.ReadWrite.All, Organization.Read.All, LicenseAssignment.ReadWrite.All, User.Read.All, AuditLog.Read.All -NoWelcome
}

function Disconnect-Sessions {
    Disconnect-MicrosoftTeams
    Disconnect-MgGraph
    Get-PSSession | Remove-PSSession
}