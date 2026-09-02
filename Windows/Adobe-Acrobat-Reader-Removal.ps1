# Requires Administrator privileges
# Targets Adobe Acrobat Reader 32-bit and 64-bit installations

# 1. Close any running Acrobat/Reader processes
$Processes = @("AcroRd32", "Acrobat", "AcroCEF", "AdobeARM")
foreach ($Proc in $Processes) {
    Get-Process -Name $Proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# 2. Query registry paths for Adobe Reader Uninstall Strings
$RegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$AdobeApps = Get-ChildItem -Path $RegPaths -ErrorAction SilentlyContinue | 
    Get-ItemProperty | 
    Where-Object { $_.DisplayName -like "*Adobe*Reader*" -or $_.DisplayName -like "*Adobe Acrobat DC*" }

if ($AdobeApps) {
    foreach ($App in $AdobeApps) {
        $UninstallString = $App.UninstallString
        $ProductCode = $App.PSChildName
        
        Write-Output "Found: $($App.DisplayName)"
        
        # Execute silent uninstall via msiexec if product code is a GUID
        if ($ProductCode -match '^\{[A-F0-9-]+\}$') {
            Write-Output "Uninstalling via MSIExec code $ProductCode..."
            Start-Process "msiexec.exe" -ArgumentList "/x $ProductCode /qn /norestart" -Wait
        }
        # Fallback to direct uninstall string execution
        elseif ($UninstallString) {
            Write-Output "Uninstalling via command string..."
            $Exe = ($UninstallString -split " ")[0]
            $Args = ($UninstallString -split " ")[1..(($UninstallString -split " ").Count - 1)] + "/qn /norestart"
            Start-Process $Exe -ArgumentList $Args -Wait
        }
    }
    Write-Output "Remediation complete."
} else {
    Write-Output "Adobe Acrobat Reader was not found on this system."
}