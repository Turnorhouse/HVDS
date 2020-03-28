Function FirstDC
{
 $hvds = 'C:\HVDS'
 if (!(Test-Path ([STRING]::Concat($hvds,'\logs'))))
  {
   New-Item -ItemType Directory -Path ([STRING]::Concat($hvds,'\logs'))
  }
 $hvdslogs = ([STRING]::Concat($hvds,'\logs'))
 [XML]$creds = Get-Content ([STRING]::Concat($hvds,'\XML\creds.xml'))
 [XML]$layout = Get-Content ([STRING]::Concat($hvds,'\XML\layout.xml'))
 if (!(Test-Path -Path ([STRING]::Concat($hvdslogs,'\',$layout.layout.deployment.project.ToUpper(),'.txt'))))
 {
  $hvds_ad_report = [STRING]::Concat($hvdslogs,'\',$layout.layout.deployment.project.ToUpper(),'.txt')
  New-Item $hvds_ad_report
 }
 Add-WindowsFeature AD-Domain-Services
 Import-Module ADDSDeployment
 Install-ADDSForest `
 -ForestMode $layout.layout.deployment.AD_Mode `
 -DomainMode $layout.layout.deployment.AD_Mode `
 -DomainName ([STRING]::Concat($layout.layout.deployment.project,'.',$layout.layout.network.dns.upn)) `
 -DomainNetBIOSName ($layout.layout.deployment.project).ToUpper() `
 -InstallDNS:$true `
 -DatabasePath 'C:\Windows\NTDS' `
 -LogPath 'C:\Windows\NTDS' `
 -SYSVOLPath 'C:\Windows\SYSVOL' `
 -CreateDNSDelegation:$false `
 -NoRebootOnCompletion:$true `
 -Force:$true `
 -SafeModeAdministratorPassword (ConvertTo-SecureString -AsPlainText -Force ($creds.creds.accounts|Where-Object {$_.hostname -like $ENV:COMPUTERNAME}|Where-Object {$_.Function -like 'AD_Safe'}).pass)
 New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'DC_Finish' -Value "powershell `". C:\HVDS\POSTCONFIG\firstdc.ps1;DC_Finish`""
 Write-Host 'Begin 60 second debug sleep'
 Start-Sleep -Seconds 60
 Restart-Computer
}

Function DC_Finish
{
 $hvds = 'C:\HVDS'
 $hvdslogs = ([STRING]::Concat($hvds,'\logs'))
 [XML]$creds = Get-Content ([STRING]::Concat($hvds,'\XML\creds.xml'))
 [XML]$layout = Get-Content ([STRING]::Concat($hvds,'\XML\layout.xml'))
 if (!(Test-Path -Path ([STRING]::Concat($hvdslogs,'\AD.log'))))
  {
   New-Item -ItemType File -Path ([STRING]::Concat($hvdslogs,'\AD.log'))
  }
 $hvds_ad_report = [STRING]::Concat($hvdslogs,'\',$layout.layout.deployment.project.ToUpper(),'.txt')
 Add-DNSServerResourceRecordA -Name 'hvdsbuild' -ZoneName ([STRING]::Concat($layout.layout.deployment.project,'.',$layout.layout.network.dns.upn)) -IPv4Address ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '01'}).ip))) -TimeToLive '00:15:00'
 Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '01'}).ip))),([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '02'}).ip)))
 dcdiag.exe > $hvds_ad_report
 if ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon').PSObject.Properties.Name -contains 'DefaultPassword')
 {
  Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultPassword'
 } 
 Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 0
 Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoLogonCount' -Value ''
 Set-ADAccountPassword -Identity ($creds.creds.accounts|Where-Object {$_.function -eq 'AD_Admin'}).user -NewPassword (ConvertTo-SecureString -AsPlainText -Force ($creds.creds.accounts|Where-Object {$_.function -eq 'AD_Admin'}).pass) -Reset
 Start-Sleep -Seconds 10
 logoff.exe
# New-PSDrive -Root ([STRING]::Concat('\\',$layout.layout.network.ipv4.prefix,'.',($layout.layout.console|Where-Object {$_.function -eq 'mgmt'}).ip,'\HVDS')) -PSProvider FileSystem -Name 'H'
# Copy-Item -Path $hvds_ad_report -Destination 'H:\LOGS' -Verbose
# Start-Sleep -Seconds 600
}


Function Disable_Autologon
 {
  Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultPassword'
  Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 0
  Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoLogonCount' -Value ''
 }