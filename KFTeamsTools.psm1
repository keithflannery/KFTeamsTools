# Universal psm file
#Requires -Version 5.0

# Get functions files
$Functions = @(Get-ChildItem -Path $PSScriptRoot\Scripts\*.ps1 -ErrorAction SilentlyContinue)

# Dot source the files
foreach ($import in @($Functions)) {
    try {
        . $import.fullname
    }
    catch {
        Write-Error -Message "Failed to import function $($import.fullname): $_"
    }
}

# Export everything in the public folder
Export-ModuleMember -Function * -Cmdlet * -Alias *

# Banner to display when the module is imported
Write-Host "Imported KFTeamsTools" -ForegroundColor Green
Write-Host "written by Keith Flannery, kflannery@yesit.com.au" -ForegroundColor Green