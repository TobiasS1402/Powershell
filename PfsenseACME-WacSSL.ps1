<#
  .SYNOPSIS
  Tobias, 6-8-2021.
  This script is based on 2 articles i have read about downloading ACME certificates via the Pfsense webUI. In this specific case i tailored the script specifically for the use on my Windows Admin Center host.

  .DESCRIPTION
  This script downloads ACME certificates from Pfsense and imports them into your WAC instance.

  .EXAMPLE
  PS> .\PfsenseACME-WacSSL.ps1
  Scheduled task: powershell.exe -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File c:\PfsenseACME-WacSSL.ps1

  .LINK
  Webrequests to Pfsense based on:
  https://www.chadmccune.net/2020/07/30/scripting-pfsense-dhcp-static-assignments/
  https://forum.netgate.com/topic/123405/get-certificates-from-pfsense-cert-manager-using-linux-commandline/4
#>

$PFSENSE_USERNAME = "CertMgmt" #Username of your restricted useraccoun
$PFSENSE_PASSWORD = "Password" #Password of your restricted useraccount
$SITE = "https://fqdn.pfsense.local" #FQDN or IP address of your Pfsense instance
$CERTID = "certid" #Pfsense certificate id to download
$CERTNAME = "intranet" #Name to give to the downloaded files
$CERTDIR = "c:\certificates\intranet" #Location on your Windows instance where the certificates will be downloaded
$PFXPASSWORD = "pfxpassword" #password to generate and import the pfx file with certutil
$GUID = New-Guid | Select-Object -ExpandProperty Guid #$GUID generates a GUID for the netsh app id
$WACPORT = 443 #Port on which your WAC is running

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

    #Request to download the private key
    $postParams = @{act='key';id=$CERTID;__csrf_magic=$lastRequest.InputFields[0].value}
    (Invoke-WebRequest "$SITE/system_certmanager.php" -OutFile "$CERTDIR\$CERTNAME.key" -WebSession $pfSenseSession -Method Post -Body $postParams)
}
catch {
    #TLS config as system / service acount
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

#merge pfx for Windows Admin Center and import the certificate into the personal LocalMachine store
certutil.exe -p "$PFXPASSWORD,$PFXPASSWORD" -f -MergePFX $CERTDIR\$CERTNAME.crt $CERTDIR\$CERTNAME.pfx
$thumbprint = Import-pfxCertificate -FilePath "$CERTDIR\$CERTNAME.pfx" -password (ConvertTo-SecureString $PFXPASSWORD -AsPlainText -Force) -CertStoreLocation Cert:\LocalMachine\My | Select-Object -ExpandProperty Thumbprint

#Cleanup actions for the certificates
Remove-Item -Path $CERTDIR\*.* -Force

#netsh remove ssl config for WAC @ port 443
netsh http delete sslcert ipport=0.0.0.0:$WACPORT
netsh http add sslcert ipport=0.0.0.0:$WACPORT certhash=$thumbprint appid="{$GUID}"

#restart the WAC service for sslconfig to take effect
Restart-Service ServerManagementGateway -Force
