
function Get-KFLicensedUsers	{
    param (
        [string[]]$licenseskus = $voiceskus
    )

    $licensedusers = @()

    $users = Get-MgUser -All -Filter "(assignedLicenses/`$count ne 0 and userType eq 'Member') and (accountEnabled eq true)" -ConsistencyLevel eventual -CountVariable Records

    foreach ($user in $users) {
        $licenseDetails = Get-MgUserLicenseDetail -UserId $user.Id
        foreach ($licenseDetail in $licenseDetails) {
            if ($licenseskus.Contains($licenseDetail.SkuPartNumber)) {
                $licensedusers += $user.UserPrincipalName
                break
            }
        }
        
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
    <#
    .SYNOPSIS
    Creates a new user in Teams
    .DESCRIPTION
    Creates a new user in Teams
    .EXAMPLE
    New-KFCsUser -UPN bsmith@yesit.com.au -LineURI +61733694714
    .PARAMETER UPN
    The User Principal Name of the user to create
    .PARAMETER LineURI
    The LineURI of the user to create
    .PARAMETER OnlineVoiceRoutingPolicy
    The Online Voice Routing Policy to assign to the user
    .PARAMETER TenantDialPlan
    The Tenant Dial Plan to assign to the user
    .NOTES
    #>

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

    $LineURI = Get-LineURI -LineURI $LineURI
    
    $FeatureTypes = "PhoneSystem"

    $userdetails = Get-CsOnlineUser -Identity $UPN

    if ($FeatureTypes -in $userdetails.FeatureTypes) {
        write-host "$($FeatureTypes) is enabled for $($userdetails.DisplayName)" -ForegroundColor Green

        if ($TenantDialPlan -eq $null) {
            $TenantDialPlan = Get-TenantDialPlan -LineURI $LineURI
        }
        try {
            Write-Host "Enabling Enterprise Voice..."
            Set-CsPhoneNumberAssignment -Identity $UPN -EnterpriseVoiceEnabled $true
        }
        catch {
            throw $_
            write-host "Couldn't enable Enterprise voice" -ForegroundColor Red
        }
        
        try {
            Write-Host "Setting phone number $($LineURI)..."
            Set-CsPhoneNumberAssignment -Identity $UPN -PhoneNumber $LineURI -PhoneNumberType DirectRouting
        }
        catch {
            throw $_
            write-host "Couldn't set phone number on user user!" -ForegroundColor Red
        }
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

function Get-ValidatedUsers {
    
    param (
        [parameter()]
        [Switch]$IgnoreEVDisabled
    )

    if ($IgnoreEVDisabled -eq $true) {
        $csonlineusers = get-csonlineuser | Where-Object { $_.EnterpriseVoiceEnabled -eq $true } | select-object FirstName, LastName, EnterpriseVoiceEnabled, HostedVoiceMail, LineURI, UsageLocation, UserPrincipalName, WindowsEmailAddress, SipAddress, OnlineVoiceRoutingPolicy, TenantDialPlan, HostingProvider, TeamsUpgradeEffectiveMode, OnPremLineURIManuallySet, TeamsIPPhonePolicy
    }
    else {
        $csonlineusers = get-csonlineuser | select-object FirstName, LastName, EnterpriseVoiceEnabled, HostedVoiceMail, LineURI, UsageLocation, UserPrincipalName, WindowsEmailAddress, SipAddress, OnlineVoiceRoutingPolicy, TenantDialPlan, HostingProvider, TeamsUpgradeEffectiveMode, OnPremLineURIManuallySet, TeamsIPPhonePolicy        
    }
    $licensedusers2 = Get-KFLicensedUsers -licenseskus $voiceskus

    $data = @()

    foreach ($user in $csonlineusers) {
        if ($licensedusers2 -contains $user.UserPrincipalName) {
            $data += $user
        }
    }

    foreach ($user in $data) {
        $borkedusers = @{}
        $BORKED = $false
        $reasons = New-Object System.Collections.Generic.List[string]

        if ($user.LineURI -notmatch '^(?:|tel:)\+?61[2378]\d{8}(?:|;ext\=\d+)$') {
            $BORKED = $true
            $reasons.Add("LineURI Invalid!")
        }
        if ($user.EnterpriseVoiceEnabled -eq $false) {
            $BORKED = $true
            $reasons.Add("EnterpriseVoiceEnabled is False!")
        }
        if ($user.TenantDialPlan -eq $null) {
            $BORKED = $true
            $reasons.Add("TenantDialPlan is Empty!")
        }
        if ($user.OnlineVoiceRoutingPolicy -eq $null) {
            $BORKED = $true
            $reasons.Add('OnlineVoiceRoutingPolicy is Empty!')
        }

        if ($BORKED -eq $true) {
            $borkedusers += @{$user.UserPrincipalName = $reasons }


        }

        $borkedusers

    }
}


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

    # validate the URI using the Get-LineURI function
    $URI = Get-LineURI -LineURI $URI

    # Get the variable for the tenant dial plan
    $TenantDialPlan = Get-TenantDialPlan -LineURI $URI

    # Create the account and wait 30 seconds for it to be created
    write-host "Creating new resource account...$($UPN)"
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
        write-host "waiting 2 mins for license to apply..."
        Start-Sleep -Seconds 120
        write-host "Setting phone number $($URI)..."
        Set-CsPhoneNumberAssignment -Identity $UPN -PhoneNumber $URI -PhoneNumberType DirectRouting
        start-sleep -Seconds 10
        write-host "Setting Routing Policy $($OnlineVoiceRoutingPolicy)..."
        Grant-CsOnlineVoiceRoutingPolicy -id $UPN -PolicyName $OnlineVoiceRoutingPolicy
        Grant-CsTenantDialPlan -id $UPN -PolicyName $TenantDialPlan
        write-host "process complete - please make sure the phone number is set below (if you set one!):" -ForegroundColor Yellow
        Get-CsOnlineApplicationInstance -Identity $UPN | fl
    }
}

# Function return the correct tenant dial plan for a given number
function Get-TenantDialPlan {
    <#
    .SYNOPSIS
    Returns the correct tenant dial plan for a given number
    .DESCRIPTION
    Returns the correct tenant dial plan for a given number
    .EXAMPLE
    Get-TenantDialPlan -LineURI +61733694714
    .PARAMETER LineURI
    The LineURI to check
    .NOTES
    #>
    param (
        [parameter(Mandatory = $true)]
        $LineURI
    )
    if ($LineURI -match '^(?:|tel:)\+612\d{8}(?:|;ext\=\d+)$') {
        return "AU-02"
    }
    elseif ($LineURI -match '^(?:|tel:)\+613\d{8}(?:|;ext\=\d+)$') {
        return "AU-03"
    }
    elseif ($LineURI -match '^(?:|tel:)\+617\d{8}(?:|;ext\=\d+)$') {
        return "AU-07"
    }
    elseif ($LineURI -match '^(?:|tel:)\+618\d{8}(?:|;ext\=\d+)$') {
        return "AU-08"
    }
    elseif ($LineURI -match '^(?:|tel:)\+611300\d{6}(?:|;ext\=\d+)$') {
        return "AU-National"
    }
    elseif ($lineURI -match '^(?:|tel:)\+643(\d{7}|\d{9})(?:|;ext\=\d+)$') {
        return "NZ-03"
    }
    elseif ($lineURI -match '^(?:|tel:)\+644(\d{7}|\d{9})(?:|;ext\=\d+)$') {
        return "NZ-04"
    }
    elseif ($lineURI -match '^(?:|tel:)\+646(\d{7}|\d{9})(?:|;ext\=\d+)$') {
        return "NZ-06"
    }
    elseif ($lineURI -match '^(?:|tel:)\+647(\d{7}|\d{9})(?:|;ext\=\d+)$') {
        return "NZ-07"
    }
    elseif ($lineURI -match '^(?:|tel:)\+64(2|9)(\d{7}|\d{9})(?:|;ext\=\d+)$') {
        return "NZ-09"
    }
    else {
        Write-Error "Line URI not a valid Australian/NewZealand Landline Number e.g.: AU +61733694714, NZ +6495238436"
        exit
    }
}

# function to validate and return a lineuri
function Get-LineURI {
    <#
    .SYNOPSIS
    Validates and returns a lineuri
    .DESCRIPTION
    Validates and returns a lineuri
    .EXAMPLE
    Get-LineURI -LineURI +61733694714
    .PARAMETER LineURI
    The LineURI to check
    .NOTES
    #>
    param (
        [parameter(Mandatory = $true)]
        $LineURI
    )
    if ($LineURI -match '^tel:\+.*$') {
        Write-Host "WARNING: tel: is no longer required!, automatically omitting tel:" -ForegroundColor Yellow
        $NewNumber = $LineURI | Select-String -Pattern '^tel:(\+.*)$'
        $LineURI = $NewNumber.Matches.Groups[1]
        write-host "    New Number: $($LineURI)" -ForegroundColor Yellow
    }
    if ($LineURI -match '^(?:|tel:)\+?61[2378]\d{8}(?:|;ext\=\d+)|(?:|tel:)\+?611300\d{6}(?:|;ext\=\d+)$') {
        return $LineURI
    }
    else {
        Write-Error "Line URI not a valid Australian/NewZealand Landline Number e.g.: AU +61733694714, NZ +6495238436"
        exit
    }
}

# Add dialplans to the customers tenant
function Add-DialPlans {
    $nr1 = New-CsVoiceNormalizationRule -Parent Global -Name AU-Emergency -Description "AU-Emergency" -Pattern '^(000|112|911)$' -Translation '+61000' -InMemory
    $nr2 = New-CsVoiceNormalizationRule -Parent Global -Name AU-National -Description "AU-National" -Pattern '^(61|0)?(\d{9})$' -Translation '+61$2' -InMemory
    $nr3 = New-CsVoiceNormalizationRule -Parent Global -Name AU-Service -Description "AU-Service" -Pattern '^((1[38](00)?((\d{6})|(\d{4})))|122[12345]|12[45])$' -Translation '+61$1' -InMemory
    $nr4 = New-CsVoiceNormalizationRule -Parent Global -Name AU-02 -Description "AU-02" -Pattern '^(612|02|2)?(\d{8})$' -Translation '+612$2' -InMemory
    $nr5 = New-CsVoiceNormalizationRule -Parent Global -Name AU-03 -Description "AU-03" -Pattern '^(613|03|3)?(\d{8})$' -Translation '+613$2' -InMemory
    $nr6 = New-CsVoiceNormalizationRule -Parent Global -Name AU-07 -Description "AU-07" -Pattern '^(617|07|7)?(\d{8})$' -Translation '+617$2' -InMemory
    $nr7 = New-CsVoiceNormalizationRule -Parent Global -Name AU-08 -Description "AU-08" -Pattern '^(618|08|8)?(\d{8})$' -Translation '+618$2' -InMemory
    $nr8 = New-CsVoiceNormalizationRule -Parent Global -Name AU-International -Description "AU International" -Pattern '^(?:\+|0011)(1|7|2[07]|3[0-46]|39\d|4[013-9]|5[1-8]|6[0-6]|8[1246]|9[0-58]|2[1235689]\d|24[013-9]|242\d|3[578]\d|42\d|5[09]\d|6[789]\d|8[035789]\d|9[679]\d)(?:0)?(\d{6,14})(\D+\d+)?$' -Translation '+$1$2' -InMemory
    New-CsTenantDialPlan -Identity "AU-National" -NormalizationRules @{Add = $nr1, $nr2, $nr3 }
    New-CsTenantDialPlan -Identity "AU-02" -NormalizationRules @{Add = $nr1, $nr2, $nr3, $nr4, $nr8 }
    New-CsTenantDialPlan -Identity "AU-03" -NormalizationRules @{Add = $nr1, $nr2, $nr3, $nr5, $nr8 }
    New-CsTenantDialPlan -Identity "AU-07" -NormalizationRules @{Add = $nr1, $nr2, $nr3, $nr6, $nr8 }
    New-CsTenantDialPlan -Identity "AU-08" -NormalizationRules @{Add = $nr1, $nr2, $nr3, $nr7, $nr8 }
}

# Function to setup the tenant for direct routing
function New-TenantSetup {
    <#
    .SYNOPSIS
    Sets up the tenant for direct routing
    .DESCRIPTION
    Sets up the tenant for direct routing
    .EXAMPLE
    New-TenantSetup -tenant_sbc_fqdn sbc.yesit.com.au
    .PARAMETER tenant_sbc_fqdn
    The FQDN of the SBC
    .NOTES
    #>
    param (
        [parameter(Mandatory = $true)]
        $sbc_fqdn
    )

    if ($sbc_fqdn -eq $null) {
        Write-Error "You must specify the FQDN of the SBC"
        exit
    }

    Set-CsOnlinePstnUsage -Identity Global -Usage @{Add = "YCLTeamsVoice" }
    New-CsOnlineVoiceRoute -Identity "YCLTeamsVoice" -NumberPattern ".*" -OnlinePstnGatewayList $sbc_fqdn -OnlinePstnUsages "YCLTeamsVoice"
    New-CsOnlineVoiceRoutingPolicy -id YCLTeamsVoice -OnlinePstnUsages "YCLTeamsVoice" -Description "Yes Cloud Voice Routing Policy"
    Set-CsTeamsCallingPolicy -Identity Global -BusyOnBusyEnabledType Enabled
    Add-DialPlans
}