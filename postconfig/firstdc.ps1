function HVDS_Staging
 {
  $hostname = $env:COMPUTERNAME
  Start-Transcript -Path ([STRING]::Concat('C:\',$hostname,'.txt')) -NoClobber -Append
  $staging_source = Get-Volume -FileSystemLabel 'HVDS_Autorun'
  $staging_path = [STRING]::Concat($staging_source.DriveLetter,':\')
  [XML]$staging_layoutxml = Get-Content ([STRING]::Concat($staging_path,'layout.xml'))
  $vhsource = [STRING]::Concat('\\',$staging_layoutxml.build.server.vhost.vhostname,'\c$\hvds')
  $hvds_report_path = [STRING]::Concat($vhsource,'\reports\')
  $vhostuser = [STRING]::Concat($staging_layoutxml.build.server.vhost.vhostname,'\Administrator')
  $vhostpass = Get-Content ([STRING]::Concat($staging_path,'\password.txt'))|ConvertTo-SecureString -Key (1..16)
  $vhostlogin = New-Object System.Management.Automation.PSCredential ($vhostuser,$vhostpass)
  New-PSDrive -Persist -Name H -PSProvider FileSystem -Root $vhsource -Credential $vhostlogin -Scope Global
  Copy-Item H: C:\HVDS -Recurse -Verbose
  if (($hostname -like '*win7*') -or ('*ex14*'))
   {
    netsh interface set interface name="Local Area Connection" newname="LAN"
   }
  if (($hostname -notlike '*win7*') -or ('*ex14*'))
   {
    Get-NetAdapter |Rename-NetAdapter -NewName LAN
   }
  New-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'ADDS_Install' -Value 'powershell.exe . C:\HVDS\postconfig\firstdc.ps1;ADDS_Install'
  Copy-Item ([STRING]::Concat('C:\',$hostname,'.txt')) -Destination 'H:\reports'
  Start-Sleep -Seconds 30
  Restart-Computer
 }

function ADDS_Install
 {
  $hostname = $env:COMPUTERNAME
  [XML]$layoutxml = Get-Content 'C:\HVDS\XML\layout.xml'
  Start-Transcript -Path ([STRING]::Concat('\\',$layoutxml.build.server.vhost.vhostname,'\c$\hvds\reports\',$hostname,'.txt')) -NoClobber -Append
  Add-WindowsFeature AD-Domain-Services
  New-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'Domain_Build' -Value 'powershell.exe . C:\HVDS\postconfig\firstdc.ps1;Domain_Build'
  Start-Sleep -Seconds 30
  Restart-Computer
 }

function Domain_Build
 {
  $hostname = $env:COMPUTERNAME
  [XML]$layoutxml = Get-Content 'C:\HVDS\XML\layout.xml'
  Start-Transcript -Path ([STRING]::Concat('\\',$layoutxml.build.server.vhost.vhostname,'\c$\hvds\reports\',$hostname,'.txt')) -NoClobber -Append
  $netbiosname = [STRING]$layoutxml.build.network.dns.siteid
  $netdnsname = [STRING]::Concat($netbiosname,'.',$layoutxml.build.network.dns.domainname)
  $vhostpass = Get-Content 'C:\HVDS\tools\password.txt' |ConvertTo-SecureString -Key (1..16)

  Import-Module ADDSDeployment
  
  # Build the first domain controller
  Install-ADDSForest `
  -ForestMode 'Win2012' `
  -DomainMode 'Win2012' `
  -DomainName $netdnsname `
  -DomainNetBIOSName $netbiosname `
  -InstallDNS:$true `
  -DatabasePath 'C:\Windows\NTDS' `
  -LogPath 'C:\Windows\NTDS' `
  -SYSVOLPath 'C:\Windows\SYSVOL' `
  -CreateDNSDelegation:$false `
  -NoRebootOnCompletion:$true `
  -Force:$true `
  -SafeModeAdministratorPassword $vhostpass

  New-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'AD_Report' -Value 'powershell.exe . C:\HVDS\postconfig\firstdc.ps1;AD_Report'
  Restart-Computer
 }

function AD_Report
 {
  # Save AD install report
  $hostname = $env:COMPUTERNAME
  [XML]$layoutxml = Get-Content 'C:\HVDS\XML\layout.xml'
  Start-Transcript -Path ([STRING]::Concat('\\',$layoutxml.build.server.vhost.vhostname,'\c$\hvds\reports\',$hostname,'.txt')) -NoClobber -Append
  $netbiosname = [STRING]$layoutxml.build.network.dns.siteid
  $hvds_ad_report = [STRING]::Concat('\\',$layoutxml.build.server.vhost.vhostname,'\c$\hvds\reports\',$netbiosname,'.txt')
  $DC01 = ($layoutxml.build.server.vm |Where {$_.servername -like '*DC01'}).ip
  $DC02 = ($layoutxml.build.server.vm |Where {$_.servername -like '*DC02'}).ip
  $DC03 = ($layoutxml.build.server.vm |Where {$_.servername -like '*DC03'}).ip
  $DC04 = ($layoutxml.build.server.vm |Where {$_.servername -like '*DC04'}).ip
  $IPv4 = $layoutxml.build.network.IPv4.Prefix
  $IPv6 = $layoutxml.build.network.IPv6.Prefix
  $IPv6MATCH = '247'
  if ($hostname -like '*dc01')
   {
    Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses ([STRING]::Concat($IPv4,'.',$DC01,',',$IPv4,'.',$DC02,',',$IPv4,'.',$DC03,',',$IPv4,'.',$DC04))
    Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses ([STRING]::Concat($IPv6,'::',$IPv6MATCH,':',$DC01,',',$IPv6,'::',$IPv6MATCH,':',$DC02,',',$IPv6,'::',$IPv6MATCH,':',$DC03,',',$IPv6,'::',$IPv6MATCH,':',$DC04))
   }
  if ($hostname -like '*dc02')
   {
    Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses ([STRING]::Concat($IPv4,'.',$DC02,',',$IPv4,'.',$DC03,',',$IPv4,'.',$DC04,',',$IPv4,'.',$DC01))
    Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses ([STRING]::Concat($IPv6,'::',$IPv6MATCH,':',$DC02,',',$IPv6,'::',$IPv6MATCH,':',$DC03,',',$IPv6,'::',$IPv6MATCH,':',$DC04,',',$IPv6,'::',$IPv6MATCH,':',$DC01))
   }
  if ($hostname -like '*dc03')
   {
    Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses ([STRING]::Concat($IPv4,'.',$DC03,',',$IPv4,'.',$DC04,',',$IPv4,'.',$DC01,',',$IPv4,'.',$DC01))
    Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses ([STRING]::Concat($IPv6,'::',$IPv6MATCH,':',$DC03,',',$IPv6,'::',$IPv6MATCH,':',$DC04,',',$IPv6,'::',$IPv6MATCH,':',$DC01,',',$IPv6,'::',$IPv6MATCH,':',$DC02))
   }
  if ($hostname -like '*dc04')
   {
    Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses ([STRING]::Concat($IPv4,'.',$DC04,',',$IPv4,'.',$DC01,',',$IPv4,'.',$DC02,',',$IPv4,'.',$DC03))
    Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses ([STRING]::Concat($IPv6,'::',$IPv6MATCH,':',$DC04,',',$IPv6,'::',$IPv6MATCH,':',$DC01,',',$IPv6,'::',$IPv6MATCH,':',$DC02,',',$IPv6,'::',$IPv6MATCH,':',$DC03))
   }
  dcdiag.exe > $hvds_ad_report
  Remove-PSDrive -Name H
  Remove-Item C:\HVDS -Recurse -Force
  Remove-Item ([STRING]::Concat('C:\',$hostname,'.txt'))
  Logoff
 }

