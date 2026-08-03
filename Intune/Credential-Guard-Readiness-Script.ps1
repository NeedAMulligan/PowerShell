<#
.SYNOPSIS
    Checks Windows Credential Guard and HVCI readiness and current status.
    Designed for deployment via RMM (ManageEngine Endpoint Central).
#>

$results = [PSCustomObject]@{
    ComputerName           = $env:COMPUTERNAME
    OSVersion              = (Get-CimInstance Win32_OperatingSystem).Caption
    SecureBootEnabled      = $false
    TPM2Present            = $false
    VBSCapable             = $false
    HVCIRunning            = $false
    CredentialGuardRunning = $false
    OverallStatus          = "Not Ready"
}

# 1. Check Secure Boot Status
try {
    $secureBoot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    if ($secureBoot) { $results.SecureBootEnabled = $true }
} catch {
    $results.SecureBootEnabled = $false
}

# 2. Check TPM 2.0 Status
$tpm = Get-Tpm -ErrorAction SilentlyContinue
if ($tpm -and $tpm.TpmPresent -and $tpm.TpmReady -and ($tpm.SpecVersion -match "2\.0")) {
    $results.TPM2Present = $true
}

# 3. Check VBS and Security Services via DeviceGuard Class
$dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
if ($dg) {
    if ($dg.AvailableSecurityProperties -contains 2 -or $dg.AvailableSecurityProperties -contains 1) {
        $results.VBSCapable = $true
    }
    # SecurityServicesRunning values: 1 = Credential Guard, 2 = HVCI (Hypervisor-enforced Code Integrity)
    if ($dg.SecurityServicesRunning -contains 1) {
        $results.CredentialGuardRunning = $true
    }
    if ($dg.SecurityServicesRunning -contains 2) {
        $results.HVCIRunning = $true
    }
}

# 4. Determine Overall Readiness
if ($results.CredentialGuardRunning) {
    $results.OverallStatus = "Already Active"
} elseif ($results.VBSCapable) {
    $results.OverallStatus = "Ready (Not Enabled)"
} else {
    $results.OverallStatus = "Hardware Incompatible or Missing BIOS Settings"
}

# Output results nicely formatted for RMM logs
$results | Format-List

# Exit code mapping for Endpoint Central
if ($results.CredentialGuardRunning -or $results.OverallStatus -eq "Ready (Not Enabled)") {
    exit 0
} else {
    exit 1603
}