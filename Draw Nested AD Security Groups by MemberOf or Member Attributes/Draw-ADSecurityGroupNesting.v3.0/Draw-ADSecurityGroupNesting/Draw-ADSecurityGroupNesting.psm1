if (!(Get-Module ActiveDirectory))
{
	Import-Module ActiveDirectory -ErrorAction Stop
}

function Remove-LastBackSlash
{
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[String] $Str
	)
	
	$Index = $Str.LastIndexOf("\")
	$Length = $Str.Length -1
	
	If ($Index -eq $Length)
	{
		$Str = $Str.SubString(0,$Index)
	}
	
	return $Str
}

function Ask-ForChoice
{
	param
	(
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("CT")]
		[String] $ChoiceTle,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("CM")]
		[String] $ChoiceMsg,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("YM")]
		[String] $YesMsg,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("NM")]
		[String] $NoMsg
	)
	
	$yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Y',$YesMsg
	$no = New-Object System.Management.Automation.Host.ChoiceDescription '&N',$NoMsg
	
	$ChoiceOpt = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
	
	$Choice = $host.ui.PromptForChoice($ChoiceTle,$ChoiceMsg,$ChoiceOpt,0)
	
	return $Choice
}

function Test-ADObject
{
	param
	(
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("Path")]
		[String] $LdapPath,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[String] $Filter,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
        [Alias("SC")]
		[Microsoft.ActiveDirectory.Management.ADSearchScope] $Scope = "Subtree"
	)
	
	$ADSearch = New-Object DirectoryServices.DirectorySearcher 
    $ADSearch.SearchRoot = $LdapPath 
    $ADSearch.SearchScope = $Scope.ToString()
    $ADSearch.Filter = $Filter
    $ADResult = $ADSearch.FindOne().Path

	$ADSearch.Dispose()
    
	return [Boolean]$ADResult
}

function List-ADGCOnePerDomainReachable
{
	param
	(	
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("FQDN")]
		[String[]] $ADDomainFQDNCol,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[ValidateSet("3268","3269")]
		[Alias("Port")]
		[String] $ADGCPort = "3268",
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[ValidateScript({Test-Path $_ -PathType 'Container'})]
        [Alias("Path")]
		[String] $ADForestGCListRoot = "$env:USERPROFILE\Desktop",
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[ValidateSet("ASCII","UTF8")]
		[Alias("CS")]
		[String] $Charset = "UTF8",
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("SGCL")]
		[Boolean] $SaveGCList = $true
	)
	
	if ($ADForestGCListRoot -ne "$env:USERPROFILE\Desktop")
	{
		$ADForestGCListRoot = Remove-LastBackSlash $ADForestGCListRoot
	}
	
	$ADForestGCListPath = $ADForestGCListRoot + "\ADForestGCList.csv"
	
	$ADForestGCListExists = Test-Path -Path $ADForestGCListPath -PathType Leaf
	
	if ($ADForestGCListExists)
	{
		$Choice_Tle = 'Flush Global Catalog list'
		$Choice_Msg = 'Do you want to rediscover Global Catalog list rather than reusing "' + $ADForestGCListPath + '" ?'
		$Choice_YesMsg = 'GC list flush confirmed.'
		$Choice_NoMsg = 'GC list flush canceled.'
		
		$Choice = Ask-ForChoice $Choice_Tle $Choice_Msg $Choice_YesMsg $Choice_NoMsg
		
		Write-Host ""
	}
	else
	{
		$Choice = 0
		
		Write-Host ''
	}
	
	if ($Choice -eq 0)
	{
		Remove-Item $ADForestGCListPath -ErrorAction SilentlyContinue
	
		$ADDomainPSHostFQDN = (Get-ADDomain).DNSRoot
		$ADDomainPSHostSite = ([System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite()).Name
	
		$ADForestGCPsoCol = @()

		foreach ($ADDomainFQDN in $ADDomainFQDNCol)
		{
			$Msg = 'Discovering one Global Catalog avalaible in Domain "' + $ADDomainFQDN + '":' + "`n"
			Write-Host $Msg -ForegroundColor White
		
			if ($ADDomainFQDN -eq $ADDomainPSHostFQDN)
			{
				$ADDomainGCColInt = Get-ADDomainController -Server $ADDomainFQDN -Filter { IsGlobalCatalog -eq "True" -and Site -eq $ADDomainPSHostSite }
				$ADDomainGCColExt = Get-ADDomainController -Server $ADDomainFQDN -Filter { IsGlobalCatalog -eq "True" -and Site -ne $ADDomainPSHostSite }
				$ADDomainGCCol = @($ADDomainGCColInt) + @($ADDomainGCColExt)
			}
			
			else
			{
				$ADDomainGCCol = Get-ADDomainController -Server $ADDomainFQDN -Filter { IsGlobalCatalog -eq "True" }
			}
		
			$ADDomainGCCtr = $null	

			:nextdom while (!$ADDomainGCCtr)
			{
				foreach ($ADDomainGC in $ADDomainGCCol)
				{
					$ADDomainGCFQDN = $ADDomainGC.HostName
					$ADDomainGCConxStr = $ADDomainGCFQDN + ":" + $ADGCPort
					
					$ADDomainGCConx = $null
					
					try
					{
						$ADDomainGCConx = Get-ADObject $ADDomainGC.ComputerObjectDN -Server $ADDomainGCConxStr -ErrorAction Stop | Select Name
					}
					catch [Microsoft.ActiveDirectory.Management.ADServerDownException]
					{
						$Msg = 'Global Catalog "' + $ADDomainGCFQDN + '" is not responding on port ' + $ADGCPort + '. Seeking for another Domain Controller...'
						Write-Host $Msg
					}

					if ($ADDomainGCConx)
					{
						$Msg = 'Global Catalog "' + $ADDomainGCFQDN + '" is responding on port "' + $ADGCPort + '". Now it is the target Domain Controller for LDAP search on "'+ $ADDomainFQDN + '".' + "`n"
						Write-Host $Msg
					
						$ADDomainGCPso = New-Object -TypeName PSObject
						$ADDomainGCPso | Add-Member -MemberType NoteProperty -Name HostName -Value $ADDomainGC.HostName
						$ADDomainGCPso | Add-Member -MemberType NoteProperty -Name Port -Value $ADGCPort
						$ADDomainGCPso | Add-Member -MemberType NoteProperty -Name DomainFQDN -Value $ADDomainGC.Domain
						$ADDomainGCPso | Add-Member -MemberType NoteProperty -Name DomainDN -Value $ADDomainGC.DefaultPartition

						$ADForestGCPsoCol = $ADForestGCPsoCol + $ADDomainGCPso
						
						break nextdom
					}
				}

				$ADDomainGCCtr++
			}
		}

		if($SaveGCList)
		{
			$Msg = 'Saving Global Catalog list in "' + $ADForestGCListPath + '".'
			Write-Host $Msg -ForegroundColor White
		
			$ADForestGCPsoCol | Export-Csv -Path $ADForestGCListPath -NoTypeInformation -Encoding $Charset
		}
	}
	else
	{
		$Msg = 'Importing existing Global Catalog list from "' + $ADForestGCListPath + '".'
		Write-Host $Msg -ForegroundColor White
		
		$ADForestGCPsoCol = @(Import-Csv -Path $ADForestGCListPath)
		
		if(!$SaveGCList)
		{
			$Msg = "`n" + 'Deleting Global Catalog list "' + $ADForestGCListPath + '".'
			Write-Host $Msg -ForegroundColor White
		
			Remove-Item $ADForestGCListPath -ErrorAction SilentlyContinue
		}		
	}
	
	if ($ADForestGCPsoCol.Count -ge $ADDomainFQDNCol.Count)
	{
		return $ADForestGCPsoCol
	}
}

function Get-ADGCOneForADObj
{
	param
	(
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("DN")]
		[String] $ADObjDN,
				
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("GC")]
	    [PSObject[]] $ADForestGCPsoCol
	)

	$Index = $ADObjDN.IndexOf("DC=")
	$ADDomainDN = $ADObjDN.Substring($Index)
	$ADDomainGCPso = $ADForestGCPsoCol |
	? {
		$_.DomainDN -eq  $ADDomainDN
	} |
	Select-Object -First 1
	
	if ($ADDomainGCPso)
	{
		return $ADDomainGCPso
	}
	else
	{
		return $ADForestGCPsoCol[0]
	}
}

function Get-ADObjDuplicated
{
	param
	(	
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[PSObject] $ADObjPsoDupCol,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("For")]
		[String] $ADObjStr,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("By")]
		[String] $Property
	)
	
	$Msg = @()
		
	foreach ($ADObjPsoDup in $ADObjPsoDupCol)
	{	
		if ($ADObjPsoDup.Duplicated -eq $true)
		{	
			if ($ADObjPsoDup.CanonicalName -eq $ADObjStr)
			{
				$DupStr = '- ' + ' loop on ' + '"' + $ADObjPsoDup.CanonicalName + '"' + "`n"
			}	
			else
			{
				$DupStr = '- ' + '"' + $ADObjPsoDup.CanonicalName + '"' + ' appears more than one time' + "`n"
			}
			
			$Msg = $Msg + @($DupStr)
		}
	}
	
	if ($Msg.Count)
	{
		if ($Msg.Count -gt 1)
		{
			$Msg = $Msg[0..($Msg.Count-2)] + @($Msg[$Msg.Count-1].SubString(0,$Msg[$Msg.Count-1].LastIndexof("`n")))
		}
		else
		{
			$Msg = $Msg[$Msg.Count-1].SubString(0,$Msg[$Msg.Count-1].LastIndexof("`n"))
		}
		
		switch ($Property)
		{
			"MemberOf"
			{
				$DupTle = 'MemberOf nesting chain for "' + $ADObjStr + '" seems not optimal on some points:' + "`n"
			}
			
			"Member"
			{
				$DupTle = 'Member nesting chain for "' + $ADObjStr + '" seems not optimal on some points:' + "`n"
			}
		}
		
		$Msg = @($DupTle) + $Msg
		Write-Host $Msg -BackgroundColor DarkRed
		
		Write-Host
	}
}

function Measure-ADTokenSize
{
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[PSObject[]] $ADSGroupPsoCol,
		
		[Parameter(ValueFromPipeline = $true, Mandatory = $false)]
		[Alias("DN")]
		[String] $ADObjDN
	)
	
	foreach ($ADSGroupPso in $ADSGroupPsoCol)
	{
		switch ($ADSGroupPso.GroupScope)
		{
			"DomainLocal"
			{
				$D++
			}
			
			"Global"
			{
				$S++
			}
			
			"Universal"
			{
				if ( $ADSGroupPso.DistinguishedName.Substring($ADSGroupPso.DistinguishedName.IndexOf("DC=")) -eq $ADObjDN.Substring($ADObjDN.IndexOf("DC=")) )
				{
					$S++
				}
				else
				{
					$D++
				}
			}
		}
	}
	
	$ADTokenSize = 1200 + 40*$D + 8*$S
	
	return $ADTokenSize
}

function DigG-ADSecurityGroupMemberOf
{
	param
	(  
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[ValidateScript({$_.GroupCategory -eq "Security"})]
        [Microsoft.ActiveDirectory.Management.ADGroup] $ADSGroup,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("GC")]
        [PSObject[]] $ADForestGCPsoCol,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("RL")]		
		[Int] $RecursionLevel = 0		
    )
 
	$ADSGroupMbrOf =  @()
	$ADSGroupMbrOf_NotFound = @()
	
	if ($RecursionLevel -gt $MaxRecursionLevel)
	{
		$global:MaxRecursionLevel = $RecursionLevel
	}
 
	foreach ($ADGroupPso in $ADGroupPsoCol)
	{	
		if ($ADGroupPso.DistinguishedName -eq $ADSGroup.DistinguishedName)
		{	
			if ($ADGroupPso.Duplicated -eq $false)
			{
				$ADGroupPso.Duplicated = $true
			}
			
			return
		}
    }
	
	$Msg = 'Analyzing Security Group "' + $ADSGroup.CanonicalName + '"'
	Write-Host $Msg
	
	if ($ADSGroup.GroupScope -eq "DomainLocal")
	{	
		$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroup.DistinguishedName -GC $ADForestGCPsoCol
		$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
		
		$Msg = 'from "' + $GC + '"'
		Write-Host $Msg
		
		foreach ($ADGroupDN in (Get-ADGroup $ADSGroup.DistinguishedName -Properties MemberOf -Server $GC).MemberOf)
		{
			$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
			$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
			try
			{	
				$ADGroup = Get-ADGroup $ADGroupDN -Server $GC
			}
			catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
			{
				$Msg = "`nQuery for " + $ADGroupDN + "`non " + $GC + "`nreturned 'AD Identity Not Found'."
				$Msg += "`nYou should check ACL restriction."
				$Msg += "`nThat group can't be explored further.`n"
				Write-Warning $Msg
				
				$ADSGroupMbrOf_NotFound = $ADSGroupMbrOf_NotFound + @($ADGroupDN)
				$ADSGroupMbrOf = $ADSGroupMbrOf + @($ADGroupDN)
				
				continue
			}
			
			if ($ADGroup.GroupCategory -eq "Security")
			{
				$ADSGroupMbrOf = $ADSGroupMbrOf + @($ADGroupDN)
			}
		}
	}
	else
	{   
	    foreach ($ADForestGCPso in $ADForestGCPsoCol)
		{
			$GC = $ADForestGCPso.HostName + ":" + $ADForestGCPso.Port
			
			$Msg = 'from "' + $GC + '"'
			Write-Host $Msg
	
			foreach ($ADGroupDN in (Get-ADGroup $ADSGroup.DistinguishedName -Properties MemberOf -Server $GC).MemberOf)
			{
				$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
				$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
				try
				{	
					$ADGroup = Get-ADGroup $ADGroupDN -Server $GC
				}
				catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
				{	
					$Msg = "`nQuery for " + $ADGroupDN + "`non " + $GC + "`nreturned 'AD Identity Not Found'."
					$Msg += "`nYou should check ACL restriction."
					$Msg += "`nThat group can't be explored further.`n"
					Write-Warning $Msg
					
					$ADSGroupMbrOf_NotFound = $ADSGroupMbrOf_NotFound + @($ADGroupDN)
					$ADSGroupMbrOf = $ADSGroupMbrOf + @($ADGroupDN)
				
					continue
				}
		
				if ($ADGroup.GroupCategory -eq "Security")
				{
					$ADSGroupMbrOf = $ADSGroupMbrOf + @($ADGroupDN)
				}
			}
		}
		
		$ADSGroupMbrOf_NotFound = @($ADSGroupMbrOf_NotFound | Sort-Object -Unique)
		
		$ADSGroupMbrOf = @($ADSGroupMbrOf | Sort-Object -Unique)
	}

    $ADSGroupPso = New-Object PSObject -Property @{
		CanonicalName		= $ADSGroup.CanonicalName
		DistinguishedName	= $ADSGroup.DistinguishedName
		Duplicated			= $false
        GroupScope			= $ADSGroup.GroupScope		
		MemberOf			= $ADSGroupMbrOf
		Name				= $ADSGroup.Name
    }
	
	$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADSGroupPso)
	
	$next_RecursionLevel = $RecursionLevel + 1
	
	foreach ($ADGroupDN in $ADSGroupMbrOf_NotFound)
	{	
		$Exists = $false
		
		foreach ($ADGroupPso in $ADGroupPsoCol)
		{
			if ($ADGroupPso.DistinguishedName -eq $ADGroupDN)
			{
				if ($ADGroupPso.Duplicated -eq $false)
				{
					$ADGroupPso.Duplicated = $true
				}
				
				$Exists = $true

				break
			}
		}
		
		if (!$Exists)
		{	
			$Index = $ADGroupDN.IndexOf("DC=")
			
			$ADGroupRDN = $ADGroupDN.Substring(0,$Index-1)
			$StrSplit = $ADGroupRDN -split "=|,"
			$ADGroupName = $StrSplit[1]
			
			$DomainName = $ADGroupDN.Substring($Index+3) -replace ",DC=","."
			$ADGroupCN = $DomainName.ToLower()

			for ($i=($StrSplit.Count)-1; $i -ge 1; $i-=2)
			{
				$ADGroupCN = $ADGroupCN + "/" + $StrSplit[$i]
			}
			
			$ADGroupPso = New-Object PSObject -Property @{
				CanonicalName		= $ADGroupCN
				DistinguishedName	= $ADGroupDN
				Duplicated			= $false
        		GroupScope			= 'Unknown'		
				MemberOf			= @()
				Name				= $ADGroupName
    		}
			
			$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADGroupPso)
		}
	}
    
    if ($ADSGroupMbrOf -and $ADSGroupMbrOf_NotFound)
    {
        foreach ($ADGroupDN in $ADSGroupMbrOf)
		{
			if ([Array]::IndexOf($ADSGroupMbrOf_NotFound,$ADGroupDN) -eq -1)
			{
				$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
				$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
				$ADSGroup = Get-ADGroup $ADGroupDN -Properties CanonicalName -Server $GC
			
				DigG-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL $next_RecursionLevel
			}
    	}
	}
	elseif ($ADSGroupMbrOf)
	{
        foreach ($ADSGroupDN in $ADSGroupMbrOf)
		{
			$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroupDN -GC $ADForestGCPsoCol
			$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
			$ADSGroup = Get-ADGroup $ADSGroupDN -Properties CanonicalName -Server $GC
			
			DigG-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL $next_RecursionLevel
    	}
	}
}

function DigG-ADSecurityGroupMember
{
	param
	(  
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[ValidateScript({$_.GroupCategory -eq "Security"})] 
        [Microsoft.ActiveDirectory.Management.ADGroup] $ADSGroup,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("GC")]
        [PSObject[]] $ADForestGCPsoCol,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("RL")]		
		[Int] $RecursionLevel = 0,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Boolean] $Force
    )
 
 	$ADSGroupMbrAll = @()
	$ADSGroupMbr =  @()
	$ADSGroupMbr_NotFound = @()
	
	if ($RecursionLevel -gt $MaxRecursionLevel)
	{
		$global:MaxRecursionLevel = $RecursionLevel
	}
	
	foreach ($ADObjPso in $ADObjPsoCol)
	{	
		if ($ADObjPso.DistinguishedName -eq $ADSGroup.DistinguishedName)
		{	
			if ($ADObjPso.Duplicated -eq $false)
			{
				$ADObjPso.Duplicated = $true
			}
			
			return
		}
    }
	
	$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroup.DistinguishedName -GC $ADForestGCPsoCol
	$DC = $DomainGCPso.HostName
	
	$Msg = 'Analyzing Security Group "' + $ADSGroup.CanonicalName + '" from "' + $DC + '".'
	Write-Host $Msg
	
	$Overlimit = $false
	$Ignore = $false
	
	try # Get-ADGroupMember does not support connection to GC
	{
		$ADSGroupMbrAll = @(Get-ADGroupMember $ADSGroup.DistinguishedName -Server $DC |
			Where { $_.objectClass -eq 'group' } |
			Select DistinguishedName)
	}
	catch [Microsoft.ActiveDirectory.Management.ADException]
	{
		if ($_.Exception.ServerErrorMessage)
		{
			$Msg = ($_.Exception.ServerErrorMessage).Trim()
		}
		
		if ($Msg -eq "Exceeded groups or group members limit.")
		{
			$Msg += "`n" + 'Retrieving "' + $ADSGroup.CanonicalName + '" members failed because of ADWS limitation.'
			$Msg += "`nIts members are ignored.`n"
			Write-Warning $Msg
			
			$Overlimit = $true
		}
		elseif ($Msg -eq "The specified directory service attribute or value does not exist.")
		{
			$Msg += "`n" + 'Retrieving "' + $ADSGroup.CanonicalName + '" members failed because of ACL restriction on at least one member object.'
			$Msg += "`nIts members are ignored.`n"
			Write-Warning $Msg
			
			$Overlimit = $true
		}
		else
		{
			if ($_.Exception.GetType().Name -eq "ADReferralException") # If Domain mode exploration, member objects located out of source domain fall here
			{
				# Referral can be followed using $_.Exception.Referral
				$Msg = "`n" + 'Retrieving "' + $ADSGroup.CanonicalName + '" members failed because the group is out of source Domain.'
				$Msg += "`nYou should run the script using -Mode Forest."
				$Msg += "`nIts members are ignored.`n"
				Write-Warning $Msg
			}
			else
			{
				$Msg = $_.Exception.GetType().Name + " | "  + ($_.Exception.Message).Trim()
				$Msg += "`n" + 'Retrieving "' + $ADSGroup.CanonicalName + '" members failed.'
				$Msg += "`nPlease report exception to script author."
				$Msg += "`nIts members are ignored.`n"
				Write-Warning $Msg
			}
			
			$Overlimit = $true
			$Ignore = $true
		}
	}
	catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
	{
		$Msg = "`n" + 'Retrieving "' + $ADSGroup.CanonicalName + '" members failed due to ACL restriction.'
		$Msg += "`nIts members are ignored.`n"
		Write-Warning $Msg
		
		$Overlimit = $true
		$Ignore = $true
	}
	catch
	{
		$Msg = $_.Exception.GetType().Name + " | "  + ($_.Exception.Message).Trim()
		$Msg += "`n" + 'Retrieving "' + $ADSGroup.CanonicalName + '" members failed.'
		$Msg += "`nPlease report exception to script author."
		$Msg += "`nIts members are ignored.`n"
		Write-Warning $Msg
			
		$Overlimit = $true
		$Ignore = $true	
	}
	
	if(!$Ignore)
	{
		if(!$Overlimit)
		{	
			foreach ($ADObj in $ADSGroupMbrAll)
			{
				$ADObjDN = $ADObj.DistinguishedName
				
				$DomainGCPso = Get-ADGCOneForADObj -DN $ADObjDN -GC $ADForestGCPsoCol
				$GC = $DomainGCPso.HostName
				
				$Index = $ADObjDN.IndexOf("DC=")
				$DomainDN = $ADObjDN.Substring($Index)
				
				$Path = 'GC://' + $GC + '/' + $DomainDN
				
				$Filter1 = '(&(distinguishedName=' + $ADObjDN + ')(groupType:1.2.840.113556.1.4.803:=2147483648))'
				$Filter2 = '(&(distinguishedName=' + $ADObjDN + '))'
					
				if(Test-ADObject -Path $Path -Filter $Filter1)
				{
					$ADSGroupMbr = $ADSGroupMbr + @($ADObjDN)
				}
				else
				{
					if(!(Test-ADObject -Path $Path -Filter $Filter2))
					{
						$Msg = "`nQuery for " + $ADObjDN + "`non " + $GC + "`nreturned 'AD Identity Not Found'."	
						$Msg += "`nYou should check ACL restriction."
						$Msg += "`nThat object can't be explored further.`n"
						Write-Warning $Msg
				
						$ADSGroupMbr_NotFound = $ADSGroupMbr_NotFound + @($ADObjDN)
						$ADSGroupMbr = $ADSGroupMbr + @($ADObjDN)
					}
				}				
			
			}
		}
		elseif ($Overlimit -and $Force)
		{
			$Msg = "SCRIPT FALLS BACK TO BEST EFFORT GROUP MEMBER ENUMERATION.`n"
			Write-Warning $Msg
			
			$GC = $DC + ":" + $DomainGCPso.Port

			$LdapFilter = '(&(objectclass=group)(groupType:1.2.840.113556.1.4.803:=2147483648)(memberof:={0}))' -f $ADSGroup.DistinguishedName # only direct member unlike memberOf:1.2.840.113556.1.4.1941:=
				
			$ADSGroupMbrAll = Get-ADObject -LDAPFilter $LdapFilter -ResultSetSize $null -ResultPageSize 1000 -server $GC
					
			foreach ($ADSGrp in $ADSGroupMbrAll)
			{
				$ADSGroupMbr = $ADSGroupMbr + @($ADSGrp.DistinguishedName)
			}
		}
		else
		{
			$Msg = "SCRIPT HALTS GROUP MEMBER ENUMERATION."
			$Msg += "`nYou could run the script using -Force option.`n"
			Write-Warning $Msg
		}
	}

	$ADSGroupPso = New-Object PSObject -Property @{
		CanonicalName		= $ADSGroup.CanonicalName
		DistinguishedName	= $ADSGroup.DistinguishedName
		Duplicated			= $false
        GroupScope			= $ADSGroup.GroupScope		
		Member				= $ADSGroupMbr
		Name				= $ADSGroup.Name
		Overlimit			= $Overlimit
	}
	
	$global:ADObjPsoCol = $ADObjPsoCol + @($ADSGroupPso)
	
	$next_RecursionLevel = $RecursionLevel + 1	

	foreach ($ADObjDN in $ADSGroupMbr_NotFound)
	{	
		$Exists = $false
		
		foreach ($ADObjPso in $ADObjPsoCol)
		{
			if ($ADObjPso.DistinguishedName -eq $ADObjDN)
			{
				if ($ADObjPso.Duplicated -eq $false)
				{
					$ADObjPso.Duplicated = $true
				}
				
				$Exists = $true

				break
			}
		}
		
		if (!$Exists)
		{	
			$Index = $ADObjDN.IndexOf("DC=")
			
			$ADObjRDN = $ADObjDN.Substring(0,$Index-1)
			$StrSplit = $ADObjRDN -split "=|,"
			$ADObjName = $StrSplit[1]
			
			$DomainName = $ADObjDN.Substring($Index+3) -replace ",DC=","."
			$ADObjCN = $DomainName.ToLower()

			for ($i=($StrSplit.Count)-1; $i -ge 1; $i-=2)
			{
				$ADObjCN = $ADObjCN + "/" + $StrSplit[$i]
			}
			
			$ADObjPso = New-Object PSObject -Property @{
				CanonicalName		= $ADObjCN
				DistinguishedName	= $ADObjDN
				Duplicated			= $false
        		GroupScope			= 'Unknown'
				Member				= @()
				Name				= $ADObjName
				Overlimit			= $false
    		}
			
			$global:ADObjPsoCol = $ADObjPsoCol + @($ADObjPso)
		}
	}
		
	if ($ADSGroupMbr -and $ADSGroupMbr_NotFound)
	{	
		foreach ($ADObjDN in $ADSGroupMbr)
		{
			if ([Array]::IndexOf($ADSGroupMbr_NotFound,$ADObjDN) -eq -1)
			{		
				$DomainGCPso = Get-ADGCOneForADObj -DN $ADObjDN -GC $ADForestGCPsoCol
				$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
				$ADSGroup = Get-ADGroup $ADObjDN -Properties CanonicalName -Server $GC
			
				DigG-ADSecurityGroupMember $ADSGroup -GC $ADForestGCPsoCol -RL $next_RecursionLevel -Force $Force
			}
    	}
	}
	elseif ($ADSGroupMbr)
	{
        foreach ($ADSGroupDN in $ADSGroupMbr)
		{	
			$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroupDN -GC $ADForestGCPsoCol
			$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
			$ADSGroup = Get-ADGroup $ADSGroupDN -Properties CanonicalName -Server $GC
			
			DigG-ADSecurityGroupMember $ADSGroup -GC $ADForestGCPsoCol -RL $next_RecursionLevel -Force $Force
		}
	}
}

function ListG-ADSecurityGroupMemberOf
{
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[Alias("DN")]
		[String] $ADObjDN,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
        [Alias("SC")]
		[Microsoft.ActiveDirectory.Management.ADSearchScope] $Scope,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("GC")]
        [PSObject[]] $ADForestGCPsoCol
    )
	
	$Console_ObjSummary = {
	
		param
		(
			$MaxRecursionLevel,
			$ADSGroupPsoCount,			
			$ADSGroupPsoDupCount,
			$ADTokenSize,			
			$UnknownPsoCount,
			$UnknownPsoDupCount
		)
		
		"{0,0}{1,26}" -f "Nesting Level:", $MaxRecursionLevel | Write-Host -ForegroundColor White
		"{0,0}{1,19}" -f "Known Group(s) Count:", $ADSGroupPsoCount | Write-Host -ForegroundColor White
		"{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $ADSGroupPsoDupCount | Write-Host -ForegroundColor White
		"{0,0}{1,19} bytes`n" -f "Estimated Token Size:", $ADTokenSize | Write-Host -ForegroundColor White
		
		"{0,0}{1,17}" -f "Unknown Group(s) Count:", $UnknownPsoCount | Write-Host -ForegroundColor White
		"{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $UnknownPsoDupCount | Write-Host -ForegroundColor White
	}
	
	$Graph_ObjSummary = {
	
		param
		(
			$MaxRecursionLevel,
			$ADSGroupPsoCount,			
			$ADSGroupPsoDupCount,
			$ADTokenSize,			
			$UnknownPsoCount,
			$UnknownPsoDupCount
		)
		
		$ObjSummary = "Nesting Level: $MaxRecursionLevel" +
		"|Known Group(s) Count: $ADSGroupPsoCount" +
		"|Nesting Potential Issue(s): $ADSGroupPsoDupCount" +
		"|Estimated Token Size: $ADTokenSize" +		
		"|Unknown Group(s) Count: $UnknownPsoCount" +
		"|Nesting Potential Issue(s): $UnknownPsoDupCount"
		
		return $ObjSummary
	}
	
	$DomainGCPso = Get-ADGCOneForADObj -DN $ADObjDN -GC $ADForestGCPsoCol
	$DomainGC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
	
	$ADObj = Get-ADObject $ADObjDN -Properties CanonicalName,GroupType -Server $DomainGC
	
	$global:MaxRecursionLevel = 0
	
	switch ($ADObj)
	{
		{($_.ObjectClass -eq "domainDNS") -or ($_.ObjectClass -eq "organizationalUnit") -or ($_.ObjectClass -eq "container") -or ($_.ObjectClass -eq "builtinDomain")}
		{	
			$ADGroupPsoCol_Temp = @()
		
			foreach ($ADSGroup in (Get-ADGroup -Filter {GroupCategory -eq "Security"} -SearchBase $ADObjDN -SearchScope $Scope.ToString() -Server $DomainGC))
			{	
				$global:ADGroupPsoCol = @()
			
				ListG-ADSecurityGroupMemberOf -DN $ADSGroup.DistinguishedName -SC $Scope.ToString() -GC $ADForestGCPsoCol
				
				foreach ($ADGroupPso in $ADGroupPsoCol)
				{
					$Exists = $false
				
					foreach ($ADGroupPso_Temp in $ADGroupPsoCol_Temp)
					{
						if ($ADGroupPso.DistinguishedName -eq $ADGroupPso_Temp.DistinguishedName)
						{
							if ($ADGroupPso.Duplicated -eq $true)
							{
								$ADGroupPso_Temp.Duplicated = $true
							}
							
							$Exists = $true
							
							break
						}
					}
					
					if (!$Exists)
					{
						$ADGroupPsoCol_Temp = $ADGroupPsoCol_Temp + @($ADGroupPso.PSObject.Copy())
					}
				}
	    	}
			
			$global:ADGroupPsoCol = $ADGroupPsoCol_Temp
			
			Remove-Variable -Name 'ADGroupPsoCol_Temp'
			
			break
		}
		
		{($_.ObjectClass -eq "group") -and ($_.GroupType -like "-2*")}
		{
			Get-ADGroup $ADObjDN -Properties CanonicalName -Server $DomainGC |
			DigG-ADSecurityGroupMemberOf -GC $ADForestGCPsoCol -RL 0
			
			Write-Host
			
			Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }) -For $ADObj.CanonicalName -By "MemberOf"	
			
			$ADSGroupPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }).Count
			$ADSGroupPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -ne "Unknown" }).Count
			$ADTokenSize = Measure-ADTokenSize @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }) -DN $ADObjDN			
			
			$UnknownPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }).Count
			$UnknownPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -eq "Unknown" }).Count
			
			if ($UnknownPsoCount)
			{
				Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }) -For $ADObj.CanonicalName -By "MemberOf"
			}
			
			&$Console_ObjSummary $MaxRecursionLevel $ADSGroupPsoCount $ADSGroupPsoDupCount $ADTokenSize $UnknownPsoCount $UnknownPsoDupCount
			
			break
		}
		
		{($_.ObjectClass -eq "computer")}
		{
			$ADComputer = Get-ADComputer $ADObjDN -Properties CanonicalName,PrimaryGroup -Server $DomainGC
			
			$Msg = 'Analyzing Computer "' + $ADComputer.CanonicalName + '"'
			Write-Host $Msg
			
			$ADComputerMbrOf = @()
			$ADComputerMbrOf_NotFound = @()
			
    		foreach ($ADForestGCPso in $ADForestGCPsoCol)
			{
				$GC = $ADForestGCPso.HostName + ":" + $ADForestGCPso.Port
				
				$Msg = 'from "' + $GC + '"'
				Write-Host $Msg
				
				foreach ($ADGroupDN in (Get-ADComputer $ADComputer.DistinguishedName -Properties MemberOf -Server $GC).MemberOf)
				{
					$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
					$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
				
					try
					{	
						$ADGroup = Get-ADGroup $ADGroupDN -Server $GC
					}
					catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
					{	
						$Msg = "`nQuery for " + $ADGroupDN + "`non " + $GC + "`nreturned 'AD Identity Not Found'."
						$Msg += "`nYou should check ACL restriction."
						$Msg += "`nThat group can't be explored further.`n"
						Write-Warning $Msg
						
						$ADComputerMbrOf_NotFound = $ADCompterMbrOf_NotFound + @($ADGroupDN)
						$ADComputerMbrOf = $ADComputerMbrOf + @($ADGroupDN)
					
						continue
					}
			
					if ($ADGroup.GroupCategory -eq "Security")
					{
						$ADComputerMbrOf = $ADComputerMbrOf + @($ADGroupDN)
					}
				}
			}
			
			$ADComputerMbrOf_NotFound = @($ADComputerMbrOf_NotFound | Sort-Object -Unique)
			
			foreach ($ADGroupDN in $ADComputerMbrOf_NotFound)
			{
				$Index = $ADGroupDN.IndexOf("DC=")
				
				$ADGroupRDN = $ADGroupDN.Substring(0,$Index-1)
				$StrSplit = $ADGroupRDN -split "=|,"
				$ADGroupName = $StrSplit[1]
				
				$DomainName = $ADGroupDN.Substring($Index+3) -replace ",DC=","."
				$ADGroupCN = $DomainName.ToLower()

				for ($i=($StrSplit.Count)-1; $i -ge 1; $i-=2)
				{
					$ADGroupCN = $ADGroupCN + "/" + $StrSplit[$i]
				}
				
				$ADGroupPso = New-Object PSObject -Property @{
					CanonicalName		= $ADGroupCN
					DistinguishedName	= $ADGroupDN
					Duplicated			= $false
	        		GroupScope			= 'Unknown'		
					MemberOf			= @()
					Name				= $ADGroupName
	    		}
				
				$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADGroupPso)
			}

			$ADComputerMbrOf = @($ADComputerMbrOf | Sort-Object -Unique)
			$ADComputerMbrOf = $ADComputerMbrOf + @($ADComputer.PrimaryGroup)
			
			if ($ADComputerMbrOf_NotFound)
    		{
				foreach ($ADGroupDN in $ADComputerMbrOf)
				{
					if ([Array]::IndexOf($ADComputerMbrOf_NotFound,$ADGroupDN) -eq -1)
					{
						$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
						$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
						
						$ADSGroup = Get-ADGroup $ADGroupDN -Properties CanonicalName -Server $GC
						
						DigG-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL 1
					}
	    		}
			}
			else
			{
				foreach ($ADSGroupDN in $ADComputerMbrOf)
				{
					$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroupDN -GC $ADForestGCPsoCol
					$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
				
					$ADSGroup = Get-ADGroup $ADSGroupDN -Properties CanonicalName -Server $GC
					
					DigG-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL 1
	    		}			
			}
			
			Write-Host
			
			Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }) -For $ADComputer.CanonicalName -By "MemberOf"
			
			$ADSGroupPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }).Count
			$ADSGroupPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -ne "Unknown" }).Count
			$ADTokenSize = Measure-ADTokenSize @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }) -DN $ADObjDN			
			
			$UnknownPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }).Count
			$UnknownPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -eq "Unknown" }).Count
			
			if ($UnknownPsoCount)
			{
				Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }) -For $ADObj.CanonicalName -By "MemberOf"
			}
						
			$ObjSummary = &$Graph_ObjSummary $MaxRecursionLevel $ADSGroupPsoCount $ADSGroupPsoDupCount $ADTokenSize $UnknownPsoCount $UnknownPsoDupCount
	
			$ADPso = New-Object PSObject -Property @{
				Name				= $ADComputer.Name
				CanonicalName		= $ADComputer.CanonicalName
				DistinguishedName	= $ObjSummary
    			GroupScope			= "None"
    			MemberOf			= $ADComputerMbrOf
				Duplicated			= $false
			}
			
			$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADPso)

			&$Console_ObjSummary $MaxRecursionLevel $ADSGroupPsoCount $ADSGroupPsoDupCount $ADTokenSize $UnknownPsoCount $UnknownPsoDupCount			
			
			break
		}
		
		{($_.ObjectClass -eq "user") -or ($_.ObjectClass -eq "inetOrgPerson")}
		{
			$ADUser = Get-ADUser $ADObjDN -Properties CanonicalName,PrimaryGroup -Server $DomainGC
			
			$Msg = 'Analyzing User "' + $ADUser.CanonicalName + '"'
			Write-Host $Msg
			
			$ADUserMbrOf = @()
			$ADUserMbrOf_NotFound = @()
			
			foreach ($ADForestGCPso in $ADForestGCPsoCol)
    		{
				$GC = $ADForestGCPso.HostName + ":" + $ADForestGCPso.Port
				
				$Msg = 'from "' + $GC + '"'
				Write-Host $Msg
				
				foreach ($ADGroupDN in (Get-ADUser $ADUser.DistinguishedName -Properties MemberOf -Server $GC).MemberOf)
				{
					$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
					$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
				
					try
					{	
						$ADGroup = Get-ADGroup $ADGroupDN -Server $GC
					}
					catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
					{	
						$Msg = "`nQuery for " + $ADGroupDN + "`non " + $GC + "`nreturned 'AD Identity Not Found'."
						$Msg += "`nYou should check ACL restriction."
						$Msg += "`nThat group can't be explored further.`n"
						Write-Warning $Msg
						
						$ADUserMbrOf_NotFound = $ADUserMbrOf_NotFound + @($ADGroupDN)
						$ADUserMbrOf = $ADUserMbrOf + @($ADGroupDN)
					
						continue
					}
			
					if ($ADGroup.GroupCategory -eq "Security")
					{
						$ADUserMbrOf = $ADUserMbrOf + @($ADGroupDN)
					}
				}
			}
			
			$ADUserMbrOf_NotFound = @($ADUserMbrOf_NotFound | Sort-Object -Unique)
			
			foreach ($ADGroupDN in $ADUserMbrOf_NotFound)
			{
				$Index = $ADGroupDN.IndexOf("DC=")
				
				$ADGroupRDN = $ADGroupDN.Substring(0,$Index-1)
				$StrSplit = $ADGroupRDN -split "=|,"
				$ADGroupName = $StrSplit[1]
				
				$DomainName = $ADGroupDN.Substring($Index+3) -replace ",DC=","."
				$ADGroupCN = $DomainName.ToLower()

				for ($i=($StrSplit.Count)-1; $i -ge 1; $i-=2)
				{
					$ADGroupCN = $ADGroupCN + "/" + $StrSplit[$i]
				}
				
				$ADGroupPso = New-Object PSObject -Property @{
					CanonicalName		= $ADGroupCN
					DistinguishedName	= $ADGroupDN
					Duplicated			= $false
	        		GroupScope			= 'Unknown'		
					MemberOf			= @()
					Name				= $ADGroupName
	    		}
				
				$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADGroupPso)
			}
			
			$ADUserMbrOf = @($ADUserMbrOf | Sort-Object -Unique)
			$ADUserMbrOf = $ADUserMbrOf + @($ADUser.PrimaryGroup)
			
			if ($ADUserMbrOf_NotFound)
    		{
				foreach ($ADGroupDN in $ADUserMbrOf)
				{
					if ([Array]::IndexOf($ADUserMbrOf_NotFound,$ADGroupDN) -eq -1)
					{
						$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
						$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
						
						$ADSGroup = Get-ADGroup $ADGroupDN -Properties CanonicalName -Server $GC
						
						DigG-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL 1
	    			}
				}
			}
			else
			{
				foreach ($ADSGroupDN in $ADUserMbrOf)
				{
					$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroupDN -GC $ADForestGCPsoCol
					$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
				
					$ADSGroup = Get-ADGroup $ADSGroupDN -Properties CanonicalName -Server $GC
					
					DigG-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL 1
	    		}			
			}

			Write-Host

			Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }) -For $ADUser.CanonicalName -By "MemberOf"
			
			$ADSGroupPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }).Count
			$ADSGroupPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -ne "Unknown" }).Count
			$ADTokenSize = Measure-ADTokenSize @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }) -DN $ADObjDN			
			
			$UnknownPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }).Count
			$UnknownPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -eq "Unknown" }).Count
			
			if ($UnknownPsoCount)
			{
				Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }) -For $ADObj.CanonicalName -By "MemberOf"
			}
			
			$ObjSummary = &$Graph_ObjSummary $MaxRecursionLevel $ADSGroupPsoCount $ADSGroupPsoDupCount $ADTokenSize $UnknownPsoCount $UnknownPsoDupCount
			
			$ADPso = New-Object PSObject -Property @{
				Name				= $ADUser.Name
				CanonicalName		= $ADUser.CanonicalName
				DistinguishedName	= $ObjSummary
    			GroupScope			= "None"
    			MemberOf			= $ADUserMbrOf
				Duplicated			= $false				
			}
			
			$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADPso)
			
			&$Console_ObjSummary $MaxRecursionLevel $ADSGroupPsoCount $ADSGroupPsoDupCount $ADTokenSize $UnknownPsoCount $UnknownPsoDupCount			
			
			break
		}
		
		default
		{
			$Msg = 'SCRIPT ABORTED.'
			$Msg += "`n" + 'Please select a Domain, an OU, a Container, a Security Group, a User or a Computer.'
			Write-Warning $Msg
		}
	}
}

function ListG-ADSecurityGroupMember
{  
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[Alias("DN")]
		[String] $ADObjDN,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
        [Alias("SC")]
		[Microsoft.ActiveDirectory.Management.ADSearchScope] $Scope,
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Boolean] $Force,

		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("GC")]
        [PSObject[]] $ADForestGCPsoCol		
    )

	$Console_ObjSummary = {
	
		param
		(
			$MaxRecursionLevel,
			$ADSGroupPsoCount,
			$ADSGroupPsoDupCount,			
			$UnknownPsoCount,
			$UnknownPsoDupCount,
			$OverlimitPsoCount
			
		)
		
		"{0,0}{1,26}" -f "Nesting Level:", $MaxRecursionLevel | Write-Host -ForegroundColor White
		"{0,0}{1,19}" -f "Known Group(s) Count:", $ADSGroupPsoCount | Write-Host -ForegroundColor White
		"{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $ADSGroupPsoDupCount | Write-Host -ForegroundColor White
		
		"{0,0}{1,16}" -f "Unknown Object(s) Count:", $UnknownPsoCount | Write-Host -ForegroundColor White
		"{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $UnknownPsoDupCount | Write-Host -ForegroundColor White
		
		"{0,0}{1,13}`n" -f "Group Enumeration Error(s):", $OverlimitPsoCount | Write-Host -ForegroundColor White		
	}

	$DomainGCPso = Get-ADGCOneForADObj -DN $ADObjDN -GC $ADForestGCPsoCol
	$DomainGC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
	
	$ADObj = Get-ADObject $ADObjDN -Properties CanonicalName,GroupType -Server $DomainGC
	
	$global:MaxRecursionLevel = 0	
	
	switch ($ADObj)
	{
		{($_.ObjectClass -eq "domainDNS") -or ($_.ObjectClass -eq "organizationalUnit") -or ($_.ObjectClass -eq "container") -or ($_.ObjectClass -eq "builtinDomain")}
		{ 
			$ADObjPsoCol_Temp = @()
		
			foreach ($ADSGroup in (Get-ADGroup -Filter {GroupCategory -eq "Security"} -SearchBase $ADObjDN -SearchScope $Scope.ToString() -Server $DomainGC))
			{	
				$global:ADObjPsoCol = @()
			
				ListG-ADSecurityGroupMember -DN $ADSGroup.DistinguishedName -SC $Scope.ToString() -Force $Force -GC $ADForestGCPsoCol
				
				foreach ($ADObjPso in $ADObjPsoCol)
				{
					$Exists = $false
				
					foreach ($ADObjPso_Temp in $ADObjPsoCol_Temp)
					{
						if ($ADObjPso.DistinguishedName -eq $ADObjPso_Temp.DistinguishedName)
						{
							if ($ADObjPso.Duplicated -eq $true)
							{
								$ADObjPso_Temp.Duplicated = $true
							}
							
							$Exists = $true
							
							break
						}
					}
					
					if (!$Exists)
					{
						$ADObjPsoCol_Temp = $ADObjPsoCol_Temp + @($ADObjPso.PSObject.Copy())
					}
				}
	    	}
			
			$global:ADObjPsoCol = $ADObjPsoCol_Temp
			
			Remove-Variable -Name 'ADObjPsoCol_Temp'
			
			break
		}
		
		{($_.ObjectClass -eq "group") -and ($_.GroupType -like "-2*")}
		{
			Get-ADGroup $ADObjDN -Properties CanonicalName -Server $DomainGC |
			DigG-ADSecurityGroupMember -GC $ADForestGCPsoCol -RL 0 -Force $Force
			
			Write-Host
			
			Get-ADObjDuplicated @($ADObjPsoCol | Where { $_.GroupScope -ne "Unknown" }) -For $ADObj.CanonicalName -By "Member"
			
			$ADSGroupPsoCount = @($ADObjPsoCol | Where { $_.GroupScope -ne "Unknown" }).Count
			$ADSGroupPsoDupCount = @($ADObjPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -ne "Unknown" }).Count		
			
			$UnknownPsoCount = @($ADObjPsoCol | Where { $_.GroupScope -eq "Unknown" }).Count
			$UnknownPsoDupCount = @($ADObjPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -eq "Unknown" }).Count
			
			if ($UnknownPsoCount)
			{
				Get-ADObjDuplicated @($ADObjPsoCol | Where { $_.GroupScope -eq "Unknown" }) -For $ADObj.CanonicalName -By "Member"
			}
			
			$OverlimitPsoCount = @($ADObjPsoCol | Where { $_.Overlimit -eq $true }).Count
			
			&$Console_ObjSummary $MaxRecursionLevel $ADSGroupPsoCount $ADSGroupPsoDupCount $UnknownPsoCount $UnknownPsoDupCount $OverlimitPsoCount
			
			break
		}
	
		default
		{
			$Msg = 'SCRIPT ABORTED.'
			$Msg += "`n" + 'Please select a Domain, an OU, a Container or a Security Group.' 
			Write-Warning $Msg
		}
	}
}

function Graph-ADSecurityGroupMemberOf
{   
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[PSObject[]] $ADGroupPsoCol,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("DN")]
		[String] $ADObjDN,
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("SC")]
		[String] $Scope,
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[String] $Mode,
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("CS")]
		[String] $Charset,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("DGC")]
		[String] $DomainLocalColor = "Red",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("GGC")]
        [String] $GlobalColor = "Green",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UGC")]
        [String] $UniversalColor = "Cyan",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UOC")]
        [String] $UnknownObjColor = "Magenta",	
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
        [Alias("NGC")]
		[String] $NonGroupColor = "Black"
    )

    $NodeColor = {
        
		param
		(	
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[String] $Scope
		)

        switch ($Scope)
		{
            "DomainLocal"	{ return $DomainLocalColor }
            "Global"		{ return $GlobalColor }
            "Universal"		{ return $UniversalColor }
			"Unknown"		{ return $UnknownObjColor }
			"None"			{ return $NonGroupColor }
        }
    }
	
    $NodeStyle = {
        
		param
		(	
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[Bool] $Duplicated
		)

		$Style = "rounded"
		
        if ($Duplicated)
		{
			$Style = "filled,rounded"
        }

		return $Style
    }	
	
    $GraphNode = {
	
		param
		(
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[PSObject] $ADGroupPso
		)
		
		'ADObj_{0} [' -f [Array]::IndexOf($ADGroupPsoCol,$ADGroupPso) | Write-Output

		if ($ADGroupPso.DistinguishedName.IndexOf("DC=") -ne -1)
		{
			$Index = $ADGroupPso.DistinguishedName.IndexOf("DC=")
			$DomainDN = $ADGroupPso.DistinguishedName.Substring($Index)

        	'label="{0}|{1}",' -f $ADGroupPso.Name,$DomainDN | Write-Output
		}
		else
		{
			'label="{0}|{1}",' -f $ADGroupPso.Name,$ADGroupPso.DistinguishedName | Write-Output
		}
		
        'color="{0}",' -f (&$NodeColor $ADGroupPso.GroupScope) | Write-Output
		'style="{0}"' -f (&$NodeStyle $ADGroupPso.Duplicated) | Write-Output
        '];' | Write-Output
    }

    'digraph G {' | Write-Output
	
	if ($Charset -eq "UTF8")
	{
		'charset="utf-8";' | Write-Output
	}
	
	'fontsize="9";' | Write-Output
	'fontname="serif";' | Write-Output
	
	'label="~*~' | Write-Output
	' ' | Write-Output
	'Security Groups and nesting found with {0} search starting from {1} and using MemberOf back-link attribute over {2}' -f $Scope,$ADObjDN,$Mode | Write-Output
	'{0}' -f (Get-Date).ToShortDateString() | Write-Output
	' ' | Write-Output
	'~*~' | Write-Output
	' ' | Write-Output
	'{0}: Global Group' -f $GlobalColor | Write-Output
	'{0}: Domain Local Group' -f $DomainLocalColor | Write-Output
	'{0}: Universal Group' -f $UniversalColor | Write-Output
	'{0}: GroupType/Scope unknown due to ACL restriction' -f $UnknownObjColor | Write-Output
	'Color Filled: Nesting issue"' | Write-Output
    
	'graph [overlap="false",rankdir="LR"];' | Write-Output
	'node [fontsize="8",fontname="serif",shape="record",style="rounded"];' | Write-Output
	'edge [dir="forward",arrowsize="0.5",arrowhead="empty"];' | Write-Output
		
	foreach ($ADGroupPso in $ADGroupPsoCol)
	{
		$Msg = 'Graphing "' + $ADGroupPso.CanonicalName + '".'
		Write-Host $Msg
		
		$ADGroupChildPso = $ADGroupPso
        
		&$GraphNode $ADGroupChildPso

		foreach ($ADGroupDN in $ADGroupChildPso.MemberOf)
		{
			foreach ($ADGrpPso in $ADGroupPsoCol)
			{	
				if ($ADGrpPso.DistinguishedName -eq $ADGroupDN)
				{
					$ADGroupParentPso = $ADGrpPso
					
					'ADObj_{0} -> ADObj_{1};' -f [Array]::IndexOf($ADGroupPsoCol,$ADGroupChildPso), [Array]::IndexOf($ADGroupPsoCol,$ADGroupParentPso) |
					Write-Output
					
					break
				}
		    }
		}
	} 
	
	'}'	| Write-Output
}

function Graph-ADSecurityGroupMember
{
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[PSObject[]] $ADObjPsoCol,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("DN")]
		[String] $ADObjDN,
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("SC")]
		[String] $Scope,
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[String] $Mode,
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("CS")]
		[String] $Charset,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("DGC")]
		[String] $DomainLocalColor = "Red",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("GGC")]
        [String] $GlobalColor = "Green",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UGC")]
        [String] $UniversalColor = "Cyan",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UOC")]
        [String] $UnknownObjColor = "Magenta"
    )

    $NodeColor = {
        
		param
		(	
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[String] $Scope
		)

        switch ($Scope)
		{
            "DomainLocal"	{ return $DomainLocalColor }
            "Global"		{ return $GlobalColor }
            "Universal"		{ return $UniversalColor }
			"Unknown"		{ return $UnknownObjColor }
        }
    }
	
    $NodeStyle = {
        
		param
		(	
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[Bool] $Duplicated,
		
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[Bool] $Overlimit
		)

		$Style = "rounded"
		$Comma = ","
		
		if ($Overlimit)
		{
			$Style = ""
			$Comma = ""
        }
		
        if ($Duplicated)
		{	
			$Style = "filled" + $Comma + $Style
        }
		
		return $Style
    }
	
    $GraphNode = {
	
		param
		(
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[PSObject] $ADObjPso
		)
	
		$Index = $ADObjPso.DistinguishedName.IndexOf("DC=")
		$DomainDN = $ADObjPso.DistinguishedName.Substring($Index)

        'ADObj_{0} [' -f [Array]::IndexOf($ADObjPsoCol,$ADObjPso) | Write-Output
        'label="{0}|{1}",' -f $ADObjPso.Name, $DomainDN | Write-Output
        'color="{0}",' -f (&$NodeColor $ADObjPso.GroupScope) | Write-Output
		'style="{0}"' -f (&$NodeStyle $ADObjPso.Duplicated $ADObjPso.Overlimit) | Write-Output
        '];' | Write-Output
    }

    'digraph G {' | Write-Output
	
	if ($Charset -eq "UTF8")
	{
		'charset="utf-8";' | Write-Output
	}
	
	'fontsize="9";' | Write-Output
	'fontname="serif";' | Write-Output
	
	'label="~*~' | Write-Output
	' ' | Write-Output
	'Security Groups and nesting found with {0} search starting from {1} and using Member attribute over {2}' -f $Scope,$ADObjDN,$Mode | Write-Output
	'{0}' -f (Get-Date).ToShortDateString() | Write-Output
	' ' | Write-Output
	'~*~' | Write-Output
	' ' | Write-Output
	'{0}: Global Group' -f $GlobalColor | Write-Output
	'{0}: Domain Local Group' -f $DomainLocalColor | Write-Output
	'{0}: Universal Group' -f $UniversalColor | Write-Output
	'{0}: ObjectType/GroupScope unknown due to ACL restriction' -f $UnknownObjColor | Write-Output
	'Color Filled: Nesting issue' | Write-Output
	'Rectangle Shape: Member enumeration issue' | Write-Output
	'due to ADWS limitation' | Write-Output
	if ($Mode -eq "Domain" )
	{
		'or ACL restriction' | Write-Output
		'or because user targeted exploration to source Domain only"' | Write-Output
	}
	else
	{
		'or ACL restriction"' | Write-Output	
	}
	
    'graph [overlap="false",rankdir="LR"];' | Write-Output
	'node [fontsize="8",fontname="serif",shape="record",style="rounded"];' | Write-Output
	'edge [dir="back",arrowsize="0.5",arrowtail="empty"];' | Write-Output

	foreach ($ADObjPso in $ADObjPsoCol)
	{
		$Msg = 'Graphing "' + $ADObjPso.CanonicalName + '".'
		Write-Host $Msg
	
		$ADObjParentPso = $ADObjPso

        &$GraphNode $ADObjParentPso

    	foreach ($ADObjMbr in $ADObjParentPso.Member)
		{
        	foreach ($ADGrpPso in $ADObjPsoCol)
			{
				if ($ADGrpPso.DistinguishedName -eq $ADObjMbr)
				{
					$ADObjChildPso = $ADGrpPso
					
					'ADObj_{0} -> ADObj_{1};' -f [Array]::IndexOf($ADObjPsoCol,$ADObjParentPso), [Array]::IndexOf($ADObjPsoCol,$ADObjChildPso) |
					Write-Output
					
					break
				}
			}
		}
	}

	'}'	| Write-Output
}

function Console-ADSecurityGroupMemberOf
{
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[PSObject] $ADGroupPso,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("RL")]		
		[Int] $RecursionLevel = 0,		
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("DGC")]
		[String] $DomainLocalColor = "Red",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("GGC")]
        [String] $GlobalColor = "Green",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UGC")]
        [String] $UniversalColor = "Cyan",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UOC")]
        [String] $UnknownObjColor = "Magenta",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
        [Alias("NGC")]
		[String] $NonGroupColor = $host.UI.RawUI.ForegroundColor
    )

    $NodeColor = {
        
		param
		(	
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[String] $Scope
		)

        switch ($Scope)
		{
            "DomainLocal"	{ return $DomainLocalColor }
            "Global"		{ return $GlobalColor }
            "Universal"		{ return $UniversalColor }
			"Unknown"		{ return $UnknownObjColor }
			"None"			{ return $NonGroupColor }
        }
    }
		
	$Index = $ADGroupPso.DistinguishedName.IndexOf("DC=")
	$DomainDN = $ADGroupPso.DistinguishedName.Substring($Index)
	
	$StrPadding = "   " * $RecursionLevel
	
	$StrLink = "└─"
	if ($RecursionLevel -eq 0)
	{
		$StrLink = "  "	
	}
	
	$GroupName = $ADGroupPso.Name
	$FgColor = &$NodeColor $ADGroupPso.GroupScope
	$BgColor = $host.UI.RawUI.BackgroundColor
	
	if ($ADGroupPso.GroupScope -notmatch "Unknown|None")
	{
		$GroupScope = '*' + ($ADGroupPso.GroupScope).ToString()[0] + '*'
	}
	else
	{
		$GroupScope = '*' + ($ADGroupPso.GroupScope).ToString() + '*'
	}
	
	if($ADGroupPso.Duplicated)
	{
		$BgColor = 'Dark' + $FgColor
		$FgColor = 'White'
		
		$GroupScope = '!: ' + $GroupScope		
	}

	"{0:d2} {1}{2} " -f $RecursionLevel, $StrPadding, $StrLink | Write-Host -NoNewline
	"{0}" -f $GroupName | Write-Host -Foreground $FgColor -Background $BgColor
	"{0}      {1}" -f $StrPadding, $DomainDN | Write-Host
	
	$global:TreeViewData += ("{0:d2} {1}{2} {3} {4}`n" -f $RecursionLevel, $StrPadding, $StrLink, $GroupScope, $GroupName)
	$global:TreeViewData += ("{0}      {1}`n" -f $StrPadding, $DomainDN)
}

function Console-ADSecurityGroupMember
{
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[PSObject] $ADGroupPso,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("RL")]		
		[Int] $RecursionLevel = 0,		
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("DGC")]
		[String] $DomainLocalColor = "Red",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("GGC")]
        [String] $GlobalColor = "Green",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UGC")]
        [String] $UniversalColor = "Cyan",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UOC")]
        [String] $UnknownObjColor = "Magenta"
    )

    $NodeColor = {
        
		param
		(	
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[String] $GroupScope
		)

        switch ($GroupScope)
		{
            "DomainLocal"	{ return $DomainLocalColor }
            "Global"		{ return $GlobalColor }
            "Universal"		{ return $UniversalColor }
			"Unknown"		{ return $UnknownObjColor }
        }
    }
		
	$Index = $ADGroupPso.DistinguishedName.IndexOf("DC=")
	$DomainDN = $ADGroupPso.DistinguishedName.Substring($Index)
	
	$StrPadding = "   " * $RecursionLevel
	
	$StrLink = "└─"
	if ($RecursionLevel -eq 0)
	{
		$StrLink = "  "	
	}
	
	$GroupName = $ADGroupPso.Name
	$FgColor = &$NodeColor $ADGroupPso.GroupScope
	$BgColor = $host.UI.RawUI.BackgroundColor
	
	if ($ADGroupPso.GroupScope -ne 'Unknown')
	{
		$GroupScope = '*' + ($ADGroupPso.GroupScope).ToString()[0] + '*'
	}
	else
	{
		$GroupScope = 'Unknown'
	}
	
	if($ADGroupPso.Duplicated)
	{
		$BgColor = 'Dark' + $FgColor
		$FgColor = 'White'		
		
		$GroupScope = '!: ' + $GroupScope
	}
		
	if($ADGroupPso.Overlimit)
	{
		$GroupName = '>> ' + $GroupName + ' <<'
	}
	
	"{0:d2} {1}{2} " -f $RecursionLevel, $StrPadding, $StrLink | Write-Host -NoNewline
	"{0}" -f $GroupName | Write-Host -Foreground $FgColor -Background $BgColor
	"{0}      {1}" -f $StrPadding, $DomainDN | Write-Host
	
	$global:TreeViewData += ("{0:d2} {1}{2} {3} {4}`n" -f $RecursionLevel, $StrPadding, $StrLink, $GroupScope, $GroupName)
	$global:TreeViewData += ("{0}      {1}`n" -f $StrPadding, $DomainDN)
}

function DigC-ADSecurityGroupMemberOf
{
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[ValidateScript({$_.GroupCategory -eq "Security"})]
        [Microsoft.ActiveDirectory.Management.ADGroup] $ADSGroup,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("GC")]
        [PSObject[]] $ADForestGCPsoCol,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("RL")]		
		[Int] $RecursionLevel = 0
    )
 
	$ADSGroupMbrOf =  @()
	$ADSGroupMbrOf_NotFound = @()
	
	if ($RecursionLevel -gt $MaxRecursionLevel)
	{
		$global:MaxRecursionLevel = $RecursionLevel
	}

	$Index = $ADSGroup.DistinguishedName.IndexOf("DC=")
	$DomainDN = $ADSGroup.DistinguishedName.Substring($Index)
 
	foreach ($ADGroupPso in $ADGroupPsoCol)
	{	
		if ($ADGroupPso.DistinguishedName -eq $ADSGroup.DistinguishedName)
		{	
			if ($ADGroupPso.Duplicated -eq $false)
			{
				$ADGroupPso.Duplicated = $true
			}
			
			Console-ADSecurityGroupMemberOf $ADGroupPso $RecursionLevel
			
			return
		}
    }

	if ($ADSGroup.GroupScope -eq "DomainLocal")
	{	
		$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroup.DistinguishedName -GC $ADForestGCPsoCol
		$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
		
		foreach ($ADGroupDN in (Get-ADGroup $ADSGroup.DistinguishedName -Properties MemberOf -Server $GC).MemberOf)
		{
			$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
			$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
			try
			{	
				$ADGroup = Get-ADGroup $ADGroupDN -Server $GC
			}
			catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
			{	
				$ADSGroupMbrOf_NotFound = $ADSGroupMbrOf_NotFound + @($ADGroupDN)
				$ADSGroupMbrOf = $ADSGroupMbrOf + @($ADGroupDN)
				
				continue
			}
			
			if ($ADGroup.GroupCategory -eq "Security")
			{
				$ADSGroupMbrOf = $ADSGroupMbrOf + @($ADGroupDN)
			}
		}
	}
	else
	{   
	    foreach ($ADForestGCPso in $ADForestGCPsoCol)
		{
			$GC = $ADForestGCPso.HostName + ":" + $ADForestGCPso.Port
			
			foreach ($ADGroupDN in (Get-ADGroup $ADSGroup.DistinguishedName -Properties MemberOf -Server $GC).MemberOf)
			{
				$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
				$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
				try
				{	
					$ADGroup = Get-ADGroup $ADGroupDN -Server $GC
				}
				catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
				{
					$ADSGroupMbrOf_NotFound = $ADSGroupMbrOf_NotFound + @($ADGroupDN)
					$ADSGroupMbrOf = $ADSGroupMbrOf + @($ADGroupDN)
				
					continue
				}
		
				if ($ADGroup.GroupCategory -eq "Security")
				{
					$ADSGroupMbrOf = $ADSGroupMbrOf + @($ADGroupDN)
				}
			}
		}
		
		$ADSGroupMbrOf_NotFound = @($ADSGroupMbrOf_NotFound | Sort-Object -Unique)
		
		$ADSGroupMbrOf = @($ADSGroupMbrOf | Sort-Object -Unique)
	}
	
	$ADSGroupPso = New-Object PSObject -Property @{
		CanonicalName		= $ADSGroup.CanonicalName
		DistinguishedName	= $ADSGroup.DistinguishedName
		Duplicated			= $false
        GroupScope			= $ADSGroup.GroupScope
		Member				= $ADSGroupMbr
		Name				= $ADSGroup.Name
		Overlimit			= $Overlimit
	}
	
	$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADSGroupPso)
	
	Console-ADSecurityGroupMemberOf $ADSGroupPso $RecursionLevel
	
	$next_RecursionLevel = $RecursionLevel + 1	
	
	foreach ($ADGroupDN in $ADSGroupMbrOf_NotFound)
	{	
		$Exists = $false
		
		foreach ($ADGroupPso in $ADGroupPsoCol)
		{
			if ($ADGroupPso.DistinguishedName -eq $ADGroupDN)
			{
				if ($ADGroupPso.Duplicated -eq $false)
				{
					$ADGroupPso.Duplicated = $true
				}
				
				Console-ADSecurityGroupMemberOf $ADGroupPso $next_RecursionLevel
				
				$Exists = $true
				
				break
			}
		}
		
		if (!$Exists)
		{
			$Index = $ADGroupDN.IndexOf("DC=")
		
			$ADGroupRDN = $ADGroupDN.Substring(0,$Index-1)
			$StrSplit = $ADGroupRDN -split "=|,"
			$ADGroupName = $StrSplit[1]
			
			$DomainName = $ADGroupDN.Substring($Index+3) -replace ",DC=","."
			$ADGroupCN = $DomainName.ToLower()

			for ($i=($StrSplit.Count)-1; $i -ge 1; $i-=2)
			{
				$ADGroupCN = $ADGroupCN + "/" + $StrSplit[$i]
			}
			
			$ADGroupPso = New-Object PSObject -Property @{
				CanonicalName		= $ADGroupCN
				DistinguishedName	= $ADGroupDN
				Duplicated			= $false
        		GroupScope			= 'Unknown'		
				MemberOf			= @()
				Name				= $ADGroupName
    		}
			
			$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADGroupPso)
			
			Console-ADSecurityGroupMemberOf $ADGroupPso $next_RecursionLevel
		}
	}
	
    if ($ADSGroupMbrOf -and $ADSGroupMbrOf_NotFound)
    {
        foreach ($ADGroupDN in $ADSGroupMbrOf)
		{
			if ([Array]::IndexOf($ADSGroupMbrOf_NotFound,$ADGroupDN) -eq -1)
			{
				$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
				$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
				$ADSGroup = Get-ADGroup $ADGroupDN -Properties CanonicalName -Server $GC
			
				DigC-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL $next_RecursionLevel
			}
    	}
	}
	elseif ($ADSGroupMbrOf)
	{
        foreach ($ADSGroupDN in $ADSGroupMbrOf)
		{
			$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroupDN -GC $ADForestGCPsoCol
			$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
			$ADSGroup = Get-ADGroup $ADSGroupDN -Properties CanonicalName -Server $GC
			
			DigC-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL $next_RecursionLevel
    	}
	}
}

function DigC-ADSecurityGroupMember
{
	param
	(  
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[ValidateScript({$_.GroupCategory -eq "Security"})] 
        [Microsoft.ActiveDirectory.Management.ADGroup] $ADSGroup,

		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("GC")]
        [PSObject[]] $ADForestGCPsoCol,

		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("RL")]		
		[Int] $RecursionLevel = 0,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Boolean] $Force	
    )
	
 	$ADSGroupMbrAll = @()
	$ADSGroupMbr =  @()
	$ADSGroupMbr_NotFound = @()
	
	if ($RecursionLevel -gt $MaxRecursionLevel)
	{
		$global:MaxRecursionLevel = $RecursionLevel
	}

	$Index = $ADSGroup.DistinguishedName.IndexOf("DC=")
	$DomainDN = $ADSGroup.DistinguishedName.Substring($Index)
	
	foreach ($ADObjPso in $ADObjPsoCol)
	{
		if ($ADObjPso.DistinguishedName -eq $ADSGroup.DistinguishedName)
		{	
			if ($ADObjPso.Duplicated -eq $false)
			{
				$ADObjPso.Duplicated = $true
			}
			
			Console-ADSecurityGroupMember $ADObjPso $RecursionLevel
			
			return
		}
    }
	
	$DC = (Get-ADGCOneForADObj -DN $ADSGroup.DistinguishedName -GC $ADForestGCPsoCol).HostName
	
	$Overlimit = $false
	$Ignore = $false
	
	try
	{
		$ADSGroupMbrAll = @(Get-ADGroupMember $ADSGroup.DistinguishedName -Server $DC |
			Where { $_.objectClass -eq 'group' } |
			Select DistinguishedName)
	}
	catch [Microsoft.ActiveDirectory.Management.ADException]
	{
		if ($_.Exception.ServerErrorMessage)
		{
			$Msg = ($_.Exception.ServerErrorMessage).Trim()
		}
		
		if ($Msg -eq "Exceeded groups or group members limit." -or $Msg -eq "The specified directory service attribute or value does not exist.")
		{			
			$Overlimit = $true
		}
		else
		{
			$Overlimit = $true
			$Ignore = $true
		}
	}
	catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
	{	
		$Overlimit = $true
		$Ignore = $true
	}
	catch
	{		
		$Overlimit = $true
		$Ignore = $true	
	}
	
	if(!$Ignore)
	{
		if(!$Overlimit)
		{
			foreach ($ADObj in $ADSGroupMbrAll)
			{
				$ADObjDN = $ADObj.DistinguishedName
			
				$DomainGCPso = Get-ADGCOneForADObj -DN $ADObjDN -GC $ADForestGCPsoCol
				$GC = $DomainGCPso.HostName
					
				$Index = $ADObjDN.IndexOf("DC=")
				$DomainDN = $ADObjDN.Substring($Index)
				
				$Path = 'GC://' + $GC + '/' + $DomainDN
				$Filter1 = '(&(distinguishedName=' + $ADObjDN + ')(groupType:1.2.840.113556.1.4.803:=2147483648))'
				$Filter2 = '(&(distinguishedName=' + $ADObjDN + '))'
				
				if(Test-ADObject -Path $Path -Filter $Filter1)
				{
					$ADSGroupMbr = $ADSGroupMbr + @($ADObjDN)
				}
				else
				{
					if(!(Test-ADObject -Path $Path -Filter $Filter2))
					{
						$ADSGroupMbr_NotFound = $ADSGroupMbr_NotFound + @($ADObjDN)
						$ADSGroupMbr = $ADSGroupMbr + @($ADObjDN)	
					}
				}
			}
		}
		elseif ($Overlimit -and $Force)
		{	
			$GC = $DC + ":" + $DomainGCPso.Port

			$LdapFilter = '(&(objectclass=group)(groupType:1.2.840.113556.1.4.803:=2147483648)(memberof:={0}))' -f $ADSGroup.DistinguishedName # only direct member unlike memberOf:1.2.840.113556.1.4.1941:=
				
			$ADSGroupMbrAll = Get-ADObject -LDAPFilter $LdapFilter -ResultSetSize $null -ResultPageSize 1000 -server $GC
					
			foreach ($ADSGrp in $ADSGroupMbrAll)
			{
				$ADSGroupMbr = $ADSGroupMbr + @($ADSGrp.DistinguishedName)
			}
		}
	}

	$ADSGroupPso = New-Object PSObject -Property @{
		CanonicalName		= $ADSGroup.CanonicalName
		DistinguishedName	= $ADSGroup.DistinguishedName
		Duplicated			= $false
        GroupScope			= $ADSGroup.GroupScope
		Member				= $ADSGroupMbr
		Name				= $ADSGroup.Name
		Overlimit			= $Overlimit
	}
	
	$global:ADObjPsoCol = $ADObjPsoCol + @($ADSGroupPso)
	
	Console-ADSecurityGroupMember $ADSGroupPso $RecursionLevel
	
	$next_RecursionLevel = $RecursionLevel + 1
	
	foreach ($ADObjDN in $ADSGroupMbr_NotFound)
	{	
		$Exists = $false
		
		foreach ($ADObjPso in $ADObjPsoCol)
		{
			if ($ADObjPso.DistinguishedName -eq $ADObjDN)
			{
				if ($ADObjPso.Duplicated -eq $false)
				{
					$ADObjPso.Duplicated = $true
				}
				
				Console-ADSecurityGroupMember $ADObjPso $next_RecursionLevel
				
				$Exists = $true

				break
			}
		}
		
		if (!$Exists)
		{	
			$Index = $ADObjDN.IndexOf("DC=")
			
			$ADObjRDN = $ADObjDN.Substring(0,$Index-1)
			$StrSplit = $ADObjRDN -split "=|,"
			$ADObjName = $StrSplit[1]
			
			$DomainName = $ADObjDN.Substring($Index+3) -replace ",DC=","."
			$ADObjCN = $DomainName.ToLower()

			for ($i=($StrSplit.Count)-1; $i -ge 1; $i-=2)
			{
				$ADObjCN = $ADObjCN + "/" + $StrSplit[$i]
			}
			
			$ADObjPso = New-Object PSObject -Property @{
				CanonicalName		= $ADObjCN
				DistinguishedName	= $ADObjDN
				Duplicated			= $false
        		GroupScope			= 'Unknown'
				Member				= @()
				Name				= $ADObjName
				Overlimit			= $false
    		}
			
			$global:ADObjPsoCol = $ADObjPsoCol + @($ADObjPso)
			
			Console-ADSecurityGroupMember $ADObjPso $next_RecursionLevel
		}
	}
	
    if ($ADSGroupMbr -and $ADSGroupMbr_NotFound)
    {
        foreach ($ADObjDN in $ADSGroupMbr)
		{
			if ([Array]::IndexOf($ADSGroupMbr_NotFound,$ADObjDN) -eq -1)
			{
				$DomainGCPso = Get-ADGCOneForADObj -DN $ADObjDN -GC $ADForestGCPsoCol
				$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
				$ADSGroup = Get-ADGroup $ADObjDN -Properties CanonicalName -Server $GC
			
				DigC-ADSecurityGroupMember $ADSGroup -GC $ADForestGCPsoCol -RL $next_RecursionLevel -Force $Force
			}
    	}
	}
	elseif ($ADSGroupMbr)
	{
        foreach ($ADSGroupDN in $ADSGroupMbr)
		{	
			$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroupDN -GC $ADForestGCPsoCol
			$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
			
			$ADSGroup = Get-ADGroup $ADSGroupDN -Properties CanonicalName -Server $GC
			
			DigC-ADSecurityGroupMember $ADSGroup -GC $ADForestGCPsoCol -RL $next_RecursionLevel -Force $Force
    	}
	}
}

function ListC-ADSecurityGroupMemberOf
{  
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[Alias("DN")]
		[String] $ADObjDN,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("GC")]
        [PSObject[]] $ADForestGCPsoCol,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("DGC")]
		[String] $DomainLocalColor = "Red",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("GGC")]
        [String] $GlobalColor = "Green",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UGC")]
        [String] $UniversalColor = "Cyan",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UOC")]
        [String] $UnknownObjColor = "Magenta",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
        [Alias("NGC")]
		[String] $NonGroupColor = $host.UI.RawUI.ForegroundColor		
		
    )
	
	$Console_ObjSummary = {
	
		param
		(
			$MaxRecursionLevel,
			$ADSGroupPsoCount,
			$ADSGroupPsoDupCount,		
			$ADTokenSize,		
			$UnknownPsoCount,
			$UnknownPsoDupCount
		)
		
		"{0,0}{1,26}" -f "Nesting Level:", $MaxRecursionLevel | Write-Host -ForegroundColor White
		"{0,0}{1,19}" -f "Known Group(s) Count:", $ADSGroupPsoCount | Write-Host -ForegroundColor White
		"{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $ADSGroupPsoDupCount | Write-Host -ForegroundColor White
		"{0,0}{1,19} bytes`n" -f "Estimated Token Size:", $ADTokenSize | Write-Host -ForegroundColor White
		
		"{0,0}{1,17}" -f "Unknown Group(s) Count:", $UnknownPsoCount | Write-Host -ForegroundColor White
		"{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $UnknownPsoDupCount | Write-Host -ForegroundColor White
		
		"{0}" -f "GroupName" | Write-Host -ForegroundColor $GlobalColor -NoNewline
		"{0,-19}{1}" -f ":", "Global Group" | Write-Host -ForegroundColor White
		"{0}" -f "GroupName" | Write-Host -ForegroundColor $DomainLocalColor -NoNewline
		"{0,-19}{1}" -f ":", "Domain Local Group" | Write-Host -ForegroundColor White
		"{0}" -f "GroupName" | Write-Host -ForegroundColor $UniversalColor -NoNewline
		"{0,-19}{1}" -f ":", "Universal Group" | Write-Host -ForegroundColor White
		"{0}" -f "GroupName" | Write-Host -ForegroundColor $UnknownObjColor -NoNewline
		"{0,-19}{1}" -f ":", "GroupType/Scope unknown due to ACL restriction" | Write-Host -ForegroundColor White
		"{0,-28}{1}" -f "Color Filled:", "Nesting issue" | Write-Host -ForegroundColor White -NoNewline
		
		$global:TreeViewData += ("`n{0,0}{1,26}`n" -f "Nesting Level:", $MaxRecursionLevel)
		$global:TreeViewData += ("{0,0}{1,19}`n" -f "Known Group(s) Count:", $ADSGroupPsoCount)		
		$global:TreeViewData += ("{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $ADSGroupPsoDupCount)
		$global:TreeViewData += ("{0,0}{1,19} bytes`n" -f "Estimated Token Size:", $ADTokenSize)			

		$global:TreeViewData += ("{0,0}{1,17}`n" -f "Unknown Group(s) Count:", $UnknownPsoCount)
		$global:TreeViewData += ("{0,0}{1,13}`n`n" -f "Nesting Potential Issue(s):", $UnknownPsoDupCount)
	
		$global:TreeViewData += ("'*G*': Global Group`n")
		$global:TreeViewData += ("'*DL*': Domain Local Group`n")
		$global:TreeViewData += ("'*U*': Universal Group`n")
		$global:TreeViewData += ("'*Unknown*': GroupType/Scope unknown due to ACL restriction`n")
		$global:TreeViewData += ("'!: *GroupScope* GroupName': Nesting issue`n`n")
	}
	
	$DomainGCPso = Get-ADGCOneForADObj -DN $ADObjDN -GC $ADForestGCPsoCol
	$DomainGC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
	
	$ADObj = Get-ADObject $ADObjDN -Properties CanonicalName,GroupType -Server $DomainGC
	
	$global:MaxRecursionLevel = 0
	
	switch ($ADObj)
	{
		{($_.ObjectClass -eq "group") -and ($_.GroupType -like "-2*")}
		{
			Get-ADGroup $ADObjDN -Properties CanonicalName -Server $DomainGC |
			DigC-ADSecurityGroupMemberOf -GC $ADForestGCPsoCol -RL 0
			
			Write-Host
			
			Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }) -For $ADObj.CanonicalName -By "MemberOf"
			
			$ADSGroupPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }).Count
			$ADSGroupPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -ne "Unknown" }).Count
			$ADTokenSize = Measure-ADTokenSize @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }) -DN $ADObjDN			
			
			$UnknownPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }).Count
			$UnknownPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -eq "Unknown" }).Count
			
			if ($UnknownPsoCount)
			{
				Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }) -For $ADObj.CanonicalName -By "MemberOf"
			}
			
			&$Console_ObjSummary $MaxRecursionLevel $ADSGroupPsoCount $ADSGroupPsoDupCount $ADTokenSize $UnknownPsoCount $UnknownPsoDupCount
			
			Write-Host
			
			break
		}
		
		{($_.ObjectClass -eq "computer")}
		{
			$ADComputer = Get-ADComputer $ADObjDN -Properties CanonicalName,PrimaryGroup -Server $DomainGC
			
			$Index = $ADComputer.DistinguishedName.IndexOf("DC=")
			$DomainDN = $ADComputer.DistinguishedName.Substring($Index)
			
			$ADComputerMbrOf = @()
			$ADComputerMbrOf_NotFound = @()
			
    		foreach ($ADForestGCPso in $ADForestGCPsoCol)
			{
				$GC = $ADForestGCPso.HostName + ":" + $ADForestGCPso.Port
				
				foreach ($ADGroupDN in (Get-ADComputer $ADComputer.DistinguishedName -Properties MemberOf -Server $GC).MemberOf)
				{
					$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
					$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
				
					try
					{	
						$ADGroup = Get-ADGroup $ADGroupDN -Server $GC
					}
					catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
					{	
						$ADComputerMbrOf_NotFound = $ADCompterMbrOf_NotFound + @($ADGroupDN)
						$ADComputerMbrOf = $ADComputerMbrOf + @($ADGroupDN)
					
						continue
					}
			
					if ($ADGroup.GroupCategory -eq "Security")
					{
						$ADComputerMbrOf = $ADComputerMbrOf + @($ADGroupDN)
					}
				}
			}
			
			$ADObjPso = New-Object PSObject -Property @{
				Name				= $ADComputer.Name
				CanonicalName		= $ADComputer.CanonicalName
				DistinguishedName	= $ADComputer.DistinguishedName
    			GroupScope			= "None"
    			MemberOf			= $ADComputerMbrOf
				Duplicated			= $false
			}
			
			$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADObjPso)
			
			Console-ADSecurityGroupMemberOf $ADObjPso 0			
			
			$ADComputerMbrOf_NotFound = @($ADComputerMbrOf_NotFound | Sort-Object -Unique)		
			
			foreach ($ADGroupDN in $ADComputerMbrOf_NotFound)
			{	
				$Index = $ADGroupDN.IndexOf("DC=")
				
				$ADGroupRDN = $ADGroupDN.Substring(0,$Index-1)
				$StrSplit = $ADGroupRDN -split "=|,"
				$ADGroupName = $StrSplit[1]
				
				$DomainName = $ADGroupDN.Substring($Index+3) -replace ",DC=","."
				$ADGroupCN = $DomainName.ToLower()

				for ($i=($StrSplit.Count)-1; $i -ge 1; $i-=2)
				{
					$ADGroupCN = $ADGroupCN + "/" + $StrSplit[$i]
				}
				
				$ADGroupPso = New-Object PSObject -Property @{
					CanonicalName		= $ADGroupCN
					DistinguishedName	= $ADGroupDN
					Duplicated			= $false
	        		GroupScope			= 'Unknown'		
					MemberOf			= @()
					Name				= $ADGroupName
	    		}
				
				$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADGroupPso)
				
				Console-ADSecurityGroupMemberOf $ADGroupPso 1
			}
			
			$ADComputerMbrOf = @($ADComputerMbrOf | Sort-Object -Unique)
			$ADComputerMbrOf = $ADComputerMbrOf + @($ADComputer.PrimaryGroup)
			
			if ($ADComputerMbrOf_NotFound)
    		{
				foreach ($ADGroupDN in $ADComputerMbrOf)
				{
					if ([Array]::IndexOf($ADComputerMbrOf_NotFound,$ADGroupDN) -eq -1)
					{
						$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
						$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
						
						$ADSGroup = Get-ADGroup $ADGroupDN -Properties CanonicalName -Server $GC
						
						DigC-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL 1
					}
	    		}
			}
			else
			{
				foreach ($ADSGroupDN in $ADComputerMbrOf)
				{
					$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroupDN -GC $ADForestGCPsoCol
					$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
				
					$ADSGroup = Get-ADGroup $ADSGroupDN -Properties CanonicalName -Server $GC
					
					DigC-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL 1
	    		}			
			}
			
			Write-Host
			
			Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }) -For $ADComputer.CanonicalName -By "MemberOf"
			
			$ADSGroupPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -notmatch "None|Unknown" }).Count
			$ADSGroupPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -ne "Unknown" }).Count
			$ADTokenSize = Measure-ADTokenSize @($ADGroupPsoCol | Where { $_.GroupScope -notmatch "None|Unknown" }) -DN $ADObjDN			
			
			$UnknownPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }).Count
			$UnknownPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -eq "Unknown" }).Count
			
			if ($UnknownPsoCount)
			{
				Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }) -For $ADObj.CanonicalName -By "MemberOf"
			}
			
			&$Console_ObjSummary $MaxRecursionLevel $ADSGroupPsoCount $ADSGroupPsoDupCount $ADTokenSize $UnknownPsoCount $UnknownPsoDupCount
			
			Write-Host
			
			break
		}
		
		{($_.ObjectClass -eq "user") -or ($_.ObjectClass -eq "inetOrgPerson")}
		{
			$ADUser = Get-ADUser $ADObjDN -Properties CanonicalName,PrimaryGroup -Server $DomainGC
			
			$Index = $ADUser.DistinguishedName.IndexOf("DC=")
			$DomainDN = $ADUser.DistinguishedName.Substring($Index)
			
			$ADUserMbrOf = @()
			$ADUserMbrOf_NotFound = @()
			
    		foreach ($ADForestGCPso in $ADForestGCPsoCol)
			{
				$GC = $ADForestGCPso.HostName + ":" + $ADForestGCPso.Port
				
				foreach ($ADGroupDN in (Get-ADUser $ADUser.DistinguishedName -Properties MemberOf -Server $GC).MemberOf)
				{
					$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
					$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
				
					try
					{	
						$ADGroup = Get-ADGroup $ADGroupDN -Server $GC
					}
					catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
					{
						$ADUserMbrOf_NotFound = $ADUserMbrOf_NotFound + @($ADGroupDN)
						$ADUserMbrOf = $ADUserMbrOf + @($ADGroupDN)
					
						continue
					}
			
					if ($ADGroup.GroupCategory -eq "Security")
					{
						$ADUserMbrOf = $ADUserMbrOf + @($ADGroupDN)
					}
				}
			}
			
			$ADObjPso = New-Object PSObject -Property @{
				Name				= $ADUser.Name
				CanonicalName		= $ADUser.CanonicalName
				DistinguishedName	= $ADUser.DistinguishedName
    			GroupScope			= "None"
    			MemberOf			= $ADUserMbrOf
				Duplicated			= $false
			}
			
			$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADObjPso)			

			Console-ADSecurityGroupMemberOf $ADObjPso 0			
			
			$ADUserMbrOf_NotFound = @($ADUserMbrOf_NotFound | Sort-Object -Unique)		
			
			foreach ($ADGroupDN in $ADUserMbrOf_NotFound)
			{	
				$Index = $ADGroupDN.IndexOf("DC=")
				
				$ADGroupRDN = $ADGroupDN.Substring(0,$Index-1)
				$StrSplit = $ADGroupRDN -split "=|,"
				$ADGroupName = $StrSplit[1]
				
				$DomainName = $ADGroupDN.Substring($Index+3) -replace ",DC=","."
				$ADGroupCN = $DomainName.ToLower()

				for ($i=($StrSplit.Count)-1; $i -ge 1; $i-=2)
				{
					$ADGroupCN = $ADGroupCN + "/" + $StrSplit[$i]
				}
				
				$ADGroupPso = New-Object PSObject -Property @{
					CanonicalName		= $ADGroupCN
					DistinguishedName	= $ADGroupDN
					Duplicated			= $false
	        		GroupScope			= 'Unknown'		
					MemberOf			= @()
					Name				= $ADGroupName
	    		}
				
				$global:ADGroupPsoCol = $ADGroupPsoCol + @($ADGroupPso)
				
				Console-ADSecurityGroupMemberOf $ADGroupPso 1
			}
			
			$ADUserMbrOf = @($ADUserMbrOf | Sort-Object -Unique)
			$ADUserMbrOf = $ADUserMbrOf + @($ADUser.PrimaryGroup)			
			
			if ($ADUserMbrOf_NotFound)
    		{
				foreach ($ADGroupDN in $ADUserMbrOf)
				{
					if ([Array]::IndexOf($ADUserMbrOf_NotFound,$ADGroupDN) -eq -1)
					{
						$DomainGCPso = Get-ADGCOneForADObj -DN $ADGroupDN -GC $ADForestGCPsoCol
						$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
						
						$ADSGroup = Get-ADGroup $ADGroupDN -Properties CanonicalName -Server $GC
						
						DigC-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL 1
					}
	    		}
			}
			else
			{
				foreach ($ADSGroupDN in $ADUserMbrOf)
				{
					$DomainGCPso = Get-ADGCOneForADObj -DN $ADSGroupDN -GC $ADForestGCPsoCol
					$GC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
				
					$ADSGroup = Get-ADGroup $ADSGroupDN -Properties CanonicalName -Server $GC
					
					DigC-ADSecurityGroupMemberOf $ADSGroup -GC $ADForestGCPsoCol -RL 1
	    		}			
			}
			
			Write-Host
			
			Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -ne "Unknown" }) -For $ADUser.CanonicalName -By "MemberOf"
			
			$ADSGroupPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -notmatch "None|Unknown" }).Count
			$ADSGroupPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -ne "Unknown" }).Count
			$ADTokenSize = Measure-ADTokenSize @($ADGroupPsoCol | Where { $_.GroupScope -notmatch "None|Unknown" }) -DN $ADObjDN			
			
			$UnknownPsoCount = @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }).Count
			$UnknownPsoDupCount = @($ADGroupPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -eq "Unknown" }).Count
			
			if ($UnknownPsoCount)
			{
				Get-ADObjDuplicated @($ADGroupPsoCol | Where { $_.GroupScope -eq "Unknown" }) -For $ADObj.CanonicalName -By "MemberOf"
			}
			
			&$Console_ObjSummary $MaxRecursionLevel $ADSGroupPsoCount $ADSGroupPsoDupCount $ADTokenSize $UnknownPsoCount $UnknownPsoDupCount
			
			Write-Host
			
			break
		}
		
		default
		{
			$Msg = 'SCRIPT ABORTED.'
			$Msg += "`n" + 'Please select a Security Group, a User or a Computer.'
			Write-Warning $Msg
		}
	}
}

function ListC-ADSecurityGroupMember
{  
	param
	(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[Alias("DN")]
		[String] $ADObjDN,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[String] $Mode,
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Boolean] $Force,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
		[Alias("GC")]
        [PSObject[]] $ADForestGCPsoCol,		
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("DGC")]
		[String] $DomainLocalColor = "Red",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("GGC")]
        [String] $GlobalColor = "Green",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UGC")]
        [String] $UniversalColor = "Cyan",
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("UOC")]
        [String] $UnknownObjColor = "Magenta"
    )

	$Console_ObjSummary = {
	
		param
		(
			$MaxRecursionLevel,
			$ADSGroupPsoCount,	
			$ADSGroupPsoDupCount,
			$UnknownPsoCount,
			$UnknownPsoDupCount,
			$OverlimitPsoCount,
			$Mode
		)
		
		"{0,0}{1,26}" -f "Nesting Level:", $MaxRecursionLevel | Write-Host -ForegroundColor White
		"{0,0}{1,19}" -f "Known Group(s) Count:", $ADSGroupPsoCount | Write-Host -ForegroundColor White
		"{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $ADSGroupPsoDupCount | Write-Host -ForegroundColor White
		
		"{0,0}{1,16}" -f "Unknown Object(s) Count:", $UnknownPsoCount | Write-Host -ForegroundColor White
		"{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $UnknownPsoDupCount | Write-Host -ForegroundColor White
		
		"{0,0}{1,13}`n" -f "Group Enumeration Error(s):", $OverlimitPsoCount | Write-Host -ForegroundColor White	
		
		"{0}" -f "GroupName" | Write-Host -ForegroundColor $GlobalColor -NoNewline
		"{0,-19}{1}" -f ":", "Global Group" | Write-Host -ForegroundColor White
		"{0}" -f "GroupName" | Write-Host -ForegroundColor $DomainLocalColor -NoNewline
		"{0,-19}{1}" -f ":", "Domain Local Group" | Write-Host -ForegroundColor White
		"{0}" -f "GroupName" | Write-Host -ForegroundColor $UniversalColor -NoNewline
		"{0,-19}{1}" -f ":", "Universal Group" | Write-Host -ForegroundColor White
		"{0}" -f "GroupName" | Write-Host -ForegroundColor $UnknownObjColor -NoNewline
		"{0,-19}{1}" -f ":", "ObjectType/GroupScope unknown due to ACL restriction" | Write-Host -ForegroundColor White
		"{0,-28}{1}" -f "Color Filled:", "Nesting issue" | Write-Host -ForegroundColor White
		if ($Mode -eq "Domain" )
		{		
			$Legend = "Member enumeration issue due to ADWS limitation, ACL restriction or because user targeted exploration to source Domain only"
		}
		else
		{
			$Legend = "Member enumeration issue due to ADWS limitation or ACL restriction"
		}
		"{0,-28}{1}" -f "'>> GroupName <<':", $Legend | Write-Host -ForegroundColor White -NoNewline
		
		$global:TreeViewData += ("`n{0,0}{1,26}`n" -f "Nesting Level:", $MaxRecursionLevel)
		$global:TreeViewData += ("{0,0}{1,19}`n" -f "Known Group(s) Count:", $ADSGroupPsoCount)
		$global:TreeViewData += ("{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $ADSGroupPsoDupCount)

		$global:TreeViewData += ("{0,0}{1,16}`n" -f "Unknown Object(s) Count:", $UnknownPsoCount)
		$global:TreeViewData += ("{0,0}{1,13}`n" -f "Nesting Potential Issue(s):", $UnknownPsoDupCount)

		$global:TreeViewData += ("{0,0}{1,13}`n`n" -f "Group Enumeration Error(s):", $OverlimitPsoCount)		
		
		$global:TreeViewData += ("'*G*': Global Group`n")
		$global:TreeViewData += ("'*DL*': Domain Local Group`n")
		$global:TreeViewData += ("'*U*': Universal Group`n")
		$global:TreeViewData += ("'*Unknown*': ObjectType/GroupScope unknown due to ACL restriction`n")
		$global:TreeViewData += ("'!: *GroupScope* GroupName': Nesting issue`n")
		$global:TreeViewData += ("'>> GroupName <<': $Legend`n`n")
	}
	
	$DomainGCPso = Get-ADGCOneForADObj -DN $ADObjDN -GC $ADForestGCPsoCol
	$DomainGC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
	
	$ADObj = Get-ADObject $ADObjDN -Properties CanonicalName,GroupType -Server $DomainGC
	
	$global:MaxRecursionLevel = 0	
	
	switch ($ADObj)
	{	
		{($_.ObjectClass -eq "group") -and ($_.GroupType -like "-2*")}
		{
			Get-ADGroup $ADObjDN -Properties CanonicalName -Server $DomainGC |
			DigC-ADSecurityGroupMember -GC $ADForestGCPsoCol -RL 0 -Force $Force
			
			Write-Host
			
			Get-ADObjDuplicated @($ADObjPsoCol | Where { $_.GroupScope -ne "Unknown" }) -For $ADObj.CanonicalName -By "Member"
			
			$ADSGroupPsoCount = @($ADObjPsoCol | Where { $_.GroupScope -ne "Unknown" }).Count
			$ADSGroupPsoDupCount = @($ADObjPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -ne "Unknown" }).Count		
			
			$UnknownPsoCount = @($ADObjPsoCol | Where { $_.GroupScope -eq "Unknown" }).Count
			$UnknownPsoDupCount = @($ADObjPsoCol | Where { $_.Duplicated -eq $true -and $_.GroupScope -eq "Unknown" }).Count
			
			if ($UnknownPsoCount)
			{
				Get-ADObjDuplicated @($ADObjPsoCol | Where { $_.GroupScope -eq "Unknown" }) -For $ADObj.CanonicalName -By "Member"
			}
			
			$OverlimitPsoCount = @($ADObjPsoCol | Where { $_.Overlimit -eq $true }).Count
			
			&$Console_ObjSummary $MaxRecursionLevel $ADSGroupPsoCount $ADSGroupPsoDupCount $UnknownPsoCount $UnknownPsoDupCount $OverlimitPsoCount $Mode
			
			Write-Host
			
			break
		}

		default
		{
			$Msg = 'SCRIPT ABORTED.'
			$Msg += "`n" + 'Please select a Security Group.' 
			Write-Warning $Msg
		}
	}
}

function Draw-ADSecurityGroupNesting
{
	<#   
	.SYNOPSIS
	Draw Active Directory Security Group Nesting.
	 
	.DESCRIPTION
	The Draw-ADSecurityGroupNesting cmdlet explores Group "memberOf" back-link or "member" attributes over one Domain or entire Forest, then generates a Graphviz or a 'tree' like Text file. The cmdlet is useful to:
	- view Nested Security Groups;
	- search Circular Nesting;
	- check Security Group Nesting Strategy (ie: G.U.DL.);
	- assess User Kerberos Token Size.	

	.PARAMETER ADObjDN_List
	Alias: DN
	One object "distinguishedName" or a list of.

	.PARAMETER Scope
	Alias: SC
	"Onelevel" or "Subtree".
	Using "Graph" view, if you explore Container or Organizational Unit, you can choose to draw only direct children Security Groups or to draw descendants all the way down to last child container.		

	.PARAMETER ADGCPort
	Alias: Port
	No need to use that parameter, it is reserved for future cmdlet version.

	.PARAMETER View
	"Graph" or "Console".
	The cmdlet outputs a GraphViz file (.viz) for gvedit.exe (GUI) and dot.exe (console). Or outputs console tree view plus Text file (.txt) for advanced text editor like Notepad++.

	.PARAMETER Charset
	Alias: CS
	"ASCII" or "UTF8".
	ASCII is the only compliant encoding for GraphViz console application dot.exe.

	.PARAMETER Folder
	Alias: FD
	Folder full path where the cmdlet saves file output.

	.PARAMETER SaveGCList
	$False or $True.	
	Alias: SGCL
	The cmdlet saves Global Catalog list file to "$Folder\ADForestGCList.csv". If set to $False, Global Catalog discovery occurs at next run without prompt.	

	.PARAMETER Force
	$False or $True.
	Using "member" attribute exploration (-Member), the cmdlet ignores Security Group members if count exceeds MaxGroupOrMemberEntries (default is 5 000). With Force parameter set to $True, the cmdlet falls back to best effort enumeration.

	.NOTES
	Name: Draw-ADSecurityGroupNesting.ps1
	Author: Axel Limousin
	Version: 3.0		

	.EXAMPLE

	Draw-ADSecurityGroupNesting -MemberOf

	The cmdlet explores Nesting for all Security Group descendants of Users Container, on the source Domain only, using "memberOf" back-link atttribute. It outputs only one graphviz file, "UTF8" encoded and saved on user desktop.

	.EXAMPLE

	Draw-ADSecurityGroupNesting -DN (Get-ADUser "MyUser").DistinguishedName -Mode "Forest" -MemberOf

	The cmdlet explores "MyUser" Security Group Nesting over the Forest. It outputs one GraphViz file, "UTF8" encoded.

	.EXAMPLE

	Draw-ADSecurityGroupNesting -DN (Get-ADGroup "MyGroup").DistinguishedName -Mode "Forest" -View "Graph" -Charset "ASCII" -MemberOf

	The cmdlet explores "MyGroup" Security Group Nesting over the Forest, using "memberOf" back-link atttribute. It outputs one GraphViz file, "ASCII" encoded, so compliant with dot.exe.				

	.EXAMPLE

	Draw-ADSecurityGroupNesting -DN (Get-ADComputer "MyComputer").DistinguishedName -View "Console" -MemberOf

	The cmdlet explores "MyComputer" Security Group Nesting on the source Domain only. It outputs console tree view and one Text file, "UTF8" encoded.		

	.EXAMPLE

	Draw-ADSecurityGroupNesting -DN @((Get-ADUser "MyUser1").DistinguishedName, (Get-ADUser "MyUser2").DistinguishedName) -Mode "Forest" -View "Console" -MemberOf

	The cmdlet explores "MyUser1" and "MyUser2" Security Group Nesting over the source Forest. For each User, it outputs console tree view and one Text file, "UTF8" encoded.

	.EXAMPLE

	Draw-ADSecurityGroupNesting -DN (Get-ADGroup "MyGroup").DistinguishedName -Charset "ASCII" -Member

	The cmdlet explores "MyGroup" Security Group Nesting on the source Domain only, using "member" atttribute. It outputs one GraphViz file, "ASCII" encoded, so compliant with dot.exe.

	Warning: ADWS Limitations
	If one or more groups contains more than 5 000 members, request may be TIME & RESOURCE CONSUMING, may time out or exceed size limit. If so, prefer drawing using memberOf attribute (-MemberOf).
	For further information, please refer to "ADWS configuration" and "MaxGroupOrMemberEntries" default value: http://technet.microsoft.com/en-us/library/dd391908%28WS.10%29.aspx.

	.EXAMPLE

	Draw-ADSecurityGroupNesting -DN (Get-ADGroup "MyGroup").DistinguishedName -Mode "Forest" -Member -Force $True

	The cmdlet explores "MyGroup" Security Group Nesting over the Forest, using "member" atttribute. If member enumeration fails because of ADWS limitations, the script falls back to best effort exploration. It outputs one GraphViz file, "UTF8" encoded.

	Warning: ADWS Limitations
	If one or more groups contains more than 5 000 members, request may be TIME & RESOURCE CONSUMING, may time out or exceed size limit. If so, prefer drawing using memberOf attribute (-MemberOf).
	For further information, please refer to "ADWS configuration" and "MaxGroupOrMemberEntries" default value: http://technet.microsoft.com/en-us/library/dd391908%28WS.10%29.aspx.

	.EXAMPLE

	Draw-ADSecurityGroupNesting -DN (Get-ADGroup "MyGroup").DistinguishedName -Mode "Forest" -View "Console" -Member

	The cmdlet explores "MyGroup" Security Group Nesting over the Forest, using "member" atttribute. It outputs console tree view and one Text file, "UTF8" encoded.

	Warning: ADWS Limitations
	If one or more groups contains more than 5 000 members, request may be TIME & RESOURCE CONSUMING, may time out or exceed size limit. If so, prefer drawing using memberOf attribute (-MemberOf).
	For further information, please refer to "ADWS configuration" and "MaxGroupOrMemberEntries" default value: http://technet.microsoft.com/en-us/library/dd391908%28WS.10%29.aspx.

	.LINK

	https://gallery.technet.microsoft.com/scriptcenter/Graph-Nested-AD-Security-eaa01644
	#>
	#Requires -Version 2.0
	
	[CmdletBinding()]
	
	param
	(
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("DN")]
		[String[]] $ADObjDN_List = @((Get-ADDomain).UsersContainer),
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
        [Alias("SC")]
		[Microsoft.ActiveDirectory.Management.ADSearchScope] $Scope = "Subtree",
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[ValidateSet("Domain","Forest")]
		[String] $Mode = "Domain",

		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[ValidateSet("3268","3269")]
		[Alias("Port")]
		[String] $ADGCPort = "3268",		
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[ValidateSet("Graph","Console")]
		[String] $View = "Graph",
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[ValidateSet("ASCII","UTF8")]
		[Alias("CS")]
		[String] $Charset = "UTF8",
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[ValidateScript({Test-Path $_ -PathType 'Container'})]
		[Alias("FD")]
		[String] $Folder = "$env:USERPROFILE\Desktop",
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false)]
		[Alias("SGCL")]
		[Boolean] $SaveGCList = $true,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false, ParameterSetName = "Set 1")]
		[Switch] $MemberOf,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false, ParameterSetName = "Set 2")]
		[Switch] $Member,
		
		[Parameter(ValueFromPipeline = $false, Mandatory = $false, ParameterSetName = "Set 2")]
		[Boolean] $Force = $false
    )
	
	if($MemberOf.IsPresent)
	{
		$Property = "MemberOf"
	}
	else
	{
		$Property = "Member"
	}
	
	if ($Folder -ne "$env:USERPROFILE\Desktop")
	{
		$Folder = Remove-LastBackSlash $Folder
	}
	
	$global:VizPath = $null
	$global:TreeViewData = $null
	
	$Ending = {
	
		param
		(
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[String] $ADObjDN,
			
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[String] $View,
			
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[String] $Charset,
			
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[String] $Folder,
			
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			$DrawData,
			
			[Parameter(ValueFromPipeline = $false, Mandatory = $true)]
			[String] $Remove
		)
		
		$Msg = "`n" + 'Ending'
		Write-Host $Msg -Foregroundcolor Green -Backgroundcolor DarkBlue

		#Remove-Variable -Name $Remove, MaxRecursionLevel -Scope Global

		$ADObj = Get-ADObject $ADObjDN -Properties name,canonicalName -Server $DomainGC
		$Index = ($ADObj.CanonicalName).IndexOf("/")
		$ADObjDomainFQDN = ($ADObj.CanonicalName).Substring(0,$Index)

		$FileName = $ADObj.Name + "_" + $ADObjDomainFQDN + "_" + $Property + "_" + $Mode

		if ($View -eq 'Graph')
		{
			$global:VizPath = $Folder + '\' + $FileName + '.viz'

			$DrawData | Out-File -FilePath $VizPath -Encoding $Charset

			$Msg = "`n" + 'GraphViz file to use with dot.exe or gvedit.exe is "' + $VizPath + '".' + "`n"
		}
		else
		{
			$global:TxtPath = $Folder + '\' + $FileName + '.txt'

			$DrawData | Out-File -FilePath $TxtPath -Encoding $Charset

			$Msg = "`n" + 'Group Nesting Tree View is saved in "' + $TxtPath + '".' + "`n"
		}
		
		Write-Host $Msg -Foregroundcolor White
	}
	
	$Msg = "`nInitialization"
	Write-Host $Msg -Foregroundcolor Green -Backgroundcolor DarkBlue
	
	:nextDN foreach ($ADObjDN in $ADObjDN_List)
	{	
		try
		{	
			$Index = $ADObjDN.IndexOf("DC=")
			$DomainDN = $ADObjDN.Substring($Index)
		
			$Path = 'LDAP://' + $ADObjDN
			$Filter = '(&(distinguishedName=' + $ADObjDN + '))'
		
			Test-ADObject -Path $Path -Filter $Filter -SC 'Base' | Out-Null
		}
		catch
		{
			Write-Host ""
			$Msg = 'Non terminating error on "' + $ADObjDN + '".'
			$Msg += "`nObject does not exist, under ACL restriction or DistinguishedName is mistyped, it will be ignored in processing step."
			Write-Warning $Msg
			
			continue nextDN
		}
		
		$Index = $ADObjDN.IndexOf("DC=")
		$ADDomainFQDN = ($ADObjDN.Substring($Index)).Replace("DC=","").Replace(",",".")
		
		$ADDomainFQDN_List = $ADDomainFQDN_List + @($ADDomainFQDN)
		
		$ADObjDN_List_Checked = $ADObjDN_List_Checked + @($ADObjDN)
	}
	
	if ($ADObjDN_List_Checked)
	{
		$ADDomainFQDN_List = $ADDomainFQDN_List | Select -Unique
	
		if ($Mode -eq "Domain")
		{
			$ADGCPsoCol = List-ADGCOnePerDomainReachable -FQDN $ADDomainFQDN_List -Port $ADGCPort -Path $Folder -CS $Charset -SGCL $SaveGCList
		}
		else
		{
			$ADDomainFQDN_List = (Get-ADForest).Domains
				
			$ADGCPsoCol = List-ADGCOnePerDomainReachable -FQDN $ADDomainFQDN_List -Port $ADGCPort -Path $Folder -CS $Charset -SGCL $SaveGCList
		}
		
		if (!$ADGCPsoCol)
		{
			$Msg = "SCRIPT ABORTED."
			$Msg += "`nBe sure that at least one Global Catalog in each Domain responds and that Global Catalog list is well formed."
			$Msg += "`nYou should flush and rediscover Global Catalog list."
			Write-Warning $Msg
		
			return
		}
		
		:nextObj foreach ($ADObjDN in $ADObjDN_List_Checked)
		{
			$DomainGCPso = Get-ADGCOneForADObj -DN $ADObjDN -GC $ADGCPsoCol
			$DomainGC = $DomainGCPso.HostName + ":" + $DomainGCPso.Port
		
			if ($Mode -eq "Domain")
			{
				$ADForestGCPsoCol = @($DomainGCPso)
			}
			else
			{
				$ADForestGCPsoCol = $ADGCPsoCol
			}
			
			$Msg = "`nProcessing"
			Write-Host $Msg -Foregroundcolor Green -Backgroundcolor DarkBlue
			$Msg = "`n" + 'Exploring security group nesting for "'+ $ADObjDN + '" using property "' + $Property + '":' + "`n"
			Write-Host $Msg -Foregroundcolor White
	
			if ($View -eq 'Graph')
			{
				$global:VizPath = $null			
			
				switch ($Property)
				{
					"MemberOf"
					{	
						$global:ADGroupPsoCol = @()						
						
						ListG-ADSecurityGroupMemberOf -DN $ADObjDN -SC $Scope.ToString() -GC $ADForestGCPsoCol
						
						if ($ADGroupPsoCol)
						{
							$VizViewData = Graph-ADSecurityGroupMemberOf $ADGroupPsoCol -DN $ADObjDN -SC $Scope.ToString() -Mode $Mode -CS $Charset
						
							&$Ending $ADObjDN $View $Charset $Folder $VizViewData 'ADGroupPsoCol'
						}
					}
		
					"Member"
					{
						$Msg = "`nIf a group contains more than 5 000 members and the script is runned without Force option, its members will be ignored."
						$Msg += "`nIf using Force option, processing may be TIME & RESOURCE CONSUMING and halt unexpectedly."
						$Msg += "`n" + 'For further information, please refer to "ADWS configuration" and "MaxGroupOrMemberEntries" default value:'
						$Msg += "`nhttp://technet.microsoft.com/en-us/library/dd391908%28WS.10%29.aspx`n`n"

						Write-Warning $Msg
						
						if ($Force)
						{
							$Msg = "If member enumeration fails, script will retry in best effort mode.`n"
							Write-Host $Msg -Foregroundcolor White
						}						

						$global:ADObjPsoCol = @()		
				
						ListG-ADSecurityGroupMember -DN $ADObjDN -SC $Scope.ToString() -Force $Force -GC $ADForestGCPsoCol
				
						if ($ADObjPsoCol)
						{
							$VizViewData = Graph-ADSecurityGroupMember $ADObjPsoCol -DN $ADObjDN -SC $Scope.ToString() -Mode $Mode -CS $Charset
							
							&$Ending $ADObjDN $View $Charset $Folder $VizViewData 'ADObjPsoCol'
						}
					}
				}
			
				if (!$VizPath)
				{
					$Msg = 'Found no valid object for "' + $Property + '" property exploration.'
					Write-Warning $Msg
				}
			}
			else
			{
				$global:TreeViewData = $null			
				
				switch ($Property)
				{
					"MemberOf"
					{
						$global:ADGroupPsoCol = @()					
					
						ListC-ADSecurityGroupMemberOf -DN $ADObjDN -GC $ADForestGCPsoCol
						
						if ($ADGroupPsoCol)
						{						
							&$Ending $ADObjDN $View $Charset $Folder $TreeViewData 'ADGroupPsoCol'
						}	
					}
		
					"Member"
					{						
						$Msg = "`nIf a group contains more than 5 000 members and the script is runned without Force option, its members will be ignored."
						$Msg += "`nIf using Force option, processing may be TIME & RESOURCE CONSUMING and halt unexpectedly."
						$Msg += "`n" + 'For further information, please refer to "ADWS configuration" and "MaxGroupOrMemberEntries" default value:'
						$Msg += "`nhttp://technet.microsoft.com/en-us/library/dd391908%28WS.10%29.aspx`n`n"

						Write-Warning $Msg
						
						if ($Force)
						{
							$Msg = "If member enumeration fails, script will retry in best effort mode.`n"
							Write-Host $Msg -Foregroundcolor White
						}						
						
						$global:ADObjPsoCol = @()					
					
						ListC-ADSecurityGroupMember -DN $ADObjDN -Mode $Mode -Force $Force -GC $ADForestGCPsoCol
						
						if ($ADObjPsoCol)
						{
							&$Ending $ADObjDN $View $Charset $Folder $TreeViewData 'ADObjPsoCol'
						}
					}
				}
				
				if (!$TxtPath)
				{
					$Msg = 'Found no valid object for "' + $Property + '" property exploration.'
					Write-Warning $Msg
				}
			}
		}
	}
	else
	{
		$Msg = "SCRIPT ABORTED."
		$Msg += "`nFound no valid DistinguishedName."
		Write-Warning $Msg
		
		return		
	}
}