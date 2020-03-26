Function ORCA
{ 
 $hvds = 'C:\HVDS'
 $hvdslogs = ([STRING]::Concat($hvds,'\logs'))
 [XML]$creds = Get-Content ([STRING]::Concat($hvds,'\XML\creds.xml'))
 [XML]$layout = Get-Content ([STRING]::Concat($hvds,'\XML\layout.xml'))
 $escahost = [STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,($layout.layout.virtual.vm|Where-Object {$_.function -like 'esca'}).function)
 Add-WindowsFeature ADCS-Cert-Authority
 Start-Sleep -Seconds 30
 Install-ADCSCertificationAuthority -CAType StandaloneRootCA -KeyLength 2048 -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider' -HashAlgorithmName SHA256 -CACommonName $ENV:COMPUTERNAME -ValidityPeriod Years -ValidityPeriodUnits 2 -Confirm:$false
 Get-CACrlDistributionPoint|Remove-CACrlDistributionPoint -Force
 Get-CAAuthorityInformationAccess|Remove-CAAuthorityInformationAccess -Force
 Add-CACrlDistributionPoint -Uri 'C:\Windows\system32\CertSrv\CertEnroll\<CAName><CRLNameSuffix><DeltaCRLAllowed>.crl' -PublishToServer:$true -PublishDeltaToServer:$true -Force
 Add-CACrlDistributionPoint -Uri ([STRING]::Concat('http://',$layout.layout.deployment.site,$layout.layout.deployment.platform,($layout.layout.virtual.vm|Where-Object {$_.function -like 'esca'}).function.ToLower(),'.',$layout.layout.deployment.project,'.',$layout.layout.network.dns.upn,'/CertEnroll/<CaName><CRLNameSuffix><DeltaCRLAllowed>.crl')) -AddToCertificateCdp:$true -AddToFreshestCrl:$true -Force
 Add-CAAuthorityInformationAccess -Uri ([STRING]::Concat('http://',$layout.layout.deployment.site,$layout.layout.deployment.platform,($layout.layout.virtual.vm|Where-Object {$_.function -like 'esca'}).function.ToLower(),'.',$layout.layout.deployment.project,'.',$layout.layout.network.dns.upn,'/CertEnroll/<ServerDNSName>_<CAName><CertificateName>.crt')) -AddToCertificateAia -Force
 certutil.exe -crl
 certutil -setreg CA\CRLPeriodUnits 52
 certutil -setreg CA\CRLPeriod 'Weeks'
 Restart-Service certsvc
 While (!(Test-Path ([STRING]::Concat('C:\',$escahost,'_req.req'))))
  {
   Write-Host ([STRING]::Concat('Waiting for request file - C:\',$escahost,'_req.req - from host ',$escahost))
   Start-Sleep -Seconds 5
  }
 $reqid = certreq.exe -config - -submit ([STRING]::Concat('C:\',$escahost,'_req.req')) -Force|FindSTR RequestId
 certutil.exe -resubmit $reqid[0].Substring(11)
 certreq.exe -config - -retrieve $reqid[0].Substring(11) ([STRING]::Concat('C:\',$escahost,'_cer.cer'))
}