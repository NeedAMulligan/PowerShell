#requires -Version 5.1

<#
.SYNOPSIS
    Locates the source computer and Domain Controller that processed a failed user logon attempt resulting in an account lockout.

.DESCRIPTION
    Queries all active Domain Controllers in the domain to inspect user account bad password attempt counters and timestamps. 
    Queries the PDC Emulator Domain Controller for Security Event ID 4740 (Account Lockout) to identify the specific originating 
    workstation or IP address location. Writes execution logs to C:\Temp and automatically maintains a 7-day log cleanup rotation.

.PARAMETER Identity
    The Identity (SamAccountName, UPN, or DistinguishedName) of the locked-out Active Directory user account.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    Get-LockedOutLocation.ps1 -Identity "jdoe"

.EXAMPLE
    Get-LockedOutLocation.ps1 -Identity "Joe.Davis" -LogDirectory "C:\Temp"

.NOTES
    Author       : System Administrator / Sanitized (Refactored from Jason Walker)
    Prerequisites: RSAT Active Directory Tools module, Security Event Log Read Access, Administrator Elevation.
    Change Log   :
        1.0 - Initial sanitized production release with standard logging and housekeeping.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Specify target user identity.")]
    [ValidateNotNullOrEmpty()]
    [string]$Identity,

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
$ScriptName = "Get_LockedOutLocation"
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
    Write-Log "Initializing Account Lockout Location analysis for user identity: $Identity" "INFO"

    # Enumerate Domain Controllers
    $DomainControllers = Get-ADDomainController -Filter * -ErrorAction Stop
    $PDCEmulator = $DomainControllers | Where-Object { $_.OperationMasterRoles -contains "PDCEmulator" }

    if (-not $PDCEmulator) {
        Write-Log "Could not locate PDC Emulator Domain Controller in domain." "ERROR"
        exit 1
    }

    Write-Log "Discovered $($DomainControllers.Count) Domain Controller(s). PDC Emulator: $($PDCEmulator.HostName)" "INFO"

    $LockedOutStats = [System.Collections.Generic.List[PSCustomObject]]::new()
    $DCCounter = 0
    $TargetUserSID = $null

    foreach ($DC in $DomainControllers) {
        $DCCounter++
        Write-Progress -Activity "Contacting DCs for bad password info" -Status "Querying $($DC.Hostname)" -PercentComplete (($DCCounter / $DomainControllers.Count) * 100)

        try {
            $UserInfo = Get-ADUser -Identity $Identity -Server $DC.Hostname -Properties AccountLockoutTime, LastBadPasswordAttempt, BadPwdCount, LockedOut -ErrorAction Stop
            
            if (-not $TargetUserSID) {
                $TargetUserSID = $UserInfo.SID.Value
            }

            if ($UserInfo.LastBadPasswordAttempt) {
                $LockedOutStats.Add([PSCustomObject]@{
                    Name                   = $UserInfo.SamAccountName
                    SID                    = $UserInfo.SID.Value
                    LockedOut              = $UserInfo.LockedOut
                    BadPwdCount            = $UserInfo.BadPwdCount
                    BadPasswordTime        = $UserInfo.BadPasswordTime
                    DomainController       = $DC.Hostname
                    AccountLockoutTime     = $UserInfo.AccountLockoutTime
                    LastBadPasswordAttempt = ($UserInfo.LastBadPasswordAttempt).ToLocalTime()
                })
            }
        }
        catch {
            Write-Log "Failed to query user stats on DC '$($DC.Hostname)': $($_.Exception.Message)" "WARN"
        }
    }

    Write-Progress -Activity "Contacting DCs for lockout info" -Completed

    if ($LockedOutStats.Count -gt 0) {
        Write-Log "Retrieved bad password statistics across $($LockedOutStats.Count) Domain Controller(s)." "INFO"
    }

    # Query PDC Emulator Security Event Log for Event ID 4740
    Write-Log "Querying Security Event Log on PDC Emulator ($($PDCEmulator.HostName)) for Event ID 4740..." "INFO"

    $LockoutEvents = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $FilterHashtable = @{
            LogName = 'Security'
            Id      = 4740
        }

        $RawEvents = Get-WinEvent -ComputerName $PDCEmulator.HostName -FilterHashtable $FilterHashtable -ErrorAction Stop | 
            Sort-Object -Property TimeCreated -Descending

        foreach ($Event in $RawEvents) {
            # Check if event SID matches target user
            if ($Event.Properties[2].Value -match $TargetUserSID -or $Event.Properties[0].Value -eq $Identity) {
                $LockoutEvents.Add([PSCustomObject]@{
                    User               = $Event.Properties[0].Value
                    DomainController   = $Event.MachineName
                    EventId            = $Event.Id
                    LockedOutTimeStamp = $Event.TimeCreated
                    Message            = ($Event.Message -split "`r")[0]
                    LockedOutLocation  = $Event.Properties[1].Value
                })
            }
        }
    }
    catch {
        Write-Log "Failed to query Lockout Events from PDC Emulator: $($_.Exception.Message)" "WARN"
    }

    Write-Log "Lockout location analysis complete. Found $($LockoutEvents.Count) matching lockout event(s)." "INFO"

    # Pipeline Output
    [PSCustomObject]@{
        UserStats       = $LockedOutStats
        LockoutLocation = $LockoutEvents
    }
}
catch {
    Write-Log "CRITICAL ERROR during lockout location discovery: $($_.Exception.Message)" "ERROR"
    exit 1
}