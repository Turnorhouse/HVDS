function New-IsoFile 
{ 
  <# 
   .Synopsis 
    Creates a new .iso file 
   .Description 
    The New-IsoFile cmdlet creates a new .iso file containing content from chosen folders 
   .Example 
    New-IsoFile "c:\tools","c:Downloads\utils" 
    Description 
    ----------- 
    This command creates a .iso file in $env:temp folder (default location) that contains c:\tools and c:\downloads\utils folders. The folders themselves are added in the root of the .iso image. 
   .Example 
    dir c:\WinPE | New-IsoFile -Path c:\temp\WinPE.iso -BootFile etfsboot.com -Media DVDPLUSR -Title "WinPE" 
    Description 
    ----------- 
    This command creates a bootable .iso file containing the content from c:\WinPE folder, but the folder itself isn't included. Boot file etfsboot.com can be found in Windows AIK. Refer to IMAPI_MEDIA_PHYSICAL_TYPE enumeration for possible media types: 
 
      http://msdn.microsoft.com/en-us/library/windows/desktop/aa366217(v=vs.85).aspx 
   .Notes 
    NAME:  New-IsoFile 
    AUTHOR: Chris Wu 
    LASTEDIT: 03/06/2012 14:06:16 
 #> 
 
  Param ( 
    [parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]$Source, 
    [parameter(Position=1)][string]$Path = "$($env:temp)\" + (Get-Date).ToString("yyyyMMdd-HHmmss.ffff") + ".iso", 
    [string] $BootFile = $null, 
    [string] $Media = "Disk", 
    [string] $Title = (Get-Date).ToString("yyyyMMdd-HHmmss.ffff"), 
    [switch] $Force 
  )#End Param 
 
  Begin { 
    ($cp = new-object System.CodeDom.Compiler.CompilerParameters).CompilerOptions = "/unsafe" 
    if (!("ISOFile" -as [type])) { 
 Add-Type -CompilerParameters $cp -TypeDefinition @"
public class ISOFile 
{ 
    public unsafe static void Create(string Path, object Stream, int BlockSize, int TotalBlocks) 
    { 
        int bytes = 0; 
        byte[] buf = new byte[BlockSize]; 
        System.IntPtr ptr = (System.IntPtr)(&bytes); 
        System.IO.FileStream o = System.IO.File.OpenWrite(Path); 
        System.Runtime.InteropServices.ComTypes.IStream i = Stream as System.Runtime.InteropServices.ComTypes.IStream; 
 
        if (o == null) { return; } 
        while (TotalBlocks-- > 0) { 
            i.Read(buf, BlockSize, ptr); o.Write(buf, 0, bytes); 
        } 
        o.Flush(); o.Close(); 
    } 
} 
"@ 
    }#End If 
 
    if ($BootFile -and (Test-Path $BootFile)) { 
      ($Stream = New-Object -ComObject ADODB.Stream).Open() 
      $Stream.Type = 1  # adFileTypeBinary 
      $Stream.LoadFromFile((Get-Item $BootFile).Fullname) 
      ($Boot = New-Object -ComObject IMAPI2FS.BootOptions).AssignBootImage($Stream) 
    }#End If 
 
    $MediaType = @{CDR=2; CDRW=3; DVDRAM=5; DVDPLUSR=6; DVDPLUSRW=7; ` 
      DVDPLUSR_DUALLAYER=8; DVDDASHR=9; DVDDASHRW=10; DVDDASHR_DUALLAYER=11; ` 
      DISK=12; DVDPLUSRW_DUALLAYER=13; BDR=18; BDRE=19 } 
     
    if ($MediaType[$Media] -eq $null) { write-debug "Unsupported Media Type: $Media"; write-debug ("Choose one from: " + $MediaType.Keys); break } 
    ($Image = new-object -com IMAPI2FS.MsftFileSystemImage -Property @{VolumeName=$Title}).ChooseImageDefaultsForMediaType($MediaType[$Media]) 
 
    if ((Test-Path $Path) -and (!$Force)) { "File Exists $Path"; break } 
    if (!($Target = New-Item -Path $Path -ItemType File -Force)) { "Cannot create file $Path"; break } 
  } 
 
  Process { 
    switch ($Source) { 
      { $_ -is [string] } { $Image.Root.AddTree((Get-Item $_).FullName, $true); continue } 
      { $_ -is [IO.FileInfo] } { $Image.Root.AddTree($_.FullName, $true); continue } 
      { $_ -is [IO.DirectoryInfo] } { $Image.Root.AddTree($_.FullName, $true); continue } 
    }#End switch 
  }#End Process 
   
  End { 
    if ($Boot) { $Image.BootImageOptions=$Boot } 
    $Result = $Image.CreateResultImage() 
    [ISOFile]::Create($Target.FullName,$Result.ImageStream,$Result.BlockSize,$Result.TotalBlocks) 
    $Target 
  }#End End 
}#End function New-IsoFile