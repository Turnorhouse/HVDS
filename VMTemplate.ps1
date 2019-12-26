$HVPATH = 'V:\Hyper-V'
[XML]$layoutxml = Get-Content 'C:\HVDS\xml\layout.xml'
foreach ($vm in $layoutxml.build.server.vm)
 {
  New-VM -Path $hvpath -Generation $vm.hvgen -Name $vm.servername -MemoryStartupBytes ($vm.vram| Invoke-Expression) -NewVHDSizeBytes ($vm.vhd| Invoke-Expression) -NewVHDPath $vhdpath -SwitchName $vm.net
   if ($vm.hvgen -eq '2')
    {
     Set-VMFirmware -VMName $vm.servername -EnableSecureBoot Off
    }
   if ($vm.dvram -eq 'Yes')
    {
     Set-VM -VMName $vm.servername -DynamicMemory:$true -MemoryMinimumBytes 512MB -MemoryMaximumBytes ($vm.vram| Invoke-Expression)
    }
   Set-VM -Name $vm.servername -ProcessorCount $vm.vcpu
  }