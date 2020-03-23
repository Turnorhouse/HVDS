Function HVDS_Build
{
# Identify where things 'should' be. This should be replaced by a UI dialog to populate these values.
$path = 'C:\HVDS'
$dest = 'C:\Hyper-V'

# Begin the messy process of testing for paths and files.
$hvds = Get-Item $path
$HVDS_Toolpath = ([STRING]::Concat($hvds,'\tools'))
$winfix = ([STRING]::Concat($HVDS_Toolpath,'\winfix'))
switch ($hvds)
 {
  {!(Test-Path ($hvds.FullName +'\XML'))} {Write-Host ($hvds.FullName +'\XML does not exist, can not continue.') ;break}
  {!(Test-Path ($hvds.FullName +'\XML\layout.xml'))} {Write-Host ($hvds.FullName +'\XML\layout.xml does not exist, can not continue.') ;break}
  {!(Test-Path ($hvds.FullName +'\XML\autounattend.xml'))} {Write-Host ($hvds.FullName +'\XML\autounattend.xml does not exist, can not continue.') ;break}
  {!(Test-Path ($hvds.FullName +'\POSTCONFIG'))} {Write-Host ($hvds.FullName +'\POSTCONFIG does not exist, can not continue.') ;break}
  {!(Test-Path ($hvds.FullName +'\TOOLS'))} {Write-Host ($hvds.FullName +'\TOOLS does not exist, can not continue.') ;break}
  {!(Test-Path ($hvds.FullName +'\TOOLS\oscdimg.exe'))} {Write-Host ($hvds.FullName +'\TOOLS\oscdimg.exe does not exist, can not continue') ;break}
  {!(Test-Path ($dest))} {New-Item -Path $dest -ItemType Directory}
  {!(Test-Path ($hvds.FullName +'\TOOLS\WINFIX'))} {New-Item -ItemType Directory ($hvds.FullName +'\TOOLS\WINFIX')}
  {!(Test-Path ($hvds.Fullname +'\LOGS'))} {New-Item -ItemType Directory ($hvds.FullName +'\LOGS')}
  default {Write-Host 'Test completed, continuing.'}
 }
# End the messy process of testing for paths and files

# Start pulling info from config files.
# Note that layout.xml is not, and never should be, changed by this process. This is by design.
[XML]$layout = Get-Content ([STRING]::Concat($hvds.FullName,'\XML\layout.xml'))
$unattendxml = Get-Item ([STRING]::Concat($hvds.FullName,'\XML\autounattend.xml'))
[XML]$unattend = (Get-Content $unattendxml.FullName)


# Build the start of our password XML file. Note that this is plain text, human readable, and exists ONLY for the process of allowing the user to change passwords.
[System.Xml.XmlDocument]$credlist = New-Object System.Xml.XmlDocument
[System.Xml.XmlElement]$creds=$credlist.CreateElement('creds')
$credlist.AppendChild($creds)
[System.Xml.XmlElement]$account=$creds.AppendChild($credlist.CreateElement('accounts'))
$account.SetAttribute('hostname',$vmname)
$account.SetAttribute('user','Administrator')
$account.SetAttribute('pass','changeme')
$account.SetAttribute('function','changeme')
# Base creds.xml has been created. Uncomment $credslist.save to write to file at this stage.

# Set AD admin password
$creds.accounts.hostname = ([STRING]::Concat($layout.layout.deployment.project,'.',$layout.layout.network.dns.upn))
$creds.accounts.function = 'AD_Admin'
$creds.accounts.pass = (-join ((48..57) + (65..90) + (97..122)| Get-Random -Count 12 | ForEach-Object {[CHAR]$_})+'1Aa')
# End building of creds.xml

# Define VM networking
$nic1 = 'vLAN'

# Fix Windows ISO (obnoxious "Press any key to boot from DVD...")
$winiso = Mount-DiskImage (Get-ChildItem -Path ([STRING]::Concat($hvds,'\ISO')) | Where-Object {$_.Name -like '*server*2016*.iso'}).FullName -PassThru | Get-Volume
Copy-Item -Path ([STRING]::Concat($winiso.DriveLetter,':\*')) -Destination $WINFIX -Recurse -Verbose
Rename-Item ([STRING]::Concat($WINFIX,'\efi\microsoft\boot\cdboot.efi')) ([STRING]::Concat($WINFIX,'\efi\microsoft\boot\cdboot_prompt.efi'))
Rename-Item $WINFIX\efi\microsoft\boot\cdboot_noprompt.efi $WINFIX\efi\microsoft\boot\cdboot.efi
Rename-Item $WINFIX\efi\microsoft\boot\efisys.bin $WINFIX\efi\microsoft\boot\efisys_prompt.bin
Rename-Item $WINFIX\efi\microsoft\boot\efisys_noprompt.bin $WINFIX\efi\microsoft\boot\efisys.bin
Dismount-DiskImage (Get-ChildItem -Path 'C:\HVDS\ISO' | Where-Object {$_.Name -like '*server*2016*.iso'}).FullName

# Build VM's based on config file
ForEach ($vm in $layout.layout.virtual.vm)
 {
# Determine service version and count (ex1501, dc02, sfb6x, etc) and set $vmname
# Note that some VM's may have neither service version or count in hostname.
  if (($null -eq ($vm.ver)) -and ($null -eq ($vm.unit)))
   {
    $vmname = ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,$vm.function))
   }
    elseif (($null -ne ($vm.ver) -and ($null -eq ($vm.unit))))
   {
    $vmname = ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,$vm.function,$vm.ver))
   }
    elseif (($null -eq ($vm.ver) -and ($null -ne ($vm.unit))))
   {
    $vmname = ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,$vm.function,$vm.unit))
   }
  elseif (($null -ne ($vm.ver) -and ($null -ne ($vm.unit))))
   {
    $vmname = ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,$vm.function,$vm.ver,$vm.unit))
   }
# End check for service version and count

# Generate creds for VM and service
 $newcred = $creds.AppendChild($credlist.CreateElement('accounts'))
 $newcred.SetAttribute('hostname',$vmname)
 $newcred.SetAttribute('user','Administrator')
 $newcred.SetAttribute('pass',(-join ((48..57) + (65..90) + (97..122)| Get-Random -Count 12 | ForEach-Object {[CHAR]$_})))
 $newcred.SetAttribute('function','local')
 if ($vm.function -like 'DC')
  {
    $newcred = $creds.AppendChild($credlist.CreateElement('accounts'))
    $newcred.SetAttribute('hostname',$vmname)
    $newcred.SetAttribute('user','Administrator')
    $newcred.SetAttribute('pass',(-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[CHAR]$_})+'1Aa'))
    $newcred.SetAttribute('function','AD_Safe')
  }
 $newcred.SetAttribute('stack',$vm.function)
 if (!($null -eq $vm.unit))
  {
   $newcred.SetAttribute('unit',$vm.unit)
  }
 
 $credlist.save('C:\HVDS\XML\creds.xml')


# Set unattend.xml local admin password. This is plain text and human readable. As the expectation is to change the password on script completion, and they are already human readable with creds.xml there is little harm in doing this.
 $unattend.unattend.settings.component[2].AutoLogon.Password.value = (($creds.accounts|Where-Object {$_.hostname -like $vmname})|Where-Object {$_.function -like 'local'}).pass
 $unattend.unattend.settings.component[2].AutoLogon.Password.PlainText = 'true'
 $unattend.unattend.settings.component[2].UserAccounts.AdministratorPassword.Value = (($creds.accounts|Where-Object {$_.hostname -like $vmname})|Where-Object {$_.function -like 'local'}).pass
 $unattend.unattend.settings.component[2].UserAccounts.AdministratorPassword.PlainText = 'true'

# Set unattend.xml install image (Standard / Standard Core / Datacenter / Datacenter Core)
 $unattend.unattend.settings.component[0].ImageInstall.OSImage.InstallFrom.MetaData.Value = $vm.wimindex
 
# Set unattend.xml network config
$unattend.unattend.settings.component[3].Interfaces.Interface.UnicastIpAddresses.IpAddress.'#text' = ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',$vm.ip,'/',$layout.layout.network.ipv4.prefixlength))
$unattend.unattend.settings.component[3].Interfaces.Interface.Routes.Route.NextHopAddress = ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',$layout.layout.network.gateway))
# Adjusting DNS for testing
$unattend.unattend.settings.component[5].interfaces.Interface.DNSServerSearchOrder.IpAddress[0].'#text' = '4.2.2.2'

#$unattend.unattend.settings.component[5].interfaces.Interface.DNSServerSearchOrder.IpAddress[0].'#text' = ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',($layout.layout.virtual.vm|Where-Object {$_.function -like 'DC'}).ip[0]))
#$unattend.unattend.settings.component[5].interfaces.Interface.DNSServerSearchOrder.IpAddress[1].'#text' = ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',($layout.layout.virtual.vm|Where-Object {$_.function -like 'DC'}).ip[1]))
$unattend.unattend.settings.component[5].interfaces.Interface.DNSDomain = ([STRING]::Concat($layout.layout.deployment.project,'.',$layout.layout.network.dns.upn))
 
# Set unattend.xml product key
 if (($vm.wimindex -eq '1') -or ($vm.wimindex -eq '2'))
  {
   $unattend.unattend.settings.component[0].Userdata.ProductKey.key = ($layout.layout.productkey|Where-Object {$_.ed -eq 'Standard'}).key
  }
 if (($vm.wimindex -eq '3') -or ($vm.wimindex -eq '4'))
  {
   $unattend.unattend.settings.component[0].Userdata.ProductKey.key = ($layout.layout.productkey|Where-Object {$_.ed -eq 'DataCenter'}).key
  }

# Set unattend.xml org and name
 $unattend.unattend.settings.component[0].UserData.FullName = $layout.layout.deployment.contact
 $unattend.unattend.settings.component[0].UserData.Organization = $layout.layout.deployment.org

# Set unattend.xml computer name
 $unattend.unattend.settings.component[4].ComputerName = $vmname

# Unattend.xml first logon command #1 - Set-ExecutionPolicy -Bypass -Force
# Set unattend.xml first logon command #2 description and command
 $unattend.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[1].Description = 'Copy prebuild script to VM and jumpstart postconfig process'
 $unattend.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[1].CommandLine = "powershell `"Copy-Item ([STRING]::Concat((Get-Volume|Where-Object {`$_.FileSystemLabel -like ([STRING]::Concat(`$ENV:COMPUTERNAME,'*'))}).driveletter,':\HVDS')) -Destination 'C:\' -Recurse -Force`""

# Set unattend.xml first logon command #3 description and command
# This runs C:\prebuild.ps1
 $unattend.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[2].Description = 'Begin prebuild process'
 $unattend.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[2].CommandLine = "powershell `". C:\HVDS\POSTCONFIG\prebuild.ps1;postconfig`""

# Write the updated autounattend.xml
 $unattend.Save($unattendxml.FullName)

# Build Windows ISO baking unattend.xml and HVDS logs / postconfig / XML in the ISO root. An ISO will be built for each VM, with built ISO's being deleted at end of run.
# To change this behavior, a watcher can be added for VM build completion, but disk space is cheap, and the ~40GB of ISO's is temporary.

# Ugly hack to get around Copy-Item's exclude brokenness...
 Copy-Item -Path ([STRING]::Concat($hvds.FullName,'\LOGS')) -Destination ([STRING]::Concat($WINFIX,'\HVDS')) -Verbose -Recurse -Force
 Copy-Item -Path ([STRING]::Concat($hvds.FullName,'\POSTCONFIG')) -Destination ([STRING]::Concat($WINFIX,'\HVDS')) -Verbose -Recurse -Force
 Copy-Item -Path ([STRING]::Concat($hvds.FullName,'\XML')) -Destination ([STRING]::Concat($WINFIX,'\HVDS')) -Verbose -Recurse -Force
# End ugly hack to get around a broken Copy-Item 

 Copy-Item ($unattendxml).FullName -Destination ([STRING]::Concat($WINFIX,'\autounattend.xml')) -Verbose -Force
 $OSCDIMGCMD = ($hvds.FullName +'\TOOLS\oscdimg.exe')
 $OSCDBUILD = [STRING]::Concat($OSCDIMGCMD,' -bootdata:2#p0,e,b"',$WINFIX,'\boot\etfsboot.com"#pEF,e,b"',$WINFIX,'\efi\Microsoft\boot\efisys.bin" -o -h -m -u2 -udfver102 -l"',$vmname,'_WIN_ISO" "',$WINFIX,'\" "C:\HVDS\ISO\',$vmname,'_WIN.iso"')
 Invoke-Expression $OSCDBUILD
 
# Define VM hardware settings based on $layout.layout.virtual.vm.size
$vram = (($layout.layout.size.vm|Where-Object {$_.size -like $vm.size}).vram)
$vcpu = (($layout.layout.size.vm|Where-Object {$_.size -like $vm.size}).vcpu)

# Build and configure the VM
 if ($null -ne ($vm.vhd))
  {
   $vhdx = $vm.vhd
  }
 else
  {
   $vhdx = (($layout.layout.size.vm|Where-Object {$_.size -like $vm.size}).vhd)
  }
 $vmiso = ([STRING]::Concat('C:\HVDS\ISO\',$vmname,'_WIN.iso'))
 New-VM -Generation 2 -SwitchName $nic1 -Name $vmname -Path $dest -NewVHDPath ([STRING]::Concat($dest,'\',$vmname,'\',$vmname,'.vhdx')) -MemoryStartupBytes ($vram|Invoke-Expression) -NewVHDSizeBytes ($vhdx|Invoke-Expression) -Version ($layout.layout.deployment.vmver)
 Add-VMDvdDrive -Path $vmiso -VMName $vmname
 $dvd = Get-VMDVDDrive -VMName $vmname
 Set-VM -VMName $vmname -ProcessorCount $vcpu
 Set-VMMemory -VMName $vmname -DynamicMemoryEnabled:$false
 Set-VMFirmware -VMName $vmname -FirstBootDevice $dvd
 Disable-VMIntegrationService -VMName $vmname -Name 'Time Synchronization'

# Test to see if host is Windows Professional, and if so, disable automatic checkpoints
 if ((Get-WindowsEdition -Online).Edition -eq 'Professional')
  {
   Set-VM -VMName $vmname -AutomaticCheckpointsEnabled:$false
  }
# End windows edition test

 if ($null -ne ($vm.data_size))
 {
  $dvhd = (1..$vm.data_count)
  ForEach ($disk in $dvhd)
  {
   New-VHD -Path ([STRING]::Concat($dest,'\',$vmname,'\',$vmname,'_data',$disk,'.vhdx')) -Size ($vm.data_size|Invoke-Expression)
   Add-VMHardDiskDrive -VMName $vmname -Path ([STRING]::Concat($dest,'\',$vmname,'\',$vmname,'_data',$disk,'.vhdx'))
  }
 }
# if ($vm.function -eq 'dc')
#  {
#   Start-VM -Name $vmname
#  }
Start-VM -Name $vmname
}
# End VM build and configure

# Cleanup $WINFIX folder
if ((Test-Path  $WINFIX) -eq 'True')
{
 Remove-Item -Recurse -Force $WINFIX
}

# End HVDS. Below functions are for testing and cleanup, and are not part of main script.
# Please note post config functions are handled by post config scripts and may still be running even if hvds.ps1 completes.
}
 Function HVDS_Cleanup
  {
   $path = 'C:\HVDS'
   $hvds = Get-Item $path
   $unattendxml = Get-Item ([STRING]::Concat($hvds.FullName,'\XML\autounattend.xml'))
   [XML]$unattend = (Get-Content $unattendxml.FullName)
   $dest = 'C:\Hyper-V'
   $credxml = ([STRING]::Concat($hvds.FullName,'\XML\creds.xml'))
   $HVDS_Toolpath = ([STRING]::Concat($hvds,'\tools'))
   $winfix = ([STRING]::Concat($HVDS_Toolpath,'\winfix'))
   [XML]$layout = Get-Content ([STRING]::Concat($hvds.FullName,'\XML\layout.xml'))
   ForEach ($vm in $layout.layout.virtual.vm)
    {
     if (($null -eq ($vm.ver)) -and ($null -eq ($vm.unit)))
      {
       $vmname = ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,$vm.function))
      }
       elseif (($null -ne ($vm.ver) -and ($null -eq ($vm.unit))))
      {
       $vmname = ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,$vm.function,$vm.ver))
      }
       elseif (($null -eq ($vm.ver) -and ($null -ne ($vm.unit))))
      {
       $vmname = ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,$vm.function,$vm.unit))
      }
       elseif (($null -ne ($vm.ver) -and ($null -ne ($vm.unit))))
      {
       $vmname = ([STRING]::Concat($layout.layout.deployment.site,$layout.layout.deployment.platform,$vm.function,$vm.ver,$vm.unit))
      }
      if (!($null -eq (Get-VM -VMName $vmname -ErrorAction SilentlyContinue)))
      {
       Stop-VM -VMName $vmname -Force -TurnOff
       Remove-VM -VMName $vmname -Force
      }
    }
   if ((Test-Path $dest) -eq 'True')
    {
     Remove-Item $dest -Recurse -Force
    }
   if ((Test-Path $credxml) -eq 'True')
    {
     Remove-Item $credxml -Force
    }
   if ((Test-Path  $WINFIX) -eq 'True')
    {
     Remove-Item -Recurse -Force $WINFIX
    }
   Get-ChildItem -Path ([STRING]::Concat($hvds,'\ISO'))|Where-Object {$_.Name -notlike '*server*2016*.iso'}|Remove-Item -Recurse -Force
   $unattend.unattend.settings.component[2].AutoLogon.Password.value = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[2].AutoLogon.Password.PlainText = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[2].UserAccounts.AdministratorPassword.Value = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[2].UserAccounts.AdministratorPassword.PlainText = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[0].ImageInstall.OSImage.InstallFrom.MetaData.Value = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[3].Interfaces.Interface.UnicastIpAddresses.IpAddress.'#text' = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[3].Interfaces.Interface.Routes.Route.NextHopAddress = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[5].interfaces.Interface.DNSServerSearchOrder.IpAddress[0].'#text' = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[5].interfaces.Interface.DNSServerSearchOrder.IpAddress[1].'#text' = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[5].interfaces.Interface.DNSDomain = 'Removed by HVDS_Cleanup'
   if (($vm.wimindex -eq '1') -or ($vm.wimindex -eq '2'))
    {
     $unattend.unattend.settings.component[0].Userdata.ProductKey.key = 'Removed by HVDS_Cleanup'
    }
   if (($vm.wimindex -eq '3') -or ($vm.wimindex -eq '4'))
    {
     $unattend.unattend.settings.component[0].Userdata.ProductKey.key = 'Removed by HVDS_Cleanup'
    }
   $unattend.unattend.settings.component[0].UserData.FullName = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[0].UserData.Organization = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[4].ComputerName = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[1].Description = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[1].CommandLine = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[2].Description = 'Removed by HVDS_Cleanup'
   $unattend.unattend.settings.component[2].FirstLogonCommands.SynchronousCommand[2].CommandLine = 'Removed by HVDS_Cleanup'
   $unattend.Save($unattendxml.FullName)
}

# scratch space
