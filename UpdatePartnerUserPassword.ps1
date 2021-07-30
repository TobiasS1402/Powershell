function Update-PartnerUserPassword {
    Param (
        [Parameter(Mandatory=$true)]
        [String]$Username,

        [Parameter(Mandatory=$true)]
        [SecureString]$Newpassword
    )

     <#
        .SYNOPSIS
        Author: Tobias, 30-07-2021

        .DESCRIPTION
        This script can be used by MSP's to change the username of a username that is present in multiple partner tenants

        .PARAMETER Username
        A userprincipalname possibly prepended by a random string to run the search method on.
        Examples of usernames with param $Username = test: test@testdomain.com, testtest@domain.com, admin_test@domain.com

        .PARAMETER Newpassword
        The password that will be set for the selected users with Userprincipalname

        .EXAMPLE
        PS> UpdatePartnerUserPassword.ps1 -Username username -Newpassword newpassword

        .EXAMPLE
        PS> UpdatePartnerUserPassword.ps1 -Username sccm -Newpassword administrator

        .EXAMPLE
        PS> import-module UpdatePartnerUserPassword.ps1
        PS> Update-PartnerUserPassword -Username username -Newpassword password

    #>

    Set-StrictMode -Version Latest

    #Import and connect for the PartnerCenter module
    try {
        import-module -name PartnerCenter -ErrorAction Stop
    }
    catch {
        Install-Module -Name PartnerCenter -Force #Requires -RunAsAdministrator
        Import-Module -name PartnerCenter
    }
    Connect-PartnerCenter -usedeviceauthentication

    #Match any userprincipalname format: [*username@customertenant.com]
    $searchcriterium = "^.*($Username)@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"

    #Empty Powershell array#>
    $resultArray = @()

    #Empty progression bar#>
    $progress = 0

    #Gets all partnercustomers
    $partners = Get-PartnerCustomer

    #foreach loop that selects the userid for a match in the REGEX pattern, then if found changes the password for the user and writes it to the array
    foreach($partner in $partners)
    {
        $userid = Get-PartnerCustomerUser -CustomerId $partner.CustomerId | Where-Object UserPrincipalName -match $searchcriterium | Select-Object -ExpandProperty UserId
        if(!$userid){
            $resultArray += [pscustomobject]@{Partner=$Partner.Name;Status='Failure';Message='User was not found.'}
        }
        else{
            Set-PartnerCustomerUser -CustomerId $partner.CustomerId -UserId $userid -Password $NewPassword | Out-Null
            $resultArray += [pscustomobject]@{Partner=$Partner.Name;Status='Success';Message='Password has been succesfully changed.'}
        }
        $progress++
        Write-Progress -Activity "Looping and setting new password for selected user..." -status "Changed: $progress of $($partners.Count)" -percentComplete (($progress / $partners.Count) * 100)
    }
    #loading the array in terminal for the results
    $resultArray | Format-Table
}

#Executing the function
Update-PartnerUserPassword
