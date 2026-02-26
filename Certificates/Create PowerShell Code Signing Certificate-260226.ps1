<#
.SYNOPSIS
    Generates and installs a local Code Signing Certificate for PowerShell.

.DESCRIPTION
    Creates a self-signed certificate, installs it into the Local Machine Root and 
    Trusted Publisher stores, and exports backup files to a local directory.

.PARAMETER CertificateName
    The Friendly Name and Subject Name for the certificate.

.EXAMPLE
    .\Create-SigningCert.ps1
#>

# -------------------------------------------------------------------------
# VARIABLES
# -------------------------------------------------------------------------
$CertificateName   = "PowerShell Code Signing"
$ExpirationYears   = 10
$ExportPath        = "C:\temp"
$LogPath           = "C:\temp"
$Timestamp         = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile           = Join-Path $LogPath "CreateSigningCert_$($Timestamp).log"
$PfxPassword       = "P@ssword123" # Recommended: Change this or use Get-Credential in production

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

function Test-Admin {
    $User = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Role = [Security.Principal.WindowsBuiltInRole]::Administrator
    return (New-Object Security.Principal.WindowsPrincipal($User)).IsInRole($Role)
}

# -------------------------------------------------------------------------
# MAIN LOGIC
# -------------------------------------------------------------------------
try {
    # 1. Pre-flight Checks
    if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
    Write-Log "Starting Certificate Generation Process..."

    if (-not (Test-Admin)) {
        Write-Log "ERROR: Script must be run as Administrator to update Root Store." "ERROR"
        exit 1
    }

    # 2. Duplicate Prevention
    $ExistingCert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq "CN=$CertificateName" }
    if ($ExistingCert) {
        Write-Log "WARN: A certificate with Subject 'CN=$CertificateName' already exists." "WARN"
        $Confirm = Read-Host "Do you want to overwrite/recreate this certificate? (Y/N)"
        if ($Confirm -ne "Y") { 
            Write-Log "Execution aborted by user to prevent duplicates."
            exit 2 
        }
    }

    # 3. Create Certificate
    Write-Log "Creating Self-Signed Certificate: $CertificateName..."
    $CertParams = @{
        CertStoreLocation = "Cert:\CurrentUser\My"
        Subject           = "CN=$CertificateName"
        KeySpec           = "Signature"
        Type              = "CodeSigningCert"
        NotAfter          = (Get-Date).AddYears($ExpirationYears)
        FriendlyName      = $CertificateName
    }
    $Certificate = New-SelfSignedCertificate @CertParams
    Write-Log "Certificate created with Thumbprint: $($Certificate.Thumbprint)"

    # 4. Export Files (Public and Private)
    $PublicCertPath = Join-Path $ExportPath "$CertificateName.cer"
    $PrivateCertPath = Join-Path $ExportPath "$CertificateName.pfx"
    
    Write-Log "Exporting Public Key to $PublicCertPath..."
    Export-Certificate -Cert $Certificate -FilePath $PublicCertPath | Out-Null

    Write-Log "Exporting Private Key (PFX) to $PrivateCertPath..."
    $SecurePassword = ConvertTo-SecureString -String $PfxPassword -Force -AsPlainText
    Export-PfxCertificate -Cert $Certificate -FilePath $PrivateCertPath -Password $SecurePassword | Out-Null

    # 5. Inject into Trust Stores (LocalMachine\Root & TrustedPublisher)
    Write-Log "Adding certificate to Trusted Root Certification Authorities..."
    Import-Certificate -FilePath $PublicCertPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null

    Write-Log "Adding certificate to Trusted Publishers..."
    Import-Certificate -FilePath $PublicCertPath -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher" | Out-Null

    Write-Log "SUCCESS: Certificate is now trusted for local code signing."
    Write-Host "`n--- SETUP COMPLETE ---" -ForegroundColor Cyan
    Write-Host "Public Key: $PublicCertPath"
    Write-Host "Private Key: $PrivateCertPath"
    Write-Host "Log: $LogFile"
    
    exit 0
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 99
}
