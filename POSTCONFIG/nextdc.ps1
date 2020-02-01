Function NextDC
{
 $hvds = 'C:\HVDS'
 $hvdslogs = ([STRING]::Concat($hvds,'\logs'))
 [XML]$creds = Get-Content ([STRING]::Concat($hvds,'\XML\creds.xml'))
 [XML]$layout = Get-Content ([STRING]::Concat($hvds,'\XML\layout.xml'))
 if (!(Test-Path -Path ([STRING]::Concat($hvdslogs,'\',$layout.layout.deployment.project.ToUpper(),'.txt'))))
 {
  $hvds_ad_report = [STRING]::Concat($hvdslogs,'\',$layout.layout.deployment.project.ToUpper(),'.txt')
  New-Item $hvds_ad_report
 }
 $user = ([STRING]::Concat($layout.layout.deployment.project,'\',($creds.creds.accounts|Where-Object {$_.function -eq 'AD_Admin'}).user))
 $pass = ConvertTo-SecureString -AsPlainText -Force ($creds.creds.accounts|Where-Object {$_.function -eq 'AD_Admin'}).pass
 $adlogon = New-Object System.Management.Automation.PSCredential ($user,$pass)
 While ($null -eq (Test-Connection ([STRING]::Concat($layout.layout.deployment.project,'.',$layout.layout.network.dns.upn))))
 {
  Write-Host -ForegroundColor Yellow ([STRING]::Concat('Waiting for ',$layout.layout.deployment.project,'.',$layout.layout.network.dns.upn,' to become live. Will try again in 120 seconds.'))
  Start-Sleep -Seconds 120
 }
 Add-WindowsFeature AD-Domain-Services
 Import-Module ADDSDeployment
 Install-ADDSDomainController `
 -Credential $adlogon `
 -DomainName ([STRING]::Concat($layout.layout.deployment.project,'.',$layout.layout.network.dns.upn)) `
 -SiteName 'Default-First-Site-Name' `
 -DatabasePath 'C:\Windows\NTDS' `
 -LogPath 'C:\Windows\NTDS' `
 -SYSVOLPath 'C:\Windows\SYSVOL' `
 -CriticalReplicationOnly:$false `
 -InstallDNS:$true `
 -NoRebootOnCompletion:$true `
 -SafeModeAdministratorPassword: $(ConvertTo-SecureString -AsPlainText -Force ($creds.creds.accounts|Where-Object {$_.hostname -like $ENV:COMPUTERNAME}|Where-Object {$_.Function -like 'AD_Safe'}).pass) `
 -CreateDNSDelegation:$false `
 -Force:$true
 New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'DC_Finish' -Value "powershell `". C:\HVDS\POSTCONFIG\NextDC.ps1;DC_Finish`""
 Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultPassword' -Value (($creds.creds.accounts|Where-Object {$_.hostname -like([STRING]::Concat($layout.layout.deployment.project,'.',$layout.layout.network.dns.upn))})|Where-Object {$_.function -like 'AD_Admin'}).pass
 Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultUserName' -Value ([STRING]::Concat($layout.layout.deployment.project,'\',($creds.creds.accounts|Where-Object {$_.function -like 'AD_Admin'}).user))
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
 if ($ENV:COMPUTERNAME -like '*dc*01*')
  {
   Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '01'}).ip))),([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '02'}).ip)))
  }
  if (($ENV:COMPUTERNAME -like '*dc*0*') -and ($ENV:COMPUTERNAME -notlike '*dc*01*'))
  {
   Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '02'}).ip))),([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '01'}).ip)))
  }
 dcdiag.exe >> $hvds_ad_report
 if ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon').PSObject.Properties.Name -contains 'DefaultPassword')
 {
  Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultPassword'
 } 
 Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 0
 Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoLogonCount' -Value ''
 Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoLogonCount' -Value ''
 Write-Host 'Begin 60 second debug sleep'
 Start-Sleep -Seconds 60
 Restart-Computer
}