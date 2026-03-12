<#
Custom Exit Codes:
0    = Success
1001 = GroupPolicy or ActiveDirectory Module missing
1002 = Directory creation failed
1003 = No Links found after deep scan
1004 = General Script Error
#>

$exitCode = 0
$scriptName = "GPO_DeepLink_Discovery"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = "C:\temp"
$logFile = Join-Path $logPath "$($scriptName)_$($timestamp).log"
$exportPath = "C:\temp\GPO_DeepAudit_$timestamp"
$csvPath = Join-Path $exportPath "00_GPO_Link_Inventory.csv"

# Ensure Log and Export directories exist
try {
    if (-not (Test-Path $logPath)) { New-Item -Path $logPath -ItemType Directory -Force }
    if (-not (Test-Path $exportPath)) { New-Item -Path $exportPath -ItemType Directory -Force }
} catch {
    exit 1002
}

Function Write-Log {
    Param ([string]$Message)
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    $logEntry | Out-File -FilePath $logFile -Append
}

Write-Log "Starting Deep Discovery for Domain and OU links..."

# Check for required modules
if (-not (Get-Module -ListAvailable GroupPolicy) -or -not (Get-Module -ListAvailable ActiveDirectory)) {
    Write-Log "ERROR: GroupPolicy or ActiveDirectory module is missing."
    exit 1001
}

Import-Module GroupPolicy
Import-Module ActiveDirectory

try {
    $results = @()
    
    # 1. Get the Domain Root Link
    Write-Log "Checking Domain Root..."
    $domainObj = Get-ADDomain
    $rootDistinguishedName = $domainObj.DistinguishedName
    $domainLinks = (Get-ADObject -Identity $rootDistinguishedName -Properties gPLink).gPLink
    
    # 2. Get all OUs with links
    Write-Log "Scanning all OUs for links..."
    $containers = Get-ADOrganizationalUnit -Filter * -Properties gPLink | Where-Object { $_.gPLink }
    
    # Combine Domain Root and OUs into one list to process
    $allTargets = @()
    $allTargets += [PSCustomObject]@{ DN = $rootDistinguishedName; gPLink = $domainLinks; Type = "Domain Root" }
    foreach ($ou in $containers) {
        $allTargets += [PSCustomObject]@{ DN = $ou.DistinguishedName; gPLink = $ou.gPLink; Type = "OU" }
    }

    foreach ($target in $allTargets) {
        if ($target.gPLink) {
            # GPLink attribute format is: [LDAP://cn={GUID},cn=policies,cn=system,DC=...;0]
            # We need to extract the GUIDs
            $regex = "cn=({[0-9A-F-]+})"
            $matches = [regex]::Matches($target.gPLink, $regex)
            
            foreach ($match in $matches) {
                $gpoGuid = $match.Groups[1].Value
                try {
                    $gpo = Get-GPO -Guid $gpoGuid
                    $cleanName = $gpo.DisplayName -replace '[\\/:*?"<>|]', '_'
                    $htmlFileName = "$($cleanName).html"
                    
                    Write-Log "Linking found: $($gpo.DisplayName) on $($target.DN)"
                    
                    # Generate HTML if not already generated
                    $targetPath = Join-Path $exportPath $htmlFileName
                    if (-not (Test-Path $targetPath)) {
                        Get-GPOReport -Guid $gpo.Id -ReportType Html -Path $targetPath
                    }

                    $results += [PSCustomObject]@{
                        GPOName     = $gpo.DisplayName
                        TargetType  = $target.Type
                        TargetDN    = $target.DN
                        GPOStatus   = $gpo.GpoStatus
                        ReportFile  = $htmlFileName
                    }
                } catch {
                    Write-Log "Warning: Could not resolve GPO Guid $gpoGuid linked on $($target.DN)"
                }
            }
        }
    }

    if ($results.Count -gt 0) {
        $results | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Log "Success: $($results.Count) link entries exported to $csvPath"
    } else {
        Write-Log "No links found even with deep scan."
        $exitCode = 1003
    }

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)"
    $exitCode = 1004
}

exit $exitCode