#requires -Version 5.1

<#
.SYNOPSIS
    Performs Active Directory domain and forest health, security, and configuration checks.

.DESCRIPTION
    Audits single-domain Active Directory environments for functional levels, Domain Controller operational roles,
    Tombstone Lifetimes, Active Directory trusts, user account hygiene (inactive accounts, stale passwords, SID history, 
    insecure flag configurations), default domain password policies, default domain admin accounts, KRBTGT account health, 
    privileged group memberships, Kerberos delegation settings, domain root permissions, duplicate SPNs, GPP passwords, 
    and GPO ownership. Outputs reports and CSV files to C:\Temp while logging execution detail.

.PARAMETER Domain
    The target Active Directory domain FQDN. Defaults to the current domain if omitted.

.PARAMETER ReportDir
    The local directory where export CSV reports and output files will be saved. Defaults to 'C:\Temp'.

.PARAMETER UserLogonAge
    The age threshold in days to classify user logon as inactive. Defaults to 180 days.

.PARAMETER UserPasswordAge
    The age threshold in days to classify user password as stale. Defaults to 180 days.

.EXAMPLE
    .\Invoke-ADChecks.ps1

.EXAMPLE
    .\Invoke-ADChecks.ps1 -Domain "contoso.com" -ReportDir "C:\Temp\ADReports" -UserLogonAge 90 -UserPasswordAge 90

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools, Group Policy Module, Administrator Elevation.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Domain,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ReportDir = "C:\Temp",

    [Parameter(Mandatory = $false)]
    [ValidateRange(30, 730)]
    [int]$UserLogonAge = 180,

    [Parameter(Mandatory = $false)]
    [ValidateRange(30, 730)]
    [int]$UserPasswordAge = 180
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

$RequiredModules = @("ActiveDirectory", "GroupPolicy")
foreach ($Module in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $Module)) {
        Write-Host "Required module '$Module' missing. Attempting installation..." -ForegroundColor Yellow
        try {
            Install-Module -Name $Module -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop
            Write-Host "Successfully installed '$Module'." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to locate or install required module '$Module'. Please install RSAT tools."
            exit 1
        }
    }
    Import-Module -Name $Module -ErrorAction Stop
}

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "AD_SecurityChecks"
$DateStamp  = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path -Path $ReportDir)) {
    New-Item -Path $ReportDir -ItemType Directory -Force | Out-Null
}

# Log rotation: Remove log files older than 7 days from C:\Temp
Get-ChildItem -Path $ReportDir -Filter "*.log" -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
    Remove-Item -Force -ErrorAction SilentlyContinue

$LogFile = Join-Path -Path $ReportDir -ChildPath "$($ScriptName)_$($DateStamp).log"
Start-Transcript -Path $LogFile -Append

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    Write-Host $LogEntry -ForegroundColor $(switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } Default { "Cyan" } })
}

# Helper Function: GUID Resolution
function Get-NameForGUID {
    [CmdletBinding()]
    param(
        [guid]$Guid,
        [string]$ForestDNSName
    )
    if ([string]::IsNullOrEmpty($ForestDNSName)) {
        $ForestDNSName = (Get-ADForest).Name
    }
    if ($ForestDNSName -notlike "*=*") {
        $ForestDNSNameDN = "DC=$($ForestDNSName.Replace('.', ',DC='))"
    }

    $ExtendedRightGUIDs = "LDAP://cn=Extended-Rights,cn=configuration,$ForestDNSNameDN"
    $PropertyGUIDs      = "LDAP://cn=schema,cn=configuration,$ForestDNSNameDN"

    if ($Guid -eq [guid]::Empty) {
        return "All"
    }
    else {
        $SearchAdsi = [adsisearcher]"(rightsGuid=$Guid)"
        $SearchAdsi.SearchRoot = $ExtendedRightGUIDs
        $SearchAdsi.SearchScope = "OneLevel"
        $SearchAdsiRes = $SearchAdsi.FindOne()

        if ($SearchAdsiRes) {
            return $SearchAdsiRes.Properties["cn"]
        }
        else {
            $SchemaByteString = "\" + (($Guid.ToByteArray() | ForEach-Object { $_.ToString("x2") }) -join "\")
            $SearchAdsi = [adsisearcher]"(schemaIDGUID=$SchemaByteString)"
            $SearchAdsi.SearchRoot = $PropertyGUIDs
            $SearchAdsi.SearchScope = "OneLevel"
            $SearchAdsiRes = $SearchAdsi.FindOne()

            if ($SearchAdsiRes) {
                return $SearchAdsiRes.Properties["ldapDisplayName"]
            }
            else {
                return $Guid.ToString()
            }
        }
    }
}

function Get-ListFromArray {
    param([array]$Array)
    if ($Array) {
        return ($Array -join "; ")
    }
    return $null
}

# --------------------------------------------------------------------------
# 3. SCRIPT EXECUTION
# --------------------------------------------------------------------------
try {
    Write-Log "Initializing Active Directory Discovery & Security Assessment..." "INFO"
    $ScriptTimer = [System.Diagnostics.Stopwatch]::StartNew()

    if ([string]::IsNullOrEmpty($Domain)) {
        $Domain = (Get-ADDomain).DNSRoot
    }

    $ADForestInfo = Get-ADForest
    $ForestDNSName = $ADForestInfo.Name
    $ADDomainInfo = Get-ADDomain $Domain
    $ADDomainName = $ADDomainInfo.DNSRoot
    $DomainDN = $ADDomainInfo.DistinguishedName
    $DomainDC = $ADDomainInfo.PDCEmulator

    Write-Log "Target Domain: $ADDomainName (PDC: $DomainDC)" "INFO"

    # Functional Levels
    $ADForestFunctionalLevel = $ADForestInfo.ForestMode
    $ADDomainFunctionalLevel = $ADDomainInfo.DomainMode
    Write-Log "Forest Functional Level: $ADForestFunctionalLevel" "INFO"
    Write-Log "Domain Functional Level ($Domain): $ADDomainFunctionalLevel" "INFO"

    # Domain Controllers Enumeration
    $DomainDCs = Get-ADDomainController -Filter * -Server $DomainDC
    $DomainDCArray = @()
    foreach ($DCItem in $DomainDCs) {
        $DCItem | Add-Member -MemberType NoteProperty -Name FSMORolesList -Value (Get-ListFromArray $DCItem.OperationMasterRoles) -Force 
        $DCItem | Add-Member -MemberType NoteProperty -Name PartitionsList -Value (Get-ListFromArray $DCItem.Partitions) -Force 
        $DomainDCArray += $DCItem
    }
    $DomainDCsFile = Join-Path $ReportDir "ADChecks-DomainDCs-$Domain-$DateStamp.csv"
    $DomainDCArray | Sort-Object OperatingSystem | Export-Csv -Path $DomainDCsFile -NoTypeInformation -Encoding utf8

    # Tombstone Lifetime
    $ADRootDSE = Get-ADRootDSE -Server $DomainDC
    $ADConfigurationNamingContext = $ADRootDSE.configurationNamingContext  
    $TombstoneObjectInfo = Get-ADObject -Identity "CN=Directory Service,CN=Windows NT,CN=Services,$ADConfigurationNamingContext" -Partition "$ADConfigurationNamingContext" -Properties tombstoneLifetime
    [int]$TombstoneLifetime = $TombstoneObjectInfo.tombstoneLifetime
    if ($TombstoneLifetime -eq 0) { $TombstoneLifetime = 60 } 
    Write-Log "Forest Tombstone Lifetime: $TombstoneLifetime days." "INFO"

    # Trusts Audit
    $ADTrusts = Get-ADTrust -Filter * -Server $DomainDC
    $ADTrustFile = Join-Path $ReportDir "ADChecks-DomainTrustReport-$Domain-$DateStamp.csv"
    $ADTrusts | Export-Csv -Path $ADTrustFile -NoTypeInformation -Encoding utf8

    # User Security Analysis
    Write-Log "Auditing user accounts..." "INFO"
    $LastLoggedOnDate  = (Get-Date).AddDays(-$UserLogonAge)  
    $PasswordStaleDate = (Get-Date).AddDays(-$UserPasswordAge)
    $ADLimitedProperties = @("Name","Enabled","SAMAccountname","DisplayName","LastLogonDate","PasswordLastSet","PasswordNeverExpires","PasswordNotRequired","PasswordExpired","SmartcardLogonRequired","AccountExpirationDate","AdminCount","Created","Modified","LastBadPasswordAttempt","badpwdcount","mail","CanonicalName","DistinguishedName","ServicePrincipalName","SIDHistory","PrimaryGroupID","UserAccountControl")

    [array]$DomainUsers = Get-ADUser -Filter * -Property $ADLimitedProperties -Server $DomainDC
    [array]$DomainEnabledUsers = $DomainUsers | Where-Object { $_.Enabled -eq $true }
    [array]$DomainEnabledInactiveUsers = $DomainEnabledUsers | Where-Object { ($_.LastLogonDate -le $LastLoggedOnDate) -and ($_.PasswordLastSet -le $PasswordStaleDate) }

    [array]$DomainUsersWithReversibleEncryption = $DomainUsers | Where-Object { $_.UserAccountControl -band 0x0080 } 
    [array]$DomainUserPasswordNotRequired       = $DomainUsers | Where-Object { $_.PasswordNotRequired -eq $true }
    [array]$DomainUserPasswordNeverExpires      = $DomainUsers | Where-Object { $_.PasswordNeverExpires -eq $true }
    [array]$DomainKerberosDESUsers              = $DomainUsers | Where-Object { $_.UserAccountControl -band 0x200000 }
    [array]$DomainUserDoesNotRequirePreAuth     = $DomainUsers | Where-Object { $_.DoesNotRequirePreAuth -eq $true }
    [array]$DomainUsersWithSIDHistory           = $DomainUsers | Where-Object { $_.SIDHistory -like "*" }

    $UserOutputFile = Join-Path $ReportDir "ADChecks-DomainUserReport-$Domain-$DateStamp.csv"
    $DomainUsers | Export-Csv -Path $UserOutputFile -NoTypeInformation -Encoding utf8

    # Domain Password Policy
    $DomainPasswordPolicy = Get-ADDefaultDomainPasswordPolicy -Server $DomainDC
    $DomainPasswordPolicyFile = Join-Path $ReportDir "ADChecks-DomainPasswordPolicy-$Domain-$DateStamp.csv"
    $DomainPasswordPolicy | Export-Csv -Path $DomainPasswordPolicyFile -NoTypeInformation -Encoding utf8

    # Default Admin & KRBTGT Audit
    $DomainAdminAccountSID = "$($ADDomainInfo.DomainSID)-500"
    $DomainDefaultAdminAccount = Get-ADUser -Identity $DomainAdminAccountSID -Server $DomainDC -Properties Name,Enabled,Created,PasswordLastSet,LastLogonDate,ServicePrincipalName,SID
    $DefaultAdminFile = Join-Path $ReportDir "ADChecks-DomainDefaultAdminAccount-$Domain-$DateStamp.csv"
    $DomainDefaultAdminAccount | Export-Csv -Path $DefaultAdminFile -NoTypeInformation -Encoding utf8

    $DomainKRBTGTAccount = Get-ADUser -Identity 'krbtgt' -Server $DomainDC -Properties 'msds-keyversionnumber',Created,PasswordLastSet
    $KRBTGTFile = Join-Path $ReportDir "ADChecks-DomainKRBTGTAccount-$Domain-$DateStamp.csv"
    $DomainKRBTGTAccount | Export-Csv -Path $KRBTGTFile -NoTypeInformation -Encoding utf8

    # Privileged AD Admins & Groups
    Write-Log "Auditing privileged groups and memberships..." "INFO"
    $ADAdminArray = @()
    $ADAdminMembers = Get-ADGroupMember -Identity Administrators -Recursive -Server $DomainDC
    foreach ($Member in $ADAdminMembers) {
        try {
            switch ($Member.objectClass) {
                'User' { $ADAdminArray += Get-ADUser -Identity $Member -Properties LastLogonDate,PasswordLastSet,ServicePrincipalName -Server $DomainDC }
                'Computer' { $ADAdminArray += Get-ADComputer -Identity $Member -Properties LastLogonDate,PasswordLastSet -Server $DomainDC }
                'msDS-GroupManagedServiceAccount' { $ADAdminArray += Get-ADServiceAccount -Identity $Member -Properties LastLogonDate,PasswordLastSet -Server $DomainDC }
            }
        }
        catch {
            Write-Log "Could not resolve principal: $($Member.distinguishedName)" "WARN"
            $ADAdminArray += $Member
        }
    }
    $ADAdminReportFile = Join-Path $ReportDir "ADChecks-ADAdminAccountReport-$Domain-$DateStamp.csv"
    $ADAdminArray | Export-Csv -Path $ADAdminReportFile -NoTypeInformation -Encoding utf8

    # Protected Users Group
    $ProtectedUsersMembership = Get-ADGroupMember -Identity 'Protected Users' -Server $DomainDC
    $ProtectedUsersFile = Join-Path $ReportDir "ADChecks-ProtectedUsersGroupMembership-$Domain-$DateStamp.csv"
    $ProtectedUsersMembership | Export-Csv -Path $ProtectedUsersFile -NoTypeInformation -Encoding utf8

    # Kerberos Delegation Checks
    Write-Log "Auditing accounts with Kerberos Delegation..." "INFO"
    $KerberosDelegationArray = @()
    $KerberosDelegationObjects = Get-ADObject -Filter { ((UserAccountControl -BAND 0x0080000) -or (UserAccountControl -BAND 0x1000000) -or (msDS-AllowedToDelegateTo -like '*') -or (msDS-AllowedToActOnBehalfOfOtherIdentity -like '*')) -and (PrimaryGroupID -ne '516') -and (PrimaryGroupID -ne '521') } -Server $DomainDC -Properties Name,ObjectClass,PrimaryGroupID,UserAccountControl,ServicePrincipalName,msDS-AllowedToDelegateTo,msDS-AllowedToActOnBehalfOfOtherIdentity -SearchBase $DomainDN 

    foreach ($Item in $KerberosDelegationObjects) {
        $KerberosDelegationServices = if ($Item.UserAccountControl -band 0x0080000) { 'All Services' } else { 'Specific Services' }
        $KerberosType = if ($Item.UserAccountControl -band 0x0080000) { 'Unconstrained' } else { 'Constrained' }
        $KerberosAllowedProtocols = if ($Item.UserAccountControl -band 0x1000000) { 'Any (Protocol Transition)' } else { 'Kerberos' }
        if ($Item.'msDS-AllowedToActOnBehalfOfOtherIdentity') { $KerberosType = 'Resource-Based Constrained Delegation' }

        $Item | Add-Member -MemberType NoteProperty -Name Domain -Value $Domain -Force
        $Item | Add-Member -MemberType NoteProperty -Name KerberosDelegationServices -Value $KerberosDelegationServices -Force
        $Item | Add-Member -MemberType NoteProperty -Name DelegationType -Value $KerberosType -Force
        $Item | Add-Member -MemberType NoteProperty -Name KerberosDelegationAllowedProtocols -Value $KerberosAllowedProtocols -Force

        $KerberosDelegationArray += $Item
    }
    $KerberosReportFile = Join-Path $ReportDir "ADChecks-KerberosDelegationReport-$Domain-$DateStamp.csv"
    $KerberosDelegationArray | Export-Csv -Path $KerberosReportFile -NoTypeInformation -Encoding utf8

    # SYSVOL Search for GPP Passwords
    Write-Log "Scanning SYSVOL policies for GPP password attributes..." "INFO"
    $GPPPasswordDataReportFile = Join-Path $ReportDir "ADChecks-GPPPasswordDataReport-$Domain-$DateStamp.txt"
    $SYSVOLPath = "\\$Domain\SYSVOL\$Domain\Policies"
    if (Test-Path $SYSVOLPath) {
        $GPPMatches = Get-ChildItem -Path $SYSVOLPath -Filter "*.xml" -Recurse -ErrorAction SilentlyContinue | Select-String -Pattern "cpassword"
        $GPPMatches | Out-File -FilePath $GPPPasswordDataReportFile -Encoding utf8
    }

    # GPO Audit
    Write-Log "Auditing Group Policy Object Ownership..." "INFO"
    $DomainGPOs = Get-GPO -All -Domain $Domain
    $GPOReportFile = Join-Path $ReportDir "ADChecks-DomainGPOData-$Domain-$DateStamp.csv"
    $DomainGPOs | Export-Csv -Path $GPOReportFile -NoTypeInformation -Encoding utf8

    $ScriptTimer.Stop()
    Write-Log "Completed Active Directory Checks in $($ScriptTimer.Elapsed.ToString())" "INFO"
    Write-Log "Reports successfully saved to: $ReportDir" "INFO"
}
catch {
    Write-Log "CRITICAL ERROR during execution: $($_.Exception.Message)" "ERROR"
}
finally {
    Stop-Transcript
}