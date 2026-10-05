#requires -Version 5.1

<#
.SYNOPSIS
    Parses Active Directory security audit logs for object access events and resolves schema GUIDs.

.DESCRIPTION
    Queries Security Event Logs across specified domain controllers or local host for Event ID 4662 (Directory Service Access).
    Parses the event data to extract subject account details, access masks, and target object names. Automatically resolves
    schemaIDGUID attributes to human-readable Active Directory object class names and returns structured PSCustomObjects.
    Writes execution logs to C:\Temp\ and performs automatic 7-day log cleanup maintenance.

.PARAMETER ComputerName
    An array of target computer names or Domain Controller FQDNs to query. If omitted, queries all Domain Controllers in the current domain.

.PARAMETER EventID
    The Security Event ID(s) to query. Defaults to Event ID 4662 (Object Access).

.PARAMETER LogName
    The target Event Log to search. Defaults to 'Security'.

.PARAMETER DaysAgo
    The number of days back to search for audit logs. Defaults to 0 (today).

.PARAMETER StartTime
    The explicit start timestamp for log filtering. Overrides -DaysAgo calculation if provided.

.PARAMETER ObjectType
    An array of Active Directory object types/classes to include in the output (e.g., 'Group', 'User', 'SecretObject').

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Get-ADAuditAccess.ps1 -DaysAgo 1 -ObjectType "Group", "User"

.EXAMPLE
    .\Get-ADAuditAccess.ps1 -ComputerName "DC01.contoso.com", "DC02.contoso.com" -DaysAgo 7 -ObjectType "User"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Security Event Log Read Access, Administrator Elevation.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding(DefaultParameterSetName = "Domain")]
param(
    [Parameter(ParameterSetName = "ComputerName", Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,

    [Parameter(Mandatory = $false)]
    [string[]]$EventID = @("4662"),

    [Parameter(Mandatory = $false)]
    [string[]]$LogName = @("Security"),

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 365)]
    [int32]$DaysAgo = 0,

    [Parameter(Mandatory = $false)]
    [datetime]$StartTime = ((Get-Date).Date).AddDays(-$DaysAgo),

    [Parameter(Mandatory = $false)]
    [string[]]$ObjectType = @("Group", "User", "SecretObject"),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges to query Security Event Logs. Please run PowerShell as Administrator."
    exit 1
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
$ScriptName = "Get_ADAuditAccess"
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
    Write-Log "Initializing Active Directory Audit Access Log Analysis..." "INFO"

    if ($PSCmdlet.ParameterSetName -eq "ComputerName" -and $ComputerName) {
        Write-Log "Targeting specified ComputerName(s): $($ComputerName -join ', ')" "INFO"
    }
    else {
        Write-Log "Parameter set 'Domain' selected. Discovering Domain Controllers in target domain..." "INFO"
        try {
            $DomainControllers = Get-ADDomainController -Filter * -ErrorAction Stop
            $ComputerName = $DomainControllers.Name
            Write-Log "Discovered $($ComputerName.Count) Domain Controller(s): $($ComputerName -join ', ')" "INFO"
        }
        catch {
            Write-Log "Failed to query domain controllers via Active Directory module: $($_.Exception.Message)" "ERROR"
            exit 1
        }
    }

    $FilterSearch = @{
        ID        = $EventID
        LogName   = $LogName
        StartTime = $StartTime
    }

    # Pre-cache Schema GUID Mapping for Object Types
    $SchemaMap = @{}
    try {
        $SchemaContext = (Get-ADRootDSE).schemaNamingContext
        Get-ADObject -Filter 'objectClassCategory -eq 1' -Properties schemaIDGUID -SearchBase $SchemaContext -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.schemaIDGUID) {
                $GuidString = ([guid]$_.schemaIDGUID).ToString()
                $SchemaMap[$GuidString] = $_.Name
            }
        }
    }
    catch {
        Write-Log "Failed to pre-cache Schema GUID mappings: $($_.Exception.Message)" "WARN"
    }

    $AuditResults = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($TargetComputer in $ComputerName) {
        Write-Log "Querying Event ID $($EventID -join ',') logs on target host: $TargetComputer (Start Time: $StartTime)..." "INFO"

        try {
            $Events = Get-WinEvent -ComputerName $TargetComputer -FilterHashtable $FilterSearch -ErrorAction Stop

            foreach ($Event in $Events) {
                $FullMessage = $Event.Message

                # Parse Message Segments safely
                if ($FullMessage -match "Subject:") {
                    $MessageParts = $FullMessage -split "Subject :"
                    $SubjectPart  = ($MessageParts[1] -split "Object:")[0]
                    $ObjectPart   = (($MessageParts[1] -split "Object:")[1] -split "Operation:")[0]
                    $OperationPart= ((($MessageParts[1] -split "Object:")[1] -split "Operation:")[1] -split "Additional Information:")[0]

                    $SubjectLines   = ($SubjectPart -split '\n') -split ':' | ForEach-Object { $_.Trim() }
                    $ObjectLines    = ($ObjectPart -split '\n') -split ':' | ForEach-Object { $_.Trim() }
                    $OperationLines = ($OperationPart -split '\n') -split ':' | ForEach-Object { $_.Trim() }

                    $RawObjectType = if ($ObjectLines.Count -gt 4) { $ObjectLines[4] } else { "Unknown" }
                    $RawObjectName = if ($ObjectLines.Count -gt 6) { $ObjectLines[6] } else { "Unknown" }

                    # Resolve Schema GUID to Friendly Class Name
                    $ResolvedObjectType = $RawObjectType
                    if ($RawObjectType -match "^0x" -or $RawObjectType.Length -eq 36) {
                        $CleanGuid = $RawObjectType -replace '^0x', ''
                        if ($SchemaMap.ContainsKey($CleanGuid)) {
                            $ResolvedObjectType = $SchemaMap[$CleanGuid]
                        }
                    }

                    # Resolve Object Identity
                    $ResolvedObjectName = $RawObjectName
                    if ($RawObjectName -like "CN=*" -or $RawObjectName -like "OU=*") {
                        # Retain Distinguished Name
                        $ResolvedObjectName = $RawObjectName
                    }
                    else {
                        try {
                            $ADObj = Get-ADObject -Filter "objectGUID -eq '$RawObjectName'" -ErrorAction SilentlyContinue
                            if ($ADObj) { $ResolvedObjectName = $ADObj.DistinguishedName }
                        }
                        catch {}
                    }

                    # Filter by specified ObjectType array
                    if ($ObjectType -contains $ResolvedObjectType -or $ObjectType -contains $RawObjectType) {
                        $AuditResults.Add([PSCustomObject]@{
                            TimeCreated   = $Event.TimeCreated
                            SecurityID    = if ($SubjectLines.Count -gt 2) { $SubjectLines[2] } else { "" }
                            AccountName   = if ($SubjectLines.Count -gt 4) { $SubjectLines[4] } else { "" }
                            AccountDomain = if ($SubjectLines.Count -gt 6) { $SubjectLines[6] } else { "" }
                            LogonID       = if ($SubjectLines.Count -gt 8) { $SubjectLines[8] } else { "" }
                            ObjectServer  = if ($ObjectLines.Count -gt 2) { $ObjectLines[2] } else { "" }
                            ObjectType    = $ResolvedObjectType
                            ObjectName    = $ResolvedObjectName
                            HandleID      = if ($ObjectLines.Count -gt 8) { $ObjectLines[8] } else { "" }
                            OperationType = if ($OperationLines.Count -gt 2) { $OperationLines[2] } else { "" }
                            Accesses      = if ($OperationLines.Count -gt 4) { $OperationLines[4] } else { "" }
                        })
                    }
                }
            }
        }
        catch {
            Write-Log "Failed to query or parse event logs on host '$TargetComputer': $($_.Exception.Message)" "WARN"
        }
    }

    Write-Log "Audit analysis complete. Total matching event records found: $($AuditResults.Count)" "INFO"

    # Pipeline Output
    $AuditResults
}
catch {
    Write-Log "CRITICAL ERROR during Active Directory audit log execution: $($_.Exception.Message)" "ERROR"
    exit 1
}