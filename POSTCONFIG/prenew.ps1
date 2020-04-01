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
    {!(Test-Path ($hvdsdir+'\LOGS\update.log'))} {New-Item -ItemType File -Path ($hvdsdir+'\LOGS\update.log')}
   }
  $searchresults = $searcher.Search($criteria).Updates
  $searchresults|Select-Object Title,Description,SupportURL|Format-List|Out-File ($hvdsdir+'\LOGS\update.log') -Append
  if ($searchresults.Count -eq 0)
   {
    Write-Output 'There are no applicable updates.'|Out-File ($hvdsdir+'\LOGS\update.log') -Append
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'Postconfig' -Value "posershell `". C:\HVDS\POSTCONFIG\prebuild.ps1;postconfig`""
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
    if (!(Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce).PSObject.Properties.Name -eq 'WSUSUpdate')
     {
      New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Name 'WSUSUpdate' -Value "powershell `". C:\HVDS\POSTCONFIG\prebuild.ps1;WSUSUpdate`""
     }
    Restart-Computer
   }
 }

$hvdsdir = 'C:\HVDS'
