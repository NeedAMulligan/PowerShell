<#
.SYNOPSIS
    Standardized Folder Structure Creator.
.DESCRIPTION
    Creates a root folder and a predefined list of sub-folders in SharePoint.
#>

# --------------------------------------------------------------------------
# 1. VARIABLES & CONFIGURATION
# --------------------------------------------------------------------------
$Settings = @{
    SiteUrl      = "https://[TENANT].sharepoint.com/sites/[SITENAME]"
    LibraryName  = "Documents"
    LogDirectory = "C:\temp"
    ClientId     = "00000000-0000-0000-0000-000000000000"
    ScriptName   = "SharePoint_FolderCreator"
}

# Define your standard folder template here
$FolderTemplate = @(
    "Benefits", "Compensation", "Identity_Docs", "Performance_Reviews", "Training"
)

# --------------------------------------------------------------------------
# 2. EXIT CODES
# 0: Success | 1: Connection Failure | 3: Invalid Input
# --------------------------------------------------------------------------

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path -Path $Settings.LogDirectory -ChildPath "$($Settings.ScriptName)_$($Timestamp).log"

function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    $LogEntry | Out-File -FilePath $LogFile -Append
    Write-Host $LogEntry -ForegroundColor (switch($Level) { "ERROR" {"Red"} "WARN" {"Yellow"} Default {"White"} })
}

# --------------------------------------------------------------------------
# 3. EXECUTION
# --------------------------------------------------------------------------
Clear-Host
$NewFolderName = Read-Host "Enter the name for the new Root Folder"

if ([string]::IsNullOrWhiteSpace($NewFolderName)) { exit 3 }

try {
    Connect-PnPOnline -Url $Settings.SiteUrl -Interactive -ClientId $Settings.ClientId

    $RootPath = "$($Settings.LibraryName)/$NewFolderName"
    Write-Log "Creating Root: $NewFolderName" "INFO"
    $null = Resolve-PnPFolder -SiteRelativePath $RootPath

    foreach ($Sub in $FolderTemplate) {
        $FullSubPath = "$RootPath/$Sub"
        $null = Resolve-PnPFolder -SiteRelativePath $FullSubPath
        Write-Log "Validated Sub-Folder: $Sub" "INFO"
    }

    Write-Log "SUCCESS: Structure complete for $NewFolderName" "INFO"
    exit 0

} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 1
} finally {
    Disconnect-PnPOnline -ErrorAction SilentlyContinue
}