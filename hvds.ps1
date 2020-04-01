Function HVDS_Build
 {
  [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')|Out-Null
  $hvdsdir = New-Object System.Windows.Forms.FolderBrowserDialog
  $hvdsdir.Description = 'Select HVDS location...'
  $hvdsdir.RootFolder = 'MyComputer'
  $hvdsdir.ShowDialog()|Out-Null
  $hvdsdest = New-Object System.Windows.Forms.FolderBrowserDialog
  $hvdsdest.Description = 'Select VM destination...'
  $hvdsdest.RootFolder = 'MyComputer'
  $hvdsdest.ShowDialog()|Out-Null
  $hvdswiniso = New-Object System.Windows.Forms.OpenFileDialog
  $hvdswiniso.filter = 'Windows ISO (*windows*.iso)| *windows*.iso'
  $hvdswiniso.ShowDialog()|Out-Null

# Define VM networking - Need to find a better way to do this...
  $nic1 = 'vLAN'

# Begin sanity checks
  switch ($hvds)
   {
    {!(Test-Path ($hvdsdir.SelectedPath+'\XML'))} {Write-Host -ForegroundColor Red('Directory '+$hvdsdir.SelectedPath+'\XML does not exist - Exiting.') ;break}
    {!(Test-Path ($hvdsdir.SelectedPath+'\XML\layout.xml'))} {Write-Host -ForegroundColor Red('HVDS required config file, '+$hvdsdir.SelectedPath+'\XML\layout.xml does not exist - Exiting.') ;break}
    {!(Test-Path ($hvdsdir.SelectedPath+'\XML\autounattend.xml'))} {Write-Host -ForegroundColor Red('HVDS required config file, '+$hvdsdir.SelectedPath+'\XML\autounattend.xml') ;break}
    {!(Test-Path ($hvdsdir.SelectedPath+'\POSTCONFIG'))} {Write-Host -ForegroundColor Red('HVDS postconfig scripts not found. These are required and need to live in '+$hvdsdir.selectedpath+'\POSTCONFIG. - Exiting.')}
    {!(Test-Path ($hvdsdir.SelectedPath+'\LOGS'))} {New-Item -ItemType Directory -Path ($hvdsdir.SelectedPath+'\LOGS')}
    {!(Test-Path ($hvdsdir.SelectedPath+'\ISO'))} {New-Item -ItemType Directory -Path ($hvdsdir.SelectedPath+'\ISO')}
    {!(Test-Path ($hvdsdir.SelectedPath+'\TOOLS'))} {New-Item -ItemType Directory -Path ($hvdsdir.SelectedPath+'\TOOLS')}
    {!(Test-Path ($hvdsdir.SelectedPath+'\TOOLS\WINFIX'))} {New-Item -ItemType Directory -Path ($hvdsdir.SelectedPath+'\TOOLS\WINFIX')}
    {!(Test-Path ($hvdsdir.SelectedPath+'\TOOLS\oscdimg.exe'))}
    {
     Write-Host -ForegroundColor Yellow('Tool '+$hvdsdir.SelectedPath+'\TOOLS\oscdimg.exe does not exist - please select location of oscdimg.exe.')
     $oscdimgexe = New-Object System.Windows.Forms.OpenFileDialog
     $oscdimgexe.filter = 'OSCDIMG.EXE(oscdimg.exe)| oscdimg.exe'
     $oscdimgexe.ShowDialog()|Out-Null
     if ($null -eq $oscdimgexe.filename){break}
     else {Copy-Item -Path $oscdimgexe.filename -Destination ($hvdsdir.SelectedPath+'\TOOLS') -Verbose}
     $oscdimgexe.FileName = ($hvdsdir.SelectedPath+'\TOOLS\oscdimg.exe')
    }
    {(Test-Path ($hvdsdir.SelectedPath+'\TOOLS\oscdimg.exe'))}
     {
      $oscdimgexe = New-Object System.Windows.Forms.OpenFileDialog
      $oscdimgexe.FileName = ($hvdsdir.SelectedPath+'\TOOLS\oscdimg.exe')
     }
    {!(Test-Path ($hvdsdest.SelectedPath))}
     {
      Write-Host -ForegroundColor Yellow('The selected VM destination - '+$hvdsdest.SelectedPath+' - does not exist or could not be found. Please re-select the VM destination location.')
      $hvdsdest = New-Object System.Windows.Forms.FolderBrowserDialog
      $hvdsdest.Description = 'Select VM destination...'
      $hvdsdest.ShowDialog()|Out-Null
      if ($null -eq $hvdsdest.SelectedPath){Write-Host -ForegroundColor Red('Invalid VM location configuration. HVDS can not continue.');break}
     }
   }
  [XML]$layoutxml = Get-Content ($hvdsdir.SelectedPath+'\XML\layout.xml')
  [XML]$unattendxml = Get-Content ($hvdsdir.SelectedPath+'\XML\autounattend.xml')
# End sanity checks

# Build the start of our password XML file. Note that this is plain text, human readable, and exists ONLY for the process of allowing the user to change passwords.
  $credlist = New-Object System.Xml.XmlDocument
  $credxml = $credlist.CreateElement('creds')
  $credlist.AppendChild($credxml)
  $accounts = $credxml.AppendChild($credlist.CreateElement('accounts'))
  $accounts.SetAttribute('hostname','changeme')
  $accounts.SetAttribute('user','Administrator')
  $accounts.SetAttribute('pass','changeme')
  $accounts.SetAttribute('function','changeme')
# Base creds.xml has been created.

# Set AD admin password
  $credxml.accounts.hostname = ($layoutxml.layout.deployment.project+'.'+$layoutxml.layout.network.dns.upn)
  $credxml.accounts.function = 'AD_Admin'
  $credxml.accounts.pass = [System.Web.Security.Membership]::GeneratePassword(15,0)
# End building of creds.xml

# Fix Windows ISO (obnoxious "Press any key to boot from DVD...")
  $winiso = Mount-DiskImage ($hvdswiniso.FileName) -PassThru | Get-Volume
  Copy-item -Path ($winiso.DriveLetter+':\*') -Destination ($hvdsdir.SelectedPath+'\TOOLS\WINFIX') -Recurse -Verbose
  Dismount-DiskImage $hvdswiniso.FileName
  Rename-Item -Path ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\efi\microsoft\boot\cdboot.efi') -NewName ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\efi\microsoft\boot\cdboot_prompt.efi')
  Rename-Item -Path ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\efi\microsoft\boot\efisys.bin') -NewName ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\efi\microsoft\boot\efisys_prompt.bin')
  Rename-Item -Path ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\efi\microsoft\boot\cdboot_noprompt.efi') -NewName ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\efi\microsoft\boot\cdboot.efi')
  Rename-Item -Path ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\efi\microsoft\boot\efisys_noprompt.bin') -NewName ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\efi\microsoft\boot\efisys.bin')

# Build VM's based on config file
  ForEach ($vm in $layoutxml.layout.virtual.vm)
   {
# Determine service version and count (ex1501, dc02, sfb6x, etc) and set $vmname
# Note that some VM's may have neither service version or count in hostname.
    Switch ($switch)
     {
      {($null -eq $vm.ver) -and ($null -eq $vm.unit)} {$vmname = $layoutxml.layout.deployment.site+$layoutxml.layout.deployment.platform+$vm.function}
      {($null -ne $vm.ver) -and ($null -eq $vm.unit)} {$vmname = $layoutxml.layout.deployment.site+$layoutxml.layout.deployment.platform+$vm.function+$vm.ver}
      {($null -eq $vm.ver) -and ($null -ne $vm.unit)} {$vmname = $layoutxml.layout.deployment.site+$layoutxml.layout.deployment.platform+$vm.function+$vm.unit}
      {($null -ne $vm.ver) -and ($null -ne $vm.unit)} {$vmname = $layoutxml.layout.deployment.site+$layoutxml.layout.deployment.platform+$vm.function+$vm.ver+$vm.unit}
     }
    $newcred = $credxml.AppendChild($credlist.CreateElement('accounts'))
    $newcred.SetAttribute('hostname',$vmname)
    $newcred.SetAttribute('user','Administrator')
    $newcred.SetAttribute('pass',[System.Web.Security.Membership]::GeneratePassword(15,0))
    $newcred.SetAttribute('function','local')
    if ($vm.function -like 'DC')
     {
      $newcred = $credxml.AppendChild($credlist.CreateElement('accounts'))
      $newcred.SetAttribute('hostname',$vmname)
      $newcred.SetAttribute('user','Administrator')
      $newcred.SetAttribute('pass',[System.Web.Security.Membership]::GeneratePassword(15,0))
      $newcred.SetAttribute('function','AD_Safe')
     }
    $newcred.SetAttribute('stack',$vm.function)
    if ($null -ne $vm.unit) {$newcred.SetAttribute('unit',$vm.unit)}
    $credlist.Save($hvdsdir.SelectedPath+'\XML\creds.xml')

# Set unattend.xml local admin password. This is plain text and human readable. As the expectation is to change the password on script completion, and they are already human readable with creds.xml there is little harm in doing this.
    $unattendxml.unattend.settings.component[2].AutoLogon.Password.value = (($credxml.accounts|Where-Object {$_.hostname -eq $vmname})|Where-Object {$_.function -eq 'local'}).pass
    $unattendxml.unattend.settings.component[2].AutoLogon.Password.PlainText = 'True'
    $unattendxml.unattend.settings.component[2].UserAccounts.AdministratorPassword.Value = (($credxml.accounts|Where-Object {$_.hostname -eq $vmname})|Where-Object {$_.function -eq 'local'}).pass
    $unattendxml.unattend.settings.component[2].Useraccounts.AdministratorPassword.PlainText = 'True'

# Set unattend.xml install image (Standard / Standard Core / Datacenter / Datacenter Core)
    $unattendxml.unattend.settings.component[0].ImageInstall.OSImage.InstallFrom.MetaData.Value = $vm.wimindex

# Set unattend.xml network config
    $unattendxml.unattend.settings.component[3].Interfaces.Interface.UnicastIpAddresses.IpAddress.'#text' = $layoutxml.layout.network.ipv4.prefix+'.'+$vm.ip+'/'+$layoutxml.layout.network.ipv4.prefixlength
    $unattendxml.unattend.settings.component[3].Interfaces.Interface.Routes.Route.NextHopAddress = $layoutxml.layout.network.ipv4.prefix+'.'+$layoutxml.layout.network.gateway

# Adjust DNS for testing.
 #$unattendxml.unattend.settings.component[5].Interfaces.Interface.DNSServerSearchOrder.IpAddress[0].'#text' = '4.2.2.2'

# Set DNS based on DC01 / DC02. Can be changed if NS01 / NS02 are brought into play. NS01/NS02 feature not yet written or planned.
    $unattendxml.unattend.settings.component[5].Interfaces.Interface.DNSServerSearchOrder.IpAddress[0].'#text' = $layoutxml.layout.network.ipv4.prefix+'.'+(($layoutxml.layout.virtual.vm|Where-Object {$_.function -eq 'DC'})|Where-Object {$_.Unit -eq '01'}).ip
    $unattendxml.unattend.settings.component[5].Interfaces.Interface.DNSServerSearchOrder.IpAddress[1].'#text' = $layoutxml.layout.network.ipv4.prefix+'.'+(($layoutxml.layout.virtual.vm|Where-Object {$_.function -eq 'DC'})|Where-Object {$_.Unit -eq '02'}).ip
    $unattendxml.unattend.settings.component[5].Interfaces.Interface.DNSDomain = $layoutxml.layout.deployment.project+'.'+$layoutxml.layout.network.dns.upn

# Set unattend.xml product key
    switch ($key)
     {
      {($vm.wimindex -eq '1') -or ($vm.wimindex -eq '2')} {$unattendxml.unattend.settings.component[0].UserData.ProductKey.Key = ($layoutxml.layout.productkey|Where-Object {$_.ed -eq 'Standard'}).key}
      {($vm.wimindex -eq '3') -or ($vm.wimindex -eq '4')} {$unattendxml.unattend.settings.component[0].UserData.ProductKey.Key = ($layoutxml.layout.productkey|Where-Object {$_.ed -eq 'DataCenter'}).key}
     }

# Set unattend.xml org and name
    $unattendxml.unattend.settings.component[0].UserData.FullName = $layoutxml.layout.deployment.contact
    $unattendxml.unattend.settings.component[0].UserData.Organization = $layoutxml.layout.deployment.org

# Set unattend.xml computer name
    $unattendxml.unattend.settings.component[4].ComputerName = $vmname

# Unattend.xml first logon command #1 - Set-ExecutionPolicy -Bypass -Force
# Set unattend.xml first logon command #2 description and command
    $unattendxml.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[1].Description = 'Copy prebuild script to VM and jumpstart postconfig process'
    $unattendxml.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[1].CommandLine = "powershell.exe `"Copy-Item -Path ((Get-Volume |Where-Object {`$_.FileSystemLabel -eq `$ENV:COMPUTERNAME+'_win_iso'}).DriveLetter+':\HVDS') -Destination 'C:\' -Recurse -Force`""

# Set unattend.xml first logon command #3 description and command
# This runs C:\prebuild.ps1
    $unattendxml.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[2].Description = 'Begin prebuild process'
    $unattendxml.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[2].CommandLine = "powershell `". C:\HVDS\POSTCONFIG\prebuild.ps1;postconfig`""

# Write the updated autounattend.xml
    $unattendxml.Save($hvdsdir.SelectedPath+'\XML\autounattend.xml')

# Build Windows ISO baking unattend.xml and HVDS logs / postconfig / XML in the ISO root. An ISO will be built for each VM, with built ISO's being deleted at end of run.
# To change this behavior, a watcher can be added for VM build completion, but disk space is cheap, and the ~40GB of ISO's is temporary.

# Ugly hack to get around Copy-Item's exclude brokenness...
    Copy-Item -Path ($hvdsdir.SelectedPath+'\LOGS') -Destination ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\HVDS') -Verbose -Recurse -Force
    Copy-Item -Path ($hvdsdir.SelectedPath+'\POSTCONFIG') -Destination ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\HVDS') -Verbose -Recurse -Force
    Copy-Item -Path ($hvdsdir.SelectedPath+'\XML') -Destination ($hvdsdir.SelectedPath+'\TOOLS\WINFIX\HVDS') -Verbose -Recurse -Force
# End ugly hack to get around a broken Copy-Item 

    Copy-Item -Path ($hvdsdir.SelectedPath+'\XML\autounattend.xml') -Destination ($hvdsdir.SelectedPath+'\TOOLS\WINFIX') -Verbose -Force
    $buildiso = $oscdimgexe.FileName+' -bootdata:2#p0,e,b"'+$hvdsdir.SelectedPath+'\TOOLS\WINFIX\boot\etfsboot.com"#pEF,e,b"'+$hvdsdir.SelectedPath+'\TOOLS\WINFIX\efi\Microsoft\boot\efisys.bin" -o -h -m -u2 -udfver102 -l"'+$vmname+'_WIN_ISO" "'+$hvdsdir.SelectedPath+'\TOOLS\WINFIX\" "C:\HVDS\ISO\'+$vmname+'_WIN.iso"'
    Invoke-Expression $buildiso

# Define VM hardware settings based on $layout.layout.virtual.vm.size
    $vram = ($layoutxml.layout.size.vm|Where-Object {$_.size -eq $vm.size}).vram
    $vcpu = ($layoutxml.layout.size.vm|Where-Object {$_.size -eq $vm.size}).vcpu
    switch ($vhdx)
     {
      {($null -ne ($vm.vhd))} {$vhdx = $vm.vhd}
      {($null -eq ($vm.vhd))} {$vhdx = ($layoutxml.layout.size.vm|Where-Object {$_.size -eq $vm.size}).vhd}
     }

    New-VM -Generation 2 -SwitchName $nic1 -Name $vmname -path $hvdsdest.SelectedPath -NewVHDPath ($hvdsdest.SelectedPath+'\'+$vmname+'\'+$vmname+'.vhdx') -MemoryStartupBytes ($vram|Invoke-Expression) -NewVHDSizeBytes ($vhdx|Invoke-Expression) -Version $layoutxml.layout.deployment.vmver
    Add-VMDvdDrive -Path ($hvdsdir.SelectedPath+'\ISO\'+$vmname+'_WIN.iso') -VMName $vmname
    Set-VMMemory -VMName $vmname -DynamicMemoryEnabled:$false
    Set-VM -VMName $vmname -ProcessorCount $vcpu
    Set-VMFirmware -VMName $vmname -FirstBootDevice (Get-VMDvdDrive -VMName $vmname)
    Disable-VMIntegrationService -VMName $vmname -Name 'Time Synchronization'

# Test to see if host is Windows Professional, and if so, disable automatic checkpoints
    if ((Get-WindowsEdition -Online).Edition -eq 'Professional') {Set-VM -VMName $vmname -AutomaticCheckpointsEnabled:$false}
# End windows edition test

# Check for and add data disks to VM vis-à-vis Exchange and SQL.
    if ($null -ne ($vm.data_size))
     {
      $dvhd = (1..$vm.data_count)
      ForEach ($disk in $dvhd)
       {
        New-VHD -Path ($hvdsdest.SelectedPath+'\'+$vmname+'\'+$vmname+'\'+'_data'+$disk+'.vhdx') -Size ($vm.data_size|Invoke-Expression)
        Add-VMHardDiskDrive -VMName $vmname -Path  ($hvdsdest.SelectedPath+'\'+$vmname+'\'+$vmname+'\'+'_data'+$disk+'.vhdx')
       }
     }

# Hold on to your butts, we're starting VM's...
  Start-VM -Name $vmname

  }
# Nuke WINFIX...
  if (Test-Path ($hvdsdir.SelectedPath+'\TOOLS\WINFIX')) {Remove-Item -Path ($hvdsdir.SelectedPath+'\TOOLS\WINFIX') -Recurse -Force}
 }

# End HVDS. Below functions are for testing and cleanup, and are not part of main script.
# Please note post config functions are handled by post config scripts and may still be running even if hvds.ps1 completes.

Function HVDS_Cleanup
 {
  [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')|Out-Null
  $hvdsdir = New-Object System.Windows.Forms.FolderBrowserDialog
  $hvdsdir.Description = 'Select HVDS location...'
  $hvdsdir.RootFolder = 'MyComputer'
  $hvdsdir.ShowDialog()|Out-Null
  $hvdsdest = New-Object System.Windows.Forms.FolderBrowserDialog
  $hvdsdest.Description = 'Select VM destination...'
  $hvdsdest.RootFolder = 'MyComputer'
  $hvdsdest.ShowDialog()|Out-Null
  [XML]$layoutxml = Get-Content ($hvdsdir.SelectedPath+'\XML\layout.xml')
  [XML]$unattendxml = Get-Content ($hvdsdir.SelectedPath+'\XML\autounattend.xml')
  ForEach ($vm in $layoutxml.layout.virtual.vm)
   {
    Switch ($switch)
     {
      {($null -eq $vm.ver) -and ($null -eq $vm.unit)} {$vmname = $layoutxml.layout.deployment.site+$layoutxml.layout.deployment.platform+$vm.function}
      {($null -ne $vm.ver) -and ($null -eq $vm.unit)} {$vmname = $layoutxml.layout.deployment.site+$layoutxml.layout.deployment.platform+$vm.function+$vm.ver}
      {($null -eq $vm.ver) -and ($null -ne $vm.unit)} {$vmname = $layoutxml.layout.deployment.site+$layoutxml.layout.deployment.platform+$vm.function+$vm.unit}
      {($null -ne $vm.ver) -and ($null -ne $vm.unit)} {$vmname = $layoutxml.layout.deployment.site+$layoutxml.layout.deployment.platform+$vm.function+$vm.ver+$vm.unit}
     }
    Switch ($cleanup)
     {
      {!($null -eq (Get-VM -VMName $vmname -ErrorAction SilentlyContinue))} {Stop-VM -VMName $vmname -Force -Turnoff;Remove-VM -VMName $vmname -Force}
      {(Test-Path ($hvdsdir.SelectedPath+'\XML\CREDS.XML'))} {Remove-Item ($hvdsdir.SelectedPath+'\XML\CREDS.XML') -Recurse -Force}
      {(Test-Path ($hvdsdir.SelectedPath+'\TOOLS\WINFIX'))} {Remove-Item ($hvdsdir.SelectedPath+'\TOOLS\WINFIX') -Recurse -Force}
      {(Test-Path ($hvdsdest.SelectedPath+'\'+$vmname))} {Remove-Item ($hvdsdest.SelectedPath+'\'+$vmname) -Recurse -Force}
      {($vm.wimindex -eq '1') -or ($vm.wimindex -eq '2')} {$unattendxml.unattend.settings.component[0].Userdata.ProductKey.key = 'Removed by HVDS_Cleanup'}
      {($vm.wimindex -eq '3') -or ($vm.wimindex -eq '4')} {$unattendxml.unattend.settings.component[0].Userdata.ProductKey.key = 'Removed by HVDS_Cleanup'}
     }
    $unattendxml.unattend.settings.component[2].AutoLogon.Password.value = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[2].AutoLogon.Password.PlainText = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[2].UserAccounts.AdministratorPassword.Value = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[2].UserAccounts.AdministratorPassword.PlainText = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[0].ImageInstall.OSImage.InstallFrom.MetaData.Value = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[3].Interfaces.Interface.UnicastIpAddresses.IpAddress.'#text' = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[3].Interfaces.Interface.Routes.Route.NextHopAddress = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[5].interfaces.Interface.DNSServerSearchOrder.IpAddress[0].'#text' = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[5].interfaces.Interface.DNSServerSearchOrder.IpAddress[1].'#text' = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[5].interfaces.Interface.DNSDomain = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[0].UserData.FullName = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[0].UserData.Organization = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[4].ComputerName = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[1].Description = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[1].CommandLine = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[2].Description = 'Removed by HVDS_Cleanup'
    $unattendxml.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[2].CommandLine = 'Removed by HVDS_Cleanup'
    $unattendxml.Save($hvdsdir.SelectedPath+'\XML\autounattend.xml')
  }
  Get-ChildItem -Path ($hvdsdir.SelectedPath+'\ISO')|Where-Object {$_.Name -notlike '*server*2016*.iso'}|Remove-Item -Recurse -Force
 }