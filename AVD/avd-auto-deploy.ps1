workflow avd-auto-deploy
{
    
   <#	Param(
[parameter (mandatory = $true)][string]$WVDResourceGroupName = "we-rg-app-avd",
[parameter (mandatory = $true)][string]$WVDhostpoolname = "we-wvd-app-v1"
)#>
write-output "##------------------------------------------------------------------------------------------------------------"
write-output "## | Section 1 - Check for latest Folder in the Share"
    write-output "##------------------------------------------------------------------------------------------------------------"	
    # Save the password so the drive will persist on reboot
        cmd.exe /C "cmdkey /add:`"stoageaccount.file.core.windows.net`" /user:`"localhost\storageaccount`" /pass:`"key`""
        # Mount the drive
        InlineScript{ New-PSDrive -Name Z -PSProvider FileSystem -Root "\\storageaccount.file.core.windows.net\images" -Persist
        }
        $latestfolder = gci "Z:\app\latest" | sort -Property LastWriteTime -Descending | select -First 1
        if ( $latestfolder.LastWriteTime.Date -ge [datetime]::Today ){     
        'file has been changed today'
        $flname = $latestfolder.Name
        $hostpoolname = ""
        $hostpoolname = "we-app-avd-"+$flname
        $resourceGroup = "we-rg-apprg-prd-001"

    write-output "##------------------------------------------------------------------------------------------------------------"
    write-output "## | Section 2 - Logging onto Azure"
    write-output "##------------------------------------------------------------------------------------------------------------"
    #retrive login credentials
    [String]$tenantID = Get-AutomationVariable -Name "tenantID"
    [String]$dcadminid = Get-AutomationVariable -Name "dcadminUPN"
    [String]$dcadminPW = get-AutomationVariable -Name "dcadminPW"
    [String]$subID = Get-AutomationVariable -Name "subid"
    [String]$WVDResourceGroupName = Get-AutomationVariable -Name "WVDResourceGroupName"
    $spWVDCreds = get-AutomationPScredential -Name "WVDAppID"
    [string]$spWVDAppID = $spWVDCreds.UserName
    [string]$spWVDAppSecret = $spWVDCreds.GetNetworkCredential().Password
    $wvdSPPassword = ConvertTo-SecureString $spWVDAppSecret -AsPlainText -Force
    $wvdSPCreds = New-Object System.Management.Automation.PScredential ($spWVDAppID, $wvdSPPassword)
    #Logon to Azure 
    $spSession = Connect-AzAccount -Credential $spWVDCreds -TenantId $tenantID -SubscriptionId $subid -ServicePrincipal

write-output "##------------------------------------------------------------------------------------------------------------"
write-output "## | Section 3 - Copy Json Files"
write-output "##------------------------------------------------------------------------------------------------------------"

    $sourcetemplateFile = "Z:\ARMTemplates\template.json" 
    $destinationtemplatefile = "c:\temp\template.json"
    $sourcetemplateparaFile = "Z:\ARMTemplates\parametersFile.json" 
    $destinationtemplateparafile = "c:\temp\parametersFile.json"
    Copy-Item  -Path $sourcetemplateFile -Destination $destinationtemplatefile -Recurse -force
    Copy-Item -Path $sourcetemplateparaFile -Destination $destinationtemplateparafile -Recurse -force
    $jsonTemplateFile = "c:\temp\template.json"
    $jsonTemplateParams = "c:\temp\parametersFile.json"
write-output "##------------------------------------------------------------------------------------------------------------"
write-output "## | Section 4 - Change Parameters in ARM template"
write-output "##------------------------------------------------------------------------------------------------------------"
#Create WVD Host pool, using ARM Template and TemplateParameterObject for (input) parameters 
$tokenexptime="$((get-date).ToUniversalTime().AddDays(20).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ'))"
InlineScript {
    $latestfolder = gci "Z:\app\latest" | sort -Property LastWriteTime -Descending | select -First 1
     $flname = $latestfolder.Name
     $hostpoolname = ""
     $hostpoolname = "we-app-avd-"+$flname
     $flname = $flname.Split(".")[3]
            $vmprefix = "we-sn-"+$flname
     $tokenexptime="$((get-date).ToUniversalTime().AddDays(20).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ'))"
      $vmimage = Get-AzGalleryImageVersion -ResourceGroupName $resourceGroup -GalleryName we_cg_ap_avd -GalleryImageDefinitionName we-id-app-auto -GalleryImageVersionName 1.0.0
     $vmimage = $vmimage.id
     $workspace = "we-ws-app-"
     write-output "Image resource id" $vmimage
     Write-Output "Hostpool Name is " $hostpoolname
     write-output "VM prefix is " $vmprefix
   

                $sourcetemplateFile = "Z:\ARMTemplates\template.json" 
                $destinationtemplatefile = "c:\temp\template.json"
                $sourcetemplateparaFile = "Z:\ARMTemplates\parametersFile.json" 
                $destinationtemplateparafile = "c:\temp\parametersFile.json"
                Copy-Item  -Path $sourcetemplateFile -Destination $destinationtemplatefile -Recurse -force
                Copy-Item -Path $sourcetemplateparaFile -Destination $destinationtemplateparafile -Recurse -force
                $pathToJson = "C:\Temp\parametersFile.json"
                $jsonimport = Get-Content $pathToJson -Raw | ConvertFrom-Json
                $jsonimport.parameters.hostpoolName.value = $hostpoolname
                $jsonimport.parameters.hostpoolFriendlyName.value = $hostpoolname
                $jsonimport.parameters.tokenExpirationTime.value = $tokenexptime
                $jsonimport.parameters.vmCustomImageSourceId.value = $vmimage
                $jsonimport.parameters.vmNamePrefix.value = $vmprefix
                $jsonimport.parameters.workSpaceName.value = $workspace
                $jsonimport | ConvertTo-Json -Depth 100 | set-content $pathToJson
}

write-output "##------------------------------------------------------------------------------------------------------------"
write-output "## | Section 5 - Create Host pool from Json Files"
write-output "##------------------------------------------------------------------------------------------------------------"
#with input as paramter file
New-AzResourceGroupDeployment -ResourceGroupName $WVDResourceGroupName -TemplateFile $jsonTemplateFile -TemplateParameterFile $jsonTemplateParams -Verbose

write-output "##------------------------------------------------------------------------------------------------------------"
write-output "## | Section 6 - Get Application Group for the host pool"
write-output "##------------------------------------------------------------------------------------------------------------"
        $appgp = $hostpoolname+"-DAG"
        write-output "Application Group is " $appgp
        $appname = "SessionDesktop"
        $updateappname = "Schuecal_"+$flname
        Update-AzWvdDesktop -ResourceGroupName $WVDResourceGroupName -ApplicationGroupName $appgp -Name $appname -FriendlyName $updateappname
        write-output "Application Name Updated"
        $gpid = "dda279c4-2ab4-4a5c-b01d-30ea7808caa3"
        <#
        New-AzRoleAssignment -ObjectId $gpid -RoleDefinitionName "Desktop Virtualization User"  -ResourceGroupName $WVDResourceGroupName -ResourceName $appgp -ResourceType 'Microsoft.DesktopVirtualization/applicationGroups' -debug
        Write-Output "Permission assigned for the aplication group"
        #>
        
        write-output "Wating for 3600 Seconds"
        Start-Sleep -Second 3600
        write-output "Wait Completed"

write-output "##------------------------------------------------------------------------------------------------------------"
write-output "## | Section 7 - Manage Host VM in Host pools"
write-output "##------------------------------------------------------------------------------------------------------------"
    $hostname = Get-AzWvdSessionHost -ResourceGroupName $WVDResourceGroupName -HostPoolName $hostpoolname
    foreach ($sh in $hostname) {
            $VMName = $sh.Name.Split("/")[1]
            $VMName = $VMName.Split(".")[0]
            write-output "Restarting Virtual Machine : " $VMName
            Restart-AzVM -ResourceGroupName $WVDResourceGroupName -Name $VMName
            Write-Output "Restart Initiated for the virtual Machine : " $VMName


    }
    write-output "Wating for 300 Seconds"
    Start-Sleep -Second 300
    write-output "Wait Compleated Start Depoloyment"
    $hostname1 = Get-AzWvdSessionHost -ResourceGroupName $WVDResourceGroupName -HostPoolName $hostpoolname
foreach ($sh1 in $hostname1) {
            $VMName1 = $sh1.Name.Split("/")[1]
            $VMName1 = $VMName1.Split(".")[0]
            $Status = $sh1.Status
            write-output "Starting the deployment for the Virtual Machine " $VMName1
            Restart-AzVM -ResourceGroupName $WVDResourceGroupName -Name $VMName1
            write-output "Deployment Ended for the Virtual Machine " $VMName1
}

write-output "##------------------------------------------------------------------------------------------------------------"
write-output "## | Section End"
write-output "##------------------------------------------------------------------------------------------------------------"
# Disconnect the Azure Session
        Disconnect-AzAccount
Write-Output "Azure Session Disconnected Successfully"        
write-output "All Steps Executed "
write-output "##------------------------------------------------------------------------------------------------------------"
 }
 
 else{
     'File was not changed today.'

}

}