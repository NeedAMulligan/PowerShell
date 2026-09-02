# Intune / SCCM Detection Script for Edge Game Assist
$PackageName = "Microsoft.Edge.GameAssist"

$Installed = Get-AppxPackage -AllUsers -Name $PackageName -ErrorAction SilentlyContinue
$Provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $PackageName }

if ($Installed -or $Provisioned) {
    Write-Output "Detected: $PackageName is installed."
    Exit 1 # Non-compliant -> Triggers Remediation
} else {
    Write-Output "Compliant: $PackageName is not present."
    Exit 0
}