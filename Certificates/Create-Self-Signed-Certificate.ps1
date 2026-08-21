<#
.SYNOPSIS
    Generates and exports a self-signed certificate with public and private key outputs.
.DESCRIPTION
    This script checks for administrative privileges, creates a self-signed certificate 
    valid for a specified duration, exports the public certificate (.cer), and exports 
    the password-protected private key (.pfx) to the designated local directory with 
    comprehensive logging.
#>

[CmdletBinding()]
param()

# =========================================================================
# CONFIGURABLE VARIABLES
# =========================================================================
$Script:CertSubject      = "CN=CERTIFICATE-NAME"
$Script:CertStoreLocation = "Cert:\CurrentUser\My"
$Script:KeyLength         = 2048
$Script:ValidYears        = NUMBER OF YEARS
$Script:CerOutputPath     = "C:\temp\CERTIFICATE-NAMECert.cer"
$Script:PfxOutputPath     = "C:\temp\CERTIFICATE-NAMECert.pfx"
$Script:PlainPassword     = "ENTER-PASSWORD-HERE"

# Logging Configuration
$Script:LogDirectory      = "C:\temp"
$Script:ScriptBaseName    = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
if (-not $Script:ScriptBaseName) { $Script:ScriptBaseName = "Create-SelfSignedCertificate" }
$Script:Timestamp         = Get-Date -Format "yyyyMMdd_HHmmss"
$Script:LogFilePath       = Join-Path $Script:LogDirectory "$($Script:ScriptBaseName)_$($Script:Timestamp).log"

# =========================================================================
# LOGGING & UTILITY FUNCTIONS
# =========================================================================
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $LogTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$LogTime] [$Level] [ScriptExecution] $Message"

    # Ensure log directory exists
    if (-not (Test-Path $Script:LogDirectory)) {
        New-Item -ItemType Directory -Force -Path $Script:LogDirectory | Out-Null
    }

    # Write to log file
    Add-Content -Path $Script:LogFilePath -Value $LogEntry

    # Output to console with color coding
    switch ($Level) {
        "INFO"    { Write-Host $LogEntry -ForegroundColor Cyan }
        "SUCCESS" { Write-Host $LogEntry -ForegroundColor Green }
        "WARNING" { Write-Host $LogEntry -ForegroundColor Yellow }
        "ERROR"   { Write-Host $LogEntry -ForegroundColor Red }
    }
}

function Test-AdminElevation {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# =========================================================================
# EXECUTION START
# =========================================================================
try {
    Write-Log -Message "Initializing script execution." -Level "INFO"

    # 1. Elevation & Context Check
    if (-not (Test-AdminElevation)) {
        Write-Log -Message "Administrative privileges are required to run this script. Please relaunch from an elevated PowerShell console." -Level "ERROR"
        exit 1
    }
    Write-Log -Message "Administrative privilege validation passed." -Level "SUCCESS"

    # Ensure target output directory exists
    if (-not (Test-Path $Script:LogDirectory)) {
        New-Item -ItemType Directory -Force -Path $Script:LogDirectory | Out-Null
        Write-Log -Message "Created output directory at $Script:LogDirectory." -Level "INFO"
    }

    # 2. Certificate Generation
    Write-Log -Message "Creating self-signed certificate for subject '$Script:CertSubject'..." -Level "INFO"
    $Cert = New-SelfSignedCertificate `
        -Subject $Script:CertSubject `
        -CertStoreLocation $Script:CertStoreLocation `
        -KeyExportPolicy Exportable `
        -KeySpec Signature `
        -KeyLength $Script:KeyLength `
        -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears($Script:ValidYears)

    if ($null -eq $Cert) {
        throw "Failed to generate the self-signed certificate."
    }
    Write-Log -Message "Certificate successfully created with thumbprint: $($Cert.Thumbprint)" -Level "SUCCESS"

    # 3. Export Public Key (.cer)
    Write-Log -Message "Exporting public key to '$Script:CerOutputPath'..." -Level "INFO"
    Export-Certificate -Cert $Cert -FilePath $Script:CerOutputPath | Out-Null
    Write-Log -Message "Public key successfully exported." -Level "SUCCESS"

    # 4. Export Private Key (.pfx)
    Write-Log -Message "Exporting private key to '$Script:PfxOutputPath'..." -Level "INFO"
    $SecurePassword = ConvertTo-SecureString -String $Script:PlainPassword -Force -AsPlainText
    Export-PfxCertificate -Cert $Cert -FilePath $Script:PfxOutputPath -Password $SecurePassword | Out-Null
    Write-Log -Message "Private key successfully exported with secure password." -Level "SUCCESS"

    Write-Log -Message "All operations completed successfully." -Level "SUCCESS"
    exit 0
}
catch {
    Write-Log -Message "An error occurred during execution: $_" -Level "ERROR"
    exit 2
}
finally {
    Write-Log -Message "Execution finished. Log file saved to '$Script:LogFilePath'." -Level "INFO"
}