function HVDS_Staging
 {
  $hostname = $env:COMPUTERNAME
  $staging_source = Get-Volume -FileSystemLabel 'HVDS_Autorun'
  $staging_path = [STRING]::Concat($staging_source.DriveLetter,':\')
  [XML]$staging_layoutxml = Get-Content ([STRING]::Concat($staging_path,'layout.xml'))
  $vhsource = [STRING]::Concat('\\',$staging_layoutxml.build.server.vhost.vhostname,'\c$\hvds')
  $hvds_report_path = [STRING]::Concat($vhsource,'\reports\')
  $vhostuser = [STRING]::Concat($staging_layoutxml.build.server.vhost.vhostname,'\Administrator')
  $vhostpass = Get-Content ([STRING]::Concat($staging_path,'\password.txt'))|ConvertTo-SecureString -Key (1.16)
  $vhostlogin = New-Object System.Management.Automation.PSCredential ($vhostuser,$vhostpass)
  New-PSDrive -Persist -Name H -PSProvider FileSystem -Root $vhsource -Credential $vhostlogin
  Copy-Item T: C:\ASCT -Recurse -Verbose
  New-Item -Path $hvds_report_path -Name ([STRING]::Concat($hostname,'.txt')) -ItemType File
  Remove-PSDrive -Name T
  if (($hostname -like '*win7*') -or ('*ex14*'))
   {
    netsh interface set interface name="Local Area Connection" newname="LAN"
   }
  else
   {
    Get-NetAdapter |Rename-NetAdapter -NewName LAN
   }
  New-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'Function' -Value 'powershell.exe . C:\HVDS\postconfig\task.ps1;Function'
  Restart-Computer
 }