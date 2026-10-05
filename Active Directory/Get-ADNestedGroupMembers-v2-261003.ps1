#requires -Version 5.1

<#
.SYNOPSIS
    Recursively enumerates nested Active Directory group members with depth levels and circular membership detection.

.DESCRIPTION
    Recursively audits Active Directory group memberships for a specified group or pipeline input. 
    Tracks nesting levels, parent group relationships, account status (Enabled/Disabled), and identifies 
    circular group dependencies. Optionally outputs formatted indented hierarchy views. 
    Writes execution logs to C:\Temp and automatically maintains a 7-day log cleanup rotation.

.PARAMETER GroupName
    The Identity (Name, SamAccountName, or DistinguishedName) of the target Active Directory group. Accepts pipeline input.

.PARAMETER Nesting
    Internal parameter used for tracking recursion depth level. Defaults to 0 for top-level calls.

.PARAMETER Circular
    Internal flag parameter used for tracking circular membership states during recursion.

.PARAMETER Indent
    Switch parameter to output a tree-like hierarchy formatted display instead of structured objects.

.PARAMETER LogDirectory
    The local directory path where execution logs are stored. Defaults to 'C:\Temp'.

.EXAMPLE
    Get-ADNestedGroupMembers -GroupName "Domain Admins"

.EXAMPLE
    Get-ADNestedGroupMembers -GroupName "Finance_Dept" -Indent

.EXAMPLE
    Get-ADGroup -Filter "Name -like 'Sec_*'" | Get-ADNestedGroupMembers | Export-Csv -Path "C:\Temp\NestedMembers.csv" -NoTypeInformation

.NOTES
    Author       : System Administrator / Sanitized (Refactored from Piotr Lewandowski v1.01)
    Prerequisites: RSAT Active Directory Tools module, Domain User privileges.
    Change Log   :
        1.0 - Initial sanitized production release with standard logging and housekeeping.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$GroupName,

    [Parameter(Mandatory = $false)]
    [int]$Nesting = 0,

    [Parameter(Mandatory = $false)]
    [int]$Circular = 0,

    [Parameter(Mandatory = $false)]
    [switch]$Indent,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "C:\Temp"
)

begin {
    # --------------------------------------------------------------------------
    # 1. PREREQUISITES & MODULE CHECKS
    # --------------------------------------------------------------------------
    $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $IsAdmin) {
        Write-Warning "Running in non-elevated context. Ensure proper Domain User rights to query Active Directory."
    }

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
    $ScriptName = "Get_ADNestedGroupMembers"
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

    function Format-IndentedName {
        param([string]$Name, [int]$DepthLevel)
        $Padding = "    " * $DepthLevel
        return "${Padding}${Name}"
    }
}

process {
    try {
        Write-Log "Processing nested membership audit for group: $GroupName (Nesting Depth: $Nesting)" "INFO"

        $ADGroup = Get-ADGroup -Identity $GroupName -Properties MemberOf, Members -ErrorAction Stop
        $GroupMemberOf = $ADGroup.MemberOf

        if ($Circular -eq 1) {
            $NestedMembers = Get-ADGroupMember -Identity $ADGroup.DistinguishedName -Recursive -ErrorAction SilentlyContinue
            $Circular = 0
        }
        else {
            $NestedMembers = Get-ADGroupMember -Identity $ADGroup.DistinguishedName -ErrorAction SilentlyContinue | Sort-Object ObjectClass -Descending
            
            if (-not $NestedMembers -and $ADGroup.Members) {
                $NestedMembers = [System.Collections.Generic.List[PSObject]]::new()
                foreach ($MemberDN in $ADGroup.Members) {
                    $Obj = Get-ADObject -Identity $MemberDN -ErrorAction SilentlyContinue
                    if ($Obj) { $NestedMembers.Add($Obj) }
                }
            }
        }

        foreach ($Member in $NestedMembers) {
            $BaseProps = [ordered]@{
                Type        = $Member.ObjectClass
                Name        = $Member.Name
                DisplayName = ""
                ParentGroup = $ADGroup.Name
                Enabled     = ""
                Nesting     = $Nesting
                DN          = $Member.DistinguishedName
                Comment     = ""
            }

            if ($Member.ObjectClass -eq "user") {
                $ADUser = Get-ADUser -Identity $Member.DistinguishedName -Properties Enabled, DisplayName -ErrorAction SilentlyContinue
                
                $Record = [PSCustomObject]$BaseProps
                $Record.Enabled     = $ADUser.Enabled
                $Record.Name        = $ADUser.SamAccountName
                $Record.DisplayName = $ADUser.DisplayName

                if ($Indent) {
                    $IndentedName = Format-IndentedName -Name $Record.Name -DepthLevel $Nesting
                    [PSCustomObject]@{
                        Name = "$IndentedName ($($Record.DisplayName))"
                    }
                }
                else {
                    $Record | Select-Object Type, Name, DisplayName, ParentGroup, Nesting, Enabled, DN, Comment
                }
            }
            elseif ($Member.ObjectClass -eq "group") {
                $Record = [PSCustomObject]$BaseProps

                if ($GroupMemberOf -contains $Member.DistinguishedName) {
                    $Record.Comment = "Circular membership"
                    $Circular = 1
                }

                if ($Indent) {
                    $IndentedName = Format-IndentedName -Name $Record.Name -DepthLevel $Nesting
                    if ($Record.Comment) {
                        Write-Host "$IndentedName (Circular Membership)" -ForegroundColor Red
                    }
                    else {
                        Write-Host "$IndentedName" -ForegroundColor Yellow
                    }

                    Get-ADNestedGroupMembers -GroupName $Member.DistinguishedName -Nesting ($Nesting + 1) -Circular $Circular -Indent -LogDirectory $LogDirectory
                }
                else {
                    $Record | Select-Object Type, Name, DisplayName, ParentGroup, Nesting, Enabled, DN, Comment
                    Get-ADNestedGroupMembers -GroupName $Member.DistinguishedName -Nesting ($Nesting + 1) -Circular $Circular -LogDirectory $LogDirectory
                }
            }
            else {
                if ($Member) {
                    $Record = [PSCustomObject]$BaseProps
                    if ($Indent) {
                        $IndentedName = Format-IndentedName -Name $Record.Name -DepthLevel $Nesting
                        [PSCustomObject]@{ Name = $IndentedName }
                    }
                    else {
                        $Record | Select-Object Type, Name, DisplayName, ParentGroup, Nesting, Enabled, DN, Comment
                    }
                }
            }
        }
    }
    catch {
        Write-Log "ERROR processing group '$GroupName': $($_.Exception.Message)" "ERROR"
    }
}

end {
    Write-Log "Nested group membership audit completed." "INFO"
}