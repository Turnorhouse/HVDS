Function ESCA
{

Add-WindowsFeature -IncludeManagementTools -Name ADCS-Cert-Authority, ADCS-Web-Enrollment, Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-Static-Content, Web-Http-Redirect, Web-Http-Logging, `
Web-Log-Libraries, Web-Request-Monitor, Web-Http-Tracing, Web-Stat-Compression, Web-Filtering, Web-Windows-Auth, Web-ASP, Web-ISAPI-Ext


Install-ADCSCertificationAuthority -CAType EnterpriseSubordinateCA -KeyLength 2048 -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider' -HashAlgorithmName SHA256 -CACommonName $ENV:COMPUTERNAME -ValidityPeriod Years -ValidityPeriodUnits 2 -Confirm:$false

}


