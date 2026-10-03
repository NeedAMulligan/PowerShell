#requires -Version 5.1

<#
.SYNOPSIS
    Exports sub-folder structures from a target SharePoint Online document library directory.

.DESCRIPTION
    Connects to SharePoint Online using PnP PowerShell and crawls the sub-folder structure of a designated 
    root folder within a specified Document Library. Outputs the discovered folder hierarchy to a CSV report 
    and logs execution details in C:\Temp, while automatically cleaning up log files older than 7 days.

.PARAMETER SiteUrl
    The full URL of the target SharePoint Online site collection.

.PARAMETER LibraryName
    The target document library containing the target folder structure. Defaults to 'Documents'.

.PARAMETER TargetFolder
    The root folder name or path within the document library to crawl (e.g., 'John Smith').

.PARAMETER ClientId
    The Application (Client) ID registered in Microsoft Entra ID for authentication.

.PARAMETER LogDirectory
    The local directory path where execution logs and CSV reports will be saved. Defaults to 'C:\Temp'.

.EXAMPLE
    .\Export-SharePointFolderStructure.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/HR" -TargetFolder "John Smith" -ClientId "11111111-2222-3333-4444-555555555555"

.EXAMPLE
    .\Export-SharePointFolderStructure.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/Legal" -LibraryName "Confidential" -TargetFolder "CaseFiles" -ClientId "11111111-2222-3333-4444-555555555555" -LogDirectory "C:\Temp"

.NOTES
    Author       : System Administrator
    Prerequisites: PnP.PowerShell module, app registration in Microsoft Entra ID.
    Change Log  :
        1.0 - Initial sanitized production release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Specify the target SharePoint Site URL.")]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LibraryName = "Documents",

    [Parameter(Mandatory = $true, HelpMessage = "Specify the target root folder name to crawl.")]
    [ValidateNotNullOrEmpty()]
    [string]$TargetFolder,

    [Parameter(Mandatory = $true, HelpMessage = "Specify the Entra ID Application (Client) ID.")]
    [ValidateNotNullOrEmpty()]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

# --------------------------------------------------------------------------
# 1. PREREQUISITES & MODULE CHECKS
# --------------------------------------------------------------------------
$RequiredModule = "PnP.PowerShell"

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
$ScriptName = "SharePoint_SingleExport"
$DateStamp  = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

# Remove log files older than 7 days from the log directory
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
$SafeName   = $TargetFolder -replace '[^a-zA-Z0-9]', '_'
$ExportPath = Join-Path -Path $LogDirectory -ChildPath "Export-$($SafeName)-$($DateStamp).csv"

try {
    Write-Log "Connecting to $SiteUrl..." "INFO"
    Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $ClientId -ErrorAction Stop

    # Calculate Server Relative Path
    $web = Get-PnPWeb -Includes ServerRelativeUrl
    $ServerRelativePath = "$($web.ServerRelativeUrl)/$LibraryName/$TargetFolder" -replace "//", "/"
    
    Write-Log "Crawling sub-folders at: $ServerRelativePath" "INFO"
    
    $allItems = Get-PnPListItem -List $LibraryName -FolderServerRelativeUrl $ServerRelativePath -PageSize 500 -ErrorAction Stop
    $results  = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($item in $allItems) {
        if ($item.FileSystemObjectType -eq "Folder") {
            $results.Add([PSCustomObject]@{
                "ParentFolder" = $TargetFolder
                "FolderName"   = $item["FileLeafRef"]
                "RelativeURL"  = $item["FileRef"]
            })
        }
    }

    if ($results.Count -gt 0) {
        $results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
        Write-Log "SUCCESS! Exported $($results.Count) items to $ExportPath" "INFO"
        exit 0
    }
    else {
        Write-Log "No sub-folders found inside '$TargetFolder'." "WARN"
        exit 2
    }

}
catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 1
}
finally {
    Disconnect-PnPOnline -ErrorAction SilentlyContinue
}
