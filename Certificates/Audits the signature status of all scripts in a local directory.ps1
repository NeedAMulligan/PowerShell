<#
.SYNOPSIS
    Audits the signature status of all scripts in a local directory.

.DESCRIPTION
    Checks every .ps1 file for a valid Authenticode signature. Categorizes files
    to help administrators identify scripts that will fail under AllSigned policy.

.PARAMETER TargetFolder
    The folder to audit. Defaults to C:\Scripts.
#>

# -------------------------------------------------------------------------
# VARIABLES
# -------------------------------------------------------------------------
$TargetFolder    = "C:\Scripts"
$LogPath         = "C:\temp"
$Timestamp       = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile         = Join-Path $LogPath "SignatureAudit_$($Timestamp).log"

# -------------------------------------------------------------------------
# HELPER FUNCTIONS
# -------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR")] $Level = "INFO")
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Stamp] [$Level] $Message"
    $Line | Out-File -FilePath $LogFile -Append
    
    $Color = switch($Level) {
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        Default { "White" }
    }
    Write-Host $Line -ForegroundColor $Color
}

# -------------------------------------------------------------------------
# MAIN LOGIC
# -------------------------------------------------------------------------
try {
    if (-not (Test-Path $LogPath)) { New-Item $LogPath -ItemType Directory -Force | Out-Null }
    Write-Log "Starting Signature Audit for: $TargetFolder"

    if (-not (Test-Path $TargetFolder)) {
        Write-Log "ERROR: Directory $TargetFolder not found." "ERROR"
        exit 2
    }

    $Files = Get-ChildItem -Path $TargetFolder -Filter "*.ps1" -Recurse
    $AuditResults = @()

    foreach ($File in $Files) {
        $Sig = Get-AuthenticodeSignature -FilePath $File.FullName
        
        $ResultObj = [PSCustomObject]@{
            FileName = $File.Name
            Status   = $Sig.Status
            Signer   = $Sig.SignerCertificate.Subject
            Path     = $File.FullName
        }
        $AuditResults += $ResultObj

        if ($Sig.Status -ne "Valid") {
            Write-Log "ISSUE FOUND: $($File.Name) is $($Sig.Status)" "WARN"
        }
    }

    # Display Results
    Write-Host "`n--- SIGNATURE AUDIT REPORT ---" -ForegroundColor Cyan
    $AuditResults | Format-Table -AutoSize

    # Final logic check for exit codes
    $Issues = $AuditResults | Where-Object { $_.Status -ne "Valid" }
    if ($Issues) {
        Write-Log "Audit Complete: $($Issues.Count) file(s) require signing/repair." "WARN"
        exit 1
    } else {
        Write-Log "Audit Complete: All files are valid and signed." "INFO"
        exit 0
    }
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 99
}
