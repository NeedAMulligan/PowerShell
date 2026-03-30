<#
.SYNOPSIS
    Queries Entra ID and Intune for devices inactive for 90+ days.
    Prefixes all output files with the Tenant Domain Name.

.DESCRIPTION
    1. Checks/Installs Microsoft.Graph modules.
    2. Connects to Microsoft Graph (Interactive).
    3. Retrieves the Primary Tenant Domain Name.
    4. Compares Entra ID and Intune check-in timestamps.
    5. Exports results to C:\temp\[TenantName]_StaleDevices_...
#>

# ---------------------------------------------------------------------------
# VARIABLES SECTION
# ---------------------------------------------------------------------------
$InactivityDays   = 90
$LogPath          = "C:\temp"
$Timestamp        = Get-Date -Format "yyyyMMdd_HHmmss"
$RequiredModules  = @("Microsoft.Graph.Authentication", "Microsoft.Graph.Devices", "Microsoft.Graph.DeviceManagement", "Microsoft.Graph.Identity.DirectoryManagement")
$TargetDate       = (Get-Date).AddDays(-$InactivityDays)

# Note: ExportFile and LogFile names are defined dynamically after Tenant Name is retrieved.

# ---------------------------------------------------------------------------
# FUNCTIONS
# ---------------------------------------------------------------------------

function Write-LocalLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]$Level = "INFO",
        [string]$Path = $null
    )
    
    $Color = "Cyan"
    if ($Level -eq "ERROR") { $Color = "Red" }
    elseif ($Level -eq "WARN") { $Color = "Yellow" }

    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    
    Write-Host $LogEntry -ForegroundColor $Color
    if ($Path) { $LogEntry | Out-File -FilePath $Path -Append }
}

function Initialize-Environment {
    Write-LocalLog "Checking environment and local directory structure..."
    if (!(Test-Path $LogPath)) {
        try { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
        catch { Write-LocalLog "Failed to create $LogPath." "ERROR"; exit 3 }
    }

    foreach ($Module in $RequiredModules) {
        if (!(Get-Module -ListAvailable -Name $Module)) {
            Write-LocalLog "Module $Module is missing. Attempting installation..." "WARN"
            try { Install-Module -Name $Module -Scope CurrentUser -AllowClobber -Force -Confirm:$false }
            catch { Write-LocalLog "Failed to install $Module." "ERROR"; exit 1 }
        }
    }
}

# ---------------------------------------------------------------------------
# MAIN EXECUTION BLOCK
# ---------------------------------------------------------------------------

Try {
    Initialize-Environment

    Write-LocalLog "Initiating Interactive Login to Microsoft Graph..."
    # Scopes: Added 'Organization.Read.All' to get the Tenant Name
    Connect-MgGraph -Scopes "Device.Read.All", "DeviceManagementManagedDevices.Read.All", "Organization.Read.All" -ContextScope CurrentUser

    # 1. Fetch Tenant Name for file naming
    Write-LocalLog "Retrieving Tenant information..."
    $Org = Get-MgOrganization | Select-Object -First 1
    $TenantName = ($Org.VerifiedDomains | Where-Object { $_.IsDefault }).Name
    if (!$TenantName) { $TenantName = "UnknownTenant" }

    # Define dynamic file paths
    $ExportFile = "$LogPath\${TenantName}_StaleDevices_$Timestamp.csv"
    $LogFile    = "$LogPath\${TenantName}_StaleDeviceLog_$Timestamp.log"

    Write-LocalLog "Tenant identified as: $TenantName" -Path $LogFile

    # 2. Fetch Data
    Write-LocalLog "Fetching Entra ID Devices..." -Path $LogFile
    $EntraDevices = Get-MgDevice -All -Property "Id","DisplayName","OperatingSystem","ApproximateLastSignInDateTime","AccountEnabled","DeviceId"
    
    Write-LocalLog "Fetching Intune Managed Devices..." -Path $LogFile
    $IntuneDevices = Get-MgDeviceManagementManagedDevice -All -Property "Id","DeviceName","LastSyncDateTime","AzureADDeviceId"

    $Results = New-Object System.Collections.Generic.List[PSCustomObject]

    Write-LocalLog "Filtering for activity older than $($TargetDate.ToShortDateString())..." -Path $LogFile
    
    foreach ($ECloud in $EntraDevices) {
        $ICloud = $IntuneDevices | Where-Object { $_.AzureADDeviceId -eq $ECloud.DeviceId }

        $EntraDate  = $ECloud.ApproximateLastSignInDateTime
        $IntuneDate = $ICloud.LastSyncDateTime

        $IsStaleInEntra  = ($null -eq $EntraDate) -or ($EntraDate -lt $TargetDate)
        $IsStaleInIntune = ($null -eq $IntuneDate) -or ($IntuneDate -lt $TargetDate)

        if ($IsStaleInEntra -and $IsStaleInIntune) {
            $Status = if ($ECloud.AccountEnabled) { "Enabled" } else { "Disabled" }
            
            $Object = [PSCustomObject]@{
                TenantName         = $TenantName
                DisplayName        = $ECloud.DisplayName
                EntraObjectID      = $ECloud.Id
                PhysicalDeviceId   = $ECloud.DeviceId
                AccountStatus      = $Status
                OS                 = $ECloud.OperatingSystem
                EntraLastSignIn    = $EntraDate
                IntuneLastSync     = $IntuneDate
                IntuneManagedID    = if($ICloud.Id){$ICloud.Id} else {"Not Managed"}
            }
            $Results.Add($Object)
        }
    }

    if ($Results.Count -gt 0) {
        Write-LocalLog "Found $($Results.Count) stale devices. Exporting to $ExportFile" -Path $LogFile
        $Results | Export-Csv -Path $ExportFile -NoTypeInformation
        Write-LocalLog "Export Success." -Path $LogFile
    } else {
        Write-LocalLog "No stale devices found matching the criteria." "WARN" -Path $LogFile
    }

} Catch {
    Write-LocalLog "A critical error occurred: $($_.Exception.Message)" "ERROR"
    exit 2
} Finally {
    if (Get-MgContext) {
        Write-LocalLog "Closing Microsoft Graph session..."
        Disconnect-MgGraph
    }
}

exit 0