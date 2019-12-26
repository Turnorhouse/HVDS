function Debug
 {
  [XML]$layoutxml = Get-Content C:\hvds\xml\layout.xml
  [XML]$unattendxml = Get-Content C:\HVDS\xml\autounattend.xml
  $unattendfile = Get-Item 'C:\HVDS\XML\autounattend.xml'
  $layoutfile = Get-Item 'C:\HVDS\XML\layout.xml'
 }

$hvds_source = (Get-Volume -FileSystemLabel 'HVDS*').DriveLetter
$hvds_path = ([STRING]::Concat($hvds_source,':\HVDS'))
[XML]$layoutxml = Get-Content ([STRING]::Concat($hvds_path,'\xml\layout.xml'))
[XML]$unattendxml = Get-Content ([STRING]::Concat($hvds_path,'\xml\autounattend.xml'))
$layoutfile = Get-Item ([STRING]::Concat($hvds_path,'\xml\layout.xml'))
$unattendfile = Get-Item ([STRING]::Concat($hvds_path,'\xml\autounattend.xml'))
$Interface = Get-NetAdapter -Name '*Ethernet*'
$ADDNSDomain = [STRING]::Concat($layoutxml.build.network.dns.siteid,'.',$layoutxml.build.network.dns.domainname)
$ADNetBIOS = $layoutxml.build.network.dns.siteid
$IPv4NET = $layoutxml.build.network.IPv4.Prefix
$IPv4Address = [STRING]::Concat($IPv4NET,'.',$IP)
$IPv4Gateway = [STRING]::Concat($IPv4NET,'.',$layoutxml.build.network.gateway)
$IPv4NS1 = [STRING]::Concat($IPv4NET,'.',$layoutxml.build.network.dns.ns1)
$IPv4NS2 = [STRING]::Concat($IPv4NET,'.',$layoutxml.build.network.dns.ns2)


# Begin system configuration
New-Item 'C:\Hyper-V' -ItemType Directory
Copy-Item $hvds_path -Destination 'C:\' -Recurse -Verbose

# Begin reboot loops
Rename-Computer -NewName $layoutxml.build.server.vhost.vhostname
Add-WindowsFeature -Name Hyper-V,RSAT-ADDS,GPMC -IncludeManagementTools
New-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'Config_Network' -Value 'powershell.exe . C:\HVDS\HVDS.PS1;Config_Network'
Restart-Computer

Function Config_Network
 {
  [XML]$layoutxml = Get-Content 'C:\HVDS\xml\layout.xml'
  [XML]$unattendxml = Get-Content 'C:\HVDS\xml\autounattend.xml'
  $layoutfile = Get-Item 'C:\HVDS\xml\layout.xml'
  $unattendfile = Get-Item 'C:\HVDS\xml\autounattend.xml'
  $Interface = Get-NetAdapter -Name '*Ethernet*'
  $ADDNSDomain = [STRING]::Concat($layoutxml.build.network.dns.siteid,'.',$layoutxml.build.network.dns.domainname)
  $ADNetBIOS = $layoutxml.build.network.dns.siteid
  $IPv4NET = $layoutxml.build.network.IPv4.Prefix
  $IPv4Address = [STRING]::Concat($IPv4NET,'.',$IP)
  $IPv4Gateway = [STRING]::Concat($IPv4NET,'.',$layoutxml.build.network.gateway)
  $IPv4NS1 = [STRING]::Concat($IPv4NET,'.',$layoutxml.build.network.dns.ns1)
  $IPv4NS2 = [STRING]::Concat($IPv4NET,'.',$layoutxml.build.network.dns.ns2)
  Rename-NetAdapter -InterfaceAlias ($Interface).Name -NewName LAN
  New-NetIPAddress -InterfaceAlias LAN -AddressFamily IPv4 -IPAddress ([STRING]::Concat($IPv4NET,'.',$layoutxml.build.server.vhost.ip)) -PrefixLength $layoutxml.build.network.IPv4.PrefixLength -DefaultGateway $IPv4Gateway
  Set-DnsClientServerAddress -InterfaceAlias LAN -ServerAddresses $IPv4NS1,$IPv4NS2
  Set-DnsClient -InterfaceAlias LAN -ConnectionSpecificSuffix $ADDNSDomain
  Set-NetIPInterface -Dhcp Disabled
  New-VMSwitch -InterfaceAlias LAN -SwitchName vLAN
  New-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'Lab_Build' -Value 'powershell.exe . C:\HVDS\HVDS.PS1;Lab_Build'
 }

 Function Lab_Build
  {
   [XML]$layoutxml = Get-Content 'C:\HVDS\xml\layout.xml'
   [XML]$unattendxml = Get-Content 'C:\HVDS\xml\autounattend.xml'
   $layoutfile = Get-Item 'C:\HVDS\xml\layout.xml'
   $unattendfile = Get-Item 'C:\HVDS\xml\autounattend.xml'
   $Interface = Get-NetAdapter -Name '*Ethernet*'
   $ADDNSDomain = [STRING]::Concat($layoutxml.build.network.dns.siteid,'.',$layoutxml.build.network.dns.domainname)
   $ADNetBIOS = $layoutxml.build.network.dns.siteid
   $IPv4NET = $layoutxml.build.network.IPv4.Prefix
   $IPv4Prefix = $layoutxml.build.network.IPv4.PrefixLength
   $IPv4Address = [STRING]::Concat($IPv4NET,'.',$IP)
   $IPv4Gateway = [STRING]::Concat($IPv4NET,'.',$layoutxml.build.network.gateway)
   $IPv4NS1 = [STRING]::Concat($IPv4NET,'.',$layoutxml.build.network.dns.ns1)
   $IPv4NS2 = [STRING]::Concat($IPv4NET,'.',$layoutxml.build.network.dns.ns2)
   # Preload the iso creation script.
   . C:\HVDS\tools\new-iso.ps1
   # Create temporary firewall exception for file and print sharing
   Enable-NetFirewallRule -DisplayGroup 'File and printer sharing'
   foreach ($vm in $layoutxml.build.server.vm)
    {
     if (($vm.servername -notlike '*ex14*') -or ($vm.servername -notlike '*cwin*'))
     {
      # Setup keys and install images
 
      # Apparently there is an argument to be made for case statements here. I'm looking into it.
      if ((($vm.wimindex -eq '1') -or ($vm.wimindex -eq '2')) -and (($vm.servername -notlike '*EX14*') -or ('CWIN*')))
       {
         $VMINSKEY = $layoutxml.build.feature.KMS.KEY[0]
        }
       if ((($vm.wimindex -eq '3') -or ($vm.wimindex -eq '4')) -and (($vm.servername -notlike '*EX14*') -or ('CWIN*')))
        {
         $VMINSKEY = $layoutxml.build.feature.KMS.KEY[1]
        }
       if ((($vm.wimindex -eq '1') -or ($vm.wimindex -eq '2')) -and ($vm.servername -like '*EX14*'))
        {
         $VMINSKEY = $layoutxml.build.feature.KMS.KEY[2]
        }
       if ($vm.servername -like 'CWIN8*')
        {
         $VMINSKEY = $layoutxml.build.feature.KMS.KEY[4]
        }
       if ($vm.servername -like 'CWIN7*')
        { 
         $VMINSKEY = $layoutxml.build.feature.KMS.KEY[5]
        }
      
      # Set items for autounattned.xml
      $unattendxml.unattend.settings.component[4].Interfaces.Interface.DNSDomain = $ADDNSDomain
      $unattendxml.unattend.settings.component[3].Interfaces.Interface.UnicastIpAddresses.IpAddress.'#text' = [STRING]::Concat($IPv4NET,'.',$vm.ip,'/',$IPv4Prefix)
      $unattendxml.unattend.settings.component[3].Interfaces.Interface.Routes.Route.NextHopAddress = $IPv4Gateway
      $unattendxml.unattend.settings.component[4].Interfaces.Interface.DNSServerSearchOrder.IpAddress[0].'#text' = $IPv4NS1
      $unattendxml.unattend.settings.component[4].Interfaces.Interface.DNSServerSearchOrder.IpAddress[1].'#text' = $IPv4NS2
      $unattendxml.unattend.settings.component[2].ComputerName = $vm.servername
      $unattendxml.unattend.settings.component[1].ImageInstall.OSImage.InstallFrom.MetaData.Value = $vm.wimindex
      $unattendxml.unattend.settings.component[2].ProductKey = $VMINSKEY
      
      # Set autounattend.xml disk layout based on hvgen.
      # Gen 1 = MBR disk layout
      # Gen 2 = uEFI disk layout
      if ($vm.hvgen -eq '1')
       {
        $PartCount = $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition.Count
        if ($PartCount -eq '3')
         {
          $RemovedPart = $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[1]
          $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.RemoveChild($RemovedPart)
          $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[0].Size = '256'
          $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[0].Type = 'Primary'
          $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[1].Order = '2'
          $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.ModifyPartitions.ModifyPartition[0].Format = 'NTFS'
          $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.ModifyPartitions.ModifyPartition[1].PartitionID ='2'
         $unattendxml.unattend.settings[0].component[1].ImageInstall.OSImage.InstallTo.PartitionID = '2'
        }
      }
     elseif ($vm.hvgen -eq '2')
      {
       $PartCount = $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition.Count
       if ($PartCount -eq '2')
        {
         $ClonePart = ($unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[0]).Clone()
         $AddPart = $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[0]
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.InsertAfter($ClonePart, $AddPart)
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[0].Order = '1'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[0].Size = '128'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[0].Type = 'EFI'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[1].Order = '2'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[1].Size = '128'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[1].Type = 'MSR'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[2].Order = '3'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.CreatePartitions.CreatePartition[2].Extend = 'True'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.ModifyPartitions.ModifyPartition[0].Format = 'FAT32'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.ModifyPartitions.ModifyPartition[0].Order = '1'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.ModifyPartitions.ModifyPartition[0].PartitionID = '1'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.ModifyPartitions.ModifyPartition[1].Format = 'NTFS'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.ModifyPartitions.ModifyPartition[1].Order = '2'
         $unattendxml.unattend.settings[0].component[1].DiskConfiguration.Disk.ModifyPartitions.ModifyPartition[1].PartitionID ='3'
         $unattendxml.unattend.settings[0].component[1].ImageInstall.OSImage.InstallTo.PartitionID = '3'
        }
      }

    # Set postconfig tasks based on server task, and select correct Windows ISO. Note that this is pulled based on the VM name.
    # Also a case statement cantidate.
    if ($vm.servername -like '*dc01')
     {
      $vmtask = 'C:\HVDS\postconfig\firstdc.ps1'
      $unattendxml.unattend.settings.component.firstlogoncommands.synchronouscommand[1].CommandLine = "powershell `"[STRING]::Concat(' . ',(Get-Volume -FileSystemLabel 'HVDS*').DriveLetter,':\firstdc.ps1;HVDS_Staging')| Invoke-Expression`""
      $winiso = ([STRING]::Concat('C:\HVDS\ISO\',(Get-Item C:\HVDS\ISO\* |Where {$_.Name -like '*server_2012_r2*'}).Name))
     }
    if (($vm.servername -like '*dc0*') -and ($vm.servername -notlike '*dc01'))
     {
      $vmtask = 'C:\HVDS\postconfig\nextdc.ps1'
      $unattendxml.unattend.settings.component.firstlogoncommands.synchronouscommand[1].CommandLine = "powershell `"[STRING]::Concat(' . ',(Get-Volume -FileSystemLabel 'HVDS*').DriveLetter,':\nextdc.ps1;HVDS_Staging')| Invoke-Expression`""
      $winiso = ([STRING]::Concat('C:\HVDS\ISO\',(Get-Item C:\HVDS\ISO\* |Where {$_.Name -like '*server_2012_r2*'}).Name))
     }



    # Save changes to unattent.xml
    $unattendxml.Save($unattendfile.FullName)

    # Call a pre-encryped password stored in a text file that will be passed to VM's as needed.
    $passfile = Get-Item C:\HVDS\tools\password.txt

    # Test for autounattend.iso and delete if exists, as new-iso doesn't check if a file exists, but will throw an error if it does.
    $unattendiso = 'C:\HVDS\ISO\autounattend.iso'
    $isotest = Test-Path $unattendiso
     if ($isotest -eq 'True')
      {
       Remove-Item 'C:\HVDS\ISO\autounattend.iso'
       }

    # Build the autounattend.iso
    New-IsoFile -Source $unattendfile,$vmtask,$layoutfile,$passfile -Path $unattendiso -Title 'HVDS_Autorun'
    
    # Set VM storage paths
    $hvpath = 'C:\Hyper-V'
    $vhdpath = [STRING]::Concat($hvpath,'\',$vm.servername,'\',$vm.servername,'.vhdx')

    # Build the VM's
    New-VM -Path $hvpath -Generation $vm.hvgen -Name $vm.servername -MemoryStartupBytes ($vm.vram| Invoke-Expression) -NewVHDSizeBytes ($vm.vhd| Invoke-Expression) -NewVHDPath $vhdpath -SwitchName $vm.net
    if ($vm.hvgen -eq '2')
     {
      Set-VMFirmware -VMName $vm.servername -EnableSecureBoot Off
     }
    if ($vm.dvram -eq 'Yes')
     {
      Set-VM -VMName $vm.servername -DynamicMemory:$true -MemoryMinimumBytes 512MB -MemoryMaximumBytes ($vm.vram| Invoke-Expression)
     }
#    if ($vm.servername -like '*ex1*')
#     { 
#      Convert-VHD -Path $vhdpath -VHDType Fixed
#     }
    Set-VM -Name $vm.servername -ProcessorCount $vm.vcpu

    if ($vm.hvgen -eq '1')
     {
      Add-VMDvdDrive -VMName $vm.servername -ControllerNumber 1 -ControllerLocation 1
      Set-VMDvdDrive -VMName $vm.servername -ControllerNumber 1 -ControllerLocation 0 -Path $winiso
      Set-VMDvdDrive -VMName $vm.servername -ControllerNumber 1 -ControllerLocation 1 -Path $unattendiso
     }
    if ($vm.hvgen -eq '2')
     {
      Add-VMDvdDrive -VMName $vm.servername -ControllerNumber 0 -ControllerLocation 10
      Add-VMDvdDrive -VMName $vm.servername -ControllerNumber 0 -ControllerLocation 11
      Set-VMDvdDrive -VMName $vm.servername -ControllerNumber 0 -ControllerLocation 10 -Path $winiso
      Set-VMDvdDrive -VMName $vm.servername -ControllerNumber 0 -ControllerLocation 11 -Path $unattendiso
      $bootdvd = Get-VMDvdDrive -VMName $vm.servername
      Set-VMFirmware -VMName $vm.servername -FirstBootDevice $bootdvd[0] 
     }
    
   
    
    
    Start-VM -Name $vm.servername

    # Report feature still in development, but in this case all we're looking for is if the file exists
    $reportpath = [STRING]::Concat('C:\HVDS\reports\',$vm.servername,'.txt')
    $report = Test-Path $reportpath
    While ($report -eq $false)
     {
      $report = Test-Path $reportpath
      Start-Sleep -Seconds 5
     }

    Stop-VM -Name $vm.servername

    if ($vm.hvgen -eq '1')
     {
      Remove-VMDvdDrive -VMName $vm.servername -ControllerNumber 1 -ControllerLocation 0
      Remove-VMDvdDrive -VMName $vm.servername -ControllerNumber 1 -ControllerLocation 1
     }
    if ($vm.hvgen -eq '2')
     {
      Remove-VMDvdDrive -VMName $vm.servername -ControllerNumber 0 -ControllerLocation 10
      Remove-VMDvdDrive -VMName $vm.servername -ControllerNumber 0 -ControllerLocation 11
     }
   

    Start-VM -Name $vm.servername
 }
}
}

 Function Debug_Cleanup
  {
   Get-VM |Stop-VM -Force
   Get-VM |Remove-VM -Force
   del C:\hvds\reports\*.* -Force
   del C:\Hyper-V\* -Force -Recurse
  }