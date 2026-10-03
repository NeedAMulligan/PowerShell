#requires -Version 5.1

<#
.SYNOPSIS
    Performs comprehensive Active Directory Domain Controller health checks and generates an HTML report.

.DESCRIPTION
    Queries the current Active Directory forest for all Domain Controllers and performs connectivity, 
    service, and dcdiag diagnostic checks (Ping, Netlogon, NTDS, DNS, Replications, Services, Advertising, 
    and FSMOCheck). Generates an HTML report saved to C:\Temp\ and optionally sends the report via SMTP email.

.PARAMETER SmtpServer
    The FQDN or IP address of the SMTP server used to send the health report email.

.PARAMETER From
    The sender email address for the health report notification.

.PARAMETER To
    The recipient email address or array of addresses for the report.

.PARAMETER ReportPath
    The target file path where the generated HTML report will be saved. Defaults to 'C:\Temp\ADReport.htm'.

.PARAMETER LogDirectory
    The directory path where execution logs are stored. Defaults to 'C:\Temp'.

.PARAMETER Timeout
    The maximum execution timeout in seconds for background jobs running service and dcdiag tests. Defaults to 60 seconds.

.EXAMPLE
    .\Invoke-ADHealthCheck.ps1 -SmtpServer "mail.contoso.com" -From "reports@contoso.com" -To "admin@contoso.com"

.EXAMPLE
    .\Invoke-ADHealthCheck.ps1 -ReportPath "C:\Temp\CustomADReport.htm" -Timeout 90

.NOTES
    Author       : System Administrator / Sanitized
    Prerequisites: RSAT Active Directory Domain Services Tools, Administrator Elevation.
    Change Log   :
        1.0 - Initial sanitized production release with standard logging and housekeeping.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SmtpServer,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$From,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$To,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ReportPath = "C:\Temp\ADReport.htm",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp",

    [Parameter(Mandatory = $false)]
    [ValidateRange(10, 300)]
    [int]$Timeout = 60
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & PRIVILEGE CHECKS
# --------------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

$RequiredModule = "ActiveDirectory"
if (-not (Get-Module -ListAvailable -Name $RequiredModule)) {
    Write-Error "Required module '$RequiredModule' was not found. Please install RSAT Active Directory Tools."
    exit 1
}

Import-Module -Name $RequiredModule -ErrorAction Stop

# --------------------------------------------------------------------------
# 2. LOGGING INITIALIZATION & HOUSEKEEPING
# --------------------------------------------------------------------------
$ScriptName = "AD_HealthCheck"
$DateStamp  = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

# Log rotation: Remove log files older than 7 days
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

# Helper function to execute background jobs with timeouts
function Invoke-JobWithTimeout {
    param(
        [scriptblock]$ScriptBlock,
        [array]$ArgumentList,
        [int]$TimeoutSeconds,
        [string]$TestName
    )
    
    $Job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    $Completed = Wait-Job $Job -Timeout $TimeoutSeconds

    if (-not $Completed) {
        Stop-Job $Job
        Remove-Job $Job -Force
        return @{ "Status" = "Timeout"; "Output" = $null }
    }
    else {
        $Result = Receive-Job $Job
        Remove-Job $Job -Force
        return @{ "Status" = "Completed"; "Output" = $Result }
    }
}

# --------------------------------------------------------------------------
# 3. REPORT SETUP & EXECUTION
# --------------------------------------------------------------------------
Write-Log "Starting Active Directory Health Check processing..." "INFO"

$HtmlHeader = @"
<html>
<head>
    <meta http-equiv='Content-Type' content='text/html; charset=iso-8859-1'>
    <title>AD Status Report</title>
    <style type="text/css">
        td { font-family: Tahoma; font-size: 11px; border: 1px solid #999999; padding: 3px; }
        body { margin: 5px; }
        table { border: thin solid #000000; border-collapse: collapse; }
    </style>
</head>
<body>
    <table width='100%'>
        <tr bgcolor='Lavender'>
            <td colspan='10' height='25' align='center'>
                <font face='tahoma' color='#003399' size='4'><strong>Active Directory Health Check</strong></font>
            </td>
        </tr>
    </table>
    <table width='100%'>
        <tr bgcolor='IndianRed'>
            <td width='10%' align='center'><B>Identity</B></td>
            <td width='9%' align='center'><B>PingStatus</B></td>
            <td width='9%' align='center'><B>NetlogonService</B></td>
            <td width='9%' align='center'><B>NTDSService</B></td>
            <td width='9%' align='center'><B>DNSServiceStatus</B></td>
            <td width='9%' align='center'><B>NetlogonsTest</B></td>
            <td width='9%' align='center'><B>ReplicationTest</B></td>
            <td width='9%' align='center'><B>ServicesTest</B></td>
            <td width='9%' align='center'><B>AdvertisingTest</B></td>
            <td width='9%' align='center'><B>FSMOCheckTest</B></td>
        </tr>
"@

$HtmlRows = [System.Text.StringBuilder]::new()

try {
    $Forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
    $DCServers = $Forest.Domains | ForEach-Object { $_.DomainControllers } | ForEach-Object { $_.Name }
    Write-Log "Discovered $($DCServers.Count) Domain Controller(s) across forest." "INFO"
}
catch {
    Write-Log "Failed to query Active Directory forest: $($_.Exception.Message)" "ERROR"
    exit 1
}

foreach ($DC in $DCServers) {
    Write-Log "Testing Domain Controller: $DC" "INFO"
    [void]$HtmlRows.AppendLine("<tr>")
    [void]$HtmlRows.AppendLine("<td bgcolor='GainsBoro' align='center'><B>$DC</B></td>")

    if (Test-Connection -ComputerName $DC -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        Write-Log "$DC - Ping: Success" "INFO"
        [void]$HtmlRows.AppendLine("<td bgcolor='Aquamarine' align='center'><B>Success</B></td>")

        # Define services to check
        $Services = @("Netlogon", "NTDS", "DNS")
        foreach ($Svc in $Services) {
            $SvcBlock = { param($Server, $Name) Get-Service -ComputerName $Server -Name $Name -ErrorAction SilentlyContinue }
            $JobResult = Invoke-JobWithTimeout -ScriptBlock $SvcBlock -ArgumentList $DC, $Svc -TimeoutSeconds $Timeout -TestName "$Svc Service"

            if ($JobResult.Status -eq "Timeout") {
                Write-Log "$DC - $Svc Service Timeout" "WARN"
                [void]$HtmlRows.AppendLine("<td bgcolor='Yellow' align='center'><B>${Svc}Timeout</B></td>")
            }
            else {
                $SvcStatus = $JobResult.Output.Status
                if ($SvcStatus -eq "Running") {
                    Write-Log "$DC - $Svc Service: Running" "INFO"
                    [void]$HtmlRows.AppendLine("<td bgcolor='Aquamarine' align='center'><B>Running</B></td>")
                }
                else {
                    Write-Log "$DC - $Svc Service: $($SvcStatus ?? 'Stopped')" "ERROR"
                    [void]$HtmlRows.AppendLine("<td bgcolor='Red' align='center'><B>$($SvcStatus ?? 'Stopped')</B></td>")
                }
            }
        }

        # Define dcdiag tests to run
        $DcdiagTests = @(
            @{ Name = "Netlogons"; Target = "passed test NetLogons" },
            @{ Name = "Replications"; Target = "passed test Replications" },
            @{ Name = "Services"; Target = "passed test Services" },
            @{ Name = "Advertising"; Target = "passed test Advertising" },
            @{ Name = "FsmoCheck"; Target = "passed test FsmoCheck" }
        )

        foreach ($Test in $DcdiagTests) {
            $TestName = $Test.Name
            $TargetString = $Test.Target
            
            $DcDiagBlock = { param($Server, $TestType) dcdiag /test:$TestType /s:$Server }
            $JobResult = Invoke-JobWithTimeout -ScriptBlock $DcDiagBlock -ArgumentList $DC, $TestName -TimeoutSeconds $Timeout -TestName "dcdiag $TestName"

            if ($JobResult.Status -eq "Timeout") {
                Write-Log "$DC - $TestName Test Timeout" "WARN"
                [void]$HtmlRows.AppendLine("<td bgcolor='Yellow' align='center'><B>${TestName}Timeout</B></td>")
            }
            else {
                $OutputString = $JobResult.Output -join " "
                if ($OutputString -like "*$TargetString*") {
                    Write-Log "$DC - $TestName Test: Passed" "INFO"
                    [void]$HtmlRows.AppendLine("<td bgcolor='Aquamarine' align='center'><B>${TestName}Passed</B></td>")
                }
                else {
                    Write-Log "$DC - $TestName Test: Failed" "ERROR"
                    [void]$HtmlRows.AppendLine("<td bgcolor='Red' align='center'><B>${TestName}Fail</B></td>")
                }
            }
        }
    }
    else {
        Write-Log "$DC - Ping: Failed" "ERROR"
        [void]$HtmlRows.AppendLine("<td bgcolor='Red' align='center'><B>Ping Fail</B></td>")
        1..8 | ForEach-Object { [void]$HtmlRows.AppendLine("<td bgcolor='Red' align='center'><B>Ping Fail</B></td>") }
    }

    [void]$HtmlRows.AppendLine("</tr>")
}

$HtmlFooter = @"
    </table>
</body>
</html>
"@

$FinalHtml = $HtmlHeader + $HtmlRows.ToString() + $HtmlFooter
Set-Content -Path $ReportPath -Value $FinalHtml -Encoding UTF8 -Force
Write-Log "AD Health Check report generated at: $ReportPath" "INFO"

# --------------------------------------------------------------------------
# 4. EMAIL REPORT DELIVERY
# --------------------------------------------------------------------------
if ($SmtpServer -and $From -and $To) {
    try {
        Write-Log "Sending health report email to $To via $SmtpServer..." "INFO"
        Send-MailMessage -SmtpServer $SmtpServer -From $From -To $To -Subject "Active Directory Health Monitor Report" -Body $FinalHtml -BodyAsHtml -ErrorAction Stop
        Write-Log "Email sent successfully." "INFO"
    }
    catch {
        Write-Log "Failed to send email notification: $($_.Exception.Message)" "ERROR"
    }
}
else {
    Write-Log "SMTP configuration incomplete or omitted. Skipping email delivery." "INFO"
}
