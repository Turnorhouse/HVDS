Function WSUSUpdate {
    $hvds = 'C:\HVDS'
    $hvdslogs = ([STRING]::Concat($hvds,'\logs'))
    $Criteria = "IsInstalled=0 and Type='Software'"
    $Searcher = New-Object -ComObject Microsoft.Update.Searcher
    if ((Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run).PSObject.Properties.Name -contains 'WSUSUpdate')
     {
      Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run -Name 'WSUSUpdate'
     }
    if (!(Test-Path ([STRING]::Concat($hvds,'\XML'))))
     {
      Write-Host ([STRING]::Concat($hvds,'\XML does not exist, can not continue.'))
      Break
     }
     if (!(Test-Path ([STRING]::Concat($hvds,'\XML\creds.xml'))))
     {
      Write-Host ([STRING]::Concat($hvds,'\XML\creds.xml does not exist, can not continue.'))
      Break
     }
    if ((Test-Path -Path $hvdslogs) -ne 'True')
     {
      New-Item -ItemType Directory -Path $hvdslogs
     }
    if (!(Test-Path -Path ([STRING]::Concat($hvdslogs,'\update.log'))))
     {
      New-Item -ItemType File -Path ([STRING]::Concat($hvdslogs,'\update.log'))
     }
    [XML]$creds = Get-Content ([STRING]::Concat($hvds,'\XML\creds.xml'))
    # Set registry keys for auto-logon
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 1
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultUserName' -Value 'Administrator'
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultPassword' -Value (($creds.creds.accounts|Where-Object {$_.hostname -like $ENV:COMPUTERNAME})|Where-Object {$_.function -like 'local'}).pass
    # Begin update loops
    $SearchResult = $Searcher.Search($Criteria).Updates
    $SearchResult|Select-Object Title,Description,SupportURL|Format-List|Out-File ([STRING]::Concat($hvdslogs,'\update.log')) -Append
    if ($SearchResult.Count -eq 0) 
     {
      Write-Output 'There are no applicable updates.'|Out-File ([STRING]::Concat($hvdslogs,'\update.log')) -Append
      New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'Postconfig' -Value "powershell `". C:\HVDS\POSTCONFIG\prebuild.ps1;postconfig`""
      Write-Host 'Begin 60 second debug sleep'
      Start-Sleep -Seconds 60
      Restart-Computer
     } 
      else 
       {
        $Session = New-Object -ComObject Microsoft.Update.Session
        $Downloader = $Session.CreateUpdateDownloader()
        $Downloader.Updates = $SearchResult
        $Downloader.Download()
        $Installer = New-Object -ComObject Microsoft.Update.Installer
        $Installer.Updates = $SearchResult
        $Installer.Install()|Out-File ([STRING]::Concat($hvdslogs,'\update.log')) -Append
        if (!(Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce).PSObject.Properties.Name -contains 'WSUSUpdate')
        {
          New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'WSUSUpdate' -Value "powershell `". C:\HVDS\POSTCONFIG\prebuild.ps1;WSUSUpdate`""
        }
        Write-Host 'Begin 60 second debug sleep'
        Start-Sleep -Seconds 60
        Restart-Computer
       }
   }

Function postconfig
 {
  $hvds = 'C:\HVDS'
  [XML]$layout = Get-Content ([STRING]::Concat($hvds,'\XML\layout.xml'))
  [XML]$creds = Get-Content ([STRING]::Concat($hvds,'\XML\creds.xml'))
  $node = ($creds.creds.accounts|Where-Object {$_.hostname -like $ENV:COMPUTERNAME})
  if (!($null -eq $creds.creds.accounts|Where-Object {$_.hostname -like $ENV:COMPUTERNAME}).count)
   {
    if (($node.stack -eq 'dc') -and ($node.unit -eq '01'))
   {
    $function = 'dc01'
   }
    elseif (($node.stack -eq 'dc') -and ($node.stack -ne '01'))
   {
    Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '01'}).ip)))
    While ($null -eq (Test-Connection ([STRING]::Concat('hvdsbuild.',$layout.layout.deployment.project,'.',$layout.layout.network.dns.upn)) -ErrorAction SilentlyContinue))
     {
      Write-Host -ForegroundColor Yellow ([STRING]::Concat('Waiting for ',$layout.layout.deployment.project,'.',$layout.layout.network.dns.upn,' to become live. Will try again in 120 seconds.'))
      Start-Sleep -Seconds 120
     }
    $function = 'dcX'
   }
    elseif ($node.stack -eq 'orca')
     {
      Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '01'}).ip))),([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '02'}).ip)))
      While ($null -eq (Test-Connection ([STRING]::Concat('hvdsbuild.',$layout.layout.deployment.project,'.',$layout.layout.network.dns.upn)) -ErrorAction SilentlyContinue))
       {
        Write-Host -ForegroundColor Yellow ([STRING]::Concat('Waiting for ',$layout.layout.deployment.project,'.',$layout.layout.network.dns.upn,' to become live. Will try again in 120 seconds.'))
        Start-Sleep -Seconds 120
       }
      $function = $node.stack
     }
    else
   {
    $function = $node.stack
    Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses ([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '01'}).ip))),([STRING]::Concat($layout.layout.network.ipv4.prefix,'.',(($layout.layout.virtual.vm|Where-Object {$_.function -like '*dc*'}|Where-Object {$_.unit -eq '02'}).ip)))
    While ($null -eq (Test-Connection ([STRING]::Concat('hvdsbuild.',$layout.layout.deployment.project,'.',$layout.layout.network.dns.upn))-ErrorAction SilentlyContinue))
     {
      Write-Host -ForegroundColor Yellow ([STRING]::Concat('Waiting for ',$layout.layout.deployment.project,'.',$layout.layout.network.dns.upn,' to become live. Will try again in 120 seconds.'))
      Start-Sleep -Seconds 120
     }
     $user = ([STRING]::Concat($layout.layout.deployment.project,'\',($creds.creds.accounts|Where-Object {$_.function -like 'AD_Admin'}).user))
     $pass = ConvertTo-SecureString -AsPlainText -Force ($creds.creds.accounts|Where-Object {$_.function -eq 'AD_Admin'}).pass
     $adlogon = New-Object System.Management.Automation.PSCredential ($user,$pass)
     Add-Computer -DomainName ([STRING]::Concat($layout.layout.deployment.project,'.',$layout.layout.network.dns.upn)) -Credential $adlogon
     Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultUserName' -Value ([STRING]::Concat($layout.layout.deployment.project,'\',($creds.creds.accounts|Where-Object {$_.function -like 'AD_Admin'}).user))
     Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultPassword' -Value (($creds.creds.accounts|Where-Object {$_.hostname -like([STRING]::Concat($layout.layout.deployment.project,'.',$layout.layout.network.dns.upn))})|Where-Object {$_.function -like 'AD_Admin'}).pass  
    }
  }
 
Switch ($function)
 {
  dc01
   {
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'FirstDC' -Value ([STRING]::Concat('powershell.exe . ',$hvds,'\postconfig\firstdc.ps1;FirstDC'))
   }
  dcX
   {
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'NextDC' -Value ([STRING]::Concat('powershell.exe . ',$hvds,'\postconfig\nextdc.ps1;NextDC'))
   }
  orca
   {
    Write-Host 'Build out the Offline Root Certificate Authority'
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'ORCA' -Value ([STRING]::Concat('powershell.exe . ',$hvds,'\postconfig\ORCA.ps1;ORCA'))

   }
  esca
   {
    Write-Host 'Build out the Enterprise Subordinate Certificate Authority'
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'ESCA' -Value ([STRING]::Concat('powershell.exe . ',$hvds,'\postconfig\ESCA.ps1;ESCA'))
   }
  adfs
   {
    Write-Host 'Build out Active Directory Federation Services'
   }
  adds
   {
    Write-Host 'Build out azure Active Directory Directory Sync'
   }
  exch
   {
    Write-Host 'Build out EXCHange server'
   }
  sfb
   {
    Write-Host 'Build out Skype For Business server'
   }
 }
 Write-Host 'Begin 60 second debug sleep'
 Start-Sleep -Seconds 60
Restart-Computer
}