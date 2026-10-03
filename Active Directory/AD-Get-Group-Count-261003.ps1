#requires -Version 5.1

<#
.SYNOPSIS
    Queries Active Directory for a specified group and returns the total member count.

.DESCRIPTION
    Connects to Active Directory using the ActiveDirectory module, retrieves the target group,
    and calculates the total number of members. Logs execution output to C:\Temp\ and cleans up
    log files older than 7 days.

.PARAMETER GroupName
    The Identity (Name, SamAccountName, or DistinguishedName) of the target Active Directory group. Defaults to 'VPN'.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Get-ADGroupMemberCount.ps1 -GroupName "VPN"

.EXAMPLE
    .\Get-ADGroupMemberCount.ps1 -GroupName "Domain Admins" -LogDirectory "C:\Temp"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Tools module, Domain User/Admin privileges.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the target Active Directory group name.")]
    [ValidateNotNullOrEmpty()]
    [string]$GroupName = "VPN",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & MODULE CHECKS
# --------------------------------------------------------------------------
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
$ScriptName = "AD_GroupMemberCount"
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
    Write-Log "Searching for Active Directory group '$GroupName'..." "INFO"
    
    $GroupObject = Get-ADGroup -Identity $GroupName -Properties Member -ErrorAction Stop
    
    if ($GroupObject) {
        $MemberCount = @($GroupObject.Member).Count
        Write-Log "Group '$($GroupObject.Name)' found. Total Member Count: $MemberCount" "INFO"
        
        # Output custom object to pipeline
        [PSCustomObject]@{
            GroupName   = $GroupObject.Name
            DN          = $GroupObject.DistinguishedName
            MemberCount = $MemberCount
        }
    }
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Log "The Active Directory group '$GroupName' was not found." "ERROR"
    exit 1
}
catch {
    Write-Log "Failed to query Active Directory: $($_.Exception.Message)" "ERROR"
    exit 1
}