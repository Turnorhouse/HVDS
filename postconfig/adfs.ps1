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
  New-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'Domain_Bind' -Value 'powershell.exe . C:\HVDS\postconfig\adfs.ps1;Domain_Bind'
  Copy-Item ([STRING]::Concat('C:\',$hostname,'.txt')) -Destination 'H:\reports'
  Start-Sleep -Seconds 30
  Restart-Computer
 }

 function Domain_Bind
  {
   [XML]$layoutxml = Get-Content 'C:\HVDS\XML\layout.xml'
   $hostname = $env:COMPUTERNAME
   Start-Transcript -Path ([STRING]::Concat('\\',$layoutxml.build.server.vhost.vhostname,'\c$\hvds\reports\',$hostname,'.txt')) -NoClobber -Append
   $netbiosname = [STRING]$layoutxml.build.network.dns.siteid
   $netdnsname = [STRING]::Concat($netbiosname,'.',$layoutxml.build.network.dns.domainname)
   $vhostuser = [STRING]::Concat($netdnsname,'\Administrator')
   $vhostpass = Get-Content 'C:\HVDS\tools\password.txt' |ConvertTo-SecureString -Key (1..16)
   $vhostlogin = New-Object System.Management.Automation.PSCredential ($vhostuser,$vhostpass)
   Add-Computer -DomainName $netdnsname -Credential $vhostlogin -Confirm:$false -Force
   Remove-PSDrive -Name H
   Remove-Item C:\HVDS -Recurse -Force
   Remove-Item ([STRING]::Concat('C:\',$hostname,'.txt'))
   Restart-Computer
  }