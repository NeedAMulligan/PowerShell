#requires -Version 5.1

<#
.SYNOPSIS
    Audits Active Directory user logon history by querying Kerberos TGT Request events (Event ID 4768) across Domain Controllers.

.DESCRIPTION
    Inspects Security Event Logs across active Domain Controllers for Kerberos TGT Requests (Event ID 4768).
    Extracts requesting user accounts, client IP addresses, resolves DNS PTR records for workstation names, 
    and queries Active Directory for user and computer Canonical Name locations. Excludes system accounts 
    and health mailboxes. Outputs structured pipeline objects, writes execution logs to C:\Temp, and 
    automatically maintains a 7-day log cleanup rotation.

.PARAMETER MaxEvent
    Specifies the maximum number of Event ID 4768 records to inspect per Domain Controller. Defaults to 1000.

.PARAMETER LastLogonOnly
    Switch parameter to group results by user and return only the most recent logon record per account.

.PARAMETER OuOnly
    Switch parameter to truncate full canonical paths and display only the Organizational Unit (OU) container path.

.PARAMETER ExportPath
    Optional CSV file path to export the audit results.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Get-ADUserLogonHistory.ps1 -MaxEvent 500 -LastLogonOnly -OuOnly

.EXAMPLE
    .\Get-ADUserLogonHistory.ps1 -MaxEvent 1000 -ExportPath "C:\Temp\Users_Loggedon_History.csv"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain Security Event Log Read Access, Administrator Elevation.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Display only the most recent logon event per user account.")]
    [switch]$LastLogonOnly,

    [Parameter(Mandatory = $false, HelpMessage = "Display only the OU container path instead of the full canonical path.")]
    [switch]$OuOnly,

    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Maximum Event ID 4768 records to query per Domain Controller.")]
    [ValidateRange(1, 200000)]
    [int]$MaxEvent = 1000,

    [Parameter(Mandatory = $false, HelpMessage = "Optional CSV file path to export results.")]
    [string]$ExportPath,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges to query Security Event Logs across Domain Controllers."
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
$ScriptName = "Get_ADUserLogonHistory"
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
# 3. SCRIPT EXECUTION & WORKFLOW DEFINITION
# --------------------------------------------------------------------------
try {
    $Domain = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
    Write-Log "Initializing logon history audit across Domain: $Domain" "INFO"

    # Define ScriptBlock for Event Query
    $ReadLogScriptBlock = {
        param($MaxEventsToRead, $ShowOuOnly, $DomainName)

        $Events = Get-WinEvent -FilterHashtable @{ LogName = "Security"; Id = 4768 } -MaxEvents ($MaxEventsToRead * 5) -ErrorAction SilentlyContinue | 
            Where-Object { $_.Properties[0].Value -notmatch "SM_" -and $_.Properties[0].Value -notmatch "\$" } | 
            Select-Object -First $MaxEventsToRead

        $ParsedRecords = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($Event in $Events) {
            $TargetUser = [string]$Event.Properties[0].Value
            $ClientIP   = [string]$Event.Properties[9].Value

            if ($ClientIP -eq "::1" -or $ClientIP -eq "127.0.0.1") {
                $ClientIP = "localhost"
                $WorkstationHost = [System.Net.Dns]::GetHostName()
            }
            else {
                try {
                    $PtrRecord = Resolve-DnsName -Name $ClientIP -Type PTR -TcpOnly -DnsOnly -ErrorAction SilentlyContinue
                    $WorkstationHost = if ($PtrRecord) { $PtrRecord.NameHost } else { "NOT FOUND" }
                }
                catch {
                    $WorkstationHost = "NOT FOUND"
                }
            }

            # User Location Lookup
            $UserLocation = "NOT FOUND"
            try {
                $ADUser = Get-ADUser -Identity $TargetUser -Properties CanonicalName -ErrorAction SilentlyContinue
                if ($ADUser -and $ADUser.CanonicalName) {
                    $UserLocation = $ADUser.CanonicalName.TrimStart($DomainName).TrimStart('/')
                    if ($ShowOuOnly -and $UserLocation.Contains('/')) {
                        $UserLocation = $UserLocation.Substring(0, $UserLocation.LastIndexOf('/'))
                    }
                }
            }
            catch {}

            # Workstation Clean Name & Location Lookup
            $CleanWorkstation = if ($WorkstationHost -ne "NOT FOUND") { ($WorkstationHost -split "\." + $DomainName)[0] } else { "NOT FOUND" }
            $ComputerLocation = "NOT FOUND"

            if ($CleanWorkstation -ne "NOT FOUND") {
                try {
                    $ADComp = Get-ADComputer -Identity $CleanWorkstation -Properties CanonicalName -ErrorAction SilentlyContinue
                    if ($ADComp -and $ADComp.CanonicalName) {
                        $ComputerLocation = $ADComp.CanonicalName.TrimStart($DomainName).TrimStart('/')
                        if ($ShowOuOnly -and $ComputerLocation.Contains('/')) {
                            $ComputerLocation = $ComputerLocation.Substring(0, $ComputerLocation.LastIndexOf('/'))
                        }
                    }
                }
                catch {}
            }

            $ParsedRecords.Add([PSCustomObject]@{
                "Authenticated DC"   = $Event.MachineName
                "LoggedOn Time"      = $Event.TimeCreated
                "User"               = $TargetUser
                "User Location"      = $UserLocation
                "Workstation"        = $CleanWorkstation
                "IP Address"         = $ClientIP
                "Computer Location"  = $ComputerLocation
            })
        }

        return $ParsedRecords
    }

    # Query Domain Controllers
    Write-Log "Enumerating domain controllers..." "INFO"
    $DomainControllers = (Get-ADDomainController -Filter *).Name
    Write-Log "Discovered $($DomainControllers.Count) Domain Controller(s)." "INFO"

    $Jobs = [System.Collections.Generic.List[System.Management.Automation.Job]]::new()
    $LocalHostName = [System.Net.Dns]::GetHostName()

    foreach ($DC in $DomainControllers) {
        Write-Log "Dispatching query job to DC: $DC" "INFO"
        if ($DC -eq $LocalHostName -or $DC.StartsWith($LocalHostName)) {
            $Jobs.Add((Start-Job -ScriptBlock $ReadLogScriptBlock -ArgumentList $MaxEvent, $OuOnly, $Domain))
        }
        else {
            $Jobs.Add((Invoke-Command -ComputerName $DC -ScriptBlock $ReadLogScriptBlock -ArgumentList $MaxEvent, $OuOnly, $Domain -AsJob))
        }
    }

    Write-Log "Waiting for Domain Controller audit jobs to complete..." "INFO"
    $RawResults = $Jobs | Wait-Job | Receive-Job
    $Jobs | Remove-Job -Force -ErrorAction SilentlyContinue

    if (-not $RawResults) {
        Write-Log "No logon events were returned from target Domain Controllers." "WARN"
        return
    }

    Write-Log "Retrieved $($RawResults.Count) logon event record(s). Processing formatting..." "INFO"

    $FinalResults = if ($LastLogonOnly) {
        $RawResults | Sort-Object "LoggedOn Time" -Descending | Group-Object User | ForEach-Object {
            $_.Group | Select-Object -First 1 -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
        }
    }
    else {
        $RawResults | Sort-Object "LoggedOn Time" -Descending | Select-Object -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
    }

    # Export to CSV if specified
    if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
        $ExportDir = Split-Path -Path $ExportPath -Parent
        if ($ExportDir -and (-not (Test-Path -Path $ExportDir))) {
            New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
        }
        $FinalResults | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
        Write-Log "SUCCESS! Exported audit results to: $ExportPath" "INFO"
    }

    # Output to Pipeline
    $FinalResults
}
catch {
    Write-Log "CRITICAL ERROR during logon history audit execution: $($_.Exception.Message)" "ERROR"
    exit 1
}