<#
.SYNOPSIS
    Bulk SharePoint Library Folder Mapping.
.DESCRIPTION
    Recursively scans a Document Library and identifies top-level folders 
    vs sub-folders, exporting the hierarchy to CSV.
#>

# --------------------------------------------------------------------------
# 1. VARIABLES & CONFIGURATION
# --------------------------------------------------------------------------
$Settings = @{
    SiteUrl      = "https://[TENANT].sharepoint.com/sites/[SITENAME]"
    LibraryName  = "Documents"
    LogDirectory = "C:\temp"
    ClientId     = "00000000-0000-0000-0000-000000000000"
    ScriptName   = "SharePoint_BulkCrawl"
}

# --------------------------------------------------------------------------
# 2. EXIT CODES
# 0: Success | 1: Connection/Auth Failure | 2: Library Not Found
# --------------------------------------------------------------------------

$DateStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ExportPath = Join-Path -Path $Settings.LogDirectory -ChildPath "BulkExport_$($DateStamp).csv"

try {
    Write-Host "Connecting to $($Settings.SiteUrl)..." -ForegroundColor Cyan
    Connect-PnPOnline -Url $Settings.SiteUrl -Interactive -ClientId $Settings.ClientId

    Write-Host "Deep-crawling library: $($Settings.LibraryName)..." -ForegroundColor Yellow
    $allItems = Get-PnPListItem -List $Settings.LibraryName -PageSize 500

    $results = @()
    foreach ($item in $allItems) {
        if ($item.FileSystemObjectType -eq "Folder") {
            $fullPath = $item["FileRef"]
            $parts = $fullPath.Split("/")
            
            # Logic: Adjust index based on site depth. 
            # Usually /sites/Name/Library/Folder (Index 4 is Top Level)
            if ($parts.Count -ge 5) {
                $results += [PSCustomObject]@{
                    "TopLevelFolder" = $parts[4]
                    "CurrentFolder"  = $item["FileLeafRef"]
                    "DepthLevel"     = $parts.Count
                    "FullUrlPath"    = $fullPath
                }
            }
        }
    }

    $results | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "SUCCESS! Exported to $ExportPath" -ForegroundColor Green
    exit 0

} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Disconnect-PnPOnline -ErrorAction SilentlyContinue
}