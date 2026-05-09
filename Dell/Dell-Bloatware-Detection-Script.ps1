Start-Transcript -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\DellAppDetection.log" -Append

# App list to check
$appList = @(
    "Dell Command | Update for Windows Universal",
    "Dell Pair",
    "Dell Optimizer",
    "Dell SupportAssist"
)

# Registry paths used by Programs and Features
$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($appName in $appList) {
    $found = $false
    foreach ($path in $registryPaths) {
        if (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $appName }) {
            $found = $true
            break
        }
    }

    if ($found) {
        Write-Output "${appName}: True"
    } else {
        Write-Output "${appName}: False"
    }
}

Stop-Transcript