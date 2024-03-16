Function XString {
    Param (
        [Parameter(Mandatory = $true)]
        [string]$string
        ,
        [Parameter(Mandatory = $true)]
        [char]$character
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Right", "Left")]
        [string]$range
        ,
        [Parameter(Mandatory = $false)]
        [int]$afternumber
        ,
        [Parameter(Mandatory = $false)]
        [int]$tonumber
    )
    Process {
        [string]$return = ""
        
        if ($range -eq "Right") {
            $return = $string.Split("$character")[($string.Length - $string.Replace("$character", "").Length)]
        }
        elseif ($range -eq "Left") {
            $return = $string.Split("$character")[0]
        }
        elseif ($tonumber -ne 0) {
            for ($i = $afternumber; $i -le ($afternumber + $tonumber); $i++) {
                $return += $string.Split("$character")[$i]
            }
        }
        else {
            $return = $string.Split("$character")[$afternumber]
        }
        
        return $return
    }
}


function Get-KFLicensedUsers	{

    param (
        [string[]]$licenseskus
    )

    $licensedusers = @()

    $msolusers = Get-MsolUser -All | Where-Object { ($_.isLicensed -eq "TRUE" -and $_.BlockCredential -ne $true ) }
    
    foreach ($user in $msolusers) {
        # if ($user.isLicensed -eq $true) {
        foreach ($sku in $user.Licenses.AccountSkuID) {
            $fuxsku = XString -string $sku -character ":" -range Right
            if ($licenseskus.Contains($fuxsku)) {
                $licensedusers += $user.UserPrincipalName
            }
        }
        # }
    }

    return $licensedusers
}


function Get-KFData {

    param (
        [parameter(Mandatory = $true)]
        $licensedusers
    )

    $ht = @{}
    foreach ($user in $licensedusers) {

        $data = "FirstName", "LastName", "EnterpriseVoiceEnabled", "HostedVoiceMail", "LineURI", "UsageLocation", "UserPrincipalName", "WindowsEmailAddress", "SipAddress", "OnPremLineURI", "OnlineVoiceRoutingPolicy", "TenantDialPlan", "HostingProvider", "TeamsUpgradeEffectiveMode", "OnPremLineURIManuallySet", "TeamsIPPhonePolicy"

        $teamsdata = get-csonlineuser -id $user

        $datahash = @{}
        foreach ($x in $data) { $datahash += @{$x = $teamsdata.$x } }
        $dataobject = [pscustomobject]$datahash

        $ht += @{$user = $dataobject }
    }

    return $ht
}

function New-KFCsUser {

    param (
        [parameter(Mandatory = $true)]
        $UPN
        ,
        [parameter(Mandatory = $true)]
        $LineURI
        ,
        [parameter()]
        $OnlineVoiceRoutingPolicy = 'YCLTeamsVoice'
        ,
        [parameter()]
        $TenantDialPlan
    )

    if ($LineURI -match '^tel:\+.*$') {
        Write-Host "WARNING: tel: is no longer required!, automatically omitting tel:" -ForegroundColor Yellow
        $NewNumber = $LineURI | Select-String -Pattern '^tel:(\+.*)$'
        $LineURI = $NewNumber.Matches.Groups[1]
        write-host "    New Number: $($LineURI)" -ForegroundColor Yellow
    }
    
    $FeatureTypes = "PhoneSystem"

    $userdetails = Get-CsOnlineUser -Identity $UPN

    if ($FeatureTypes -in $userdetails.FeatureTypes) {
        write-host "$($FeatureTypes) is enabled for $($userdetails.DisplayName)" -ForegroundColor Green

        if ($TenantDialPlan -eq $null) {
            if ($LineURI -match '^(?:|tel:)\+612\d{8}(?:|;ext\=\d+)$') {
                $TenantDialPlan = "AU-02"
            }
            elseif ($LineURI -match '^(?:|tel:)\+613\d{8}(?:|;ext\=\d+)$') {
                $TenantDialPlan = "AU-03"
            }
            elseif ($LineURI -match '^(?:|tel:)\+617\d{8}(?:|;ext\=\d+)$') {
                $TenantDialPlan = "AU-07"
            }
            elseif ($LineURI -match '^(?:|tel:)\+618\d{8}(?:|;ext\=\d+)$') {
                $TenantDialPlan = "AU-08"
            }
            elseif ($lineURI -match '^(?:|tel:)\+643(\d{7}|\d{9})(?:|;ext\=\d+)$') {
                $TenantDialPlan = "NZ-03"
            }
            elseif ($lineURI -match '^(?:|tel:)\+644(\d{7}|\d{9})(?:|;ext\=\d+)$') {
                $TenantDialPlan = "NZ-04"
            }
            elseif ($lineURI -match '^(?:|tel:)\+646(\d{7}|\d{9})(?:|;ext\=\d+)$') {
                $TenantDialPlan = "NZ-06"
            }
            elseif ($lineURI -match '^(?:|tel:)\+647(\d{7}|\d{9})(?:|;ext\=\d+)$') {
                $TenantDialPlan = "NZ-07"
            }
            elseif ($lineURI -match '^(?:|tel:)\+64(2|9)(\d{7}|\d{9})(?:|;ext\=\d+)$') {
                $TenantDialPlan = "NZ-09"
            }
            else {
                Write-Error "Line URI not a valid Australian/NewZealand Landline Number e.g.: AU +61736249100, NZ +6495238436"
                exit
            }
        }
        try {
            Write-Host "Enabling Enterprise Voice..."
            Set-CsPhoneNumberAssignment -Identity $UPN -EnterpriseVoiceEnabled $true
        }
        catch {
            throw $_
            write-host "Couldn't enable Enterprise voice" -ForegroundColor Red
        }
        #if ($userdata.OnPremLineURIManuallySet -eq $false){
        
        try {
            Write-Host "Setting phone number $($LineURI)..."
            Set-CsPhoneNumberAssignment -Identity $UPN -PhoneNumber $LineURI -PhoneNumberType DirectRouting
        }
        catch {
            throw $_
            write-host "Couldn't set phone number on user user!" -ForegroundColor Red
        }
        #}
        try {
            Write-Host "Setting Routing Policy $($OnlineVoiceRoutingPolicy)..."
            Grant-CsOnlineVoiceRoutingPolicy -id $UPN -PolicyName $OnlineVoiceRoutingPolicy
        }
        catch {
            throw $_
            write-host "Couldn't set Voice Routing Policy on user!" -ForegroundColor Red
        }

        try {
            Write-Host "Setting Tenant Dialplan... $($TenantDialPlan)"
            Grant-CsTenantDialPlan -id $UPN -PolicyName $TenantDialPlan
        }
        catch {
            throw $_
            write-host "Couldn't set TenantDialPlan on user!" -ForegroundColor Red
        }

    }
    else {
        write-host "User $($UPN) doesn't appear to have a Phone System license assigned!" -ForegroundColor Red
    }
}

function Get-Phonenumbers {
    get-csonlineuser | where-object { $_.LineUri -match '^(?:|tel:)\+?61[2378]\d{8}(?:|;ext\=\d+)$' } | Select-Object UserPrincipalName, GivenName, LastName, DisplayName, LineUri, TenantDialPlan, OnlineVoiceRoutingPolicy, City | export-excel
}

set-alias -Name Get-AUPhonenumbers -Value Get-PhoneNumbers

function Get-NZPhonenumbers {
    get-csonlineuser | where-object { $_.LineUri -match '^(?:|tel:)\+?64(?:\d{8}|\d{10})(?:|;ext\=\d+)$' } | Select-Object UserPrincipalName, GivenName, LastName, DisplayName, LineUri, TenantDialPlan, OnlineVoiceRoutingPolicy, City | export-excel
}

# function Get-ValidatedUsers {
    
#     param (
#         [parameter()]
#         [Switch]$IgnoreEVDisabled
#     )

#     if ($IgnoreEVDisabled -eq $true) {
#         $csonlineusers = get-csonlineuser | Where-Object { $_.EnterpriseVoiceEnabled -eq $true } | select-object FirstName, LastName, EnterpriseVoiceEnabled, HostedVoiceMail, LineURI, UsageLocation, UserPrincipalName, WindowsEmailAddress, SipAddress, OnlineVoiceRoutingPolicy, TenantDialPlan, HostingProvider, TeamsUpgradeEffectiveMode, OnPremLineURIManuallySet, TeamsIPPhonePolicy
#     }
#     else {
#         $csonlineusers = get-csonlineuser | select-object FirstName, LastName, EnterpriseVoiceEnabled, HostedVoiceMail, LineURI, UsageLocation, UserPrincipalName, WindowsEmailAddress, SipAddress, OnlineVoiceRoutingPolicy, TenantDialPlan, HostingProvider, TeamsUpgradeEffectiveMode, OnPremLineURIManuallySet, TeamsIPPhonePolicy        
#     }
#     $licensedusers2 = Get-KFLicensedUsers -licenseskus $voiceskus

#     $data = @()

#     foreach ($user in $csonlineusers) {
#         if ($licensedusers2 -contains $user.UserPrincipalName) {
#             $data += $user
#         }
#     }

#     foreach ($user in $data) {
#         $borkedusers = @{}
#         $BORKED = $false
#         $reasons = New-Object System.Collections.Generic.List[string]

#         if ($user.LineURI -notmatch '^(?:|tel:)\+?61[2378]\d{8}(?:|;ext\=\d+)$') {
#             $BORKED = $true
#             $reasons.Add("LineURI Invalid!")
#         }
#         if ($user.EnterpriseVoiceEnabled -eq $false) {
#             $BORKED = $true
#             $reasons.Add("EnterpriseVoiceEnabled is False!")
#         }
#         if ($user.TenantDialPlan -eq $null) {
#             $BORKED = $true
#             $reasons.Add("TenantDialPlan is Empty!")
#         }
#         if ($user.OnlineVoiceRoutingPolicy -eq $null) {
#             $BORKED = $true
#             $reasons.Add('OnlineVoiceRoutingPolicy is Empty!')
#         }

#         if ($BORKED -eq $true) {
#             $borkedusers += @{$user.UserPrincipalName = $reasons }


#         }

#         $borkedusers

#     }
# }


function Get-UserDetails {
    get-csonlineuser | Where-Object { $_.EnterpriseVoiceEnabled -eq $true } | select-object FirstName, LastName, EnterpriseVoiceEnabled, HostedVoiceMail, LineURI, UsageLocation, UserPrincipalName, WindowsEmailAddress, SipAddress, OnlineVoiceRoutingPolicy, TenantDialPlan, HostingProvider, TeamsUpgradeEffectiveMode, OnPremLineURIManuallySet, TeamsIPPhonePolicy | Export-Excel
}




function Remove-KFCsUser {

    param (
        [parameter(Mandatory = $true)]
        $UPN
    )
    Remove-CsPhoneNumberAssignment -id $UPN -RemoveAll
    Set-CsPhoneNumberAssignment -Identity $UPN -EnterpriseVoiceEnabled $false
}

function New-KFResourceAccount {
    <#
    .SYNOPSIS
    Creates a new resource account in Teams
    .DESCRIPTION
    Creates a new resource account in Teams
    .EXAMPLE
    New-KFResourceAccount -ratype aa -UPN aa-61700000000@yesit.com.au -DisplayName "AA-61700000000" -URI 61700000000
    .EXAMPLE
    New-KFResourceAccount -ratype cq -UPN cq-61700000000@yesit.com.au -DisplayName "CQ-61700000000" -URI 61700000000
    .PARAMETER ratype
    The type of resource account to create, either aa (auto attendent) or cq (call queue)
    .PARAMETER UPN
    The User Principal Name of the resource account to create
    .PARAMETER DisplayName
    The display name of the resource account to create
    .PARAMETER usagelocation
    The usage location of the resource account to create
    .PARAMETER URI
    The phone number of the resource account to create
    .PARAMETER IgnoreWarning
    Ignore any warnings
    .PARAMETER OnlineVoiceRoutingPolicy
    The Online Voice Routing Policy to assign to the resource account
    .NOTES

    #>
    param (
        [parameter(Mandatory = $true)]
        $ratype,
        $UPN,
        $DisplayName,
        $usagelocation = "AU",
        $URI = $null,
        $IgnoreWarning = $false,
        $OnlineVoiceRoutingPolicy = 'YCLTeamsVoice'
    )
    if ($ratype -eq 'aa') {
        $appid = 'ce933385-9390-45d1-9512-c8d228074e07'
    }
    Elseif ($ratype -eq 'cq') {
        $appid = '11cd3e2e-fccb-42ad-ad00-878b93575e07'
    }
    else {
        Get-Help New-KFResourceAccount
        Get-Help New-KFResourceAccount -Examples
        exit
    }
    # Create the account and wait 30 seconds for it to be created
    write-host "Creating new resource account...$(UPN)"
    New-CsOnlineApplicationInstance -UserPrincipalName $UPN -DisplayName $DisplayName -ApplicationId $appid
    start-sleep -Seconds 30

    # Set the Usage Location to AU
    Update-MgUser -UserId $UPN -UsageLocation $usagelocation

    # Check if theres enough licenses to assign Virtual User to the account
    $vu_sku = Get-MgSubscribedSku -All | Where SkuPartNumber -eq 'PHONESYSTEM_VIRTUALUSER'
    $vu_free = $vu_sku.PrepaidUnits.Enabled - $vu_sku.ConsumedUnits
    if ($vu_free -lt 1) {
        write-host "You have no free Virtual User Licenses! Purchase more in the 365 portal and try again! (don't panic, they are free!!)" -ForegroundColor Red
        exit
    }
    else {
        write-host "Assigning license and waiting 2 mins for license to apply..."
        Set-MgUserLicense -UserId $UPN -AddLicenses @{SkuId = $vu_sku.SkuId } -RemoveLicenses @()
        Start-Sleep -Seconds 120
        write-host "Setting phone number $($URI)..."
        Set-CsPhoneNumberAssignment -Identity $UPN -PhoneNumber $URI -PhoneNumberType DirectRouting
        start-sleep -Seconds 10
        write-host "Setting Routing Policy $($OnlineVoiceRoutingPolicy)..."
        Grant-CsOnlineVoiceRoutingPolicy -id $UPN -PolicyName $OnlineVoiceRoutingPolicy
        write-host "process complete - please make sure the phone number is set below (if you set one!):" -ForegroundColor Yellow
        Get-CsOnlineApplicationInstance -Identity $UPN | fl
    }
}