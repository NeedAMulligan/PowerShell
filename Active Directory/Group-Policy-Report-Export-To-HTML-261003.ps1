#requires -Version 5.1

<#
.SYNOPSIS
    Performs a deep discovery audit of Group Policy Objects (GPOs) linked across the domain root and all OUs.

.DESCRIPTION
    Scans Active Directory domain root and all Organizational Units (OUs) for gPLink attributes, extracts GPO GUIDs, 
    resolves GPO display names, generates individual HTML GPO reports, and exports a master CSV link inventory. 
    Includes standard execution logging in C:\Temp and automated 7-day log maintenance cleanup.

.PARAMETER ExportPath
    The target directory where HTML GPO reports and the master CSV link inventory will be written. 
    Defaults to 'C:\Temp\GPO_DeepAudit_<yyyyMMdd_HHmmss>'.

.PARAMETER Domain
    Target Active Directory Domain or Domain Controller FQDN. Defaults to current domain if omitted.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Discover-GPODeepLinks.ps1

.EXAMPLE
    .\Discover-GPODeepLinks.ps1 -ExportPath "C:\Temp\GPO_Audit_Report" -Domain "contoso.com"

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Group Policy Tools module, RSAT Active Directory module, Domain Read Rights.
    Change Log   :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify directory path for exported GPO HTML reports and CSV inventory.")]
    [string]$ExportPath,

    [Parameter(Mandatory = $false, HelpMessage = "Specify target Active Directory Domain or Server FQDN.")]
    [string]$Domain,

    [Parameter(Mandatory = $false, HelpMessage = "Specify directory for execution log storage.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Warning "Running in non-elevated context. Ensure proper privileges to query Active Directory and Group Policy reports."
}

$RequiredModules = @("GroupPolicy", "ActiveDirectory")

foreach ($Module in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $Module)) {
        Write-Host "Required module '$Module' was not found. Attempting installation for CurrentUser..." -ForegroundColor Yellow
        try {
            Install-Module -Name $Module -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop
            Write-Host "Successfully installed '$Module'." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install required module '$Module': $($_.Exception.Message)"
            exit 1
        }
    }
    Import-Module -Name $Module -ErrorAction Stop
}

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "GPO_DeepLink_Discovery"
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
        $ExportPath = Join-Path -Path $LogDirectory -ChildPath "GPO_DeepAudit_$DateStamp"
    }

    $CsvPath = Join-Path -Path $ExportPath -ChildPath "00_GPO_Link_Inventory.csv"

    Write-Log "Starting Deep Discovery for Domain Root and OU GPO Links..." "INFO"
    Write-Log "Export Directory Target: $ExportPath" "INFO"

    if (-not (Test-Path -Path $ExportPath)) {
        New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
    }

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $AllTargets = [System.Collections.Generic.List[PSCustomObject]]::new()

    # 1. Domain Root Link Query
    Write-Log "Checking Domain Root GPO links..." "INFO"
    $DomainQueryParams = @{ ErrorAction = "Stop" }
    if ($Domain) { $DomainQueryParams.Add("Server", $Domain) }

    $DomainObj = Get-ADDomain @DomainQueryParams
    $RootDN    = $DomainObj.DistinguishedName

    $DomainObjectParams = @{ Identity = $RootDN; Properties = "gPLink"; ErrorAction = "Stop" }
    if ($Domain) { $DomainObjectParams.Add("Server", $Domain) }

    $DomainLinks = (Get-ADObject @DomainObjectParams).gPLink

    $AllTargets.Add([PSCustomObject]@{ DN = $RootDN; gPLink = $DomainLinks; Type = "Domain Root" })

    # 2. OU Link Query
    Write-Log "Scanning all OUs for linked GPOs..." "INFO"
    $OuQueryParams = @{ Filter = "*"; Properties = "gPLink"; ErrorAction = "Stop" }
    if ($Domain) { $OuQueryParams.Add("Server", $Domain) }

    $OUs = Get-ADOrganizationalUnit @OuQueryParams | Where-Object { $_.gPLink }

    foreach ($OU in $OUs) {
        $AllTargets.Add([PSCustomObject]@{ DN = $OU.DistinguishedName; gPLink = $OU.gPLink; Type = "OU" })
    }

    Write-Log "Discovered $($AllTargets.Count) target container(s) to process." "INFO"

    # 3. Process GPO Links
    $Regex = "cn=({[0-9A-F-]+})"

    foreach ($Target in $AllTargets) {
        if ($Target.gPLink) {
            $Matches = [regex]::Matches($Target.gPLink, $Regex)

            foreach ($Match in $Matches) {
                $GpoGuid = $Match.Groups[1].Value

                try {
                    $GpoParams = @{ Guid = $GpoGuid; ErrorAction = "Stop" }
                    if ($Domain) { $GpoParams.Add("Domain", $Domain) }

                    $GPO = Get-GPO @GpoParams
                    $CleanName = $GPO.DisplayName -replace '[\\/:*?"<>|]', '_'
                    $HtmlFileName = "$($CleanName).html"

                    Write-Log "Link found: '$($GPO.DisplayName)' on $($Target.Type) ($($Target.DN))" "INFO"

                    # Generate HTML Report if not already present
                    $TargetReportPath = Join-Path -Path $ExportPath -ChildPath $HtmlFileName
                    if (-not (Test-Path -Path $TargetReportPath)) {
                        $ReportParams = @{ Guid = $GPO.Id; ReportType = "Html"; Path = $TargetReportPath; ErrorAction = "Stop" }
                        if ($Domain) { $ReportParams.Add("Domain", $Domain) }
                        Get-GPOReport @ReportParams
                    }

                    $Results.Add([PSCustomObject]@{
                        GPOName    = $GPO.DisplayName
                        TargetType = $Target.Type
                        TargetDN   = $Target.DN
                        GPOStatus  = $GPO.GpoStatus
                        ReportFile = $HtmlFileName
                    })
                }
                catch {
                    Write-Log "WARNING: Could not resolve GPO GUID '$GpoGuid' linked on $($Target.DN): $($_.Exception.Message)" "WARN"
                }
            }
        }
    }

    if ($Results.Count -gt 0) {
        $Results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding utf8
        Write-Log "SUCCESS: Exported $($Results.Count) GPO link entry(ies) to $CsvPath" "INFO"
    }
    else {
        Write-Log "No GPO links were found across domain containers." "WARN"
    }
}
catch {
    Write-Log "CRITICAL ERROR during GPO deep discovery execution: $($_.Exception.Message)" "ERROR"
    exit 1
}