# Intune Detection Script for Adobe Acrobat / Reader Removal
# Returns Exit 1 if present (triggers remediation), Exit 0 if clean

$RegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Search registry for Adobe Reader or Acrobat DC
$AdobeApps = Get-ChildItem -Path $RegPaths -ErrorAction SilentlyContinue | 
    Get-ItemProperty | 
    Where-Object { $_.DisplayName -like "*Adobe*Reader*" -or $_.DisplayName -like "*Adobe Acrobat DC*" }

if ($AdobeApps) {
    # App found -> Device is NON-COMPLIANT -> Trigger Remediation Script
    Write-Output "Detected: $($AdobeApps.DisplayName -join ', ')"
    Exit 1
} else {
    # App not found -> Device is COMPLIANT -> Do Nothing
    Write-Output "Adobe Acrobat Reader is not installed."
    Exit 0
}