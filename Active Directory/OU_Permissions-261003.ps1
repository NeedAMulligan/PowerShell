#requires -Version 5.1

<#
.SYNOPSIS
    Generates a comprehensive security permission audit report for Active Directory OUs and root containers.

.DESCRIPTION
    Enumerates all Organizational Units, domain root, and top-level container objects within Active Directory.
    Reads access control lists (ACLs), maps schemaIDGUIDs and controlAccessRights to human-readable object class 
    and extended right names, and exports the findings to CSV. Writes execution logs to C:\Temp\ and automatically 
    performs 7-day log maintenance cleanup.

.PARAMETER ExportPath
    The file path where the exported CSV permission report will be written. Defaults to 'C:\Temp\OU_Permissions_<yyyyMMdd_HHmmss>.csv'.

.PARAMETER TargetIdentity
    Optional user or group identity string to filter permission entries in the generated report.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Get-ADOUPermissions.ps1

.EXAMPLE
    .\Get-ADOUPermissions.ps1 -TargetIdentity "Domain Admins" -ExportPath "C:\Temp\DomainAdmins_OU_Permissions.csv"

.NOTES
    Author       : System Administrator / Sanitized (Refactored from Ashley McGlone PFE v1.0)
    Prerequisites: RSAT Active Directory Tools module, Domain User privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify target CSV output file path.")]
    [string]$ExportPath,

    [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Specify an optional user or group identity string to filter results.")]
    [string]$TargetIdentity,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Warning "Running in non-elevated context. Ensure proper Domain User rights to query Active Directory Security Descriptors."
}

$RequiredModule = "ActiveDirectory"

if (-not (Get-Module -ListAvailable -Name $RequiredModule)) {
    Write-Host "Required module '$RequiredModule' was not found. Attempting installation for CurrentUser..." -ForegroundColor Yellow
    try {
        Install-Module -Name $RequiredModule -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop
        Write-Host "Successfully installed '$RequiredModule'." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install required module '$RequiredModule': $($_.Exception.Message)"
        exit 1
    }
}

Import-Module -Name $RequiredModule -ErrorAction Stop

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "AD_AuditOUPermissions"
$DateStamp  = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

# Log rotation: Remove log files older than 7 days from C:\Temp
Get-ChildItem -Path $LogDirectory -Filter "*.log" -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
    Remove-Item -Force -ErrorAction SilentlyContinue

$LogFile = Join-Path -Path $LogDirectory -ChildPath "$($ScriptName)_$($DateStamp).log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    $LogEntry | Out-File -FilePath $LogFile -Append -Encoding utf8
    
    $Color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        Default { "Cyan" }
    }
    Write-Host $LogEntry -ForegroundColor $Color
}

# --------------------------------------------------------------------------
# 3. SCRIPT EXECUTION
# --------------------------------------------------------------------------
try {
    if ([string]::IsNullOrWhiteSpace($ExportPath)) {
        $ExportPath = Join-Path -Path $LogDirectory -ChildPath "OU_Permissions_${DateStamp}.csv"
    }

    Write-Log "Initializing Active Directory OU Permissions Audit..." "INFO"

    # Pre-cache Schema GUID and Control Access Rights Mappings
    $SchemaIDGUID = @{}
    
    Write-Log "Caching Schema Object Class GUIDs..." "INFO"
    $SchemaObjects = Get-ADObject -SearchBase (Get-ADRootDSE).schemaNamingContext -LDAPFilter '(schemaIDGUID=*)' -Properties name, schemaIDGUID -ErrorAction SilentlyContinue
    foreach ($Obj in $SchemaObjects) {
        if ($Obj.schemaIDGUID) {
            $Guid = [System.Guid]$Obj.schemaIDGUID
            if (-not $SchemaIDGUID.ContainsKey($Guid)) {
                $SchemaIDGUID.Add($Guid, $Obj.name)
            }
        }
    }

    Write-Log "Caching Control Access Rights Extended Rights GUIDs..." "INFO"
    $ControlAccessRights = Get-ADObject -SearchBase "CN=Extended-Rights,$((Get-ADRootDSE).configurationNamingContext)" -LDAPFilter '(objectClass=controlAccessRight)' -Properties name, rightsGUID -ErrorAction SilentlyContinue
    foreach ($Right in $ControlAccessRights) {
        if ($Right.rightsGUID) {
            $Guid = [System.Guid]$Right.rightsGUID
            if (-not $SchemaIDGUID.ContainsKey($Guid)) {
                $SchemaIDGUID.Add($Guid, $Right.name)
            }
        }
    }

    # Discover Target OUs and Containers
    Write-Log "Enumerating domain root, OUs, and container objects..." "INFO"
    $OUs = [System.Collections.Generic.List[string]]::new()
    
    $DomainDN = (Get-ADDomain).DistinguishedName
    $OUs.Add($DomainDN)

    $OrgUnits = Get-ADOrganizationalUnit -Filter * -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DistinguishedName
    foreach ($OU in $OrgUnits) { $OUs.Add($OU) }

    $Containers = Get-ADObject -SearchBase $DomainDN -SearchScope OneLevel -LDAPFilter '(objectClass=container)' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DistinguishedName
    foreach ($Container in $Containers) { $OUs.Add($Container) }

    Write-Log "Discovered $($OUs.Count) total container object(s) to process." "INFO"

    $Report = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($OU in $OUs) {
        try {
            $Acl = Get-Acl -Path "AD:\$OU" -ErrorAction Stop
            
            foreach ($Access in $Acl.Access) {
                if (-not [string]::IsNullOrWhiteSpace($TargetIdentity) -and $Access.IdentityReference -notlike "*$TargetIdentity*") {
                    continue
                }

                $ObjTypeName = if ($Access.ObjectType.ToString() -eq '00000000-0000-0000-0000-000000000000') {
                    'All'
                }
                elseif ($SchemaIDGUID.ContainsKey($Access.ObjectType)) {
                    $SchemaIDGUID[$Access.ObjectType]
                }
                else {
                    $Access.ObjectType.ToString()
                }

                $InheritedObjTypeName = if ($SchemaIDGUID.ContainsKey($Access.InheritedObjectType)) {
                    $SchemaIDGUID[$Access.InheritedObjectType]
                }
                else {
                    $Access.InheritedObjectType.ToString()
                }

                $Report.Add([PSCustomObject]@{
                    OrganizationalUnit       = $OU
                    IdentityReference        = $Access.IdentityReference
                    ActiveDirectoryRights    = $Access.ActiveDirectoryRights
                    AccessControlType        = $Access.AccessControlType
                    ObjectTypeName           = $ObjTypeName
                    InheritedObjectTypeName  = $InheritedObjTypeName
                    IsInherited              = $Access.IsInherited
                    InheritanceType          = $Access.InheritanceType
                    PropagationFlags         = $Access.PropagationFlags
                })
            }
        }
        catch {
            Write-Log "Failed to retrieve ACL for container '$OU': $($_.Exception.Message)" "WARN"
        }
    }

    if ($Report.Count -eq 0) {
        Write-Log "No matching permissions entries were found." "WARN"
        return
    }

    $ExportDir = Split-Path -Path $ExportPath -Parent
    if ($ExportDir -and (-not (Test-Path -Path $ExportDir))) {
        New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
    }

    $Report | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
    Write-Log "SUCCESS: Exported $($Report.Count) permission record(s) to: $ExportPath" "INFO"

    # Pipeline output
    $Report
}
catch {
    Write-Log "CRITICAL ERROR during OU permission audit execution: $($_.Exception.Message)" "ERROR"
    exit 1
}