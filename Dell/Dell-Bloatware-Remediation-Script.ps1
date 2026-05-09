Start-Transcript -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\DellAppRemediation.log" -Append

# Apps to check and uninstall
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
    $uninstallString = $null

    foreach ($path in $registryPaths) {
        $app = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $appName }
        if ($app) {
            $found = $true
            $uninstallString = $app.UninstallString
            break
        }
    }

    if ($found -and $uninstallString) {
        Write-Output "${appName}: Found. Attempting uninstall..."

        # Parse uninstall command and args
        if ($uninstallString -match '^(\".+?\"|\S+)(.*)$') {
            $exePath = $matches[1].Trim('"')
            $arguments = $matches[2].Trim()

            if ($arguments -notmatch '(/quiet|/qn|/s|/silent)') {
                if ($exePath -like "*.msi") {
                    $arguments += " /quiet /norestart"
                } else {
                    $arguments += " /qn /norestart"
                }
            }

            Write-Output "Running uninstall command: $exePath $arguments"
            try {
                $process = Start-Process -FilePath $exePath -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
                if ($process.ExitCode -eq 0) {
                    Write-Output "${appName}: Successfully uninstalled."
                } else {
                    Write-Output "${appName}: Uninstall exited with code $($process.ExitCode)."
                }
            }
            catch {
                Write-Output "${appName}: Uninstall failed with error: $_"
            }
        }
        else {
            Write-Output "${appName}: Unable to parse uninstall command."
        }
    }
    else {
        Write-Output "${appName}: Not found, skipping uninstall."
    }
}

Stop-Transcript
