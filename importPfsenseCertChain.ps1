<#
  .SYNOPSIS
  Tobias, 9-5-2022.
  This script is based on 2 articles i have read about downloading ACME certificates via the Pfsense webUI.
  .DESCRIPTION
  This script downloads ACME certificates from Pfsense and imports them into certificate manager with the CA certificate inside
  .EXAMPLE
  PS> .\importPfsenseCertChain.ps1
  Scheduled task: powershell.exe -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File c:\importPfsenseCertChain.ps1
  .LINK
  Webrequests to Pfsense based on:
  https://www.chadmccune.net/2020/07/30/scripting-pfsense-dhcp-static-assignments/
  https://forum.netgate.com/topic/123405/get-certificates-from-pfsense-cert-manager-using-linux-commandline/4
#>

$PFSENSE_USERNAME = "CertMgmt" #Username of your restricted useraccoun
$PFSENSE_PASSWORD = "Password" #Password of your restricted useraccount
$SITE = "https://fqdn.pfsense.local" #FQDN or IP address of your Pfsense instance
$CERTID = "" #Pfsense certificate id to download
$CAID = "" #Pfsense CA certificate id to download
$CERTNAME = "" #Name to give to the downloaded files
$CERTDIR = "c:\windows\temp" #Location on your Windows instance where the certificates will be downloaded
$PFXPASSWORD = "" #password to generate and import the pfx file with certutil

try {
    try {
        if ((Test-Path -Path $CERTDIR -ErrorAction Stop) -eq $false){
            New-Item -ItemType Directory -Path $CERTDIR
        }
        else {
        }
    }
    catch {
        New-Item -ItemType Directory -Path $CERTDIR
    }

    #Request to get the CSRF token for this session
    $lastRequest = (Invoke-WebRequest "$SITE/system_certmanager.php" -SessionVariable pfSenseSession -UseBasicParsing)
    
    #Request to authenticate
    $postParams = @{login='Login';usernamefld=$PFSENSE_USERNAME;passwordfld=$PFSENSE_PASSWORD;__csrf_magic=$lastRequest.InputFields[0].value}
    $lastRequest = (Invoke-WebRequest "$SITE/system_certmanager.php" -WebSession $pfSenseSession -Method Post -Body $postParams -UseBasicParsing)

    #Request to download the certificate
    $postParams = @{act='exp';id=$CERTID;__csrf_magic=$lastRequest.InputFields[0].value}
    (Invoke-WebRequest "$SITE/system_certmanager.php" -OutFile "$CERTDIR\$CERTNAME.crt" -WebSession $pfSenseSession -Method Post -Body $postParams -UseBasicParsing)

    #Request to download the CA certificate
    $postParams = @{act='exp';id=$CAID;__csrf_magic=$lastRequest.InputFields[0].value}
    (Invoke-WebRequest "$SITE/system_camanager.php" -OutFile "$CERTDIR\ca.crt" -WebSession $pfSenseSession -Method Post -Body $postParams -UseBasicParsing)

    #Request to download the private key
    $postParams = @{act='key';id=$CERTID;__csrf_magic=$lastRequest.InputFields[0].value}
    (Invoke-WebRequest "$SITE/system_certmanager.php" -OutFile "$CERTDIR\$CERTNAME.key" -WebSession $pfSenseSession -Method Post -Body $postParams)
}
catch {
    #TLS config as system / service acount
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

#merge pfx and import the certificate into the personal LocalMachine store
cat $CERTDIR\"ca.crt" >> $CERTDIR\$CERTNAME.crt #merge cert with ca cert
certutil.exe -p "$PFXPASSWORD,$PFXPASSWORD" -f -MergePFX $CERTDIR\$CERTNAME.crt $CERTDIR\$CERTNAME.pfx #Merge the PFX itself
$thumbprint = Import-pfxCertificate -FilePath "$CERTDIR\$CERTNAME.pfx" -password (ConvertTo-SecureString $PFXPASSWORD -AsPlainText -Force) -CertStoreLocation Cert:\LocalMachine\My | Select-Object -ExpandProperty Thumbprint #select thumbprint

#Cleanup actions for the certificates
Remove-Item  -Exclude "$CERTNAME.pfx" -Path $CERTDIR\*.* -Force

