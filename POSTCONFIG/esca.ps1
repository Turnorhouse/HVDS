Function ESCA
 {
  $hvds = 'C:\HVDS'
  $hvdslogs = ([STRING]::Concat($hvds,'\logs'))
  [XML]$creds = Get-Content ([STRING]::Concat($hvds,'\XML\creds.xml'))
  [XML]$layout = Get-Content ([STRING]::Concat($hvds,'\XML\layout.xml'))
  Add-WindowsFeature -IncludeManagementTools -Name ADCS-Cert-Authority, `
   ADCS-Web-Enrollment, Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, `
   Web-Static-Content, Web-Http-Redirect, Web-Http-Logging, Web-Log-Libraries, `
   Web-Request-Monitor, Web-Http-Tracing, Web-Stat-Compression, Web-Filtering, `
   Web-Windows-Auth, Web-ASP, Web-ISAPI-Ext

   $orcahost = ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,($layout.layout.virtual.vm|Where-Object {$_.function -eq 'orca'}).function))
   $orcauser = ($creds.creds.accounts|Where-Object {$_.stack -eq 'orca'}).user
   $orcapass = ConvertTo-SecureString -AsPlainText -Force ($creds.creds.accounts|Where-Object {$_.stack -eq 'orca'}).pass
   $orcacred = New-Object System.Management.Automation.PSCredential ($orcauser,$orcapass)
   While (!(Test-Connection $orcahost -ErrorAction SilentlyContinue))
    {
     Write-Host -ForegroundColor Yellow ([STRING]::Concat('Waiting 60 seconds for ',$orcahost,' to become live.'))
     Start-Sleep -Seconds 60
    }
   $orcapath = New-PSDrive -PSProvider FileSystem -Root ([STRING]::Concat('\\',$orcahost,'\c$')) -Name 'O' -Credential $orcacred
   Install-AdcsCertificationAuthority -CAType EnterpriseSubordinateCA -KeyLength 2048 -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider' -HashAlgorithmName SHA256 -CACommonName $ENV:COMPUTERNAME -OutputCertRequestFile ([STRING]::Concat('C:\',$ENV:COMPUTERNAME,'_req.req')) -Force
   Install-AdcsWebEnrollment -Force
   $orcacert = Get-ChildItem -Path 'C:\Windows\System32\certsrv\CertEnroll' |Where-Object {$_.Name -like ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,($layout.layout.virtual.vm|Where-Object {$_.function -eq 'orca'}).function,'*.crt'))}
   $escacert = Get-ChildItem -Path 'C:\Windows\System32\certsrv\CertEnroll' |Where-Object {$_.Name -like ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,($layout.layout.virtual.vm|Where-Object {$_.function -eq 'esca'}).function,'*.cer'))}
   While (!(Test-Path ([STRING]::Concat('C:\',$ENV:COMPUTERNAME,'_req.req'))))
    {
     Start-Sleep -Seconds 5
    }
   Copy-Item -Path ([STRING]::Concat('C:\',$ENV:COMPUTERNAME,'_req.req')) -Destination ([STRING]::Concat($orcapath.Name,':\')) -Force -Verbose
   Copy-Item -Path ([STRING]::Concat($orcapath.Name,':\Windows\System32\Certsrv\CertEnroll\*')) -Destination 'C:\Windows\System32\Certsrv\CertEnroll' -Verbose -Force
   While (!(Test-Path ([STRING]::Concat($orcapath.Name,':\',$ENV:COMPUTERNAME,'_cer.cer'))))
    {
     Write-Host 'Waiting for certificate approval and export.'
     Start-Sleep -Seconds 30
    }
   Copy-Item -Path ([STRING]::Concat($orcapath.Name,':\',$ENV:COMPUTERNAME,'_cer.cer'))  -Destination 'C:\Windows\System32\Certsrv\CertEnroll' -Verbose -Force
   Remove-PSDrive -Name 'O'
   $orcacert = Get-ChildItem -Path 'C:\Windows\System32\certsrv\CertEnroll' |Where-Object {$_.Name -like ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,($layout.layout.virtual.vm|Where-Object {$_.function -eq 'orca'}).function,'*.crt'))}
   $escacert = Get-ChildItem -Path 'C:\Windows\System32\certsrv\CertEnroll' |Where-Object {$_.Name -like ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,($layout.layout.virtual.vm|Where-Object {$_.function -eq 'esca'}).function,'*.cer'))}
   While (!(Test-Path $orcacert.FullName))
    {
     Start-Sleep -Seconds 5
    }
   Import-Certificate -FilePath $orcacert.FullName -CertStoreLocation Cert:\LocalMachine\Root\
   certutil.exe -installCert $escacert.FullName
   Restart-Service certsvc

 }

