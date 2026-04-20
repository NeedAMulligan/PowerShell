<#
.SYNOPSIS
    Targeted SharePoint Folder Export.
.DESCRIPTION
    Connects to PnP Online and exports the sub-folder structure of a specific 
    root folder (e.g., an Employee Name) within a Document Library.
.PARAMETER TargetFolder
    The name of the folder within the library to crawl.
.EXAMPLE
    .\Export-SingleUser.ps1
#>

# --------------------------------------------------------------------------
# 1. VARIABLES & CONFIGURATION
# --------------------------------------------------------------------------
$Settings = @{
    SiteUrl      = "https://[TENANT].sharepoint.com/sites/[SITENAME]"
    LibraryName  = "Documents"
    LogDirectory = "C:\temp"
    ClientId     = "00000000-0000-0000-0000-000000000000" # Entra App ID
    ScriptName   = "SharePoint_SingleExport"
}

# --------------------------------------------------------------------------
# 2. EXIT CODES
# --------------------------------------------------------------------------
# 0: Success
# 1: Connection Failure
# 2: Target Folder Not Found
# 3: User Cancelled / Empty Input

# --------------------------------------------------------------------------
# 3. LOGGING & INITIALIZATION
# --------------------------------------------------------------------------
$DateStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path -Path $Settings.LogDirectory -ChildPath "$($Settings.ScriptName)_$($DateStamp).log"

if (-not (Test-Path $Settings.LogDirectory)) { New-Item $Settings.LogDirectory -ItemType Directory | Out-Null }

function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    $LogEntry | Out-File -FilePath $LogFile -Append
    $Color = switch($Level) { "ERROR" {"Red"} "WARN" {"Yellow"} Default {"Cyan"} }
    Write-Host $LogEntry -ForegroundColor $Color
}

# --------------------------------------------------------------------------
# 4. EXECUTION
# --------------------------------------------------------------------------
Clear-Host
$TargetUser = Read-Host "Enter the Folder Name to export (e.g., John Smith)"

if ([string]::IsNullOrWhiteSpace($TargetUser)) {
    Write-Log "No name entered. Exiting." "WARN"
    exit 3
}

$SafeName = $TargetUser -replace '[^a-zA-Z0-9]', '_'
$ExportPath = Join-Path -Path $Settings.LogDirectory -ChildPath "Export-$($SafeName)-$($DateStamp).csv"

try {
    Write-Log "Connecting to $($Settings.SiteUrl)..." "INFO"
    Connect-PnPOnline -Url $Settings.SiteUrl -Interactive -ClientId $Settings.ClientId

    # Calculate Server Relative Path
    $web = Get-PnPWeb -Includes ServerRelativeUrl
    $ServerRelativePath = "$($web.ServerRelativeUrl)/$($Settings.LibraryName)/$TargetUser" -replace "//", "/"
    
    Write-Log "Crawling sub-folders at: $ServerRelativePath" "INFO"
    
    $allItems = Get-PnPListItem -List $Settings.LibraryName -FolderServerRelativeUrl $ServerRelativePath -PageSize 500
    $results = @()

    foreach ($item in $allItems) {
        if ($item.FileSystemObjectType -eq "Folder") {
            $results += [PSCustomObject]@{
                "ParentFolder" = $TargetUser
                "FolderName"   = $item["FileLeafRef"]
                "RelativeURL"  = $item["FileRef"]
            }
        }
    }

    if ($results.Count -gt 0) {
        $results | Export-Csv -Path $ExportPath -NoTypeInformation
        Write-Log "SUCCESS! Exported $($results.Count) items to $ExportPath" "INFO"
        exit 0
    } else {
        Write-Log "No sub-folders found inside '$TargetUser'." "WARN"
        exit 2
    }

} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 1
} finally {
    Disconnect-PnPOnline -ErrorAction SilentlyContinue
}