Function WSUSUpdate
# Note that WSUSUpdate runs before anything builds. If enabled, the only thing to happen prior to update cycles is verification of internet and DNS resolution using public DNS servers.
 {
  $hvdsdir = 'C:\HVDS'
  $criteria = "IsInstalled=0 and Type='Software'"
  $searcher = New-Object -ComObject Microsoft.Update.Searcher
  if ((Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run).PSObject.Properties.Name -contains 'WSUSUpdate')
   {
    Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run -Name 'WSUSUpdate'
   }
  Switch ($switch)
   { 
    {!(Test-Path ($hvdsdir+'\XML'))} {Write-Host -ForegroundColor Red('Directory '+$hvdsdir+'\XML does not exist - Exiting.') ;break}
    {!(Test-Path ($hvdsdir+'\XML\creds.xml'))} {Write-Host -ForegroundColor Red('HVDS required config file, '+$hvdsdir+'\XML\creds.xml does not exist - Exiting.') ;break}
    {!(Test-Path ($hvdsdir+'\LOGS'))} {New-Item -ItemType Directory -Path ($hvdsdir+'\LOGS')}
    {(Test-Path $hvdsdir+'\LOGS\update.log')}{attrib.exe -s -h -r ($hvdsdir+'\LOGS\update.log')}
    {!(Test-Path ($hvdsdir+'\LOGS\update.log'))} {New-Item -ItemType File -Path ($hvdsdir+'\LOGS\update.log')}
   }
  $searchresults = $searcher.Search($criteria).Updates
  $searchresults|Select-Object Title,Description,SupportURL|Format-List|Out-File ($hvdsdir+'\LOGS\update.log') -Append
  if ($searchresults.Count -eq 0)
   {
    Write-Output 'There are no applicable updates.'|Out-File ($hvdsdir+'\LOGS\update.log') -Append
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'Postconfig' -Value "powershell `". C:\HVDS\POSTCONFIG\prebuild.ps1;Postconfig`""
    Restart-Computer   
  }
  else
   {
    $session = New-Object -ComObject Microsoft.Update.Session
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $searchresults
    $downloader.Download()
    $installer = New-Object -ComObject Microsoft.Update.Installer
    $installer.Updates = $searchresults
    $installer.Install()|Out-File ($hvdsdir+'\LOGS\update.log') -Append
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'WSUSUpdate' -Value "powershell `". C:\HVDS\POSTCONFIG\prebuild.ps1;WSUSUpdate`""
    Restart-Computer
   }
 }

Function Postconfig
 {
  $hvdsdir = 'C:\HVDS'
  [XML]$layoutxml = Get-Content ($hvdsdir+'\XML\layout.xml')
  [XML]$credxml = Get-Content ($hvdsdir+'\XML\creds.xml')
  $node = ($credxml.creds.accounts|Where-Object {$_.hostname -eq $ENV:COMPUTERNAME})
  $dc01ip = ($layoutxml.layout.virtual.vm|Where-Object ({$_.function -eq 'dc' -and $_.unit -eq '01'})).ip
  $dc02ip = ($layoutxml.layout.virtual.vm|Where-Object ({$_.function -eq 'dc' -and $_.unit -eq '02'})).ip
  Switch ($vmfunction)
   {
    {(($node.stack -eq 'dc') -and ($node.unit -eq '01'))} {$postconfig = 'FirstDC'}
    {(($node.stack -eq 'dc') -and ($node.unit -ne '01'))}
    {
     Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses ($layoutxml.layout.network.ipv4.prefix+'.'+$dc01ip),($layoutxml.layout.network.ipv4.prefix+'.'+$dc02ip)
     While (!(Test-Connection ('adready.'+$layoutxml.layout.deployment.project+'.'+$layoutxml.layout.network.dns.upn) -ErrorAction SilentlyContinue))
      {
       Write-Host -ForegroundColor Yellow ('Waiting for '+$layoutxml.layout.deployment.project+'.'+$layoutxml.layout.network.dns.upn+' to become live. Will try again in 60 seconds.')
       Start-Sleep -Seconds 60
      }
     $postconfig = 'NextDC'
    }
    {($node.stack -eq 'orca')}
     {
      Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses ($layoutxml.layout.network.ipv4.prefix+'.'+$dc01ip),($layoutxml.layout.network.ipv4.prefix+'.'+$dc02ip)
      While (!(Test-Connection ('adready.'+$layoutxml.layout.deployment.project+'.'+$layoutxml.layout.network.dns.upn) -ErrorAction SilentlyContinue))
      {
       Write-Host -ForegroundColor Yellow ('Waiting for '+$layoutxml.layout.deployment.project+'.'+$layoutxml.layout.network.dns.upn+' to become live. Will try again in 60 seconds.')
       Write-Host -ForegroundColor Yellow ($ENV:COMPUTERNAME+' will not be bound to '+$layoutxml.layout.deployment.project+'.'+$layoutxml.layout.network.dns.upn+'.')
       Start-Sleep -Seconds 60
      }
     $postconfig = 'ORCA'
    }
# Set default switch to join domain. Set specific for member servers (dc01 / dc02 / orca) Pull function from creds.xml or layout.xml, default populate from that function data.
    Default
     {    
      Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses ($layoutxml.layout.network.ipv4.prefix+'.'+$dc01ip),($layoutxml.layout.network.ipv4.prefix+'.'+$dc02ip)
      While (!(Test-Connection ('adready.'+$layoutxml.layout.deployment.project+'.'+$layoutxml.layout.network.dns.upn) -ErrorAction SilentlyContinue))
      {
       Write-Host -ForegroundColor Yellow ('Waiting for '+$layoutxml.layout.deployment.project+'.'+$layoutxml.layout.network.dns.upn+' to become live. Will try again in 60 seconds.')
       Start-Sleep -Seconds 60
      }
      $aduser = ($layoutxml.layout.deployment.project+'\'+($credxml.creds.accounts|Where-Object {$_.Function -eq 'AD_Admin'}).user)
      $adpass = ConvertTo-SecureString -AsPlainText -Force ($credxml.creds.accounts|Where-Object {$_.Function -eq 'AD_Admin'}).pass
      $adcred = New-Object System.Management.Automation.PSCredential ($aduser,$adpass)
      Add-Computer -DomainName ($layoutxml.layout.deployment.project+'.'+$layoutxml.layout.network.dns.upn) -Credential $adcred
      $postconfig = $node.stack
      Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 1

      # Change user name and test.
      Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultUserName' -Value ($layoutxml.layout.deployment.project+'\'+($credxml.creds.accounts|Where-Object {$_.function -like 'AD_Admin'}).user)
      Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultPassword' -Value ($credxml.creds.accounts|Where-Object {$_.function -like 'AD_Admin'}).pass
       }
    }
  $runonce = ('powershell.exe . '+$hvdsdir+'\postconfig\'+$postconfig+'.ps1'+';'+$postconfig)
  New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name $postconfig -Value $runonce
  Restart-Computer
}