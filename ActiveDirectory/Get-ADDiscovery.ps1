<#
Information
This Script is build to capture Active Directory Domain and Domain Controller details.
This script reads the information and output result in HTML format
Execution of the Script.
Script can be executed for any domain joined computer with ActiveDirectory Powershell Modules installed.
to run the script in powershell prompt.
.\Get-ADDiscovery.ps1
Output will be saved under path  C:\Discovery
Below Files will be used
01_Index.html
02_DomainControllerInfo.csv
03_AllOus.csv
04_Allusers.csv
05_AlljoinedDevices.csv
06_groups
07_GPO

Version Update to support foreign languages tested for Russian and Arabic languages should support other as well
#>



#CSS codes
$header = @"
<style>

    h1 {

        font-family: Arial, Helvetica, sans-serif;
        color: #e68a00;
        font-size: 28px;

    }

    
    h2 {

        font-family: Arial, Helvetica, sans-serif;
        background: #395870;
        background: linear-gradient(#49708f, #293f50);
        color: #fff;
        font-size: 20px;

    }

    h3 {

          font-family: Arial, Helvetica, sans-serif;
        color: #000099;
        font-size: 16px;

    }
    
   table {
		font-size: 12px;
		border: 0px; 
		font-family: Arial, Helvetica, sans-serif;
	} 
	
    td {
		padding: 4px;
		margin: 0px;
		border: 0;
	}
	
    th {
        background: #395870;
        background: linear-gradient(#49708f, #293f50);
        color: #fff;
        font-size: 11px;
        text-transform: uppercase;
        padding: 10px 15px;
        vertical-align: middle;
	}

    tbody tr:nth-child(even) {
        background: #f0f0f2;
    }
    
    #Tile {
     
     font-family: Arial, Helvetica, sans-serif;
        color: #ff3300;
        font-size: 12px;

    }


    #CreationDate {

        font-family: Arial, Helvetica, sans-serif;
        color: #ff3300;
        font-size: 12px;

    }



    .StopStatus {

        color: #ff0000;
    }
    
  
    .RunningStatus {

        color: #008000;
    }




</style>
"@

Import-Module ActiveDirectory

#Checking and creating Path if exist will rename to previous date

$DateStamp = get-date -uformat "%Y-%m-%d@%H-%M-%S"  
$localPath = "C:\Discovery"         



$path = "c:\Discovery $((Get-Date).ToString('yyyy-MM-dd hh-mm-ss-tt'))"
$folderPath = New-Item -ItemType Directory -Path $path


<# Get the date


$extOnly = $fileObj.extension

if ($extOnly.length -eq 0) {
   $nameOnly = $fileObj.Name
   rename-item "$fileObj" "$nameOnly-$DateStamp"
   }
else {
   $nameOnly = $fileObj.Name.Replace( $fileObj.Extension,'')
   rename-item "$fileName" "$nameOnly-$DateStamp$extOnly"
   }

$DateStamp = get-date -uformat "%Y-%m-%d@%H-%M-%S"
# Recreate the directory ($null = ... suppresses the output).
$null = New-Item -ItemType Directory -Force -Path $localPath
#>

<#
# New Folder will be created and contained all the extracted data. 
$folderPath = New-Item -Path 'C:\Discovery' -ItemType Directory
#>
# Export all OUs. 
Get-ADOrganizationalUnit -Properties CanonicalName -Filter * | Select-Object -Property Name,ObjectClass,DistinguishedName | 
     Export-Csv -path $folderPath\03_AllOus.csv -Encoding UTF8


# Export all Users. 
Get-ADUser   -Filter * -Property * | 
    Select-Object -Property GivenName,Surname,DisplayName,Description,Office,telephoneNumber,mail,streetAddress,wWWHomePage,l,st,c,SamAccountName,cn,UserPrincipalName,CannotChangePassword,PasswordNeverExpires,AllowReversiblePasswordEncryption,enabled,SmartcardLogonRequired,AccountNotDelegated,UseDESKeyOnly,msDS-SupportedEncryptionTypes,DoesNotRequirePreAuth,AccountExpirationDate,ProfilePath,HomeDirectory,HomeDrive,scriptpath,EmailAddress,PasswordLastSet,LastLogonDate,SID,DistinguishedName,title,department,company,manager | 
    Export-Csv -path $folderPath\04_Allusers.csv -Encoding UTF8

# Export all Computers.
Get-ADComputer  -Filter * -Property * | 
    Select-Object -Property Name,OperatingSystem,OperatingSystemVersion,OperatingSystemServicePack,DNSHostName,ipv4Address,LastLogonDate,DistinguishedName | 
    Export-Csv -path $folderPath\05_AlljoinedDevices.csv -Encoding UTF8

# Export all Groups & Group Members.
$GroupsfolderPath = New-Item -Path $path\06_groups -ItemType Directory
$AllGroups = Get-ADGroup -Filter * | Select-Object -Property Name,GroupCategory,ObjectClass,DistinguishedName 
foreach ($members in $AllGroups.name)# Export all users inside each group:
{ 
    get-adgroupmember "$members"  | 
      Export-Csv -path $GroupsfolderPath\$members"_group".csv -Encoding UTF8
}

#Export All GPO settings
$GPOpath = New-Item -Path $path\07_Policy -ItemType Directory
Get-GPO -all | % { Get-GPOReport -GUID $_.id -ReportType HTML -Path $GPOpath\"$($_.displayName)".html }


# Total Count of : 
$TotalnumberOfOUs = (Get-ADOrganizationalUnit -Properties CanonicalName -Filter *).count
$TotalnumberOfOUs = ConvertTo-Html -Fragment -PreContent "<th>Total Count of OU </th> : <td>$($TotalnumberOfOUs) </td> "
$TotalnumberOfUsers = (Get-ADUser  -Filter *).count
$TotalnumberOfUsers = ConvertTo-Html -Fragment -PreContent "<th>Total Count of User </th> : <td>$($TotalnumberOfUsers) </td> "
$TotalnumberOfJoinedDomain = (Get-ADComputer  -Filter *).count 
$TotalnumberOfJoinedDomain = ConvertTo-Html -Fragment -PreContent "<th>Total Count of Computers </th> : <td>$($TotalnumberOfJoinedDomain) </td> "
$TotalnumberOfGroups = (Get-ADGroup -Filter *).count
$TotalnumberOfGroups = ConvertTo-Html -Fragment -PreContent "<th>Total Count of Groups </th> : <td>$($TotalnumberOfGroups) </td> "
#$overallcount = ConvertTo-Html -As list $TotalnumberOfOUs, $TotalnumberOfUsers, $TotalnumberOfJoinedDomain, $TotalnumberOfGroups -Fragment -PreContent "<h2>Over All Count of Active Directory Objects</h2>"

$domain = Get-ADDomain
#The command below will get Domain Name
$DomainName = "<h1>Report Run Against Domain: $domain </h1>"
#Get the Forest Information
$ForestInfo = Get-ADForest | ConvertTo-Html -As List -Property DomainNamingMaster, ForestMode, RootDomain, SchemaMaster -Fragment -PreContent "<h2>Forest Information</h2>"
#Get The Domain Information
$DomainInfo = Get-ADDomain | ConvertTo-Html -As List -Property DomainMode, Forest, InfrastructureMaster, NetBIOSName, PDCEmulator,RIDMaster, ParentDomain -Fragment -PreContent "<h2>Domain Information</h2>"
#Get the Site Information
$SiteInfo = Get-ADReplicationSite -Filter * | ConvertTo-Html -As Table -Property Name -Fragment -PreContent "<h2>SiteInformation</h2>"
#Get Domain Information
Get-ADDomainController -Filter * | Select Name, ipv4Address, hostname, Forest, IsGlobalCatalog, Site, IsReadOnly, DefaultPartition, Domain, Enabled, @{N='OperationMasterRoles';E={$_.OperationMasterRoles}} | Export-Csv $folderPath\02_DomainControllerInfo.csv -notypeinformation -Encoding UTF8
#Add Attachment
$display = "<h2>Attached Reports </h2>"
#Creating Links
$dominfo = '<a href=".\02_DomainControllerInfo.csv">Domain Controller Information</a>'
$allOUs = '<a href=".\03_AllOus.csv">List of OUs</a>'
$alluser = '<a href=".\04_Allusers.csv">User Account Details </a>'
$allcomp = '<a href=".\05_AlljoinedDevices.csv">Computer Account Details </a>'
$allgrp =  '<a href=".\06_groups\">Active Directory Group Details </a>'
$allgpo = '<a href=".\07_Policy\">Group Policy Details </a>'
#Creating HTMLfile
$report = ConvertTo-Html -Body "$DomainName $TotalnumberOfOUs $TotalnumberOfUsers $TotalnumberOfJoinedDomain $TotalnumberOfGroups $ForestInfo $DomainInfo $SiteInfo $display $dominfo <br>$allOUs <br> $alluser <br> $allcomp <br> $allgrp <br> $allgpo"  -Head $header -Title "Domain Discovery Report" -PostContent "<p id='CreationDate'>Creation Date: $(Get-Date)</p>"
$Report | Out-File $folderPath\01_Index.html