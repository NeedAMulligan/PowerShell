#requires -Version 5.1

<#
.SYNOPSIS
    Returns a list of users who were locked out in Active Directory by querying Security Event ID 4740 on the PDC Emulator.

.DESCRIPTION
    Queries the Security Event Log on the Active Directory Domain Controller holding the PDC Emulator role for 
    Account Lockout events (Event ID 4740). Filters results by target user identity and start time threshold. 
    Writes execution logs to C:\Temp\ and performs automatic 7-day log cleanup maintenance.

.PARAMETER DomainName
    The target Active Directory domain name. Defaults to the current execution context domain.

.PARAMETER UserName
    The target username or wildcard filter to search lockouts for. Defaults to '*' (all locked-out users).

.PARAMETER StartTime
    The datetime to start searching event records from. Defaults to 3 days prior to execution.

.PARAMETER Credential
    Optional PSCredential object used to authenticate against the PDC Emulator if executing under an alternate context.

.PARAMETER ExportPath
    Optional file path to export the locked-out user report to CSV format.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Get-LockedOutUser.ps1

.EXAMPLE
    .\Get-LockedOutUser.ps1 -UserName "jdoe" -StartTime (Get-Date).AddDays(-1)

.EXAMPLE
    .\Get-LockedOutUser.ps1 -DomainName "contoso.com" -ExportPath "C:\Temp\LockedOutUsers.csv"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Security Event Log Read Access, Administrator Elevation.
    Change Log   :
        1.0 - Initial sanitized production release with standard logging and housekeeping.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify target Active Directory domain name.")]
    [string]$DomainName,

    [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Specify username or wildcard pattern to search.")]
    [string]$UserName = "*",

    [Parameter(Mandatory = $false, Position = 2, HelpMessage = "Specify start timestamp threshold for event log search.")]
    [datetime]$StartTime = (Get-Date).AddDays(-3),

    [Parameter(Mandatory = $false, HelpMessage = "Specify alternate credentials for remote execution.")]
    [PSCredential]$Credential,

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
$ScriptName = "Get_LockedOutUser"
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
    if ([string]::IsNullOrWhiteSpace($DomainName)) {
        $DomainName = (Get-ADDomain).DNSRoot
    }

    Write-Log "Target Domain: $DomainName | User Filter: $UserName | Search Start Time: $StartTime" "INFO"

    # Discover PDC Emulator for target domain
    try {
        $DirectoryContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext('Domain', $DomainName)
        $PdcHost = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DirectoryContext).PdcRoleOwner.Name
        Write-Log "Located PDC Emulator Domain Controller: $PdcHost" "INFO"
    }
    catch {
        Write-Log "Failed to locate PDC Emulator for domain '$DomainName': $($_.Exception.Message)" "ERROR"
        exit 1
    }

    # Define Query ScriptBlock
    $QueryScriptBlock = {
        param($TargetUserName, $SearchStartTime)

        $FilterHashtable = @{
            LogName   = 'Security'
            Id        = 4740
            StartTime = $SearchStartTime
        }

        Get-WinEvent -FilterHashtable $FilterHashtable -ErrorAction SilentlyContinue | 
            Where-Object { $_.Properties[0].Value -like $TargetUserName } | 
            Select-Object @{Label = 'TimeCreated'; Expression = { $_.TimeCreated } },
                          @{Label = 'UserName'; Expression = { $_.Properties[0].Value } },
                          @{Label = 'ClientName'; Expression = { $_.Properties[1].Value } },
                          @{Label = 'DomainController'; Expression = { $_.MachineName } }
    }

    Write-Log "Querying Security Event Log (Event ID 4740) on PDC Emulator ($PdcHost)..." "INFO"

    $InvokeParams = @{
        ComputerName = $PdcHost
        ScriptBlock  = $QueryScriptBlock
        ArgumentList = $UserName, $StartTime
        ErrorAction  = "Stop"
    }

    if ($Credential) {
        $InvokeParams.Add("Credential", $Credential)
    }

    $LockoutResults = Invoke-Command @InvokeParams | Select-Object TimeCreated, UserName, ClientName, DomainController

    if (-not $LockoutResults -or $LockoutResults.Count -eq 0) {
        Write-Log "No account lockout events matching criteria were found." "WARN"
        return
    }

    Write-Log "Retrieved $($LockoutResults.Count) account lockout event record(s)." "INFO"

    if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
        $ExportDir = Split-Path -Path $ExportPath -Parent
        if ($ExportDir -and (-not (Test-Path -Path $ExportDir))) {
            New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
        }
        $LockoutResults | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
        Write-Log "SUCCESS: Exported lockout report to: $ExportPath" "INFO"
    }

    # Pipeline output
    $LockoutResults
}
catch {
    Write-Log "CRITICAL ERROR during locked-out user query execution: $($_.Exception.Message)" "ERROR"
    exit 1
}