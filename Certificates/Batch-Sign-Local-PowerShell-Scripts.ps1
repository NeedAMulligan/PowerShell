<#
.SYNOPSIS
    Batch signs all PowerShell scripts in a target directory.

.DESCRIPTION
    Iterates through a folder, locates .ps1 files, and applies an Authenticode
    signature using the specified local certificate. 

.PARAMETER TargetFolder
    The local directory containing scripts to be signed.

.EXAMPLE
    .\Batch-SignScripts.ps1 -TargetFolder "C:\Scripts\Production"
#>

# -------------------------------------------------------------------------
# VARIABLES
# -------------------------------------------------------------------------
$CertSubjectName = "PowerShell Code Signing"
$TargetFolder    = "C:\Scripts" # Update this to your local script folder
$LogPath         = "C:\temp"
$Timestamp       = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile         = Join-Path $LogPath "BatchSign_$($Timestamp).log"
$TimeServer      = "http://timestamp.digicert.com"

# -------------------------------------------------------------------------
# HELPER FUNCTIONS
# -------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Stamp] [$Level] $Message"
    $Line | Out-File -FilePath $LogFile -Append
    Write-Host $Line
}

# -------------------------------------------------------------------------
# MAIN LOGIC
# -------------------------------------------------------------------------
try {
    if (-not (Test-Path $LogPath)) { New-Item $LogPath -ItemType Directory -Force | Out-Null }
    Write-Log "Starting Batch Signing Process for: $TargetFolder"

    # 1. Pre-flight: Check Directory and Certificate
    if (-not (Test-Path $TargetFolder)) {
        Write-Log "ERROR: Target directory $TargetFolder not found." "ERROR"
        exit 2
    }

    $Cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | 
            Where-Object { $_.Subject -eq "CN=$CertSubjectName" } | 
            Select-Object -First 1

    if (-not $Cert) {
        Write-Log "ERROR: Certificate 'CN=$CertSubjectName' not found." "ERROR"
        exit 1
    }

    # 2. Get all .ps1 files
    $Files = Get-ChildItem -Path $TargetFolder -Filter "*.ps1" -Recurse
    if ($Files.Count -eq 0) {
        Write-Log "INFO: No .ps1 files found in $TargetFolder."
        exit 0
    }

    $Results = @()
    Write-Log "Found $($Files.Count) files to process."

    # 3. Process Files Interactively
    foreach ($File in $Files) {
        Write-Log "Processing: $($File.Name)..."
        try {
            $Sig = Set-AuthenticodeSignature -FilePath $File.FullName -Certificate $Cert -TimestampServer $TimeServer
            
            $StatusObj = [PSCustomObject]@{
                FileName = $File.Name
                Status   = $Sig.Status
                Path     = $File.FullName
            }
            $Results += $StatusObj
            
            if ($Sig.Status -eq "Valid") {
                Write-Log "SUCCESS: Signed $($File.Name)"
            } else {
                Write-Log "FAILED: $($File.Name) - $($Sig.StatusMessage)" "WARN"
            }
        }
        catch {
            Write-Log "Error signing $($File.Name): $($_.Exception.Message)" "ERROR"
        }
    }

    # 4. Final Report
    Write-Host "`n--- BATCH SIGNING SUMMARY ---" -ForegroundColor Cyan
    $Results | Format-Table -AutoSize
    
    $FailedCount = ($Results | Where-Object { $_.Status -ne "Valid" }).Count
    if ($FailedCount -gt 0) {
        Write-Log "Batch completed with $FailedCount failures." "WARN"
        exit 5
    }

    Write-Log "Batch signing completed successfully."
    exit 0
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 99
}
