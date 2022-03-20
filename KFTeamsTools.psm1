# Universal psm file
#Requires -Version 5.0
#Requires -Modules @{ ModuleName="MicrosoftTeams"; RequiredVersion="4.0.0" }
#Requires -Module MSOnline
#Requires -Module AzureAD
#Requires -Module ImportExcel

# Import Required Modules
import-Module MicrosoftTeams, MSOnline, ImportExcel, AzureAD

# Set Required Variables
$VoiceSKUs = "BUSINESS_VOICE_DIRECTROUTING", "MCOCV", "MCOEV", "BUSINESS_VOICE_DIRECTROUTING", "ENTERPRISEPREMIUM_NOPSTNCONF"

# Get functions files
$Functions = @(Get-ChildItem -Path $PSScriptRoot\Scripts\*.ps1 -ErrorAction SilentlyContinue)

# Dot source the files
foreach($import in @($Functions))
{
    try {
        . $import.fullname
    }
    catch {
        Write-Error -Message "Failed to import function $($import.fullname): $_"
    }
}

# Export everything in the public folder
Export-ModuleMember -Function * -Cmdlet * -Alias *