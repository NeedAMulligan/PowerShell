# Remediation Script: Deletes .log files older than 1 day in C:\Temp
$Path = "C:\Temp"
$DaysOld = 1
$TargetDate = (Get-Date).AddDays(-$DaysOld)

# 1. Stop Dell services to release file locks
$DellServices = @("DellClientManagementService", "DDVDataCollector", "SupportAssistAgent")
$StoppedServices = @()

foreach ($Svc in $DellServices) {
    $Service = Get-Service -Name $Svc -ErrorAction SilentlyContinue
    if ($Service -and $Service.Status -eq 'Running') {
        Write-Output "Stopping service: $Svc"
        Stop-Service -Name $Svc -Force -ErrorAction SilentlyContinue
        $StoppedServices += $Svc
    }
}

# 2. Delete stale log files
if (Test-Path -Path $Path) {
    $StaleLogs = Get-ChildItem -Path $Path -Filter "*.log" -File -ErrorAction SilentlyContinue | 
        Where-Object { $_.LastWriteTime -lt $TargetDate }

    foreach ($File in $StaleLogs) {
        try {
            Write-Output "Deleting: $($File.FullName)"
            Remove-Item -Path $File.FullName -Force -ErrorAction Stop
        } catch {
            Write-Warning "Failed to delete $($File.FullName): $_"
        }
    }
}

# 3. Restart previously stopped services
foreach ($Svc in $StoppedServices) {
    Write-Output "Restarting service: $Svc"
    Start-Service -Name $Svc -ErrorAction SilentlyContinue
}

Write-Output "Remediation process completed."