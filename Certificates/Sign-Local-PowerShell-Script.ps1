<#
.SYNOPSIS
    Signs a local PowerShell script using a specific Code Signing certificate.

.DESCRIPTION
    Locates a certificate by Subject Name and applies a digital signature to 
    a target .ps1 file. Includes verification of the signature.

.PARAMETER ScriptToSign
    Full path to the .ps1 file you wish to sign.

.EXAMPLE
    .\Sign-MyScript.ps1 -ScriptToSign "C:\Scripts\MyAutomation.ps1"
#>

# -------------------------------------------------------------------------
# VARIABLES
# -------------------------------------------------------------------------
$CertSubjectName = "PowerShell Code Signing"
$LogPath         = "C:\temp"
$Timestamp       = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile         = Join-Path $LogPath "SignScript_$($Timestamp).log"

# Add your target script path here for easy reuse, or use the Parameter
$TargetScript    = "C:\path\to\your\script.ps1" 

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
    Write-Log "Starting Script Signing Process..."

    # 1. Pre-flight: Check if Target Script Exists
    if (-not (Test-Path $TargetScript)) {
        Write-Log "ERROR: Target script not found at $TargetScript" "ERROR"
        exit 2
    }

    # 2. Pre-flight: Find the Certificate
    Write-Log "Searching for certificate: CN=$CertSubjectName"
    $Cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | 
            Where-Object { $_.Subject -eq "CN=$CertSubjectName" } | 
            Select-Object -First 1

    if (-not $Cert) {
        Write-Log "ERROR: Could not find a Code Signing certificate with Subject 'CN=$CertSubjectName'." "ERROR"
        exit 1
    }

    # 3. Apply Signature
    Write-Log "Signing $TargetScript..."
    $Signature = Set-AuthenticodeSignature -FilePath $TargetScript -Certificate $Cert -TimestampServer "http://timestamp.digicert.com"

    # 4. Verify Result
    if ($Signature.Status -eq "Valid") {
        Write-Log "SUCCESS: Script signed and verified."
        Write-Host "`n--- SIGNING COMPLETE ---" -ForegroundColor Green
        Write-Host "File: $TargetScript"
        Write-Host "Status: $($Signature.Status)"
        Write-Host "Log: $LogFile"
    } else {
        Write-Log "ERROR: Signing failed with status: $($Signature.Status)" "ERROR"
        Write-Host "Detailed Error: $($Signature.StatusMessage)" -ForegroundColor Red
        exit 99
    }

    exit 0
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 99
}
