# Detection Script: Checks for .log files older than 1 day in C:\Temp
$Path = "C:\Temp"
$DaysOld = 1
$TargetDate = (Get-Date).AddDays(-$DaysOld)

if (Test-Path -Path $Path) {
    # Check for stale log files
    $StaleLogs = Get-ChildItem -Path $Path -Filter "*.log" -File -ErrorAction SilentlyContinue | 
        Where-Object { $_.LastWriteTime -lt $TargetDate }

    if ($StaleLogs) {
        $Count = $StaleLogs.Count
        Write-Output "Non-Compliant: Found $Count log file(s) older than $DaysOld day(s) in $Path."
        Exit 1 # Triggers Remediation Script
    } else {
        Write-Output "Compliant: No log files older than $DaysOld day(s) found in $Path."
        Exit 0 # No action needed
    }
} else {
    Write-Output "Compliant: Directory $Path does not exist."
    Exit 0
}