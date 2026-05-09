<#
.SYNOPSIS
    Manually creates the Entra ID Service Connection Point (SCP) for GCC High.
    
.DESCRIPTION
    1. Defines custom exit codes.
    2. Logs to C:\temp.
    3. Navigates the Configuration partition.
    4. Creates the "Device Registration Configuration" container if missing.
    5. Creates the SCP object with GCC High keywords.

.EXITCODES
    0    = Success
    1901 = Failed to create Container
    1902 = Failed to create SCP Object
    1903 = Permission Denied (Must run as Domain/Enterprise Admin)
#>

$ErrorActionPreference = "Stop"

# --- USER CONFIGURATION - UPDATE THESE ---
$TenantID = "fa70b252-103b-4108-8d7f-f9f46fadc0de"
$TenantName = "optechspace.onmicrosoft.us" # Ensure .us for GCC High
# -----------------------------------------

$ExitCode = 0
$ScriptName = "Create-GCCHigh-SCP"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir = "C:\temp"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $LogDir "$($ScriptName)_$($Timestamp).log"

function Write-Log {
    Param([string]$Message)
    $Msg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') : $Message"
    $Msg | Out-File -FilePath $LogFile -Append
}

Write-Log "Initializing SCP Creation for GCC High Tenant: $TenantName"

try {
    $RootDSE = [ADSI]"LDAP://RootDSE"
    $ConfigContext = $RootDSE.configurationNamingContext
    $ServicesPath = "LDAP://CN=Services,$ConfigContext"
    $ServicesObj = [ADSI]$ServicesPath

    # 1. Create the Parent Container if it doesn't exist
    $ContainerName = "CN=Device Registration Configuration"
    $ContainerPath = "$ContainerName,CN=Services,$ConfigContext"
    
    if (-not [ADSI]::Exists("LDAP://$ContainerPath")) {
        Write-Log "Creating Container: $ContainerName"
        $NewContainer = $ServicesObj.Create("container", $ContainerName)
        $NewContainer.SetInfo()
    }

    # 2. Create the SCP Object
    $SCPName = "CN=62a0ff2e-97b9-4513-943f-0d221bd30080"
    $FullSCPPath = "LDAP://$SCPName,$ContainerPath"

    if ([ADSI]::Exists($FullSCPPath)) {
        Write-Log "SCP Object already exists. Updating keywords..."
        $SCPObj = [ADSI]$FullSCPPath
    } else {
        Write-Log "Creating SCP Object: $SCPName"
        $ContainerObj = [ADSI]"LDAP://$ContainerPath"
        $SCPObj = $ContainerObj.Create("serviceConnectionPoint", $SCPName)
        $SCPObj.SetInfo()
    }

    # 3. Set Keywords
    $SCPObj.PutEx(3, "keywords", @("azureADId:$TenantID", "azureADName:$TenantName"))
    $SCPObj.SetInfo()
    
    Write-Log "SUCCESS: SCP configured for GCC High."

} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)"
    $ExitCode = 1902
}

exit $ExitCode
